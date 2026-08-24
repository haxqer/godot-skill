# GDScript Typing And Parse Safety

Read this reference before writing or editing any `.gd` file. It is not a style
guide — it is the set of rules that decide whether generated GDScript *compiles
and boots at all*. A single parse error stops the whole script from loading,
which cascades into `Failed to load script`, null-instance errors, and a project
that will not start.

The most common way generated code fails on the first run is type inference:
`:=` used on a right-hand side that has no static type. Godot rejects that at
parse time, so the game never boots. **Default to explicit type annotations and
the problem disappears.**

Verified on `godot 4.7.stable`. Every error string quoted below was captured
from that build via `check_project`; they are stable across Godot 4.x.

## The Default Rule

Annotate every variable, parameter, and return type in generated code.

```gdscript
extends Node2D

@export var speed: float = 200.0
@export var bullet_scene: PackedScene

@onready var label: Label = %Label
@onready var sprite: Sprite2D = $Sprite2D

var _hp: int = 10
var _velocity: Vector2 = Vector2.ZERO
var _tween: Tween = null

func heal(amount: int) -> void:
	_hp += amount

func hp_ratio() -> float:
	return float(_hp) / 100.0
```

Explicit annotations are never wrong, cost one word, and remove the entire class
of inference failures. `:=` is an optimisation for hand-written code where the
author can see the right-hand side's type; when generating code, you often
cannot. When in doubt, write the annotation.

## Node References

**Always annotate node references. Never infer them.**

```gdscript
# Correct
@onready var label: Label = %Label
@onready var body: CharacterBody2D = $Player/Body
@onready var timer: Timer = get_node("Timer")

# Wrong — parses, but `label` is typed `Node`, not `Label`
@onready var label := %Label
var body := $Player/Body
var timer := get_node("Timer")
```

`$Path`, `%UniqueName`, and `get_node()` are all statically typed as `Node` —
the analyzer does not read the `.tscn` to discover that `Label` node is a
`Label`. So `:=` here does not fail loudly; it silently produces a `Node`, and
the mistake surfaces later, somewhere else, harder to trace.

Never use `:=` when the right-hand side is:

| Right-hand side | Why |
| --- | --- |
| `$Node`, `%Unique`, `get_node()`, `get_parent()`, `find_child()` | Typed `Node` — inference succeeds but is uselessly wide |
| `$Node.some_property`, `$Node.some_method()` | Member of `Node` is unknown → no set type → **parse error** |
| `PackedScene.instantiate()` | Typed `Node` — same widening |
| `dict[key]`, `dict.get(key)`, `array[i]` on an untyped array | No set type → **parse error** |
| `JSON.parse_string()`, any `Variant`-returning API | `Variant` → **parse error** |
| a call into a function with no declared return type | No set type → **parse error** |
| `null` | **parse error** |
| a `class_name` type the project has not re-imported yet | Identifier unresolved → **parse error** |

### Failure Mode A — Un-inferable Right-Hand Side

The right-hand side has no static type at all, so the script does not compile.
These are hard stops; nothing in the file runs.

```gdscript
var pos := $Sprite2D.position          # position is not on Node
var hp := data["hp"]                   # Dictionary read
var parsed := JSON.parse_string(text)  # declared Variant
var thing := null
```

```
SCRIPT ERROR: Parse Error: Cannot infer the type of "pos" variable because the value doesn't have a set type.
SCRIPT ERROR: Parse Error: Cannot infer the type of "hp" variable because the value doesn't have a set type.
SCRIPT ERROR: Parse Error: The variable type is being inferred from a Variant value, so it will be typed as Variant. (Warning treated as error.)
SCRIPT ERROR: Parse Error: Cannot infer the type of "thing" variable because the value is "null".
ERROR: Failed to load script "res://scripts/player.gd" with error "Parse error".
```

The `Variant` case is worth calling out: it is a *warning* that Godot ships set
to error. `debug/gdscript/warnings/inference_on_variant` defaults to `2`
(error) in 4.7, so `:=` from any `Variant` value is a boot-blocking failure in a
stock project, not a soft nag.

The fixes are mechanical — annotate, and convert where needed:

