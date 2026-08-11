# Automation API

Read this reference when invoking the bundled inspection, resource/project editing, import, validation, scenario, or export-preflight tools.

## Contents

- Dispatcher invocation
- Inspection operations
- Resource transactions
- Project settings transactions
- Content authoring: tilesets, tilemaps, sprite atlases, animations, audio buses, themes, gridmaps, 3D collision/CSG, glTF export, navmesh baking, replication config
- Unit tests (GUT / GdUnit4)
- Import and validation
- Scenario runner
- Typed JSON values
- Export preflight and patches

## Dispatcher Invocation

Invoke Godot-side operations with one JSON object:

```bash
godot --headless --path /absolute/project \
  --script /absolute/godot/scripts/core/dispatcher.gd \
  inspect_project '{"include_files":false}'
```

Use project-relative paths with or without `res://`; outputs normalize them to `res://`.

## Inspection Operations

`inspect_project` accepts:

- `include_files` (default `false`): include every project path; counts are always returned.
- Returns engine/host capabilities, selected settings, explicit InputMap actions, autoloads, global classes, plugins, export presets, and extension counts.

`inspect_scene` accepts:

- `scene_path` (required).
- `include_properties` (default `true`).
- `max_resource_depth` (default `2`).
- Reads `SceneState` without instantiating the scene and returns nodes, stored properties, connections, dependencies, base scene, and UID.

`inspect_resource` accepts:

- `resource_path` (required).
- `include_non_storage` (default `false`).
- `include_schema` (default `false`): enable only when property type/usage metadata is needed.
- `max_resource_depth` (default `2`).
- Returns stored values, dependencies, UID, and script method/signal/property metadata when the resource is a Script.

## Resource Transactions

`resource_batch` loads an existing resource, creates one with `create_if_missing` plus `resource_type`, or deep-duplicates `duplicate_from`. It saves to `resource_path` only after every action succeeds.

```json
{
  "resource_path": "theme/generated.tres",
  "create_if_missing": true,
  "resource_type": "StyleBoxFlat",
  "actions": [
    {"type": "set_properties", "properties": {"corner_radius_top_left": 6}},
    {"type": "set_indexed_properties", "properties": {"content_margin/left": 12}},
    {"type": "set_metadata", "metadata": {"source": "generated"}},
    {"type": "remove_metadata", "names": ["obsolete"]},
    {"type": "set_resource_name", "resource_name": "Generated"}
  ]
}
```

Prefer property-based writes because they stay inspectable through `inspect_resource`. Use `call_method` only for builder APIs that have no property equivalent — for example `Curve2D.add_point`, `Gradient.add_point`, `Theme.set_color`, `Animation.add_track`, `TileSet.add_source`, or `SpriteFrames.add_animation`:

```json
{
  "resource_path": "paths/patrol.tres",
  "create_if_missing": true,
  "resource_type": "Curve2D",
  "actions": [
    {"type": "call_method", "method": "add_point", "args": [{"__type": "Vector2", "x": 0, "y": 0}]},
    {"type": "call_method", "method": "add_point", "args": [{"__type": "Vector2", "x": 200, "y": 0}]}
  ]
}
```

