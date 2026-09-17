# Playbooks — Follow The Numbered Steps Literally

Every playbook below is a finished recipe: copy each numbered block in order,
substituting only `/absolute/path/to/godot` (this skill's root) and
`/absolute/path/to/project` (the Godot project). Do not reorder the steps, do
not merge them, and do not paraphrase the JSON — the dispatcher rejects an
unknown key with the nearest valid name, so an invented field fails loudly and
writes nothing.

Every playbook ends with a **Verify** block. A playbook is not done until that
block runs clean. Verified on `godot 4.7.stable`.

## Route By Task

| Task | Playbook | Verification command |
| --- | --- | --- |
| Start a new 2D pixel-art game | [1. 2D pixel-art bootstrap](#1-2d-pixel-art-project-bootstrap) | `validate_project.py --pretty` → `"ok": true` |
| Player that runs and jumps | [2. 2D platformer player](#2-2d-platformer-player) | `run_scenario.py` → `"ok": true` |
| Player that walks in 8 directions | [3. Top-down player](#3-top-down-player) | `run_scenario.py` → `"ok": true` |
| Enemy that patrols and can be killed | [4. Enemy, damage, pooled bullets](#4-enemy-with-patrol-hitbox-hurtbox-and-health) | `run_scenario.py` → `"ok": true` |
| Build a level out of tiles | [5. Tile level from ASCII](#5-tile-level-from-ascii) | `inspect_tilemap` `"format":"text"` → rows match the ASCII |
| Title screen that is not gray | [6. Main menu with a theme](#6-main-menu-with-a-theme) | `run_scenario.py` → `ui_report` `findings=0` |
| Score / lives / health on screen | [7. HUD bound to GameManager](#7-hud-bound-to-gamemanager) | `run_scenario.py` → `ui_report` `findings=0` |
| Esc opens a pause menu | [8. Pause menu](#8-pause-menu) | `run_scenario.py` → `paused` assertion passes |
| Characters that talk | [9. Dialog box](#9-dialog-box) | `run_scenario.py` → `dump_tree` shows the typed text |
| Persist progress between runs | [10. Save and load](#10-save-and-load) | `run_project.py` → log shows `save ok` / `load ok` |
| Fade between scenes, music and SFX | [11. Scene transitions and audio](#11-scene-transitions-and-audio-manager) | `run_project.py` → `counts.errors == 0` |
| First-person 3D starter | [12. 3D FPS starter](#12-3d-fps-starter) | `run_scenario.py` → `"ok": true` |
| Any script you just wrote | every playbook's Verify block | `lint_project.py` → `counts.errors == 0` |
| An op whose parameters you forgot | — | `help '{"op":"add_node"}'` |
| A UI that might be stacked at (0,0) | 6, 7, 8, 9 | `run_scenario.py` `ui_report` `"fail_on":["any"]` |

## Driving Input In A Scenario

The two input step types are not interchangeable, and picking the wrong one is
why a scenario "does nothing" while the game works when a human plays it.

| Step | What it does | Reaches |
| --- | --- | --- |
| `{"type":"action","action_name":"jump","pressed":true}` | Calls `Input.action_press` / `action_release` — flips the action's polled state only | `Input.is_action_pressed` / `is_action_just_pressed` in `_process` / `_physics_process` |
| `{"type":"key","keycode":4194305,"pressed":true}` | Builds a real `InputEventKey` and feeds it through `Input.parse_input_event` | `_input`, `_unhandled_input`, `_gui_input`, **and** the polled state |

- Player controllers poll, so `action` steps drive them (Playbooks 2, 3, 12).
- Menus, pause toggles, dialog advance and `interact` prompts live in
  `_unhandled_input`, so they need `key` steps (Playbooks 8, 9). An `action`
  step there silently changes nothing.
- `key` has no `release_after`: send an explicit `"pressed": false` step, or the
  key stays held for the rest of the run.
- **Never time physics with `wait_frames` in a headless run.** `wait_frames`
  counts *process* frames, and headless spins those far faster than the fixed
  60 Hz physics tick — `wait_frames: 60` is a small fraction of a second of
  simulated falling. Use `wait_seconds` (a real timer) or `wait_until` whenever
  the thing being waited for is gravity, a `move_and_slide`, or a Tween.
- Match the field the action was bound with. Godot's built-in `ui_*` actions are
  bound by **`keycode`** (`ui_cancel` 4194305, `ui_accept` 4194309, `ui_down`
  4194322); actions this skill creates use `physical_keycode`, so drive those
  with `"physical_keycode"`. Setting the wrong one produces an event that
  matches no action at all.

## Template Index

`templates/gdscript/` holds GDScript that already compiles with zero warnings
under `check_project --debug --ignore-error-breaks`. **Copy a template instead
of writing a controller from memory.** Each file starts with a comment header
giving the exact scene tree it expects, the autoloads it needs, the input
actions to create, and a runnable `attach_script` call.

| Template | What it is | Playbook |
| --- | --- | --- |
| `templates/gdscript/player_platformer_2d.gd` | CharacterBody2D: gravity, coyote time, jump buffer, short hop | 2 |
| `templates/gdscript/player_topdown_2d.gd` | CharacterBody2D: 8-way movement, remembered facing | 3 |
| `templates/gdscript/player_fps_3d.gd` | CharacterBody3D: mouse look, sprint, jump, Esc releases the mouse | 12 |
| `templates/gdscript/state.gd` | `class_name State` — enter/exit/update/physics_update + transition signal | 4 |
| `templates/gdscript/state_machine.gd` | `class_name StateMachine` — children keyed by node name | 4 |
| `templates/gdscript/enemy_patrol_2d.gd` | Waypoint or raycast patrol with edge and wall checks | 4 |
| `templates/gdscript/health.gd` | `class_name Health` — max/current, damaged/died, invulnerability window | 4, 7 |
| `templates/gdscript/hitbox.gd` | `class_name Hitbox` — Area2D that deals damage, team-filtered | 4 |
| `templates/gdscript/hurtbox.gd` | `class_name Hurtbox` — Area2D that receives it and feeds Health | 4 |
| `templates/gdscript/object_pool.gd` | `class_name ObjectPool` — reuse PackedScene instances | 4 |
| `templates/gdscript/main_menu.gd` | Title screen: New Game / Continue / Settings / Quit, gamepad focus | 6 |
| `templates/gdscript/hud.gd` | Binds score, lives and a health bar to signals | 7 |
| `templates/gdscript/pause_menu.gd` | `ui_cancel` toggles `get_tree().paused`, process mode ALWAYS | 8 |
| `templates/gdscript/dialog_box.gd` | Typewriter over `Array[String]`, `ui_accept` advances | 9 |
| `templates/gdscript/interactable.gd` | `class_name Interactable` — Area2D prompt + `interact()` to override | 9 |
| `templates/gdscript/game_manager.gd` | Autoload `GameManager`: score, lives, `reset()` | 7, 10 |
| `templates/gdscript/save_manager.gd` | Autoload `SaveManager`: versioned JSON under `user://` | 10 |
| `templates/gdscript/scene_transition.gd` | Autoload `SceneTransition`: fade + `change_scene()` | 11 |
| `templates/gdscript/audio_manager.gd` | Autoload `AudioManager`: SFX pool + music crossfade | 11 |
| `templates/gdscript/camera_shake_2d.gd` | Camera2D trauma shake with decay | 2 |

Rules that apply to every template:

- Copy the file, then read its header. The header lists node names and types
  that must exist before the script runs; `$Sprite2D` on a scene with no
  `Sprite2D` is a null at runtime, not a compile error.
- Never rewrite a template's `@onready var x: Type = $Path` as `var x := $Path`.
  `$` is statically typed `Node`, so `:=` silently widens the type and every
  later member access goes unchecked (`references/gdscript_conventions.md`).
- After copying any template with a `class_name` (`state.gd`,
  `state_machine.gd`, `health.gd`, `hitbox.gd`, `hurtbox.gd`,
  `object_pool.gd`, `interactable.gd`), run
  `godot --headless --path /absolute/path/to/project --import` before
  validating, or every reference to that class reads as undeclared.

---

## 1. 2D Pixel-Art Project Bootstrap

**Goal.** A project that renders pixel art crisply, has a window size and
stretch mode chosen on purpose, a main scene, and the input actions the other
playbooks assume.

**Prerequisites.** An empty or new Godot project at
`/absolute/path/to/project` containing a `project.godot`.

### Step 1 — Create the folders

```bash
mkdir -p /absolute/path/to/project/scenes \
         /absolute/path/to/project/scripts \
         /absolute/path/to/project/art \
         /absolute/path/to/project/theme \
         /absolute/path/to/project/tilesets
```

### Step 2 — Window, stretch, and pixel filtering

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  project_batch '{
    "backup_path": "project.godot.bak",
    "actions": [
      {"type":"set_setting","name":"display/window/size/viewport_width","value":640},
      {"type":"set_setting","name":"display/window/size/viewport_height","value":360},
      {"type":"set_setting","name":"display/window/size/window_width_override","value":1280},
      {"type":"set_setting","name":"display/window/size/window_height_override","value":720},
      {"type":"set_setting","name":"display/window/stretch/mode","value":"canvas_items"},
      {"type":"set_setting","name":"display/window/stretch/aspect","value":"keep"},
      {"type":"set_setting","name":"rendering/textures/canvas_textures/default_texture_filter","value":0},
      {"type":"set_setting","name":"gui/theme/default_font_antialiasing","value":0},
      {"type":"set_setting","name":"gui/theme/default_font_hinting","value":0},
      {"type":"set_setting","name":"gui/theme/default_font_subpixel_positioning","value":0}
    ]
  }'
```

`stretch/mode` is `canvas_items` here so UI text stays smooth at any window
size. Use `"viewport"` plus `"scale_mode":"integer"` only when the UI is itself
drawn as pixel art — mixing the two makes text mush.

Do not hand-edit `project.godot` to add these. `ProjectSettings.save()`
rewrites the whole file, so a manual edit made in the same session is dropped.

### Step 3 — Input actions

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  project_batch '{
    "actions": [
      {"type":"add_input_action","action_name":"move_left","replace":true},
      {"type":"add_input_event","action_name":"move_left","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":65}}},
      {"type":"add_input_action","action_name":"move_right","replace":true},
      {"type":"add_input_event","action_name":"move_right","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":68}}},
      {"type":"add_input_action","action_name":"move_up","replace":true},
      {"type":"add_input_event","action_name":"move_up","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":87}}},
      {"type":"add_input_action","action_name":"move_down","replace":true},
      {"type":"add_input_event","action_name":"move_down","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":83}}},
      {"type":"add_input_action","action_name":"jump","replace":true},
      {"type":"add_input_event","action_name":"jump","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":32}}},
      {"type":"add_input_action","action_name":"interact","replace":true},
      {"type":"add_input_event","action_name":"interact","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":69}}}
    ]
  }'
```

Physical keycodes: `A` 65, `D` 68, `W` 87, `S` 83, `E` 69, Space 32, Shift
4194325, Esc 4194305. Use `physical_keycode` (layout-independent), not
`keycode`, or the game is unplayable on AZERTY.

### Step 4 — Main scene and layers

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/main.tscn",
    "create_if_missing": true,
    "root_node_type": "Node2D",
    "root_node_name": "Main",
    "actions": [
      {"type":"add_node","parent_node_path":"root","node_type":"Node2D","node_name":"World"},
      {"type":"add_node","parent_node_path":"root","node_type":"CanvasLayer","node_name":"UI"}
    ]
  }'
```

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  project_batch '{
    "actions": [
      {"type":"set_main_scene","scene_path":"res://scenes/main.tscn"},
      {"type":"set_layer_name","layer_type":"2d_physics","layer":1,"layer_name":"world"},
      {"type":"set_layer_name","layer_type":"2d_physics","layer":2,"layer_name":"player"},
      {"type":"set_layer_name","layer_type":"2d_physics","layer":3,"layer_name":"enemy"},
      {"type":"set_layer_name","layer_type":"2d_physics","layer":4,"layer_name":"hitbox"}
    ]
  }'
```

### Step 5 — Register the shared autoloads

Do this now, before any UI playbook. `main_menu.gd`, `pause_menu.gd` and
`hud.gd` name `GameManager`, `SaveManager` and `SceneTransition` directly, and a
script that names an unregistered autoload does not merely misbehave — it fails
to parse, so `attach_script` aborts with
`Property does not exist at attach_script.script_properties: …`.

```bash
cp /absolute/path/to/godot/templates/gdscript/game_manager.gd \
   /absolute/path/to/godot/templates/gdscript/save_manager.gd \
   /absolute/path/to/godot/templates/gdscript/scene_transition.gd \
   /absolute/path/to/project/scripts/
```

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  project_batch '{
    "actions": [
      {"type":"add_autoload","autoload_name":"GameManager","path":"res://scripts/game_manager.gd","singleton":true},
      {"type":"add_autoload","autoload_name":"SaveManager","path":"res://scripts/save_manager.gd","singleton":true},
      {"type":"add_autoload","autoload_name":"SceneTransition","path":"res://scripts/scene_transition.gd","singleton":true}
    ]
  }'
```

`AudioManager` is deliberately not here: it must be registered *after* the audio
buses exist (Playbook 11), or every player it builds falls back to Master and
the validation run carries a warning.

### Verify

```bash
python3 /absolute/path/to/godot/scripts/debug/lint_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/validate_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/run_project.py /absolute/path/to/project --quit-after 60 --timeout 60 --pretty
```

Expected: `lint_project.py` reports `"ok": true` with `counts.errors == 0`;
`validate_project.py` reports `"ok": true`, `counts.errors == 0`,
`counts.warnings == 0`, `static.failed_count == 0`; `run_project.py` reports
`"ok": true` and `"timed_out": false`.

---

## 2. 2D Platformer Player

**Goal.** A player scene that runs, jumps with coyote time and a jump buffer,
and is followed by a camera that can shake.

**Prerequisites.** Playbook 1 (needs `move_left`, `move_right`, `jump`).

### Step 1 — Copy the templates

```bash
cp /absolute/path/to/godot/templates/gdscript/player_platformer_2d.gd \
   /absolute/path/to/project/scripts/player_platformer_2d.gd
cp /absolute/path/to/godot/templates/gdscript/camera_shake_2d.gd \
   /absolute/path/to/project/scripts/camera_shake_2d.gd
```

### Step 2 — Build the player scene

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/player.tscn",
    "create_if_missing": true,
    "root_node_type": "CharacterBody2D",
    "root_node_name": "Player",
    "actions": [
      {"type":"configure_node","node_path":"root","properties":{"collision_layer":2,"collision_mask":1},"groups_add":["player"]},
      {"type":"add_node","parent_node_path":"root","node_type":"CollisionShape2D","node_name":"CollisionShape2D",
       "properties":{"shape":{"__resource_type":"CapsuleShape2D","properties":{"radius":6.0,"height":20.0}}}},
      {"type":"add_node","parent_node_path":"root","node_type":"Sprite2D","node_name":"Sprite2D"},
      {"type":"add_node","parent_node_path":"root","node_type":"Camera2D","node_name":"Camera2D",
       "properties":{"position_smoothing_enabled":true,"position_smoothing_speed":6.0}},
      {"type":"configure_node","node_path":"root/Camera2D","unique_name_in_owner":true},
      {"type":"attach_script","node_path":"root","script_path":"scripts/player_platformer_2d.gd",
       "script_properties":{"speed":220.0,"jump_velocity":-380.0,"coyote_time":0.12,"jump_buffer_time":0.12}},
      {"type":"attach_script","node_path":"root/Camera2D","script_path":"scripts/camera_shake_2d.gd",
       "script_properties":{"decay":4.0}}
    ]
  }'
```

The node names `Sprite2D` and `Camera2D` are not decoration: the template reads
`$Sprite2D`. Rename them and the script finds nothing.

`Camera2D` is marked unique **inside `player.tscn`**, so a script on the Player
root reaches the shake as `%Camera2D.add_trauma(0.5)`. A level script cannot —
unique names resolve only within their own scene, so from the level the path is
`$Player/Camera2D`.

### Step 3 — Ground to stand on and a spawn point

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/level_1.tscn",
    "create_if_missing": true,
    "root_node_type": "Node2D",
    "root_node_name": "Level",
    "actions": [
      {"type":"add_node","parent_node_path":"root","node_type":"StaticBody2D","node_name":"Ground",
       "properties":{"position":{"__type":"Vector2","x":0,"y":200},"collision_layer":1}},
      {"type":"add_node","parent_node_path":"root/Ground","node_type":"CollisionShape2D","node_name":"CollisionShape2D",
       "properties":{"shape":{"__resource_type":"RectangleShape2D","properties":{"size":{"__type":"Vector2","x":1200,"y":32}}}}},
      {"type":"instantiate_scene","parent_node_path":"root","instance_scene_path":"scenes/player.tscn","node_name":"Player",
       "properties":{"position":{"__type":"Vector2","x":0,"y":100}}}
    ]
  }'
```

### Step 4 — Point the project at the level

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  project_batch '{"actions":[{"type":"set_main_scene","scene_path":"res://scenes/level_1.tscn"}]}'
```

### Verify

Write the scenario, then run the four checks.

```json
{
  "scene_path": "res://scenes/level_1.tscn",
  "viewport_size": {"width": 640, "height": 360},
  "settle_frames": 4,
  "steps": [
    {"type": "wait_seconds", "seconds": 1.0},
    {"type": "assert", "assertion": "property", "node_path": "Player", "property": "position:y",
     "expected": 190.0, "operator": "less_or_equal"},
    {"type": "log_marker", "message": "gravity-ok"},
    {"type": "action", "action_name": "move_right", "pressed": true},
    {"type": "wait_seconds", "seconds": 0.4},
    {"type": "assert", "assertion": "property", "node_path": "Player", "property": "position:x",
     "expected": 5.0, "operator": "greater_than"},
    {"type": "action", "action_name": "move_right", "pressed": false},
    {"type": "action", "action_name": "jump", "pressed": true, "release_after": true},
    {"type": "wait_seconds", "seconds": 0.1},
    {"type": "assert", "assertion": "property", "node_path": "Player", "property": "velocity:y",
     "expected": 0.0, "operator": "less_than"},
    {"type": "dump_tree", "node_path": "/root", "properties": ["position", "velocity"], "max_depth": 4, "label": "after-jump"}
  ],
  "assertions": [
    {"assertion": "node_exists", "node_path": "Player/Camera2D"}
  ]
}
```

```bash
python3 /absolute/path/to/godot/scripts/debug/lint_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/validate_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/run_project.py /absolute/path/to/project --quit-after 120 --timeout 60 --pretty
python3 /absolute/path/to/godot/scripts/debug/run_scenario.py /absolute/path/to/project /absolute/path/to/player_scenario.json --pretty
```

Expected: `lint_project.py` `counts.errors == 0`; `validate_project.py`
`"ok": true` with `counts.errors == 0` and `counts.warnings == 0`;
`run_project.py` `"ok": true`; `run_scenario.py` `"ok": true` with every
assertion passing and the `after-jump` `dump_tree` showing a negative
`velocity:y` on `Player`.

---

## 3. Top-Down Player

**Goal.** A player that walks in eight directions at a constant speed, with the
diagonal not faster than the cardinals.

**Prerequisites.** Playbook 1 (needs `move_left`, `move_right`, `move_up`,
`move_down`).

### Step 1 — Copy the template

```bash
cp /absolute/path/to/godot/templates/gdscript/player_topdown_2d.gd \
   /absolute/path/to/project/scripts/player_topdown_2d.gd
```

### Step 2 — Build the player scene

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/player.tscn",
    "create_if_missing": true,
    "root_node_type": "CharacterBody2D",
    "root_node_name": "Player",
    "actions": [
      {"type":"configure_node","node_path":"root","properties":{"collision_layer":2,"collision_mask":1},"groups_add":["player"]},
      {"type":"add_node","parent_node_path":"root","node_type":"CollisionShape2D","node_name":"CollisionShape2D",
       "properties":{"shape":{"__resource_type":"CircleShape2D","properties":{"radius":7.0}}}},
      {"type":"add_node","parent_node_path":"root","node_type":"Sprite2D","node_name":"Sprite2D"},
      {"type":"add_node","parent_node_path":"root","node_type":"Camera2D","node_name":"Camera2D",
       "properties":{"position_smoothing_enabled":true,"position_smoothing_speed":8.0}},
      {"type":"attach_script","node_path":"root","script_path":"scripts/player_topdown_2d.gd",
       "script_properties":{"speed":180.0,"acceleration":1400.0,"friction":1600.0}}
    ]
  }'
```

Do not build eight-direction movement by adding the four axes yourself; the
template uses `Input.get_vector`, which normalises the diagonal for you.

### Step 3 — A room with walls

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/room.tscn",
    "create_if_missing": true,
    "root_node_type": "Node2D",
    "root_node_name": "Room",
    "actions": [
      {"type":"add_node","parent_node_path":"root","node_type":"StaticBody2D","node_name":"Walls","properties":{"collision_layer":1}},
      {"type":"add_node","parent_node_path":"root/Walls","node_type":"CollisionShape2D","node_name":"North",
       "properties":{"position":{"__type":"Vector2","x":0,"y":-160},
        "shape":{"__resource_type":"RectangleShape2D","properties":{"size":{"__type":"Vector2","x":640,"y":16}}}}},
      {"type":"add_node","parent_node_path":"root/Walls","node_type":"CollisionShape2D","node_name":"South",
       "properties":{"position":{"__type":"Vector2","x":0,"y":160},
        "shape":{"__resource_type":"RectangleShape2D","properties":{"size":{"__type":"Vector2","x":640,"y":16}}}}},
      {"type":"instantiate_scene","parent_node_path":"root","instance_scene_path":"scenes/player.tscn","node_name":"Player"}
    ]
  }'
```

### Verify

```json
{
  "scene_path": "res://scenes/room.tscn",
  "viewport_size": {"width": 640, "height": 360},
  "settle_frames": 4,
  "steps": [
    {"type": "action", "action_name": "move_right", "pressed": true},
    {"type": "action", "action_name": "move_down", "pressed": true},
    {"type": "wait_seconds", "seconds": 0.5},
    {"type": "assert", "assertion": "property", "node_path": "Player", "property": "position:x",
     "expected": 5.0, "operator": "greater_than"},
    {"type": "assert", "assertion": "property", "node_path": "Player", "property": "position:y",
     "expected": 5.0, "operator": "greater_than"},
    {"type": "action", "action_name": "move_right", "pressed": false},
    {"type": "action", "action_name": "move_down", "pressed": false},
    {"type": "wait_seconds", "seconds": 0.5},
    {"type": "assert", "assertion": "property", "node_path": "Player", "property": "velocity:x",
     "expected": 0.0, "operator": "approx", "tolerance": 1.0},
    {"type": "dump_tree", "node_path": "/root", "properties": ["position"], "max_depth": 4, "label": "settled"}
  ]
}
```

```bash
python3 /absolute/path/to/godot/scripts/debug/lint_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/validate_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/run_project.py /absolute/path/to/project res://scenes/room.tscn --quit-after 120 --timeout 60 --pretty
python3 /absolute/path/to/godot/scripts/debug/run_scenario.py /absolute/path/to/project /absolute/path/to/topdown_scenario.json --pretty
```

Expected: all four report `"ok": true`, with `counts.errors == 0` and
`counts.warnings == 0` from `validate_project.py`.

---

## 4. Enemy With Patrol, Hitbox, Hurtbox And Health

**Goal.** An enemy that walks a platform and turns at edges, takes damage from
the player's attack, dies at zero health, and a pooled bullet that carries the
hitbox.

**Prerequisites.** Playbook 1 and Playbook 2.

### Step 1 — Copy the templates

```bash
cp /absolute/path/to/godot/templates/gdscript/health.gd \
   /absolute/path/to/godot/templates/gdscript/hitbox.gd \
   /absolute/path/to/godot/templates/gdscript/hurtbox.gd \
   /absolute/path/to/godot/templates/gdscript/enemy_patrol_2d.gd \
   /absolute/path/to/godot/templates/gdscript/object_pool.gd \
   /absolute/path/to/godot/templates/gdscript/state.gd \
   /absolute/path/to/godot/templates/gdscript/state_machine.gd \
   /absolute/path/to/project/scripts/
```

### Step 2 — Rebuild the class-name cache

```bash
godot --headless --path /absolute/path/to/project --import
```

Run this now, not later. `health.gd`, `hitbox.gd`, `hurtbox.gd`,
`object_pool.gd`, `state.gd` and `state_machine.gd` all declare a `class_name`,
and a `--script` dispatcher run never rebuilds
`.godot/global_script_class_cache.cfg`. Skip it and the next step fails with
`Parse Error: Identifier "Health" not declared in the current scope`.

### Step 3 — Build the enemy scene

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/enemy.tscn",
    "create_if_missing": true,
    "root_node_type": "CharacterBody2D",
    "root_node_name": "Enemy",
    "actions": [
      {"type":"configure_node","node_path":"root","properties":{"collision_layer":4,"collision_mask":1},"groups_add":["enemy"]},
      {"type":"add_node","parent_node_path":"root","node_type":"CollisionShape2D","node_name":"CollisionShape2D",
       "properties":{"shape":{"__resource_type":"CapsuleShape2D","properties":{"radius":6.0,"height":18.0}}}},
      {"type":"add_node","parent_node_path":"root","node_type":"Sprite2D","node_name":"Sprite2D"},

      {"type":"add_node","parent_node_path":"root","node_type":"RayCast2D","node_name":"EdgeCheck",
       "properties":{"enabled":true,"position":{"__type":"Vector2","x":10,"y":0},"target_position":{"__type":"Vector2","x":0,"y":20},"collision_mask":1}},
      {"type":"add_node","parent_node_path":"root","node_type":"RayCast2D","node_name":"WallCheck",
       "properties":{"enabled":true,"target_position":{"__type":"Vector2","x":14,"y":0},"collision_mask":1}},

      {"type":"add_node","parent_node_path":"root","node_type":"Node","node_name":"Health"},
      {"type":"attach_script","node_path":"root/Health","script_path":"scripts/health.gd",
       "script_properties":{"max_health":3,"invulnerability_time":0.3}},

      {"type":"add_node","parent_node_path":"root","node_type":"Area2D","node_name":"Hurtbox",
       "properties":{"collision_layer":8,"collision_mask":8}},
      {"type":"add_node","parent_node_path":"root/Hurtbox","node_type":"CollisionShape2D","node_name":"CollisionShape2D",
       "properties":{"shape":{"__resource_type":"CapsuleShape2D","properties":{"radius":7.0,"height":20.0}}}},
      {"type":"attach_script","node_path":"root/Hurtbox","script_path":"scripts/hurtbox.gd",
       "script_properties":{"team":"enemy","health_path":{"__type":"NodePath","value":"../Health"}}},

      {"type":"attach_script","node_path":"root","script_path":"scripts/enemy_patrol_2d.gd",
       "script_properties":{"speed":60.0,"ping_pong":true}}
    ]
  }'
```

`health_path` is a `NodePath`, so it is written with the typed value
`{"__type":"NodePath","value":"../Health"}`. Do not try to hand the hurtbox the
Health *node* — a headless batch has no live tree to resolve a node reference
against, and the dispatcher rejects it with
`expected Health but got NodePath`.

### Step 4 — The bullet that carries the hitbox

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/bullet.tscn",
    "create_if_missing": true,
    "root_node_type": "Area2D",
    "root_node_name": "Bullet",
    "actions": [
      {"type":"configure_node","node_path":"root","properties":{"collision_layer":8,"collision_mask":8}},
      {"type":"add_node","parent_node_path":"root","node_type":"CollisionShape2D","node_name":"CollisionShape2D",
       "properties":{"shape":{"__resource_type":"CircleShape2D","properties":{"radius":3.0}}}},
      {"type":"attach_script","node_path":"root","script_path":"scripts/hitbox.gd",
       "script_properties":{"damage":1,"team":"player","one_shot":true}}
    ]
  }'
```

### Step 5 — Pool the bullets in the level

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/level_1.tscn",
    "actions": [
      {"type":"add_node","parent_node_path":"root","node_type":"Node","node_name":"BulletPool"},
      {"type":"configure_node","node_path":"root/BulletPool","unique_name_in_owner":true},
      {"type":"attach_script","node_path":"root/BulletPool","script_path":"scripts/object_pool.gd",
       "script_properties":{"scene":{"__resource":"res://scenes/bullet.tscn"},"initial_size":24,"grow":true}},
      {"type":"instantiate_scene","parent_node_path":"root","instance_scene_path":"scenes/enemy.tscn","node_name":"Enemy",
       "properties":{"position":{"__type":"Vector2","x":220,"y":150}}}
    ]
  }'
```

### Step 6 (optional) — Give the enemy states

The machine keys states by **node name**, so `request_transition(&"Chase")`
needs a child literally named `Chase` whose script `extends State`. A
`StateMachine` whose children have no `State` script pushes
`has no State children` on the first frame — write the state scripts first.

```bash
mkdir -p /absolute/path/to/project/scripts/states
cat > /absolute/path/to/project/scripts/states/patrol_state.gd <<'GDSCRIPT'
extends State

@export var chase_range: float = 120.0

func physics_update(_delta: float) -> void:
	var body := agent as Node2D
	if body == null:
		return
	var players: Array[Node] = get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		return
	var player := players[0] as Node2D
	if player != null and body.global_position.distance_to(player.global_position) < chase_range:
		request_transition(&"Chase")
GDSCRIPT
cat > /absolute/path/to/project/scripts/states/chase_state.gd <<'GDSCRIPT'
extends State

@export var give_up_range: float = 200.0

func physics_update(_delta: float) -> void:
	var body := agent as Node2D
	if body == null:
		return
	var players: Array[Node] = get_tree().get_nodes_in_group(&"player")
	if players.is_empty():
		request_transition(&"Patrol")
		return
	var player := players[0] as Node2D
	if player == null or body.global_position.distance_to(player.global_position) > give_up_range:
		request_transition(&"Patrol")
GDSCRIPT
```

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/enemy.tscn",
    "actions": [
      {"type":"add_node","parent_node_path":"root","node_type":"Node","node_name":"StateMachine"},
      {"type":"add_node","parent_node_path":"root/StateMachine","node_type":"Node","node_name":"Patrol"},
      {"type":"add_node","parent_node_path":"root/StateMachine","node_type":"Node","node_name":"Chase"},
      {"type":"attach_script","node_path":"root/StateMachine/Patrol","script_path":"scripts/states/patrol_state.gd"},
      {"type":"attach_script","node_path":"root/StateMachine/Chase","script_path":"scripts/states/chase_state.gd"},
      {"type":"attach_script","node_path":"root/StateMachine","script_path":"scripts/state_machine.gd"}
    ]
  }'
```

### Verify

```json
{
  "scene_path": "res://scenes/level_1.tscn",
  "viewport_size": {"width": 640, "height": 360},
  "settle_frames": 4,
  "steps": [
    {"type": "assert", "assertion": "property", "node_path": "Enemy/Health", "property": "current_health", "expected": 3},
    {"type": "log_marker", "message": "before-damage"},
    {"type": "wait_seconds", "seconds": 0.5},
    {"type": "assert", "assertion": "property", "node_path": "Enemy", "property": "velocity:x",
     "expected": 0.0, "operator": "not_equals"},
    {"type": "dump_tree", "node_path": "Enemy", "properties": ["position", "velocity"], "max_depth": 3, "label": "patrolling"}
  ],
  "assertions": [
    {"assertion": "node_exists", "node_path": "Enemy/Hurtbox"},
    {"assertion": "node_exists", "node_path": "BulletPool"}
  ]
}
```

```bash
godot --headless --path /absolute/path/to/project --import
python3 /absolute/path/to/godot/scripts/debug/lint_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/validate_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/run_project.py /absolute/path/to/project --quit-after 120 --timeout 60 --pretty
python3 /absolute/path/to/godot/scripts/debug/run_scenario.py /absolute/path/to/project /absolute/path/to/enemy_scenario.json --pretty
```

Expected: `lint_project.py` reports zero `node_ref` and zero `unique_name`
diagnostics; `validate_project.py` `"ok": true` with `counts.errors == 0` and
`counts.warnings == 0`; the scenario `"ok": true`, and the `patrolling`
`dump_tree` shows a non-zero `velocity:x` on `Enemy`.

---

## 5. Tile Level From ASCII

**Goal.** A solid, collidable tile level painted from an ASCII map, and read
back as text to prove the cells landed where the map said.

**Prerequisites.** A tile texture at `res://art/tiles.png`, imported.

### Step 1 — Import the texture

```bash
python3 /absolute/path/to/godot/scripts/import/import_project.py /absolute/path/to/project --pretty
```

### Step 2 — Build the TileSet with real collision

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  build_tileset '{
    "resource_path": "tilesets/world.tres",
    "tile_size": {"x": 16, "y": 16},
    "physics_layers": [{"collision_layer": 1, "collision_mask": 1}],
    "custom_data_layers": [{"name": "kind", "type": "string"}],
    "sources": [
      {"source_id": 0, "texture": "art/tiles.png", "tiles": "all",
       "tile_defaults": {"collision": "full_cell", "custom_data": {"kind": "solid"}}}
    ]
  }'
```

Without `"collision": "full_cell"` the tiles are decorative and the player falls
straight through them. That is the single most common tilemap mistake.

### Step 3 — Add the TileMapLayer node

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/level_1.tscn",
    "create_if_missing": true,
    "root_node_type": "Node2D",
    "root_node_name": "Level",
    "actions": [
      {"type":"add_node","parent_node_path":"root","node_type":"TileMapLayer","node_name":"Ground","index":0}
    ]
  }'
```

Use `TileMapLayer`, never the `TileMap` node — it has been deprecated since
Godot 4.3 and its editor tooling is gone.

### Step 4 — Paint the level from ASCII

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  paint_tilemap '{
    "scene_path": "scenes/level_1.tscn",
    "node_path": "root/Ground",
    "tile_set": "tilesets/world.tres",
    "clear": true,
    "ascii_map": {
      "origin": {"x": 0, "y": 0},
      "legend": {
        "#": {"source_id": 0, "atlas_coords": {"x": 0, "y": 0}},
        "=": {"source_id": 0, "atlas_coords": {"x": 1, "y": 0}},
        ".": null
      },
      "rows": [
        "................",
        "................",
        ".....===........",
        "................",
        "..===...........",
        "................",
        "################"
      ]
    }
  }'
```

One character per cell, every row the same length. `null` in the legend means
"leave this cell empty" — do not use a space for a solid tile, and do not pad
rows with tabs.

### Verify

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  inspect_tilemap '{"scene_path":"scenes/level_1.tscn","node_path":"root/Ground","format":"text"}'

python3 /absolute/path/to/godot/scripts/debug/lint_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/validate_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/run_project.py /absolute/path/to/project --quit-after 120 --timeout 60 --pretty
```

Expected, for the map above:

```
.....###........
................
..###...........
................
@@@@@@@@@@@@@@@@
```

`inspect_tilemap` reports what is **painted**, not what was typed, so read it
this way:

- `bounds` covers only painted cells — here `{"x":0,"y":2,"w":16,"h":5}`, because
  the two all-empty top rows of the input hold no cells. Add `2` to a printed
  row index to get the map row it came from.
- The glyphs are re-derived, not your legend: the returned `legend` maps each
  printed character back to `{source_id, atlas_coords}`. Compare shapes and the
  `counts` map (`{"@": 16, "#": 6}` here), not the characters.
- `cell_count` is the total painted (22 = 16 ground + 6 platform).

Also expected: `validate_project.py` `"ok": true`; `run_project.py`
`counts.errors == 0`. If the printed rows are all dots, the atlas coordinates
were never exposed — go back to `build_tileset` and check `"tiles": "all"`. If
`paint_tilemap` fails with `must resolve to a TileSet resource`, Step 1 was
skipped: an unimported texture makes the whole `.tres` fail to load.

---

## 6. Main Menu With A Theme

**Goal.** A title screen built out of containers, wearing a project-wide theme
with a visible focus state, navigable with a gamepad.

**Prerequisites.** Playbook 1 **including Step 5** — `main_menu.gd` names
`GameManager`, `SaveManager` and `SceneTransition`, and will not parse until all
three are registered autoloads.

### Step 1 — Author the theme

Use the complete game theme in `references/game_ui.md` ("Theme Doctrine")
verbatim, or start from this reduced version and grow it:

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  build_theme '{
    "resource_path": "theme/game.tres",
    "default_font_size": 12,
    "types": {
      "Button": {
        "styleboxes": {
          "normal":   {"bg_color":"#222d42","border_width":2,"border_color":"#3a4a68","corner_radius":4,"content_margin":8},
          "hover":    {"bg_color":"#2e3c58","border_width":2,"border_color":"#5c76a3","corner_radius":4,"content_margin":8},
          "pressed":  {"bg_color":"#161d2b","border_width":2,"border_color":"#ffb02e","corner_radius":4,"content_margin":8},
          "disabled": {"bg_color":"#161b26","border_width":2,"border_color":"#262f40","corner_radius":4,"content_margin":8},
          "focus":    {"draw_center":false,"border_width":2,"border_color":"#ffd479","corner_radius":4,"expand_margin":3}
        },
        "colors": {"font_color":"#e9eff8","font_hover_color":"#ffffff","font_pressed_color":"#ffb02e","font_disabled_color":"#5b6478"},
        "font_sizes": {"font_size":14}
      },
      "Label": {"colors": {"font_color":"#e9eff8"}, "font_sizes": {"font_size":14}},
      "PanelContainer": {
        "styleboxes": {"panel": {"bg_color":"#182031ee","border_width":2,"border_color":"#3a4a68","corner_radius":6,"content_margin":14}}
      }
    },
    "variations": {
      "TitleLabel":   {"base":"Label","colors":{"font_color":"#ffb02e"},"font_sizes":{"font_size":32}},
      "CaptionLabel": {"base":"Label","colors":{"font_color":"#8a9bb5"},"font_sizes":{"font_size":10}}
    }
  }'
```

The font sizes here are chosen for the 640x360 base viewport Playbook 1 set. A
`56px` title plus `18px` buttons overflows 360 pixels of height, and the
overflow shows up as an `offscreen` finding on the footer — size the type to the
**base viewport**, not to the window.

Never set `"focus": "empty"`. A menu whose focus state is invisible cannot be
navigated with a gamepad or keyboard, which is most players of a game menu.

### Step 2 — Wire the theme project-wide

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  project_batch '{"actions":[{"type":"set_setting","name":"gui/theme/custom","value":"res://theme/game.tres"}]}'
```

### Step 3 — Build the menu, containers first

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/main_menu.tscn",
    "create_if_missing": true,
    "root_node_type": "Control",
    "root_node_name": "MainMenu",
    "actions": [
      {"type":"configure_control","node_path":"root","layout_preset":"FULL_RECT"},
      {"type":"add_node","parent_node_path":"root","node_type":"ColorRect","node_name":"Background",
       "properties":{"color":{"__type":"Color","r":0.05,"g":0.063,"b":0.09,"a":1},"mouse_filter":2}},
      {"type":"configure_control","node_path":"root/Background","layout_preset":"FULL_RECT"},

      {"type":"add_node","parent_node_path":"root","node_type":"MarginContainer","node_name":"Frame"},
      {"type":"configure_control","node_path":"root/Frame","layout_preset":"FULL_RECT",
       "theme_overrides":{"constants":{"margin_left":24,"margin_right":24,"margin_top":20,"margin_bottom":20}}},

      {"type":"add_node","parent_node_path":"root/Frame","node_type":"VBoxContainer","node_name":"Column"},
      {"type":"configure_control","node_path":"root/Frame/Column","theme_overrides":{"constants":{"separation":16}}},

      {"type":"add_node","parent_node_path":"root/Frame/Column","node_type":"Label","node_name":"Title",
       "properties":{"text":"EMBER HOLLOW","horizontal_alignment":1,"theme_type_variation":"TitleLabel"}},

      {"type":"add_node","parent_node_path":"root/Frame/Column","node_type":"CenterContainer","node_name":"MenuSlot"},
      {"type":"configure_control","node_path":"root/Frame/Column/MenuSlot","size_flags_vertical":"EXPAND_FILL"},
      {"type":"add_node","parent_node_path":"root/Frame/Column/MenuSlot","node_type":"VBoxContainer","node_name":"Menu"},
      {"type":"configure_control","node_path":"root/Frame/Column/MenuSlot/Menu",
       "custom_minimum_size":{"__type":"Vector2","x":240,"y":0},
       "theme_overrides":{"constants":{"separation":8}}},

      {"type":"add_node","parent_node_path":"root/Frame/Column/MenuSlot/Menu","node_type":"Button","node_name":"NewGameButton","properties":{"text":"New Game"}},
      {"type":"add_node","parent_node_path":"root/Frame/Column/MenuSlot/Menu","node_type":"Button","node_name":"ContinueButton","properties":{"text":"Continue"}},
      {"type":"add_node","parent_node_path":"root/Frame/Column/MenuSlot/Menu","node_type":"Button","node_name":"SettingsButton","properties":{"text":"Settings"}},
      {"type":"add_node","parent_node_path":"root/Frame/Column/MenuSlot/Menu","node_type":"Button","node_name":"QuitButton","properties":{"text":"Quit"}},

      {"type":"configure_node","node_path":"root/Frame/Column/MenuSlot/Menu/NewGameButton","unique_name_in_owner":true},
      {"type":"configure_node","node_path":"root/Frame/Column/MenuSlot/Menu/ContinueButton","unique_name_in_owner":true},
      {"type":"configure_node","node_path":"root/Frame/Column/MenuSlot/Menu/SettingsButton","unique_name_in_owner":true},
      {"type":"configure_node","node_path":"root/Frame/Column/MenuSlot/Menu/QuitButton","unique_name_in_owner":true},

      {"type":"add_node","parent_node_path":"root/Frame/Column","node_type":"Label","node_name":"Footer",
       "properties":{"text":"v0.1.0","horizontal_alignment":1,"theme_type_variation":"CaptionLabel"}}
    ]
  }'
```

Set `layout_preset` only on the root and the full-rect background. Never set
`position`, `size` or `offset_*` on a child of a `Container` — the container
overwrites them on the next sort, which is exactly how every control ends up
stacked at (0, 0).

### Step 4 — Attach the controller

```bash
cp /absolute/path/to/godot/templates/gdscript/main_menu.gd \
   /absolute/path/to/project/scripts/main_menu.gd
```

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/main_menu.tscn",
    "actions": [
      {"type":"attach_script","node_path":"root","script_path":"scripts/main_menu.gd",
       "script_properties":{"new_game_scene":"res://scenes/level_1.tscn","save_slot":0}}
    ]
  }'
```

### Verify

```json
{
  "scene_path": "res://scenes/main_menu.tscn",
  "viewport_size": {"width": 640, "height": 360},
  "settle_frames": 4,
  "steps": [
    {"type": "ui_report", "label": "menu-base", "ascii": true,
     "fail_on": ["overlap", "zero_size", "offscreen"]},
    {"type": "assert", "assertion": "property",
     "node_path": "Frame/Column/MenuSlot/Menu/NewGameButton", "property": "size:x",
     "expected": 240.0, "operator": "approx", "tolerance": 1.0},
    {"type": "key", "keycode": 4194322, "pressed": true},
    {"type": "key", "keycode": 4194322, "pressed": false},
    {"type": "wait_frames", "frames": 2},
    {"type": "dump_tree", "node_path": ".", "properties": ["visible", "disabled"], "max_depth": 6, "label": "menu-tree"}
  ],
  "assertions": [
    {"assertion": "node_exists", "node_path": "Frame/Column/MenuSlot/Menu/QuitButton"}
  ]
}
```

```bash
python3 /absolute/path/to/godot/scripts/debug/lint_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/validate_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/run_scenario.py /absolute/path/to/project /absolute/path/to/menu_scenario.json --pretty
```

Expected: `validate_project.py` `"ok": true`; `run_scenario.py` `"ok": true`
with the `menu-base` report showing `findings=0`, `zero_size=0`, `offscreen=0`,
`overlap=0`, and its `ascii` art placing the title above the button column.

A second `viewport_size` is **not** a second layout here. Playbook 1 set
`display/window/stretch/mode` to `canvas_items`, so the UI always lays out
against the project's base viewport (640x360) whatever the window size is; the
scenario's `viewport_size` only resizes the window. Re-run at a second size only
in a project whose stretch mode is `disabled`.

---

## 7. HUD Bound To GameManager

**Goal.** Score, lives and a health bar that update from signals, never from a
`_process` poll.

**Prerequisites.** Playbook 1 **including Step 5**, Playbook 2 (a player),
Playbook 4 (`health.gd`).

### Step 1 — Copy and register the autoload

Playbook 1 Step 5 already copied and registered `GameManager`; re-running these
two blocks is harmless (`add_autoload` overwrites the same key).

```bash
cp /absolute/path/to/godot/templates/gdscript/game_manager.gd \
   /absolute/path/to/project/scripts/game_manager.gd
cp /absolute/path/to/godot/templates/gdscript/hud.gd \
   /absolute/path/to/project/scripts/hud.gd
```

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  project_batch '{
    "actions": [
      {"type":"add_autoload","autoload_name":"GameManager","path":"res://scripts/game_manager.gd","singleton":true}
    ]
  }'
```

Never add `class_name GameManager` to that file. A `class_name` matching an
autoload fails with `Class "GameManager" hides an autoload singleton`.

### Step 2 — Build the HUD scene

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/hud.tscn",
    "create_if_missing": true,
    "root_node_type": "CanvasLayer",
    "root_node_name": "HUD",
    "actions": [
      {"type":"configure_node","node_path":"root","properties":{"layer":1}},

      {"type":"add_node","parent_node_path":"root","node_type":"MarginContainer","node_name":"TopLeft","properties":{"mouse_filter":2}},
      {"type":"configure_control","node_path":"root/TopLeft","layout_preset":"TOP_LEFT",
       "theme_overrides":{"constants":{"margin_left":24,"margin_top":20,"margin_right":0,"margin_bottom":0}}},
      {"type":"add_node","parent_node_path":"root/TopLeft","node_type":"VBoxContainer","node_name":"Vitals","properties":{"mouse_filter":2}},
      {"type":"add_node","parent_node_path":"root/TopLeft/Vitals","node_type":"ProgressBar","node_name":"HealthBar",
       "properties":{"max_value":3,"value":3,"show_percentage":false}},
      {"type":"configure_control","node_path":"root/TopLeft/Vitals/HealthBar","custom_minimum_size":{"__type":"Vector2","x":220,"y":16}},
      {"type":"add_node","parent_node_path":"root/TopLeft/Vitals","node_type":"Label","node_name":"LivesLabel","properties":{"text":"LIVES 3"}},

      {"type":"add_node","parent_node_path":"root","node_type":"MarginContainer","node_name":"TopRight",
       "properties":{"mouse_filter":2,"grow_horizontal":0,"grow_vertical":1}},
      {"type":"configure_control","node_path":"root/TopRight","layout_preset":"TOP_RIGHT",
       "theme_overrides":{"constants":{"margin_right":24,"margin_top":20,"margin_left":0,"margin_bottom":0}}},
      {"type":"add_node","parent_node_path":"root/TopRight","node_type":"Label","node_name":"ScoreLabel","properties":{"text":"SCORE 000000"}},

      {"type":"configure_node","node_path":"root/TopLeft/Vitals/HealthBar","unique_name_in_owner":true},
      {"type":"configure_node","node_path":"root/TopLeft/Vitals/LivesLabel","unique_name_in_owner":true},
      {"type":"configure_node","node_path":"root/TopRight/ScoreLabel","unique_name_in_owner":true},

      {"type":"attach_script","node_path":"root","script_path":"scripts/hud.gd"}
    ]
  }'
```

A HUD cluster anchored to a far edge must grow inward: `grow_horizontal: 0`
(BEGIN) on the `TOP_RIGHT` cluster, or it grows off-screen to the right.

### Step 3 — Put the HUD in the level and bind the health bar

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/level_1.tscn",
    "actions": [
      {"type":"instantiate_scene","parent_node_path":"root","instance_scene_path":"scenes/hud.tscn","node_name":"HUD"},
      {"type":"configure_node","node_path":"root/HUD","unique_name_in_owner":true}
    ]
  }'
