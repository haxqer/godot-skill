# Runtime Error Diagnosis And Fixing

Read this reference when the task is to run a Godot project, read the errors the
debugger reports, and fix them. It documents the exact Godot 4.7 error output
formats, how to capture them without hanging, the diagnose→fix→re-run loop, and a
table mapping common messages to their root cause and fix.

The bundled tooling for this lives in `scripts/debug/`:

- `run_project.py` — run the project headlessly and return parsed diagnostics.
- `godot_log_parser.py` — turn any Godot log text into structured diagnostics.
- `check_project` — dispatcher operation that loads every script, scene, shader,
  resource, GDExtension, and editor plugin — and instantiates every scene — and
  reports failures.
- `validate_project.py` — run `check_project` plus C# solution compilation.
- `run_scenario.py` — drive deterministic input, assertions, screenshots, logs,
  and performance thresholds.

## The Loop

1. **Reproduce.** Run the project and capture the debugger output:
   ```bash
   python3 scripts/debug/run_project.py /abs/path/to/project --quit-after 120 --timeout 60
   ```
   The runner returns JSON: `ok`, `counts`, and a `diagnostics` array where each
   entry has `severity`, `category`, `message`, `file`, `line`, `function`,
   `stack`, and a `suggested_fix`.
2. **Locate.** For each diagnostic, open `file` at `line`. The `function` and
   `stack` show how execution reached it.
3. **Fix.** Apply the fix guided by the `category`/`suggested_fix` and the table
   below. Prefer the bundled scene/script operations (see `SKILL.md`) over
   hand-editing `.tscn`/`.gd` when the fix is structural (wrong NodePath, missing
   signal wiring, wrong exported value).
4. **Confirm.** Re-run the same command. Success is `"ok": true` with
   `counts.errors == 0` and `counts.parse_errors == 0`. Do not stop at "it
   probably works" — the runner is the check.
5. **Widen.** Some errors only fire on code paths a short boot never reaches
   (a button handler, a level transition). Run the specific scene with
   `run_project.py <project> res://scenes/that_scene.tscn`, raise `--quit-after`,
   or drive the input path that triggers it.

For a fast whole-project sanity pass that does not depend on running gameplay,
validate every file first:

```bash
godot --headless --debug --ignore-error-breaks --path /abs/project \
  --script /abs/skill/scripts/core/dispatcher.gd check_project '{}' 2>&1 \
  | python3 /abs/skill/scripts/debug/godot_log_parser.py -
```

`check_project` loads every file in the project, so with the debugger attached
this one command reports the warnings of **every** script, not just the ones a
short boot happens to load. It prints a JSON summary of which files failed to
load; piping its combined output through the parser gives the line-level
diagnostics. Scope it to a subtree with `{"project_path":"scripts/enemies"}`.

It also instantiates every scene it loads, which is the only way a broken node
hierarchy surfaces: `ERROR: Invalid scene: …` plus a `failed[]` entry when the
root carries `parent=` or a non-root node has none, and
`WARNING: Parent path … has vanished` (category `scene_hierarchy`) when a
`parent=` path does not resolve. Instantiating runs each scene root script's
`_init()` and its stored-property setters — not `_ready`, and autoloads are
available — so pass `{"instantiate": false}` only when running that code is
unwanted. See `references/tscn_format.md` for the full failure table.

**Read the log, not only the summary.** Godot degrades gracefully on breakage
the editor treats as fatal — a scene whose `[ext_resource]` is missing still
loads and still instantiates, with the property left null, printing only an
`ERROR:` to stderr. `check_project` cross-checks `ResourceLoader.get_dependencies()`
to catch that case, but the general rule stands: a `failed_count` of 0 with
`ERROR:` lines in the log is a failure. `validate_project.py` does both — it runs
`check_project`, parses the captured log, and refuses to report `ok` while any
error-level diagnostic is present:

```bash
python3 scripts/debug/validate_project.py /abs/project --pretty
```