- `call_method`: `method` (must exist on the resource), typed `args` array, optional `expect_ok` to fail the transaction when an `Error`-returning method does not return `OK`.
- Arguments accept the full typed JSON surface, including `{"__resource": ...}` references and inline `{"__resource_type": ...}` construction, so a `call_method` can attach sub-resources.
- Inline `{"__resource_type": ...}` construction also accepts an ordered `method_calls` array (same shape as `call_method`), so a builder-only sub-resource can be created in a single property write. It also accepts `__curve` and `__gradient` sugar — see [Typed JSON Values](#typed-json-values).
- `bake_navmesh`: bakes the target resource (a `NavigationPolygon` or a `NavigationMesh`) from procedural geometry using the synchronous `NavigationServer2D/3D.bake_from_source_geometry_data`. Set agent/cell parameters with a preceding `set_properties` action, then supply geometry:
  - 2D (`NavigationPolygon`): `traversable_outlines` (required, an array of `[[x,y], …]` outlines) and optional `obstruction_outlines`.
  - 3D (`NavigationMesh`): `faces` (a flat list of `[x,y,z]` triangle vertices, a multiple of 3) and/or `source_meshes` (`[{"mesh": "res://…", }]`).
  - Feed collision/procedural geometry, not visual meshes — the headless dummy renderer cannot read visual-mesh geometry back from the GPU. The bake is synchronous; never the `_async` variant in a one-shot run.

```json
{
  "resource_path": "nav/level.tres",
  "create_if_missing": true,
  "resource_type": "NavigationPolygon",
  "actions": [
    {"type": "set_properties", "properties": {"agent_radius": 8.0, "cell_size": 1.0}},
    {"type": "bake_navmesh",
     "traversable_outlines": [[[0,0],[512,0],[512,512],[0,512]]],
     "obstruction_outlines": [[[200,200],[300,200],[300,300],[200,300]]]}
  ]
}
```

Two cross-cutting notes for all resource-writing ops:

- Headless-saved `.tres`/`.tscn` files carry no `uid=` header. If the project cross-references resources by UID, run `resave_resources` after bulk creation and verify the created/missing counts.
- Every dispatcher operation exits `1` when it logged an error and `0` on success, so shell callers can gate on the exit code instead of parsing stderr.

## Project Settings Transactions

`project_batch` applies every action in memory, then calls `ProjectSettings.save()` once. **`save()` rewrites `project.godot` wholesale — comments are dropped and keys re-sorted.** Rely on version control for safety, or pass `"backup_path": "project.godot.bak"` to snapshot the original before saving. Supported actions:

- `set_setting`: `name`, typed `value`.
- `clear_setting`: `name`.
- `add_input_action`: `action_name`, optional `deadzone`, optional `replace`.
- `remove_input_action`: `action_name`.
- `add_input_event`: existing `action_name`, typed Resource `event`.
- `remove_input_event`: existing `action_name`, zero-based `event_index`.
- `add_autoload`: `autoload_name`, `path`, optional `singleton` (default `true`).
- `remove_autoload`: `autoload_name`.
- `set_layer_name`: `layer_type`, `layer` from 1 to 32, `layer_name`. Types are `2d_physics`, `3d_physics`, `2d_render`, `3d_render`, `2d_navigation`, `3d_navigation`.
- `set_main_scene`: existing `scene_path`.
- `add_translation` / `remove_translation`: translation `path`.
- `set_shader_global`: `name`, `global_type` (a shader-globals type string such as `color`, `vec3`, `float`, `sampler2D`), and typed `value`. Persists to the `[shader_globals]` section as a `{type, value}` dictionary shared by all shaders that declare `global uniform`.
- `clear_shader_global`: `name` (idempotent).

Example InputMap event:

```json
{
  "type": "add_input_event",
  "action_name": "jump",
  "event": {
    "__resource_type": "InputEventKey",
    "properties": {"physical_keycode": 32}
  }
}
```

## Content Authoring

### build_tileset

Authors or updates a `TileSet` `.tres`. TileSet construction is method-driven, so use this instead of `resource_batch`:

```json
{
  "resource_path": "tilesets/world.tres",
  "tile_size": {"x": 16, "y": 16},
  "physics_layers": [{"collision_layer": 1, "collision_mask": 1}],
  "custom_data_layers": [{"name": "kind", "type": "string"}],
  "sources": [{"source_id": 0, "texture": "art/tiles.png", "tiles": "all"}]
}
```

- `sources[*].tiles`: `"all"` exposes every full grid cell of the texture; or pass explicit `[{"atlas_coords":{"x":0,"y":0},"size":{"x":1,"y":1}}]`.
- `texture_region_size` defaults to `tile_size`; `margins`/`separation` are optional Vector2i dictionaries.
- Custom data layer types: `bool`, `int`, `float`, `string`, `vector2`, `vector2i`, `color`.
- Per-tile configuration — on each tile entry, or on `sources[*].tile_defaults` to apply to every tile of that source:
  - `collision`: `"full_cell"` (rectangle sized to the tile's texture region, centered) or an explicit array of 3+ `{x,y}` points relative to the tile center. Requires at least one `physics_layers` entry; `collision_layer_index` selects which (default 0). Without collision polygons a TileSet is decorative only — characters fall through.
  - `custom_data`: `{"layer_name": value}` map writing declared custom-data layers.
  - `terrain_set` / `terrain` / `peering`: terrain membership plus peering bits, e.g. `"peering": {"left_side": 0, "right_side": 0}` (side names resolve to `TileSet.CELL_NEIGHBOR_*`).
- `terrain_sets`: `[{"mode": "match_corners_and_sides"|"match_corners"|"match_sides", "terrains": [{"name": "grass", "color": {...}}]}]`.
- Run the importer first (`import_project.py`) when the texture is a fresh, unimported image so the saved `.tres` reloads in later sessions.

### paint_tilemap

Paints cells on an existing `TileMapLayer` node (the monolithic `TileMap` node is deprecated since Godot 4.3 — add `TileMapLayer` nodes instead). Available standalone and as a `scene_batch` action:

```json
{
  "scene_path": "scenes/level.tscn",
  "node_path": "root/Ground",
  "tile_set": "tilesets/world.tres",
  "cells": [{"coords": {"x": 0, "y": 0}, "source_id": 0, "atlas_coords": {"x": 0, "y": 0}}],
  "fills": [{"from": {"x": 0, "y": 1}, "to": {"x": 9, "y": 1}, "source_id": 0, "atlas_coords": {"x": 1, "y": 0}}],
  "erase": [{"x": 5, "y": 5}],
  "clear": false
}
```

- Order per call: optional `tile_set` assignment → `clear` → `erase` → `cells` → `fills` (inclusive rectangles) → `terrain_fills`.
- `terrain_fills`: `[{"cells": [{x,y}, ...], "terrain_set": 0, "terrain": 0}]` runs `set_cells_terrain_connect` for autotiling — the TileSet's tiles need terrain membership and peering bits (see `build_tileset`).
- Painting fails fast if the atlas source has not exposed the requested `atlas_coords` — expose tiles with `build_tileset` first.

### build_sprite_frames (atlas mode)

The legacy `animation_name` + `frames_dir`/`frame_paths` form still works. The `animations` form adds spritesheet slicing, multiple animations per call, and per-frame duration:

```json
{
  "scene_path": "scenes/mob.tscn",
  "node_path": "root/Sprite",
  "spritesheet": "art/sheet.png",
  "grid": {"cell_width": 8, "cell_height": 8},
  "animations": [
    {"name": "idle", "fps": 6, "loop": true, "frames": [{"row": 0, "cols": [0, 1, 2, 3]}]},
    {"name": "attack", "fps": 12, "frames": [
      {"index": 4, "duration": 2.0},
      {"region": {"x": 8, "y": 8, "width": 8, "height": 8}},
      {"path": "art/extra_frame.png"}
    ]}
  ],
  "resource_save_path": "anims/mob_frames.tres"
}
```

- Frame specs: `{"row", "col"}` or `{"row", "cols": [...]}` or `{"index"}` (row-major) slice the grid into `AtlasTexture`s; `{"region"}` cuts an arbitrary rect; `{"path"}` loads a standalone image.
- `duration` is SpriteFrames' relative per-frame duration (default `1.0`).
- `grid` supports `margin_x`/`margin_y`/`separation_x`/`separation_y`.

### build_animation

Builds an `Animation` from declarative tracks, then saves it standalone (`resource_save_path`) and/or registers it on an `AnimationPlayer` through an `AnimationLibrary` (`scene_path` + `player_node_path`, created when missing):

```json
{
  "animation_name": "blink",
  "length": 0.8,
  "loop_mode": "linear",
  "tracks": [
    {"type": "value", "path": "Sprite2D:modulate", "update_mode": "continuous",
     "keys": [{"time": 0.0, "value": {"__type": "Color", "r": 1, "g": 1, "b": 1, "a": 1}},
              {"time": 0.4, "value": {"__type": "Color", "r": 1, "g": 1, "b": 1, "a": 0.2}}]},
    {"type": "method", "path": ".",
     "keys": [{"time": 0.8, "method": "on_blink_done", "args": []}]},
    {"type": "bezier", "path": "Sprite2D:scale:x",
     "keys": [{"time": 0.0, "value": 1.0, "in_handle": [0, 0], "out_handle": [0.2, 0.1]}]}
  ],
  "resource_save_path": "anims/blink.tres",
  "scene_path": "scenes/player.tscn",
  "player_node_path": "root/AnimationPlayer",
  "library": ""
}
```

- Track paths follow Godot's `"NodePath:property"` form relative to the AnimationPlayer's `root_node` (its parent by default).
- `loop_mode`: `none`/`linear`/`pingpong`. Value tracks accept `update_mode` (`continuous`/`discrete`/`capture`) and `interpolation` (`nearest`/`linear`/`cubic`); value keys accept `transition`.
- The default library is `""`, so animations play by bare name (`player.play("blink")`).

### build_animation_tree

Builds an `AnimationNodeStateMachine` on an `AnimationTree` node (created when missing) from clips that already exist on the linked AnimationPlayer:

```json
{
  "scene_path": "scenes/enemy.tscn",
  "tree_node_path": "root/AnimationTree",
  "anim_player": "../AnimationPlayer",
  "states": [
    {"name": "idle", "animation": "idle"},
    {"name": "run", "animation": "run"}
  ],
  "transitions": [
    {"from": "idle", "to": "run", "advance_mode": "auto", "advance_condition": "moving", "xfade_time": 0.15},
    {"from": "run", "to": "idle", "advance_mode": "auto", "advance_expression": "not moving"}
  ]
}
```

- `anim_player` is a NodePath relative to the AnimationTree node (default `../AnimationPlayer`).
- Transition fields: `xfade_time`, `advance_mode` (`disabled`/`enabled`/`auto`), `advance_condition` (a bool the game sets via `tree.set("parameters/conditions/<name>", true)`), `advance_expression`, `switch_mode` (`immediate`/`sync`/`at_end`).
- A `Start → first state` transition is added automatically unless one exists (`auto_start: false` disables) — without it the machine never enters a state.
- Drive it at runtime with `tree.get("parameters/playback").travel("run")`.
- For blend trees or 1D/2D blend spaces, assemble the `tree_root` with `resource_batch` `call_method` instead.

### set_import_options

Patches the `[params]` section of an asset's `.import` sidecar, then invalidates the imported artifact so the next import pass actually re-runs:

```json
{"file_path": "audio/bgm.ogg", "options": {"loop": true, "loop_offset": 0.0}}
```

- Follow with `python3 scripts/import/import_project.py <project>` (or `godot --headless --import`) — the op reports `reimport_required: true`.
- WAV loop uses `edit/loop_mode`, and the importer enum is offset from the resource enum: `0` Detect From WAV, `1` Disabled, `2` Forward, `3` Ping-Pong, `4` Backward. Ogg/MP3 use the simpler `loop` bool + `loop_offset` seconds.
- Whole-number values are written as ints (JSON numbers arrive as floats; importer params are typed).

### setup_audio_buses

`AudioServer` is a singleton, not a Resource, so bus routing has its own op. Buses are created or updated by name, then the layout snapshot is saved and registered:

```json
{
  "buses": [
    {"name": "Master", "volume_db": 0.0},
    {"name": "Music", "send": "Master", "volume_db": -6.0},
    {"name": "SFX", "send": "Master",
     "effects": [{"type": "AudioEffectLowPassFilter", "enabled": true, "properties": {"cutoff_hz": 4000.0}}]}
  ],
  "save_path": "default_bus_layout.tres",
  "set_project_setting": true
}
```

- Order buses before the buses that `send` to them. The Master bus cannot have a send.
- Providing `effects` replaces that bus's whole effect chain (idempotent reruns).
- `set_project_setting` writes `audio/buses/default_bus_layout`; values equal to the engine default are omitted from `project.godot` by design.
- Route players to a bus with `configure_node`: `{"properties": {"bus": "Music"}}` on an `AudioStreamPlayer`.

### build_theme

Authors a `Theme` `.tres` grouped by control type. Every Theme item setter is a positional `(name, theme_type, value)` call with no property equivalent, so `resource_batch` needs dozens of unlabeled `call_method` entries; this op groups them. Colors accept hex strings (`"#2a2a2a"`) or typed `{"__type": "Color"}`. Styleboxes accept a flat `StyleBoxFlat` shorthand (with `corner_radius` / `border_width` / `content_margin` / `expand_margin` convenience keys that call the `*_all` setters), an inline `{"__resource_type": "StyleBox…"}`, a `{"__resource": "res://…"}` reference, or the string `"empty"` for a `StyleBoxEmpty`.

```json
{
  "resource_path": "theme/main.tres",
  "default_font": {"__resource": "res://fonts/inter.ttf"},
  "default_font_size": 16,
  "types": {
    "Button": {
      "styleboxes": {
        "normal": {"bg_color": "#2a2a2a", "corner_radius": 6, "border_width": 1, "border_color": "#111111", "content_margin": 8},
        "hover": {"bg_color": "#3a3a3a", "corner_radius": 6},
        "focus": "empty"
      },
      "colors": {"font_color": "#ffffff", "font_hover_color": "#eeeeee"},
      "constants": {"h_separation": 8},
      "font_sizes": {"font_size": 16}
    }
  },
  "variations": {"HeaderLabel": {"base": "Label", "colors": {"font_color": "#88ccff"}, "font_sizes": {"font_size": 28}}}
}
```

- Item names are not validated by the engine — a typo silently falls back to the default theme. Match the control's documented item names.
- Wire the finished theme project-wide with `project_batch` `set_setting` on `gui/theme/custom`, or per-control with `configure_node` (`theme`) / `theme_type_variation`.

### paint_gridmap

The 3D parallel to `paint_tilemap`. `GridMap` cells exist only through `set_cell_item`, so there is no bulk property for `configure_node` to set. Assign a `mesh_library` (build it with `export_mesh_library`), then paint.

```json
{
  "scene_path": "scenes/level.tscn",
  "node_path": "root/GridMap",
  "mesh_library": "meshlib/tiles.meshlib",
  "cell_size": {"__type": "Vector3", "x": 2, "y": 2, "z": 2},
  "clear": false,
  "fills": [{"from": [0, 0, 0], "to": [7, 0, 7], "item": 0, "orient": 0}],
  "cells": [{"pos": [3, 1, 4], "item": 2, "orient": 22}],
  "erase": [[0, 0, 0]]
}
```

- `pos`/`from`/`to`/`erase` accept `[x,y,z]` or `{x,y,z}`. `item` must exist in the mesh library; `orient` is a `0`–`23` orthogonal index. Also runs inside `scene_batch`.

### bake_collision

Generates a `StaticBody3D` + `CollisionShape3D` child from a `MeshInstance3D` via the engine's `create_*_collision` helpers. `mode` is `trimesh` (concave, static only), `convex` (accepts `clean`/`simplify`), or `multi_convex` (convex decomposition). The op sets the mesh's `owner` to the scene root before baking so the generated subtree serializes.

```json
{"scene_path": "props/crate.tscn", "node_path": "root/Mesh", "mode": "trimesh"}
```

### collision_from_sprite

Traces a sprite's alpha silhouette into `CollisionPolygon2D` children with `BitMap.opaque_to_polygons`. Adds one collider per opaque island.

```json
{"scene_path": "actors/enemy.tscn", "node_path": "root/Sprite2D", "texture": "art/enemy.png", "alpha_threshold": 0.1, "epsilon": 2.0, "one_way": false}
```

- `texture` defaults to the target `Sprite2D`'s texture. Points are centered automatically when the sprite is `centered`; add an extra `offset` if needed. Lower `epsilon` = more vertices (higher physics cost).

### bake_csg

Freezes a `CSGShape3D` tree into a static `ArrayMesh` (+ optional collision). CSG geometry updates are deferred one frame, so this op runs inside the live SceneTree and awaits frames before baking. Point `node_path` at the CSG root (`is_root_shape`).

```json
{
  "scene_path": "proto/level.tscn",
  "node_path": "root/CSGCombiner3D",
  "out_mesh": "meshes/level.res",
  "bake_collision": true,
  "replace_with_meshinstance": true,
  "save_path": "proto/level_baked.tscn"
}
```

- `out_mesh` saves the baked mesh. `replace_with_meshinstance` swaps the CSG node for a `MeshInstance3D` (plus a `StaticBody3D`/`CollisionShape3D` when `bake_collision` is set) and rewrites the scene to `save_path` (or in place). Without `replace_with_meshinstance` the scene is untouched.

### gltf_export

Exports an edited scene (or a subtree via `node_path`) to `.glb`/`.gltf` through `GLTFDocument`. Import stays with the standard `--import` pipeline.

```json
{"scene_path": "scenes/level.tscn", "node_path": "root", "out": "export/level.glb"}
```

- `out` may be `res://`, `user://`, an absolute build path, or a bare project-relative path. The extension (`.glb` binary vs `.gltf` text) selects the format.

### build_replication_config

Authors a `SceneReplicationConfig` `.tres` for a `MultiplayerSynchronizer`. Property paths are relative to the synchronizer's `root_path` (default its parent). `replication_mode` is `never`, `always`, or `on_change`.

```json
{
  "resource_path": "net/player_repl.tres",
  "properties": [
    {"path": ".:position", "spawn": true, "replication_mode": "on_change"},
    {"path": ".:velocity", "replication_mode": "always"}
  ]
}
```

- Assign the result with `configure_node` (`replication_config`) on the synchronizer. `resource_batch` can also build this via `call_method`; this op just labels the ordering and avoids the deprecated `property_set_sync`/`property_set_watch`.

## Unit Tests (GUT / GdUnit4)

Godot has no built-in project test runner. `scripts/test/run_tests.py` auto-detects the two community standards and normalizes their exit codes:

```bash
python3 scripts/test/run_tests.py /absolute/project --pretty
python3 scripts/test/run_tests.py /absolute/project --framework gut --tests-dir test --junit-xml /tmp/report.xml
```

- Detection: `addons/gut/gut_cmdln.gd` → GUT; `addons/gdUnit4/bin/GdUnitCmdTool.gd` → GdUnit4. Default tests dir: `test/` then `tests/`.
- Exit mapping: GUT `0` pass / `1` failures; GdUnit4 `0` pass, `100` failures, `101` warnings (treated as pass). GdUnit4 writes HTML+JUnit reports under `res://reports/`.
- `--dry-run` prints the detection result and exact command without running — use it to verify wiring before a long suite.
- Minimal GUT test: `extends GutTest` + `func test_x(): assert_eq(2 + 2, 4)`. Minimal GdUnit4 test: `extends GdUnitTestSuite` + `func test_x(): assert_int(4).is_equal(2 + 2)`.

## Import And Validation

Audit existing import state:

```bash
godot --headless --path /absolute/project \
  --script /absolute/godot/scripts/core/dispatcher.gd \
  audit_imports '{"project_path":"res://","include_entries":true}'
```

Run Godot's importer first, then audit:

```bash
python3 scripts/import/import_project.py /absolute/project --pretty
```

Use `--audit-only` to skip reimport. Statuses are `ok`, `missing`, `invalid`, `stale`, and `orphaned`.

Probe the engine and host toolchain, then run the comprehensive validator:

```bash
python3 scripts/debug/probe_environment.py /absolute/project --pretty
python3 scripts/debug/validate_project.py /absolute/project --pretty
```

`validate_project.py` loads GDScript, scenes, shaders, resources, GDExtensions, and editor plugins. When a root `.csproj` exists, it also runs Godot's `--build-solutions`; override with `--csharp always|never`.

## Scenario Runner

Create a scenario JSON and run it with `scripts/debug/run_scenario.py PROJECT SCENARIO`. The wrapper uses a rendered window when a screenshot step exists and headless mode otherwise. Force the choice with `--headless` or `--no-headless`.

```json
{
  "scene_path": "scenes/menu.tscn",
  "viewport_size": {"width": 1280, "height": 720},
  "settle_frames": 2,
  "steps": [
    {"type": "action", "action_name": "ui_accept", "pressed": true, "release_after": true},
    {"type": "mouse_button", "button_index": 1, "position": {"x": 640, "y": 360}, "pressed": true},
    {"type": "wait_frames", "frames": 2},
    {"type": "assert", "assertion": "property", "node_path": "Status", "property": "text", "expected": "Ready"},
    {"type": "screenshot", "path": "/absolute/output/menu.png"}
  ],
  "assertions": [
    {"assertion": "node_exists", "node_path": "StartButton"},
    {"assertion": "visible", "node_path": "Status", "expected": true}
  ],
  "performance_frames": 30,
  "log_assertions": [{"contains": "Level loaded", "min_count": 1}],
  "performance_assertions": [
    {"monitor": "process_time", "statistic": "maximum", "operator": "less_or_equal", "value": 0.02}
  ]
}
```

Step types are `wait_frames`, `wait_seconds`, `action`, `key`, `mouse_button`, `mouse_motion`, `joypad_button`, `joypad_motion`, `assert`, `wait_until`, `set_property`, `screenshot`, and `log_marker`.

- `wait_until`: polls a property assertion every frame until it passes or `timeout_seconds` (default 5) elapses — prefer it over guessing `wait_frames` counts. Fields match `assert` (`node_path`, `property`, `expected`, `operator`, `tolerance`).
- `set_property`: writes a typed value to a node's (sub)property and waits one frame — useful for arranging state before an interaction.

Property assertion operators are `equals`, `not_equals`, `greater_than`, `greater_or_equal`, `less_than`, `less_or_equal`, `contains`, and `approx`. Performance monitors are `fps`, `process_time`, `physics_process_time`, `static_memory`, `node_count`, `resource_count`, `draw_calls`, `primitives`, and `video_memory`; statistics are `average`, `minimum`, and `maximum`.

## Typed JSON Values

The shared codec accepts plain JSON plus:

- Resource reference: `{"__resource":"res://theme/main.tres"}`.
- Resource construction: `{"__resource_type":"Gradient","properties":{...}}`, optionally with an ordered `"method_calls":[{"method":"add_point","args":[...],"expect_ok":false}]` for builder-only state.
- `StringName`, `NodePath`, `Vector2`, `Vector2i`, `Rect2`, `Rect2i`, `Vector3`, `Vector3i`, `Transform2D`, `Vector4`, `Vector4i`, `Plane`, `Quaternion`, `AABB`, `Basis`, `Transform3D`, `Projection`, and `Color` through `{"__type":"TypeName",...}`.
- Packed byte/int/float/string/vector/color arrays through `{"__type":"Packed...Array","values":[...]}`.
- Curve sugar: `{"__curve":{"min_value":0,"max_value":1,"points":[{"x":0,"y":0},{"x":1,"y":1,"left_tangent":0,"right_tangent":0}]}}` builds a `Curve` (its points are otherwise builder-only, so this is the ergonomic way to inline scale/alpha/velocity ramps).
- Gradient sugar: `{"__gradient":{"points":[{"offset":0,"color":"..."},{"offset":1,"color":"..."}]}}` (or `{"offsets":[...],"colors":[...]}`) builds a clean `Gradient` with exactly those stops — unlike `add_point`, which appends to the two default stops.

`Rect2`/`Rect2i` accept either typed `position` plus `size` dictionaries or the compatibility form `x`, `y`, `width`, `height`.

## Export Preflight And Patches

```bash
python3 scripts/export/export_project.py PROJECT PRESET OUTPUT --preflight-only
python3 scripts/export/export_project.py PROJECT PRESET update.pck \
  --mode patch --patches base.pck previous_patch.pck
```

Preflight checks the exact preset, matching export-template directory, Godot executable, platform tools, patch inputs, and common output extensions. Dry runs report preflight findings without failing unless `--strict-preflight` is set. Real exports fail on preflight errors unless `--skip-preflight` is explicitly supplied.