```

Bind the bar from the level script (`%HUD.bind_health($Player/Health)`), or from
the player's own `_ready`. `hud.gd` does not search for a Health node — a HUD
that reaches into the level by path breaks the first time the level changes.

### Verify

```json
{
  "scene_path": "res://scenes/level_1.tscn",
  "viewport_size": {"width": 1280, "height": 720},
  "settle_frames": 4,
  "steps": [
    {"type": "ui_report", "label": "hud", "node_path": "HUD", "ascii": true, "fail_on": ["any"]},
    {"type": "assert", "assertion": "property", "node_path": "HUD/TopRight/ScoreLabel",
     "property": "text", "expected": "SCORE 000000"},
    {"type": "log_marker", "message": "hud-initial"},
    {"type": "dump_tree", "node_path": "HUD", "properties": ["text", "value", "max_value"], "max_depth": 5, "label": "hud-values"}
  ],
  "assertions": [
    {"assertion": "node_exists", "node_path": "HUD/TopLeft/Vitals/HealthBar"}
  ]
}
```

```bash
python3 /absolute/path/to/godot/scripts/debug/lint_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/validate_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/run_project.py /absolute/path/to/project --quit-after 120 --timeout 60 --pretty
python3 /absolute/path/to/godot/scripts/debug/run_scenario.py /absolute/path/to/project /absolute/path/to/hud_scenario.json --pretty
```

Expected: `lint_project.py` zero `unique_name` diagnostics; the `hud` report
`findings=0`; the `hud-values` `dump_tree` shows `ScoreLabel.text` =
`SCORE 000000` and `HealthBar.max_value` = `3`.

---

## 8. Pause Menu

**Goal.** `Esc` pauses the game and opens an overlay whose buttons still work
while the tree is paused.

**Prerequisites.** Playbook 1 **including Step 5** (`pause_menu.gd` names
`SceneTransition`), Playbook 6 for the theme.

### Step 1 — Copy the template

```bash
cp /absolute/path/to/godot/templates/gdscript/pause_menu.gd \
   /absolute/path/to/project/scripts/pause_menu.gd