Its output adds `counts` and `diagnostics` (same shape as `run_project.py`) to
the file-level `static` summary. Use it when the project contains C#,
GDExtensions, or editor plugins; add `--warnings-as-errors` to make the pass
strict. Use a scenario from `references/automation_api.md` when validation
requires a specific input flow, visual state, log message, or performance bound.

## Capturing Output Correctly

- **Always run with `-d --ignore-error-breaks`.** This is what makes a CLI run
  report what the editor reports. GDScript **warnings** — unused variable,
  shadowed variable, integer division, standalone expression, unused parameter,
  narrowing conversion — are never written to stdout directly. The engine emits
  them through the *script debugger* channel, which is inactive unless a
  debugger is attached. That is why the editor (which launches the game with a
  remote debugger attached) shows a long list of warnings while
  `godot --headless --path .` prints nothing at all. `-d` attaches the local
  stdout debugger so those warnings surface; `--ignore-error-breaks` stops the
  local debugger from breaking into an interactive `debug>` prompt on the first
  error, which would otherwise end the run early. Use `-d` **alone** for
  nothing: the pair is the unit. `run_project.py`, `validate_project.py`, and
  `run_scenario.py` pass both by default (`--no-debugger` opts out) and feed the
  process `/dev/null` on stdin so any break that does slip through reads EOF and
  quits instead of hanging.

  ```bash
  # warnings visible                     # silent, even though the editor complains
  godot --headless -d --ignore-error-breaks --path /abs/project --quit-after 120
  godot --headless --path /abs/project --quit-after 120
  ```
- **An exit code of 0 is necessary, not sufficient.** A GDScript runtime error
  inside a dispatcher operation aborts that operation only — the dispatcher
  resumes and exits `0`, because nothing recorded a failure. The bundled Python
  wrappers therefore gate on the parsed log as well as the return code
  (`validate_project.py`, `import_project.py`), and `run_tests.py` /
  `export_project.py` additionally check that work actually happened (a
  non-empty suite, an artifact on disk). When you call the dispatcher directly,
  pipe its combined output through `godot_log_parser.py` rather than trusting
  `$?` alone. The complementary guard is on the input side: an unknown
  parameter key is now rejected before the operation runs, which removes the
  most common way an operation used to crash or silently do the wrong thing.