```gdscript
var pos: Vector2 = ($Sprite2D as Sprite2D).position
var hp: int = int(data.get("hp", 0))
var raw: Variant = JSON.parse_string(text)
var parsed: Dictionary = raw if raw is Dictionary else {}
var thing: Node = null
```

### Failure Mode B — Inferable But Too Wide

The right-hand side *does* have a type, but it is `Node`. The script compiles,
so this one hides: every later member access on that variable is unchecked.

```gdscript
var label := $Label   # label is Node, not Label
label.text = "hi"     # unchecked
label.set_txt("hi")   # unchecked typo — no compile error
```

In a stock project (`unsafe_property_access` and `unsafe_method_access` both
default to `0`, ignore) this produces no diagnostic at all until the line
actually executes, at which point it is a runtime error such as:

```
SCRIPT ERROR: Invalid call. Nonexistent function 'set_txt' in base 'Label'.
```

In any project that raises those warnings — many templates and studio projects
set them to `2` — the same code becomes a parse error and the game will not
boot:

```
SCRIPT ERROR: Parse Error: The property "text" is not present on the inferred type "Node" (but may be present on a subtype). (Warning treated as error.)
SCRIPT ERROR: Parse Error: The method "set_text()" is not present on the inferred type "Node" (but may be present on a subtype). (Warning treated as error.)
```

Writing `@onready var label: Label = %Label` fixes both cases at once: the typo
becomes a compile error you catch immediately, in every project.

## Where `:=` Is Still Fine

`:=` is safe when the right-hand side has a concrete declared type that is
visible on the same line:

```gdscript
var dir := Vector2.ZERO                 # Vector2
var total := 0                          # int
var display_name := "player"            # String
var tween := create_tween()             # Tween — declared return type
var enemy := body as Enemy              # Enemy — `as` narrows exactly
var config := ConfigFile.new()          # ConfigFile — typed constructor
```

The test is: *can you name the resulting type by reading only this line?* If
not, write the annotation. There is no penalty for annotating a case where `:=`
would have worked, and there is a boot failure for guessing wrong.

Typed collections are the one case that looks safe and is not: `var enemies :=
[]` infers plain `Array`, not `Array[Enemy]`, and there is no typed-array
constructor to infer from — `Array[Enemy]()` is not valid syntax and fails with
`Parse Error: Cannot call on an expression. Use ".call()" if it's a Callable.`
Always write the annotation:

```gdscript
var enemies: Array[Enemy] = []
var scores: Dictionary[String, int] = {}  # typed Dictionary needs Godot 4.4+
```

## Casting And Downcasts

Use `as` plus a null check for every downcast. `as` returns `null` on failure
rather than erroring, so the guard is what keeps the next line safe:

```gdscript
func _on_body_entered(body: Node2D) -> void:
	var enemy := body as Enemy
	if enemy == null:
		return
	enemy.take_damage(1)
```

Same pattern for instantiating a scene into a known type:

```gdscript
const ENEMY_SCENE: PackedScene = preload("res://enemies/enemy.tscn")

func spawn() -> void:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	if enemy == null:
		push_error("enemy.tscn root is not an Enemy")
		return
	add_child(enemy)
```

Note that `var x: Enemy = node` (implicit downcast) also compiles, but it is
checked at *runtime* and errors instead of yielding `null` — prefer `as` plus a
guard when the type is not guaranteed, and the annotation when it is.

For `@export`, always give a type; the bare form does not compile:

```gdscript
@export var speed: float = 200.0
@export var target: Node2D
@export_range(0, 100) var armor: int = 0
```

```
SCRIPT ERROR: Parse Error: Cannot use simple "@export" annotation with variable without type or initializer, since type can't be inferred.
```

## Other Startup Killers

Each of these stops the script from compiling. Same format as the table in
`references/debugging.md`: exact message, cause, fix.