```

### Step 2 — Build the overlay

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/pause_menu.tscn",
    "create_if_missing": true,
    "root_node_type": "CanvasLayer",
    "root_node_name": "PauseMenu",
    "actions": [
      {"type":"configure_node","node_path":"root","properties":{"layer":10,"process_mode":3}},

      {"type":"add_node","parent_node_path":"root","node_type":"Control","node_name":"PauseRoot"},
      {"type":"configure_control","node_path":"root/PauseRoot","layout_preset":"FULL_RECT"},
      {"type":"configure_node","node_path":"root/PauseRoot","unique_name_in_owner":true},

      {"type":"add_node","parent_node_path":"root/PauseRoot","node_type":"ColorRect","node_name":"Dim",
       "properties":{"color":{"__type":"Color","r":0,"g":0,"b":0,"a":0.66},"mouse_filter":2}},
      {"type":"configure_control","node_path":"root/PauseRoot/Dim","layout_preset":"FULL_RECT"},

      {"type":"add_node","parent_node_path":"root/PauseRoot","node_type":"CenterContainer","node_name":"Center"},
      {"type":"configure_control","node_path":"root/PauseRoot/Center","layout_preset":"FULL_RECT"},
      {"type":"add_node","parent_node_path":"root/PauseRoot/Center","node_type":"PanelContainer","node_name":"Dialog"},
      {"type":"configure_control","node_path":"root/PauseRoot/Center/Dialog","custom_minimum_size":{"__type":"Vector2","x":420,"y":0}},
      {"type":"add_node","parent_node_path":"root/PauseRoot/Center/Dialog","node_type":"VBoxContainer","node_name":"Body"},
      {"type":"configure_control","node_path":"root/PauseRoot/Center/Dialog/Body","theme_overrides":{"constants":{"separation":18}}},

      {"type":"add_node","parent_node_path":"root/PauseRoot/Center/Dialog/Body","node_type":"Label","node_name":"Heading",
       "properties":{"text":"PAUSED","horizontal_alignment":1}},
      {"type":"add_node","parent_node_path":"root/PauseRoot/Center/Dialog/Body","node_type":"Button","node_name":"ResumeButton","properties":{"text":"Resume"}},
      {"type":"add_node","parent_node_path":"root/PauseRoot/Center/Dialog/Body","node_type":"Button","node_name":"QuitButton","properties":{"text":"Quit To Title"}},
      {"type":"configure_node","node_path":"root/PauseRoot/Center/Dialog/Body/ResumeButton","unique_name_in_owner":true},
      {"type":"configure_node","node_path":"root/PauseRoot/Center/Dialog/Body/QuitButton","unique_name_in_owner":true},

      {"type":"attach_script","node_path":"root","script_path":"scripts/pause_menu.gd",
       "script_properties":{"title_scene":"res://scenes/main_menu.tscn"}}
    ]
  }'
```