- **One class of editor warning stays out of reach.** Node *configuration*
  warnings — the yellow triangles in the scene tree ("This node has no shape so
  it can't collide…") — come from `Node::get_configuration_warnings()`, which is
  not bound outside the editor: a `--script` run cannot read them at any flag
  combination. If the user reports warnings the tooling does not reproduce, ask
  whether they are scene-tree triangles rather than Output-panel lines, and
  inspect the scene structure directly (`inspect_scene`) instead.
- **Bound every run.** Use `--quit-after N` (frames) for a clean exit and a
  wall-clock `--timeout` as the safety net. A run that hits the timeout
  (`"timed_out": true`) is itself a finding: an infinite loop or a blocking call.
- **Use `--quit-after` ≥ 2.** A known engine quirk makes headless `--quit` /
  `--quit-after 1` fail resource import on a project's first launch.
- **Headless is the default and catches script logic errors.** Errors that only
  appear with real rendering/audio need `--no-headless`.
- Godot writes errors to **stderr**; the runner merges stdout+stderr so nothing
  is missed. `--log-file <path>` also persists the raw capture.

## Godot 4.7 Error Output Anatomy

The parser understands each of these shapes. Knowing them helps when reading raw
logs by hand.

**Runtime script error** — a GDScript error while the game runs. `at:` is the
crash site; the backtrace shows the call chain:
```
SCRIPT ERROR: Invalid access to property or key 'position' on a base object of type 'null instance'.
          at: _ready (res://scripts/main.gd:4)
          GDScript backtrace (most recent call first):
              [0] _ready (res://scripts/main.gd:4)
```

**`push_error()`** — printed as `ERROR:`. Here `at:` points into engine C++, so
the real GDScript location is the backtrace `[0]` frame:
```
ERROR: custom boom happened
   at: push_error (core/variant/variant_utility.cpp:1023)
   GDScript backtrace (most recent call first):
       [0] _ready (res://scripts/main.gd:3)
```

**`push_warning()`** — printed as `WARNING:`, same structure.

**Parse error** — the script failed to compile, so it never runs. Fix these
first; downstream `Failed to load script` / null-instance errors are often just
fallout:
```
SCRIPT ERROR: Parse Error: Identifier "foo" not declared in the current scope.
          at: GDScript::reload (res://scripts/main.gd:3)
ERROR: Failed to load script "res://scripts/main.gd" with error "Parse error".
```

Fix order: **parse errors → resource/load errors → runtime script errors →
warnings.** A single parse error usually cascades into several later errors.

Most parse errors in generated GDScript come from type inference — `:=` on a
value with no static type. `references/gdscript_conventions.md` covers the
typing rules that prevent them, and read it before writing new `.gd` files
rather than after the first failed run.

## Message → Cause → Fix

| Message contains | `category` | Likely cause | Fix |
| --- | --- | --- | --- |
| `null instance`, `on a null value` | `null_reference` | Node/object is null | Node accessed before it is in the tree, or a wrong/renamed NodePath. Use `@onready`, access in `_ready`, `get_node_or_null()` + guard, or fix the path. |
| `Invalid get index` / `Invalid set index` | `invalid_index` | Missing key/index or wrong base type | Verify the property/key name; ensure the collection or object is initialised and non-null. |
| `Invalid access to property or key` | `invalid_member` | Member does not exist on that object | Fix the member name or the object's type; the base may be null. |
| `nonexistent function`, `not found in base` | `missing_method` | Method typo, wrong node class, or renamed API | Correct the name, cast to the right type, or update to the 4.x API. |
| `nonexistent signal`, `Signal ... is not declared` | `signal` | Emitting/connecting an undeclared signal | Declare `signal name(...)`, fix the name, or target the correct node. Prefer the `connect_signal` operation for wiring. |
| `not declared in the current scope` | `undeclared_identifier` | Undeclared variable/const or missing preload | Declare it, fix the typo, or add the `preload`/`class_name`. If the identifier is a `class_name` you just wrote, the global class cache is stale: run `godot --headless --path <project> --import` before re-validating. |
| `Trying to assign value of type`, `Cannot convert` | `type_mismatch` | Typed var got an incompatible type | Convert the value or fix the declared type. |
| `Cannot infer the type of "x" variable because the value doesn't have a set type` | `parse_error` | `:=` on a right-hand side with no static type — a `Dictionary`/`Array` read, `$Node.property`, or a call into a function with no declared return type | Write the annotation instead: `var hp: int = int(data.get("hp", 0))`. See `references/gdscript_conventions.md`. |
| `Cannot infer the type of "x" variable because the value is "null"` | `parse_error` | `var x := null` — `null` carries no type | Annotate the intended type: `var x: Node = null`. |
| `The variable type is being inferred from a Variant value, so it will be typed as Variant. (Warning treated as error.)` | `parse_error` | `:=` from a `Variant`-returning API (`JSON.parse_string`, a `Variant` field). `inference_on_variant` ships set to error, so this blocks boot in a stock project | Annotate and narrow: `var raw: Variant = JSON.parse_string(s)` then `var d: Dictionary = raw if raw is Dictionary else {}`. |
| `The property "x" is not present on the inferred type`, `The method "x()" is not present on the inferred type` | `parse_error` | A too-wide inferred type (`$Node`/`get_node()`/`instantiate()` all infer `Node`) plus a project that raises `unsafe_property_access`/`unsafe_method_access` to error | Annotate the node reference: `@onready var label: Label = %Label`. Never `:=` with `$`, `%`, `get_node()`, or `instantiate()`. |
| `Cannot assign a value of type ... to variable "x" with specified type` | `parse_error` | Compile-time type mismatch, usually a `Node` from `$`/`get_node()`/`instantiate()` assigned to an unrelated type | Fix the declared type, or downcast with `as` plus a `null` guard. |
| `Cannot use simple "@export" annotation with variable without type or initializer` | `parse_error` | `@export var speed` with neither type nor default | Give it a type: `@export var speed: float = 200.0`. |
| `hides an autoload singleton`, `hides a native class` | `parse_error` | A `class_name` collides with an autoload name or a built-in engine class | Rename the class or the autoload; autoload scripts do not need a `class_name`. |
| `Used space character for indentation instead of tab`, `Used tab character for indentation instead of space` | `parse_error` | Tabs and spaces mixed in one file, typical when appending generated lines to an existing script | Use one style for the whole file; match what the file already uses (Godot's own convention is tabs). |
| `Unexpected "?" in source` | `parse_error` | C-style `cond ? a : b`; GDScript has no `?:` | `var msg: String = "alive" if hp > 0 else "dead"`. |
| `is a coroutine, so it must be called with "await"` | `parse_error` | A function containing `await` called without `await`, so it returns a `Signal` | Add `await` at the call site: `var score: int = await load_score()`. |
| `The function signature doesn't match the parent` | `parse_error` | An engine callback declared with the wrong parameters or return type | Match the documented signature exactly (`_process(delta: float) -> void`, `_input(event: InputEvent) -> void`). |
| `"@onready" can only be used in classes that inherit "Node"` | `parse_error` | `@onready` in a `RefCounted`/`Resource` class, which has no `_ready` | Initialise in `_init()`, or make the class extend `Node`. |
| `Could not find base class`, `Could not resolve super class inheritance from` | `parse_error` | Two scripts `extends` each other; inheritance cycles are still fatal in 4.7 | Break the cycle with a shared base or composition. Type-annotation and `const preload` cycles between `class_name` scripts are fine in 4.x — only `extends` cycles fail. |
| `Not all code paths return a value` | `parse_error` | A branch falls off the end of a function with a declared return type | Add a final `return` with a sensible default; do not delete the return type to silence it. |
| `Node not found` | `node_path` | `get_node()` path does not resolve | Fix the NodePath / `%UniqueName`, or use `get_node_or_null()` + guard. |
| `Failed to load resource`, `Resource file not found`, `Cannot open file` | `resource_load` | Missing/renamed resource or broken UID | Restore/fix the path; repair UID sidecars with the `get_uid` / `resave_resources` operations after a move. |
| `Failed to load script ... Parse error` | `resource_load` | A referenced script has a parse error | Fix the parse error in that script first. |
| `Parse Error: ...` | `parse_error` | GDScript syntax/identifier error | Fix the reported line; the script will not run until it compiles. |
| `Condition "..." is true` | `engine_assertion` | Engine precondition failed | A call made in the wrong state/order (often before the node is in the tree). Move the call or satisfy the precondition. |
| `Invalid scene: root node X cannot specify a parent node`, `Invalid scene: node X does not specify its parent node` | `scene_hierarchy` | Broken `[node]` parentage in a `.tscn`; `instantiate()` returns null and the scene is unusable | The first `[node]` (the root) must have no `parent=`; every other one needs a `parent=` naming an existing node. The message names the node, not the scene — take the scene path from `check_project`'s `failed[]` entry. |
| `Parent path '...' for node '...' has vanished when instantiating` | `scene_hierarchy` | A `parent=` path that does not resolve; the node is silently reparented to the root as `<path>#<name>` | Fix the `parent=` path (root-relative, no leading `./`, parent declared before its children), then confirm with `inspect_scene`. |
| shader compile messages | `shader` | Shader failed to compile | Fix the reported shader line; match uniforms/varyings to their use. `check_project` forces the compile by assigning each `.gdshader` to a `ShaderMaterial`, so these do surface without running the game. |

## Notes For Godot 4.7

- Interactive debugging in the editor benefits from 4.7's Remote Inspector
  improvements (foldable groups/subgroups and readable enum names instead of raw
  integers), but headless automation relies on the same stdout/stderr the runner
  captures — no editor required.
- The runner and parser are version-tolerant: they key off the `SCRIPT ERROR:` /
  `ERROR:` / `WARNING:` / `Parse Error:` shapes, which are stable across Godot
  4.x, and were verified against `godot 4.7.stable`.