| Message | Cause | Fix |
| --- | --- | --- |
| `Parse Error: Identifier "Enemy" not declared in the current scope.` | A newly written `class_name` script is not in `.godot/global_script_class_cache.cfg` yet. Global class names are resolved from that cache, which a `--script` run does not rebuild. | Run `godot --headless --path <project> --import` (or `scripts/import/import_project.py`) after adding any `class_name`, before validating. As a fallback, reference it by path: `const Enemy = preload("res://enemies/enemy.gd")`. |
| `Parse Error: Class "GameState" hides an autoload singleton.` | A `class_name` matches an autoload name. Godot then also logs the misleading `ERROR: Failed to instantiate an autoload, script '…' does not inherit from 'Node'.` | Rename one of them — autoload `GameState` + `class_name GameStateData`, or drop the `class_name` from the autoload script (autoloads do not need one). |
| `Parse Error: Class "Node2D" hides a native class.` | A `class_name` collides with a built-in engine class. | Pick a project-specific name. Check with `ClassDB.class_exists("Foo")` before choosing. |
| `Parse Error: Could not find base class "CyB".` / `Parse Error: Could not resolve super class inheritance from "CyA".` | Two scripts `extends` each other. Inheritance cycles are still fatal in 4.7. | Break the cycle: give both a common base, or replace one edge with composition. Cycles in *type annotations*, `const preload` references, and constructor calls between two `class_name` scripts are fine in 4.x — only `extends` cycles fail. |
| `Parse Error: Used space character for indentation instead of tab as used before in the file.` / `Parse Error: Used tab character for indentation instead of space as used before in the file.` | Tabs and spaces mixed in one file — typical when appending generated lines to an existing script. | Use one style per file. Godot's own convention (and what the editor writes) is tabs; match whatever the file already uses. |
| `Parse Error: Unexpected "?" in source. If you want a ternary operator, use "truthy_value if true_condition else falsy_value".` | C-style `cond ? a : b`. GDScript has no `?:`. | `var msg: String = "alive" if hp > 0 else "dead"`. |
| `Parse Error: Function "helper()" not found in base Node.` | `super()` called from a method that does not override anything in the parent. | Only call `super()` / `super.method()` from a genuine override. Drop the call, or fix the method name. |
| `Parse Error: Function "load_score()" is a coroutine, so it must be called with "await".` | A function containing `await` was called without `await`; its return value is a `Signal`, not the declared type. | `var score: int = await load_score()`. Awaiting a non-signal is only a warning (`"await" keyword is unnecessary because the expression isn't a coroutine nor a signal.`), so err toward adding `await`. |
| `Parse Error: The function signature doesn't match the parent. Parent signature is "_ready() -> void".` | An engine callback was declared with the wrong parameters or return type. | Match the documented signature exactly: `_ready() -> void`, `_process(delta: float) -> void`, `_physics_process(delta: float) -> void`, `_input(event: InputEvent) -> void`. |
| `Parse Error: "@onready" can only be used in classes that inherit "Node".` | `@onready` in a `RefCounted` / `Resource` / `Object` class. `@onready` needs `_ready`. | Drop `@onready` and initialise in `_init()`, or make the class extend `Node`. |
| `Parse Error: Not all code paths return a value.` | A function with a declared return type has a branch that falls off the end. | Add a final `return` with a sensible default; do not delete the return type to silence it. |
| `Parse Error: Cannot assign a value of type Node to variable "s" with specified type String.` | An incompatible assignment — commonly a `Node` from `$`/`get_node()`/`instantiate()` landing in a variable of an unrelated type. | Fix the declared type, or cast with `as` and guard for `null`. |
| `WARNING: The local variable "name" is shadowing an already-declared property in the base class "Node".` | A local named after an inherited property (`name`, `position`, `scale`, `owner`, `visible`). A warning, not fatal — but it silently detaches reads from the property you meant. | Rename the local (`display_name`, `start_position`). |

## Validate Before Finishing

Every message above is reported by this skill's own validators, so there is no
excuse for shipping code that does not parse. Run generated GDScript through one
of them before you call the task done:

```bash
# whole project, structured output, gates on the parsed log as well as exit code
python3 scripts/debug/validate_project.py /abs/project --pretty

# or the dispatcher operation directly
godot --headless --debug --ignore-error-breaks --path /abs/project \
  --script /abs/skill/scripts/core/dispatcher.gd check_project '{}' 2>&1 \
  | python3 /abs/skill/scripts/debug/godot_log_parser.py -

# then confirm it actually boots
python3 scripts/debug/run_project.py /abs/project --quit-after 120 --timeout 60
```

Success is `"ok": true` with `counts.parse_errors == 0` and `counts.errors == 0`.
If you added a `class_name`, run `--import` first or the class will read as
undeclared. See `references/debugging.md` for the full diagnose→fix→re-run loop.