`process_mode: 3` is `PROCESS_MODE_ALWAYS`. Set it on the `CanvasLayer` root, in
the scene, as well as in the script — a pause menu that inherits the default
process mode freezes with the rest of the tree the instant it pauses it.

### Step 3 — Add it to the level

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/level_1.tscn",
    "actions": [
      {"type":"instantiate_scene","parent_node_path":"root","instance_scene_path":"scenes/pause_menu.tscn","node_name":"PauseMenu"}
    ]
  }'
```

### Verify

```json
{
  "scene_path": "res://scenes/level_1.tscn",
  "viewport_size": {"width": 1280, "height": 720},
  "settle_frames": 4,
  "steps": [
    {"type": "assert", "assertion": "property", "node_path": "PauseMenu/PauseRoot", "property": "visible", "expected": false},
    {"type": "key", "keycode": 4194305, "pressed": true},
    {"type": "key", "keycode": 4194305, "pressed": false},
    {"type": "wait_until", "node_path": "PauseMenu/PauseRoot", "property": "visible", "expected": true, "timeout_seconds": 2},
    {"type": "ui_report", "label": "paused", "node_path": "PauseMenu", "ascii": true, "fail_on": ["any"]},
    {"type": "key", "keycode": 4194305, "pressed": true},
    {"type": "key", "keycode": 4194305, "pressed": false},
    {"type": "wait_until", "node_path": "PauseMenu/PauseRoot", "property": "visible", "expected": false, "timeout_seconds": 2},
    {"type": "log_marker", "message": "unpaused"}
  ]
}
```

```bash
python3 /absolute/path/to/godot/scripts/debug/lint_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/validate_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/run_scenario.py /absolute/path/to/project /absolute/path/to/pause_scenario.json --log-file /tmp/pause.log --pretty
```

Expected: `run_scenario.py` `"ok": true`; both `wait_until` steps resolve inside
the timeout (that is the proof the menu still responds while paused); the
`paused` report `findings=0`.

`ui_cancel` is driven with `key` steps, not an `action` step. See
[Driving input in a scenario](#driving-input-in-a-scenario) — an `action` step
would leave `_unhandled_input` untouched and the menu would never open.

---

## 9. Dialog Box

**Goal.** An NPC the player walks up to and talks to, with typewriter text
advanced by `ui_accept`.

**Prerequisites.** Playbook 1 (needs `interact`), Playbook 6 (a theme),
Playbook 3 or 2 (a player in the group `player`).

### Step 1 — Copy the templates

```bash
cp /absolute/path/to/godot/templates/gdscript/dialog_box.gd \
   /absolute/path/to/godot/templates/gdscript/interactable.gd \
   /absolute/path/to/project/scripts/
