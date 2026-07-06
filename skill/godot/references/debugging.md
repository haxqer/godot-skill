# Runtime Error Diagnosis And Fixing

Read this reference when the task is to run a Godot project, read the errors the
debugger reports, and fix them. It documents the exact Godot 4.7 error output
formats, how to capture them without hanging, the diagnose→fix→re-run loop, and a
table mapping common messages to their root cause and fix.

The bundled tooling for this lives in `scripts/debug/`:

- `run_project.py` — run the project headlessly and return parsed diagnostics.
- `godot_log_parser.py` — turn any Godot log text into structured diagnostics.
- `check_project` — dispatcher operation that statically loads every script,
  scene, shader, and resource and reports which ones fail to compile or load.

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
godot --headless --path /abs/project \
  --script /abs/skill/scripts/core/dispatcher.gd check_project '{}' 2>&1 \
  | python3 /abs/skill/scripts/debug/godot_log_parser.py -
```

`check_project` prints a JSON summary of which files failed to load; piping its
combined output through the parser gives line-level parse-error diagnostics. Scope
it to a subtree with `{"project_path":"scripts/enemies"}`.

## Capturing Output Correctly

- **Never use `-d` for automation.** The `-d` / `--debug` local debugger drops
  into an interactive `debug>` prompt and blocks forever waiting for stdin. Run
  **without** `-d`; Godot still prints full `SCRIPT ERROR` blocks with `at:`
  file:line and a GDScript backtrace. `run_project.py` enforces this and feeds
  the process `/dev/null` on stdin.
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

## Message → Cause → Fix

| Message contains | `category` | Likely cause | Fix |
| --- | --- | --- | --- |
| `null instance`, `on a null value` | `null_reference` | Node/object is null | Node accessed before it is in the tree, or a wrong/renamed NodePath. Use `@onready`, access in `_ready`, `get_node_or_null()` + guard, or fix the path. |
| `Invalid get index` / `Invalid set index` | `invalid_index` | Missing key/index or wrong base type | Verify the property/key name; ensure the collection or object is initialised and non-null. |
| `Invalid access to property or key` | `invalid_member` | Member does not exist on that object | Fix the member name or the object's type; the base may be null. |
| `nonexistent function`, `not found in base` | `missing_method` | Method typo, wrong node class, or renamed API | Correct the name, cast to the right type, or update to the 4.x API. |
| `nonexistent signal`, `Signal ... is not declared` | `signal` | Emitting/connecting an undeclared signal | Declare `signal name(...)`, fix the name, or target the correct node. Prefer the `connect_signal` operation for wiring. |
| `not declared in the current scope` | `undeclared_identifier` | Undeclared variable/const or missing preload | Declare it, fix the typo, or add the `preload`/`class_name`. |
| `Trying to assign value of type`, `Cannot convert` | `type_mismatch` | Typed var got an incompatible type | Convert the value or fix the declared type. |
| `Node not found` | `node_path` | `get_node()` path does not resolve | Fix the NodePath / `%UniqueName`, or use `get_node_or_null()` + guard. |
| `Failed to load resource`, `Resource file not found`, `Cannot open file` | `resource_load` | Missing/renamed resource or broken UID | Restore/fix the path; repair UID sidecars with the `get_uid` / `resave_resources` operations after a move. |
| `Failed to load script ... Parse error` | `resource_load` | A referenced script has a parse error | Fix the parse error in that script first. |
| `Parse Error: ...` | `parse_error` | GDScript syntax/identifier error | Fix the reported line; the script will not run until it compiles. |
| `Condition "..." is true` | `engine_assertion` | Engine precondition failed | A call made in the wrong state/order (often before the node is in the tree). Move the call or satisfy the precondition. |
| shader compile messages | `shader` | Shader failed to compile | Fix the reported shader line; match uniforms/varyings to their use. Shader compile errors usually surface only when running (not from `check_project`). |

## Notes For Godot 4.7

- Interactive debugging in the editor benefits from 4.7's Remote Inspector
  improvements (foldable groups/subgroups and readable enum names instead of raw
  integers), but headless automation relies on the same stdout/stderr the runner
  captures — no editor required.
- The runner and parser are version-tolerant: they key off the `SCRIPT ERROR:` /
  `ERROR:` / `WARNING:` / `Parse Error:` shapes, which are stable across Godot
  4.x, and were verified against `godot 4.7.stable`.