godot --headless --path /absolute/path/to/project --import
```

### Step 2 — Build the dialog box

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/dialog_box.tscn",
    "create_if_missing": true,
    "root_node_type": "CanvasLayer",
    "root_node_name": "DialogBox",
    "actions": [
      {"type":"configure_node","node_path":"root","properties":{"layer":5}},

      {"type":"add_node","parent_node_path":"root","node_type":"Control","node_name":"DialogRoot"},
      {"type":"configure_control","node_path":"root/DialogRoot","layout_preset":"FULL_RECT"},
      {"type":"configure_node","node_path":"root/DialogRoot","unique_name_in_owner":true},

      {"type":"add_node","parent_node_path":"root/DialogRoot","node_type":"MarginContainer","node_name":"Anchor",
       "properties":{"grow_vertical":0,"mouse_filter":2}},
      {"type":"configure_control","node_path":"root/DialogRoot/Anchor","layout_preset":"BOTTOM_WIDE",
       "theme_overrides":{"constants":{"margin_left":40,"margin_right":40,"margin_top":0,"margin_bottom":32}}},

      {"type":"add_node","parent_node_path":"root/DialogRoot/Anchor","node_type":"PanelContainer","node_name":"Box"},
      {"type":"add_node","parent_node_path":"root/DialogRoot/Anchor/Box","node_type":"VBoxContainer","node_name":"Body"},
      {"type":"configure_control","node_path":"root/DialogRoot/Anchor/Box/Body","theme_overrides":{"constants":{"separation":10}}},

      {"type":"add_node","parent_node_path":"root/DialogRoot/Anchor/Box/Body","node_type":"Label","node_name":"SpeakerLabel",
       "properties":{"text":"NPC"}},
      {"type":"add_node","parent_node_path":"root/DialogRoot/Anchor/Box/Body","node_type":"RichTextLabel","node_name":"BodyLabel",
       "properties":{"bbcode_enabled":true,"fit_content":true,"scroll_active":false,"autowrap_mode":3,"text":"..."}},
      {"type":"configure_control","node_path":"root/DialogRoot/Anchor/Box/Body/BodyLabel",
       "custom_minimum_size":{"__type":"Vector2","x":0,"y":96},"size_flags_horizontal":"EXPAND_FILL"},

      {"type":"configure_node","node_path":"root/DialogRoot/Anchor/Box/Body/SpeakerLabel","unique_name_in_owner":true},
      {"type":"configure_node","node_path":"root/DialogRoot/Anchor/Box/Body/BodyLabel","unique_name_in_owner":true},

      {"type":"attach_script","node_path":"root","script_path":"scripts/dialog_box.gd",
       "script_properties":{"characters_per_second":40.0}}
    ]
  }'
```

Reserve the text height with `custom_minimum_size.y`, not by measuring the
English string. A translated line 40% longer must not resize the panel between
lines.

### Step 3 — Build the NPC that opens it

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/npc.tscn",
    "create_if_missing": true,
    "root_node_type": "Area2D",
    "root_node_name": "Npc",
    "actions": [
      {"type":"configure_node","node_path":"root","properties":{"collision_layer":1,"collision_mask":2,"monitoring":true}},
      {"type":"add_node","parent_node_path":"root","node_type":"CollisionShape2D","node_name":"CollisionShape2D",
       "properties":{"shape":{"__resource_type":"CircleShape2D","properties":{"radius":48.0}}}},
      {"type":"add_node","parent_node_path":"root","node_type":"Sprite2D","node_name":"Sprite2D"},
      {"type":"add_node","parent_node_path":"root","node_type":"Label","node_name":"Prompt",
       "properties":{"text":"Talk","position":{"__type":"Vector2","x":-16,"y":-40}}},
      {"type":"attach_script","node_path":"root","script_path":"scripts/interactable.gd",
       "script_properties":{"prompt_text":"Talk","one_shot":false}}
    ]
  }'
```

The player body must be in the group `player` (`groups_add: ["player"]` in
Playbook 2 / 3) — `interactable.gd` ignores every other body on purpose.

### Step 4 — Write the level script that answers the signal

`connect_signal` verifies that the target node really has the method and aborts
the batch otherwise (`Target node does not have method: _on_npc_interacted`), so
the script has to exist and be attached **before** the connection is made.

```bash
cat > /absolute/path/to/project/scripts/level_1.gd <<'GDSCRIPT'
extends Node2D

@onready var _dialog: Node = %DialogBox

var _lines: Array[String] = ["Hello.", "Mind the lanterns."]

func _on_npc_interacted(_by: Node2D) -> void:
	_dialog.call(&"show_lines", _lines, "Marrow")
GDSCRIPT
```

`_lines` is annotated `Array[String]` because `show_lines` takes one; passing a
bare `[...]` literal raises a runtime type error at the call.

### Step 5 — Instantiate both scenes and connect the NPC

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/level_1.tscn",
    "actions": [
      {"type":"instantiate_scene","parent_node_path":"root","instance_scene_path":"scenes/dialog_box.tscn","node_name":"DialogBox"},
      {"type":"configure_node","node_path":"root/DialogBox","unique_name_in_owner":true},
      {"type":"instantiate_scene","parent_node_path":"root","instance_scene_path":"scenes/npc.tscn","node_name":"Npc",
       "properties":{"position":{"__type":"Vector2","x":0,"y":170}}},
      {"type":"attach_script","node_path":"root","script_path":"scripts/level_1.gd"},
      {"type":"connect_signal","node_path":"root/Npc","signal_name":"interacted",
       "target_node_path":"root","method_name":"_on_npc_interacted"}
    ]
  }'
```

### Verify

```json
{
  "scene_path": "res://scenes/level_1.tscn",
  "viewport_size": {"width": 1280, "height": 720},
  "settle_frames": 4,
  "steps": [
    {"type": "assert", "assertion": "property", "node_path": "DialogBox/DialogRoot", "property": "visible", "expected": false},
    {"type": "wait_seconds", "seconds": 1.0},
    {"type": "key", "physical_keycode": 69, "pressed": true},
    {"type": "key", "physical_keycode": 69, "pressed": false},
    {"type": "wait_until", "node_path": "DialogBox/DialogRoot", "property": "visible", "expected": true, "timeout_seconds": 2},
    {"type": "ui_report", "label": "dialog-open", "node_path": "DialogBox", "ascii": true, "fail_on": ["any"]},
    {"type": "wait_seconds", "seconds": 1.0},
    {"type": "dump_tree", "node_path": "DialogBox", "properties": ["text", "visible_characters", "visible"], "max_depth": 6, "label": "typed"},
    {"type": "key", "keycode": 4194309, "pressed": true},
    {"type": "key", "keycode": 4194309, "pressed": false},
    {"type": "wait_frames", "frames": 4}
  ]
}
```

```bash
python3 /absolute/path/to/godot/scripts/debug/lint_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/validate_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/run_scenario.py /absolute/path/to/project /absolute/path/to/dialog_scenario.json --pretty
```

Expected: `run_scenario.py` `"ok": true`; the `dialog-open` report
`findings=0`; the `typed` `dump_tree` shows `BodyLabel.text` holding the first
line and `visible_characters` greater than 0.

The `wait_frames 40` is not padding: the player has to land and settle inside
the NPC's Area2D before `interact` can do anything. `interact` was created with
`physical_keycode`, so the `key` step uses `physical_keycode`; `ui_accept` is a
built-in bound by `keycode`, so it uses `keycode`.

---

## 10. Save And Load

**Goal.** Progress that survives quitting the game, stored as versioned JSON
that cannot crash the next launch when it is missing or corrupt.

**Prerequisites.** Playbook 1 Step 5 and Playbook 7 (`GameManager`).

### Step 1 — Copy and register the autoload

```bash
cp /absolute/path/to/godot/templates/gdscript/save_manager.gd \
   /absolute/path/to/project/scripts/save_manager.gd
```

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  project_batch '{
    "actions": [
      {"type":"add_autoload","autoload_name":"SaveManager","path":"res://scripts/save_manager.gd","singleton":true}
    ]
  }'
```

### Step 2 — Save and load from game code

Write this into whatever script owns the moment (a checkpoint, a pause menu
button, the level's `_ready`):

```gdscript
func save_progress() -> void:
	var payload: Dictionary = GameManager.to_save_data()
	payload["scene_path"] = get_tree().current_scene.scene_file_path
	if SaveManager.save_game(payload, 0):
		print("[SAVE] save ok slot=0")

func load_progress() -> void:
	if not SaveManager.has_save(0):
		print("[SAVE] no save")
		return
	var data: Dictionary = SaveManager.load_game(0)
	GameManager.from_save_data(data)
	print("[SAVE] load ok score=%d" % GameManager.score)
```

Never write `var data := SaveManager.load_game(0)` when the value comes back
from `JSON.parse_string` inside — always annotate. `references/gdscript_conventions.md`
explains why `:=` from a `Variant` is a boot-blocking parse error, not a nag.

### Step 3 — Verify the failure paths on purpose

Corrupt a slot and confirm the game still starts:

```bash
mkdir -p "$HOME/Library/Application Support/Godot/app_userdata/YOUR_PROJECT_NAME/saves"
printf 'not json at all' > "$HOME/Library/Application Support/Godot/app_userdata/YOUR_PROJECT_NAME/saves/slot_0.json"
```

(On Linux the path is `~/.local/share/godot/app_userdata/YOUR_PROJECT_NAME/`.)

### Verify

```bash
python3 /absolute/path/to/godot/scripts/debug/lint_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/validate_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/run_project.py /absolute/path/to/project \
  --quit-after 180 --timeout 60 --log-file /tmp/save.log --pretty
python3 /absolute/path/to/godot/scripts/debug/godot_log_parser.py /tmp/save.log --pretty
grep '\[SAVE\]' /tmp/save.log
```

Expected: `validate_project.py` `"ok": true` with `counts.warnings == 0`;
`run_project.py` `"ok": true` and `counts.errors == 0` on a clean slot; with the
corrupt slot in place the run still reports `"ok": true` at the boot level while
the log carries exactly one `SaveManager: … is not a JSON object` error and the
game keeps running — a save that fails must never take the launch with it.
`grep` shows `save ok` and `load ok`.

---

## 11. Scene Transitions And Audio Manager

**Goal.** Scene changes that fade instead of cutting, music that crossfades, and
SFX that never cut each other off — all reachable from any scene.

**Prerequisites.** Playbook 1.

### Step 1 — Create the audio buses first

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  setup_audio_buses '{
    "buses": [
      {"name": "Master", "volume_db": 0.0},
      {"name": "Music", "send": "Master", "volume_db": -6.0},
      {"name": "SFX", "send": "Master", "volume_db": -3.0},
      {"name": "UI", "send": "SFX", "volume_db": -4.0}
    ],
    "save_path": "audio/default_bus_layout.tres",
    "set_project_setting": true
  }'
```

Do this **before** registering `AudioManager`. Assigning a player to a bus that
does not exist silently routes it to Master; the template warns about it, and
the warning is what a clean validation run must not contain.

### Step 2 — Copy and register both autoloads

```bash
cp /absolute/path/to/godot/templates/gdscript/scene_transition.gd \
   /absolute/path/to/godot/templates/gdscript/audio_manager.gd \
   /absolute/path/to/project/scripts/
```

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  project_batch '{
    "actions": [
      {"type":"add_autoload","autoload_name":"SceneTransition","path":"res://scripts/scene_transition.gd","singleton":true},
      {"type":"add_autoload","autoload_name":"AudioManager","path":"res://scripts/audio_manager.gd","singleton":true}
    ]
  }'
```

### Step 3 — Call them

```gdscript
func _on_start_pressed() -> void:
	AudioManager.play_sfx(preload("res://audio/ui_confirm.wav"))
	await SceneTransition.change_scene("res://scenes/level_1.tscn")
```

`change_scene` is a coroutine — call it with `await`, from a function that is
allowed to await. Calling `get_tree().change_scene_to_file()` directly instead
skips the fade and leaves the overlay half-drawn.

### Verify

```json
{
  "scene_path": "res://scenes/main_menu.tscn",
  "viewport_size": {"width": 1280, "height": 720},
  "settle_frames": 4,
  "steps": [
    {"type": "assert", "assertion": "node_exists", "node_path": "/root/SceneTransition"},
    {"type": "assert", "assertion": "node_exists", "node_path": "/root/AudioManager"},
    {"type": "dump_tree", "node_path": "/root/AudioManager", "properties": ["bus", "volume_db"], "max_depth": 2, "label": "audio-pool"},
    {"type": "log_marker", "message": "autoloads-ok"}
  ],
  "log_assertions": [
    {"regex": "no .SFX. audio bus", "min_count": 0, "max_count": 0}
  ]
}
```

```bash
python3 /absolute/path/to/godot/scripts/debug/lint_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/validate_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/run_project.py /absolute/path/to/project --quit-after 120 --timeout 60 --pretty
python3 /absolute/path/to/godot/scripts/debug/run_scenario.py /absolute/path/to/project /absolute/path/to/audio_scenario.json --pretty
```

Expected: `validate_project.py` `"ok": true`, `counts.errors == 0`,
`counts.warnings == 0` (a `no 'SFX' audio bus` warning here means Step 1 was
skipped or its `set_project_setting` did not stick); the `audio-pool`
`dump_tree` lists ten `AudioStreamPlayer` children — eight `Sfx*` on the `SFX`
bus plus `MusicA`/`MusicB` on `Music`.

---

## 12. 3D FPS Starter

**Goal.** A first-person player standing on a floor with baked collision, mouse
look captured on start and released with Esc.

**Prerequisites.** Playbook 1 for the shared move actions; this playbook adds
`move_forward`, `move_back` and `sprint`.

### Step 1 — Input actions and 3D gravity

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  project_batch '{
    "actions": [
      {"type":"add_input_action","action_name":"move_forward","replace":true},
      {"type":"add_input_event","action_name":"move_forward","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":87}}},
      {"type":"add_input_action","action_name":"move_back","replace":true},
      {"type":"add_input_event","action_name":"move_back","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":83}}},
      {"type":"add_input_action","action_name":"sprint","replace":true},
      {"type":"add_input_event","action_name":"sprint","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":4194325}}},
      {"type":"set_setting","name":"physics/3d/default_gravity","value":9.8}
    ]
  }'
```

### Step 2 — Copy the template

```bash
cp /absolute/path/to/godot/templates/gdscript/player_fps_3d.gd \
   /absolute/path/to/project/scripts/player_fps_3d.gd
```

### Step 3 — Build the player

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/player_3d.tscn",
    "create_if_missing": true,
    "root_node_type": "CharacterBody3D",
    "root_node_name": "Player",
    "actions": [
      {"type":"configure_node","node_path":"root","properties":{"collision_layer":2,"collision_mask":1},"groups_add":["player"]},
      {"type":"add_node","parent_node_path":"root","node_type":"CollisionShape3D","node_name":"CollisionShape3D",
       "properties":{"position":{"__type":"Vector3","x":0,"y":0.9,"z":0},
        "shape":{"__resource_type":"CapsuleShape3D","properties":{"radius":0.4,"height":1.8}}}},
      {"type":"add_node","parent_node_path":"root","node_type":"Node3D","node_name":"CameraPivot",
       "properties":{"position":{"__type":"Vector3","x":0,"y":1.6,"z":0}}},
      {"type":"add_node","parent_node_path":"root/CameraPivot","node_type":"Camera3D","node_name":"Camera3D"},
      {"type":"attach_script","node_path":"root","script_path":"scripts/player_fps_3d.gd",
       "script_properties":{"speed":5.0,"sprint_speed":8.0,"jump_velocity":4.5,"mouse_sensitivity":0.0025}}
    ]
  }'
```

The pivot is what carries the pitch. Rotating the `CharacterBody3D` itself on X
tips the collision capsule over and the player falls through the floor.

### Step 4 — Floor with baked collision

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path": "scenes/level_3d.tscn",
    "create_if_missing": true,
    "root_node_type": "Node3D",
    "root_node_name": "Level3D",
    "actions": [
      {"type":"add_node","parent_node_path":"root","node_type":"MeshInstance3D","node_name":"Floor",
       "properties":{"mesh":{"__resource_type":"BoxMesh","properties":{"size":{"__type":"Vector3","x":40,"y":1,"z":40}}},
        "position":{"__type":"Vector3","x":0,"y":-0.5,"z":0}}},
      {"type":"add_node","parent_node_path":"root","node_type":"DirectionalLight3D","node_name":"Sun",
       "properties":{"rotation":{"__type":"Vector3","x":-0.9,"y":-0.6,"z":0},"shadow_enabled":true}},
      {"type":"add_node","parent_node_path":"root","node_type":"WorldEnvironment","node_name":"WorldEnvironment",
       "properties":{"environment":{"__resource_type":"Environment","properties":{"background_mode":1,"ambient_light_source":2,"ambient_light_energy":0.4}}}},
      {"type":"instantiate_scene","parent_node_path":"root","instance_scene_path":"scenes/player_3d.tscn","node_name":"Player",
       "properties":{"position":{"__type":"Vector3","x":0,"y":2,"z":0}}}
    ]
  }'
```

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  bake_collision '{"scene_path":"scenes/level_3d.tscn","node_path":"root/Floor","mode":"trimesh"}'
```

A `MeshInstance3D` has no collider of its own. Skip `bake_collision` and the
player falls forever — that, not a broken controller, is the usual cause of
"my 3D player drops through the ground".

For imported art, drop the `.glb` into the project, run
`import_project.py`, `instantiate_scene` it, then run `bake_collision` on its
`MeshInstance3D` exactly the same way.

### Verify

```json
{
  "scene_path": "res://scenes/level_3d.tscn",
  "viewport_size": {"width": 1280, "height": 720},
  "settle_frames": 4,
  "steps": [
    {"type": "wait_seconds", "seconds": 2.0},
    {"type": "assert", "assertion": "property", "node_path": "Player", "property": "position:y",
     "expected": -0.1, "operator": "greater_than"},
    {"type": "assert", "assertion": "property", "node_path": "Player", "property": "velocity:y",
     "expected": 0.0, "operator": "approx", "tolerance": 0.5},
    {"type": "action", "action_name": "move_forward", "pressed": true},
    {"type": "wait_seconds", "seconds": 0.6},
    {"type": "assert", "assertion": "property", "node_path": "Player", "property": "position:z",
     "expected": -0.5, "operator": "less_than"},
    {"type": "action", "action_name": "move_forward", "pressed": false},
    {"type": "dump_tree", "node_path": "/root", "properties": ["position", "velocity"], "max_depth": 4, "label": "fps-settled"}
  ],
  "assertions": [
    {"assertion": "node_exists", "node_path": "Player/CameraPivot/Camera3D"},
    {"assertion": "node_exists", "node_path": "Floor/Floor_col"}
  ]
}
```

```bash
python3 /absolute/path/to/godot/scripts/debug/lint_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/validate_project.py /absolute/path/to/project --pretty
python3 /absolute/path/to/godot/scripts/debug/run_project.py /absolute/path/to/project res://scenes/level_3d.tscn --quit-after 180 --timeout 60 --pretty
python3 /absolute/path/to/godot/scripts/debug/run_scenario.py /absolute/path/to/project /absolute/path/to/fps_scenario.json --pretty
```

Expected: `validate_project.py` `"ok": true` with `counts.errors == 0` and
`counts.warnings == 0`; `run_scenario.py` `"ok": true`, which means the player
came to rest on the floor (`velocity:y ≈ 0` and `position:y` still above
`-0.1`, i.e. the capsule is standing on the box rather than sinking through it)
and the baked body exists.

`bake_collision` names the body after Godot's own helper: a `MeshInstance3D`
called `Floor` gets a `StaticBody3D` child called `Floor_col`, not
`StaticBody3D`. Read the real name out of `inspect_scene` before asserting on
it.

---

## When A Playbook Fails

| Symptom | Cause | Fix |
| --- | --- | --- |
| `Unknown parameter for <op>: <key> (did you mean …)` | An invented or misremembered field name | Run `help '{"op":"<op>"}'` and copy the parameter list it prints |
| `Parse Error: Identifier "Health" not declared in the current scope` | A `class_name` script added since the last import | `godot --headless --path /absolute/path/to/project --import`, then re-validate |
| `ui_report` finds `overlap` on siblings that should stack in a row | A bare `Control` parent instead of a `Box`/`Grid` container | Insert the container; never fix it by assigning `position` per child |
| `ui_report` finds everything at `[0, 0, …]` | `layout_preset` set on a container's child, or the scene was hand-written as `.tscn` text | Rebuild through `scene_batch`; read `references/tscn_format.md` |
| `%Name` is null at runtime | The node has no `unique_name_in_owner` | Add a `configure_node` action with `"unique_name_in_owner": true` |
| Player falls through the level | Tiles have no collision polygons, or a 3D mesh was never baked | `"collision": "full_cell"` in `build_tileset`, or `bake_collision` on the `MeshInstance3D` |
| Validation reports zero warnings on a project the editor complains about | The debugger is not attached | Keep `--debug --ignore-error-breaks` on the command; do not pass `--no-debugger` |
