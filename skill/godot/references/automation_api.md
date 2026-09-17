# Automation API

Read this reference when invoking the bundled inspection, resource/project editing, import, validation, scenario, or export-preflight tools.

## Contents

- Dispatcher invocation
- Discovering operations (`help`)
- Inspection operations: project, scene, resource, image, tilemap
- Resource transactions
- Project settings transactions
- Content authoring: tilesets, tilemaps, sprite atlases, animations, audio buses, themes, gridmaps, 3D collision/CSG, glTF export, navmesh baking, replication config
- Unit tests (GUT / GdUnit4)
- Static lint (no Godot needed)
- Import and validation
- Scenario runner: input and timing facts, screenshot, ui_report, dump_tree, verification without vision
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

## Discover Operations (`help`)

`help` answers "what can this dispatcher do, and what does that operation take" without reading this file. Nothing in it is hand-maintained: the operation list is read out of `dispatcher.gd`'s own `match` arms and the accepted parameter keys are re-derived from each operation's sources by the same function that backs the unknown-parameter check, so it cannot describe an operation the dispatcher cannot run.

```bash
godot --headless --path /absolute/project \
  --script /absolute/godot/scripts/core/dispatcher.gd \
  help '{"op":"add_node"}'
```

```json
{
  "op": "add_node",
  "summary": "Add one new node of a class under an existing node and save the scene.",
  "params": {
    "scene_path": "(required) scene to edit, project-relative or res:// — \"scenes/main.tscn\"",
    "node_type": "(required) class to instantiate: any instantiable engine class or project class_name — \"Sprite2D\", \"CharacterBody2D\", \"VBoxContainer\"",
    "node_name": "(required) name of the new node, and its path segment afterwards — \"Player\"",
    "parent_node_path": "(default: \"root\") path from the scene root, which is always addressed as \"root\" — \"root/Panel\"",
    "index": "(default: -1 = last) sibling position to insert at; for Control/CanvasItem siblings this is also draw order",
    "properties": "(default: {}) node properties by name, typed JSON — {\"position\": {\"__type\": \"Vector2\", \"x\": 160, \"y\": 96}, \"text\": \"Start\"}",
    "…": "…"
  },
  "example": {"scene_path": "scenes/main.tscn", "parent_node_path": "root", "node_type": "Sprite2D", "node_name": "Player",
              "properties": {"position": {"__type": "Vector2", "x": 160, "y": 96}}},
  "notes": ["Node paths start at the scene root, which is always addressed as \"root\" (or \".\"): \"root/Panel/Start\".", "…"],
  "see": "SKILL.md#scene-editing-surface",
  "command": "godot --headless --path /absolute/project --script /absolute/godot/scripts/core/dispatcher.gd add_node '{\"scene_path\":\"scenes/main.tscn\",…}'"
}
```

- `help '{}'` lists every operation with a one-line summary plus `count` and a `usage` line. This is the cheapest way to find the right operation name — cheaper than grepping this file, and it can never be out of date.
- `help '{"op":"<name>"}'` returns that operation's `summary`, its `params` schema, a runnable `example`, `notes` (the gotchas that cost a rerun), a `see` pointer into the docs, and `command` — the complete shell line with the example already inlined, absolute dispatcher path and all. Paste it, then edit it.
- `params` is a curated `{key: meaning}` object holding only the keys that operation uses, required keys first, each one saying `(required)` or `(default: X)` and the value shape it accepts. Read it instead of guessing: `"parent_node_path": "(default: \"root\") path from the scene root, which is always addressed as \"root\" — \"root/Panel\""`.
- Batch operations add `action_types`, one schema per `actions[*].type`. A `scene_batch` action takes its operation's own keys minus `scene_path`/`save_path`, which the batch owns, and that is exactly what the op prints.
- `"verbose": true` adds `accepted_keys`: the full derived key set the unknown-parameter check allows, which includes the shared scene/codec helper keys. It is the audit view, not the documentation — reach for it only when a key was rejected and you want to know what the check actually sees.
- `"format": "text"` renders the same information as plain lines (one operation per line for the listing, a `key — meaning` line per parameter for one operation) instead of JSON.
- An unknown operation name is an error, not an empty result: it names the three nearest real operations and exits `1`. The dispatcher's own `Unknown operation:` error does the same and ends with `Run: help '{}' to list operations`, and an unknown parameter ends with `Run: help '{"op":"add_node"}' for the accepted keys and an example`.
- `help '{"check_examples":true}'` re-derives every operation's accepted keys and validates every curated `params` key, every `action_types` key and every example key (including each `actions[*]` entry) against them, printing `{"checked", "operations", "skipped", "failures":[{"op","key","suggestions"}]}` and exiting `1` on any failure. Run it after renaming a parameter: it is what stops the schema from documenting a key the operation would reject.
- The prose lives in `scripts/core/op_examples.json`, one entry per operation (`{"summary", "params", "example", "notes", "see"}`, plus `action_types` for a batch operation, where a value of `"@<operation>"` reuses that operation's schema). Adding an operation means adding a `match` arm **and** an entry — `check_examples` reports an operation with no entry, or an entry with no `params` schema, as a failure.

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
- For a script-backed `.tres`, `resource_type` is the engine base (usually `Resource`); the identifying fields are `script_path` (the `res://….gd`), `script_class` (the script's `class_name`, empty when it declares none), and `script_properties` (its exported property names, in declaration order). The exported values themselves appear in the ordinary `properties` map.

### inspect_image

Reads an image file as numbers and ASCII, so "did the sprite render", "where is it", "is the palette pixel-art sized", "did the frame change" are text questions. It loads the file directly (`Image.load_from_file`), never through the import pipeline, so freshly generated art works before `--import` has ever run and screenshots outside the project work by absolute path.

```json
{
  "image_path": "art/player.png",
  "ascii": true,
  "ascii_width": 64,
  "ascii_color": false,
  "compare_to": "art/player_reference.png",
  "max_unique": 4096,
  "background_tolerance": 0.12,
  "expect": {"not_blank": true, "min_opaque_ratio": 0.1, "max_unique_colors": 32,
             "has_alpha": true, "width": 32, "height": 32, "max_diff_ratio": 0.01},
  "format": "json"
}
```

```json
{
  "image_path": "res://art/player.png",
  "width": 64, "height": 64, "has_alpha": true, "blank": false, "opaque_ratio": 0.0625,
  "content_bbox": {"x": 32, "y": 8, "w": 16, "h": 16},
  "content_bbox_normalized": {"x": 0.5, "y": 0.125, "w": 0.25, "h": 0.25},
  "mean_color": "#ff0000",
  "dominant_colors": [{"hex": "#ff0000", "ratio": 1.0}],
  "unique_colors": 1,
  "quadrants": {"top_left": 0.0, "top_right": 1.0, "bottom_left": 0.0, "bottom_right": 0.0},
  "background_color": "#000000", "background_transparent": true, "background_tolerance": 0.0,
  "sample_size": {"width": 64, "height": 64}, "sampled": false,
  "ascii": ["                        ", "…"],
  "diff_ratio": 0.0,
  "expect_results": [{"check": "not_blank", "expected": true, "actual": true, "passed": true}],
  "expect_passed": true
}
```

- `image_path` accepts `res://`, `user://`, an absolute host path, or a bare project-relative path; `.png`, `.jpg`, `.jpeg`, `.webp`, `.bmp`, `.tga`, `.svg`, `.exr`, `.hdr`.
- **Background** is the colour the four corner pixels agree on (ties go to the top-left corner), and a fully transparent pixel is always background. **Content** is every other pixel: that is what `content_bbox` bounds and what `quadrants` splits — the four shares are of the content, so `{"top_right": 1.0}` means everything drawn sits in the top-right quarter.
- **Lossy files ring.** JPEG paints near-background pixels around every edge, and an exact match stretches `content_bbox` over the whole chroma-bleed block (a 16 px sprite at y=8 reported as 32 rows from y=0). `background_tolerance` is the per-channel distance (0-1) under which a pixel still counts as background; it defaults to `0.12` for `.jpg`/`.jpeg` and `0` for everything else, and the result reports the value that applied. With it the JPEG box lands within a pixel of the true one. Pass it explicitly for lossy WebP or a noisy capture, or `0` to force exact matching.
- `blank` is `true` when every pixel is identical or nothing is opaque anywhere — the "nothing rendered" case. `opaque_ratio` is the share of pixels with any alpha at all (`1.0` for an opaque image, `0.0` for an empty canvas).
- `dominant_colors` are the top 8 buckets quantised to 4 bits per channel with their share of the *drawn* pixels; `unique_colors` counts exact RGBA values among drawn pixels, capped at `max_unique` (default 4096, reported as the cap when exceeded). `mean_color` averages the drawn pixels only, so a sprite on a transparent canvas reports its own colour rather than a wash toward black.
- `ascii` (with `ascii_width`, default 64) renders the image with the ramp `" .:-=+*#%@"`, halving the row count because character cells are about twice as tall as they are wide (`ascii_width` is clamped to 4-240, and a very tall image loses columns rather than producing hundreds of rows). Cells are area-averaged, transparent cells are spaces, and the ramp is stretched across the luminance actually present so a dark scene still shows its shapes. `ascii_color` renders the same grid as the nearest of `K W R G B Y C M` per cell. Both are printed after the key facts by `"format": "text"`.
- `compare_to` adds `diff_ratio`: the share of pixels where some channel differs by more than 8/255. Byte-identical images answer exactly `0.0`. Different sizes are a mistake, not a measurement — the result carries `diff_error` and the op exits 1.
- `expect` gates the exit code: every violated key logs an error, so `echo $?` is the whole check. Keys: `not_blank`, `min_opaque_ratio`, `max_unique_colors`, `has_alpha`, `width`, `height`, `max_diff_ratio` (needs `compare_to`), and `frames_consistent`. Each is also reported in `expect_results` with its expected and actual value. An invented key is rejected with the list.
- `image_paths` describes a list of files, a directory, or a mix of both in one call (directories expand in natural order, so `frame_2` precedes `frame_10`). The result is `{count, frames_consistent, frame_size, images[], expect_results, expect_passed}`, and `expect.frames_consistent` turns a frame sequence that changed canvas size mid-way into a failed run.
- Cost: colour statistics are measured on a nearest-neighbour downscale capped at 256 px on the long side (`sampled` / `sample_size` say when that happened), so a 1080p screenshot describes in about 0.2 s. `width`, `height`, `has_alpha`, `blank` and `content_bbox` are always measured on the full image — a one-pixel change is still located exactly. No rendering device is needed.

### inspect_tilemap

`inspect_tilemap` accepts:

- `scene_path` (required).
- `node_path` (optional): defaults to the first `TileMapLayer` or `GridMap` found under the root, and the chosen path is logged and returned in `node_path`.
- `legend` (optional): the same char → tile map `paint_tilemap.ascii_map.legend` takes. Tiles it does not name get characters auto-assigned from `#@%&*+=oxABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789` in first-seen order. Terrain entries are rejected here — a painted terrain is stored as concrete atlas tiles, so map those.
- `bounds` (optional): `{"x", "y", "w", "h"}` (`{"x", "z", "w", "h"}` for a `GridMap`) crops the window. Without it the window is the bounding box of the used cells, so empty edge rows/columns are trimmed.
- `format`: `json` (default) or `text` — `text` prints only the rows, plus a `y=<n>` header per layer for a `GridMap`.

```json
{"scene_path": "scenes/level.tscn", "node_path": "root/Ground", "format": "text"}
```

- A `TileMapLayer` returns `{node_path, node_type, tileset_path, bounds, cell_count, legend, counts, rows}`; a `GridMap` returns `{..., mesh_library_path, layers: [{"y": 0, "rows": [...]}]}` for every used `y`.
- Empty cells are always `.`, and the returned `legend` is exactly what `paint_tilemap`/`paint_gridmap` accept — inspect one scene, paste `legend` + `rows` into a paint call, and the level reproduces.
- When the scene holds no `TileMapLayer` or `GridMap` the op lists every node path and type it did find, so the next call can name a real one.

## Resource Transactions

`resource_batch` loads an existing resource, creates one with `create_if_missing` plus either `resource_type` (an engine class) or `script` (a project `class_name X extends Resource`), or deep-duplicates `duplicate_from`. It saves to `resource_path` only after every action succeeds.

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

Name a `script` instead of a `resource_type` to author an instance of a project's own resource class:

```json
{
  "resource_path": "items/sword.tres",
  "create_if_missing": true,
  "script": "res://items/item_data.gd",
  "actions": [
    {"type": "set_properties", "properties": {
      "display_name": "Sword",
      "price": 100,
      "tags": ["melee", "sharp"],
      "stats": {"material": {"__resource_type": "StandardMaterial3D"}}
    }}
  ]
}
```

- `script`: a `res://….gd` whose base class is `Resource` (or a Resource subclass) — the way to author the data resources a data-driven game is built from. `resource_type` is ignored when `script` is set; a contradicting `resource_type` is reported as `[INFO] resource_batch ignored resource_type=Gradient: … extends Resource`.
- The saved `.tres` is what the editor writes: `[gd_resource type="Resource" script_class="ItemData" format=3]`, an `[ext_resource type="Script" path="res://items/item_data.gd" …]` line, and `script = ExtResource("…")` in the `[resource]` block. Typed exports round-trip as `tags = Array[String](["melee", "sharp"])`.
- `duplicate_from` keeps the source's script, so duplicating a script-backed `.tres` yields another instance of the same custom class; `script` is ignored (and reported) in that case, and when the target file already exists.
- Run `godot --headless --path PROJECT --import` once after adding a new `class_name` script so the global class cache knows it — otherwise other scripts that annotate `@export var item: ItemData` fail to compile.
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
  "ascii_map": {
    "legend": {
      "#": {"source_id": 0, "atlas_coords": {"x": 0, "y": 0}, "alternative": 0},
      "o": {"source_id": 0, "atlas_coords": {"x": 1, "y": 0}},
      "G": {"terrain_set": 0, "terrain": 1},
      ".": null
    },
    "rows": ["#####", "#ooo#", "#GGG#", "#####"],
    "origin": {"x": 0, "y": 0},
    "erase_unlisted": false
  },
  "cells": [{"coords": {"x": 9, "y": 0}, "source_id": 0, "atlas_coords": {"x": 0, "y": 0}}],
  "fills": [{"from": {"x": 0, "y": 9}, "to": {"x": 9, "y": 9}, "source_id": 0, "atlas_coords": {"x": 1, "y": 0}}],
  "erase": [{"x": 5, "y": 5}],
  "clear": false
}
```

- Order per call: optional `tile_set` assignment → `clear` → `erase` → `cells` → `fills` (inclusive rectangles) → `ascii_map` → `terrain_fills`. `ascii_map` therefore wins wherever it overlaps `cells`/`fills`.
- **`ascii_map` is the readable way to author a level, and the only one a model without vision can verify** — `inspect_tilemap` reads the same rows back. Prefer it over long `cells` lists.
- `ascii_map.rows`: an array of strings, or one `\n`-separated string (`"#####\n#...#"`). Leading/trailing empty lines are dropped. Row 0 is `origin.y` and y increases downward; character column 0 is `origin.x`. `origin` defaults to `{"x": 0, "y": 0}`.
- `ascii_map.legend`: one character → one tile. `{"source_id", "atlas_coords", "alternative"}` paints a tile directly; `{"terrain_set", "terrain", "ignore_empty_terrains"}` is collected across the whole map and painted with `set_cells_terrain_connect` after the plain cells (mixing the two in one entry is an error). Mapping a character to `null` leaves those cells untouched — `.` and space mean that even with no legend entry.
- `erase_unlisted: true` makes every "untouched" character (`.`, space, and any legend entry mapped to `null`) *erase* the cell instead, which is how you cut a hole in an existing map.
- A character that is neither in the legend nor `.`/space is an **error**: the op names the unknown characters and the legend keys, paints nothing, and does not save the scene. Rows of unequal length are only a `[WARN]` — the short row simply stops early.
- `terrain_fills`: `[{"cells": [{x,y}, ...], "terrain_set": 0, "terrain": 0}]` runs `set_cells_terrain_connect` for autotiling — the TileSet's tiles need terrain membership and peering bits (see `build_tileset`). When the TileSet has no tile matching the requested neighbourhood the engine paints **nothing**; both this and the `ascii_map` terrain path emit `[WARN] ... left N of M cells empty` instead of reporting a clean save over an empty map.
- Painting fails fast if the atlas source has not exposed the requested `atlas_coords` — expose tiles with `build_tileset` first.
- Read the result back as text with `inspect_tilemap`.

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
  "legend": {"A": {"item": 0, "orientation": 0}, "B": {"item": 1}, ".": null},
  "ascii_layers": [
    {"y": 0, "rows": ["AAAA", "A..A", "AAAA"]},
    {"y": 1, "rows": ["B..B", "....", "B..B"], "origin": {"x": 0, "z": 0}}
  ],
  "clear": false,
  "fills": [{"from": [0, 0, 0], "to": [7, 0, 7], "item": 0, "orient": 0}],
  "cells": [{"pos": [3, 1, 4], "item": 2, "orient": 22}],
  "erase": [[0, 0, 0]]
}
```

- Order per call: `mesh_library` → `cell_size` → `clear` → `erase` → `cells` → `fills` → `ascii_layers`.
- `pos`/`from`/`to`/`erase` accept `[x,y,z]` or `{x,y,z}`. `item` must exist in the mesh library; `orient` is a `0`–`23` orthogonal index. Also runs inside `scene_batch`.
- `ascii_layers` is the ASCII form, one entry per horizontal slab: rows map to **z** increasing, characters to **x**, and `y` names the slab. Per-layer `origin` is `{"x": 0, "z": 0}`.
- The `legend` is shared by every layer and takes `{"item": 0, "orientation": 0}` (`orient` is accepted too); `null`, `.` and space leave the cell untouched, and `erase_unlisted: true` makes them erase. The same rules as `paint_tilemap.ascii_map` apply: unknown character → error naming it and the legend keys, nothing painted, scene not saved; ragged rows → `[WARN]`. Every layer is validated before any cell is written.
- Read it back with `inspect_tilemap`, which handles `GridMap` as well as `TileMapLayer`.

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

### Static Lint (No Godot Needed)

```bash
python3 scripts/debug/lint_project.py /absolute/project --pretty
python3 scripts/debug/lint_project.py /absolute/project --only godot3_api,node_ref
```

Runs without a Godot binary, without an import step, in well under a second, and prints the same JSON shape as `godot_log_parser.py`: `ok`, `counts`, and a `diagnostics` array of `severity`, `category`, `message`, `file`, `line`, `suggested_fix` (plus `rule` and a `scan_summary` of files scanned per kind). Exit code is 1 when any error-level diagnostic exists.

- Severity has one meaning: **error** = Godot refuses to parse or load the file, so the project does not run; **warning** = it compiles and runs but is risky. Every severity was checked against `godot 4.7.stable` rather than assumed.
- Six categories, all fixed names: `godot3_api`, `inference`, `node_ref`, `unique_name`, `signal_target`, `missing_resource`. `--only cat1,cat2` filters; `--path <subdir>` restricts the walk; `--warnings-as-errors` fails on warnings; `--include-addons` opts `addons/` back in (`.godot/`, hidden directories and `.import` files are always skipped).
- `godot3_api` catches Godot 3 API in a 4.x project — `onready var`, `export var`, `yield(`, `.instance()`, `setget`, string-form `connect("sig", obj, "method")`, `move_and_slide(velocity)`, `rand_range`, `deg2rad`, `File.new()`, `rect_min_size`, `margin_left`, `Color.white`, and the renamed classes (`KinematicBody2D`, `Spatial`, `Sprite`, `Camera`, `Pool*Array`, `StreamTexture`, …) both in `.gd` and as `type="…"` in `.tscn`/`.tres`. Every rule's fix names the exact 4.7 replacement. `references/godot3_to_4.md` is the same table as a rename doc; `--list-rules` regenerates it.
- `inference` checks the type `:=` actually produces, classifying the **outermost** expression of the right-hand side — so `var p := _to_path(params.get("p", ""))` is silent when `_to_path()` declares `-> String`. Error (Godot refuses to parse): `.get()`, a `[...]` read from an untyped `Array`/`Dictionary`, `JSON.parse_string()`, `null`, `.call()`, a call into a same-file function with no `-> Type`. Warning (compiles, but the variable is typed bare `Node` and every later `.text`/`.play()` is unchecked): `$Node`, `%Unique`, `get_node()`, `.instantiate()`. `load()`/`preload()` are not reported — the analyzer types them. See `references/gdscript_conventions.md`.
- `node_ref` / `unique_name` resolve every `$Path`, `%Name`, and bare `get_node("…")` in a script against the tree of each `.tscn` that attaches it — following `..`, and descending into an `instance=ExtResource(…)` child scene when a path reaches into one. A script attached to a sub-scene root is checked against that sub-scene, not the level that instances it. The fix names the scene, the node the script is attached to, and the children that *do* exist (`Panel has children: Title, Icon`).
- `signal_target` checks every `[connection]`: `from`/`to` must be real nodes and the target's script must define the handler — `func <method>(` in GDScript, `<method>(` in a `.cs` file, and any other scripting language is skipped rather than guessed. A wrong path is dropped silently by Godot, and a missing method only fails when the signal fires.
- `missing_resource` checks `[ext_resource]` paths, `preload()`/`load()` literals, and `project.godot`'s `run/main_scene` and `[autoload]` entries. A scene with a missing `ext_resource` still loads and instantiates, so nothing else reports it.
- It is text-only and errs toward silence: node paths built at runtime (`str()`, `+`, `%s`) are skipped rather than guessed, only a bare (or `self.`) `get_node()`/`$`/`%` is resolved (`slot.get_node("Icon")` belongs to another node), and a name the project itself defines — `class_name File`, `static func empty()` — suppresses the matching rename rule. A node that comes from `instance=ExtResource(...)` is another scene's root: its script is checked against that `.tscn`, never the level that instances it. Nodes added with `add_child()` are reported, because they are not in any `.tscn`. Multi-line `"""` strings are scanned as code.
- `validate_project.py` runs this pass first and merges the result: lint entries appear at the top of `diagnostics` with `"source": "lint"`, their counts fold into `counts`, the raw report is under `lint`, and lint errors alone make `ok` false. `--no-lint` opts out.

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

It runs Godot with `-d --ignore-error-breaks`, so its report includes the GDScript warnings the editor shows — which a plain headless run never prints — for **every** script in the project, not just the ones a boot happens to load. Output carries `counts` and `diagnostics` (same shape as `run_project.py`) alongside the file-level `static` summary, and `ok` is false whenever an error-level diagnostic appears even if every file technically loaded. Flags: `--warnings-as-errors` to fail on warnings, `--no-warnings` to drop them from the report, `--no-debugger` to reproduce the old warning-free behaviour, `--no-instantiate` to skip the scene-instantiation pass below.

### check_project And The Instantiate Pass

`validate_project.py` is a wrapper around the `check_project` operation, which can also be called directly:

```bash
godot --headless --debug --ignore-error-breaks --path /absolute/project \
  --script /absolute/godot/scripts/core/dispatcher.gd \
  check_project '{}' 2>&1 \
  | python3 /absolute/godot/scripts/debug/godot_log_parser.py -
```

Parameters: `project_path` (default `res://`, restricts the walk to a subtree) and `instantiate` (bool, **default `true`**). The JSON summary reports `checked`, `failed_count`, `failed` (path / kind / reason), `counts` per kind, plus `instantiate` and `scenes_instantiated`.

Every `.tscn`/`.scn` that loads is also passed through `PackedScene.instantiate()`. This matters because `load()` accepts every broken node hierarchy — a directory of scenes containing every hierarchy mistake in `references/tscn_format.md` used to report `"failed_count": 0`. What the pass adds:

| Mistake in the `.tscn` | What instantiating produces | Reported as |
| --- | --- | --- |
| Root `[node]` carries `parent="."` | `ERROR: Invalid scene: root node X cannot specify a parent node.`; `instantiate()` returns `null` | **Failure** in `failed[]` + an error diagnostic |
| Non-root `[node]` has no `parent=` | `ERROR: Invalid scene: node X does not specify its parent node.`; `instantiate()` returns `null` | **Failure** in `failed[]` + an error diagnostic |
| `parent=` names a node that does not exist | `WARNING: Parent path './VBox' for node 'Label' has vanished when instantiating: 'res://…tscn'.`; the node is reparented to the root as `VBox#Label` | **Warning** only — the scene still instantiates. `--warnings-as-errors` makes it fail |
| Every node carries `parent="."` (fully flat tree) | Nothing at all — a flat tree is valid | **Not caught.** Only `inspect_scene` reveals it |

The two `Invalid scene:` errors name the offending *node*, never the scene, so read the scene path from the `failed[]` entry (the log parser files them under category `scene_hierarchy`; the vanished-parent warning does name its scene and is attributed to it). A failed instantiate also makes the engine leak the half-built nodes, so a run that reports one ends with a harmless `WARNING: N ObjectDB instances were leaked at exit`.

**What instantiating executes.** The scene root script's `_init()`, and every script setter for a property stored in the `.tscn` (an `@export` with a custom setter runs with the stored value). `_enter_tree()` / `_ready()` do **not** run — nothing is added to a tree — and `get_tree()` is `null` inside `_init()` and inside those setters. That is byte-for-byte what the running game does when it instantiates the same scene, so an error raised here is an error the game would raise too. Autoload singletons **are** available (the dispatcher defers the operation until the `SceneTree` has registered them), so a scene script that reads one is not a false failure. Pass `{"instantiate": false}` (or `--no-instantiate`) for a pure load-only pass that runs no project code — the right choice only when a scene's `_init()` has side effects you do not want, since it re-opens the hierarchy blind spot.

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

Step types are `wait_frames`, `wait_seconds`, `action`, `key`, `mouse_button`, `mouse_motion`, `joypad_button`, `joypad_motion`, `assert`, `wait_until`, `set_property`, `screenshot`, `ui_report`, `dump_tree`, and `log_marker`. An unsupported type is rejected with the full list.

- `wait_until`: polls a property assertion every frame until it passes or `timeout_seconds` (default 5) elapses — prefer it over guessing `wait_frames` counts. Fields match `assert` (`node_path`, `property`, `expected`, `operator`, `tolerance`).
- `set_property`: writes a typed value to a node's (sub)property and waits one frame — useful for arranging state before an interaction.
- `ui_report`: dumps the laid-out UI as text and machine-checks the layout — see below.
- `dump_tree`: prints the live node tree with the properties you name, and returns it as data — see below.

Property assertion operators are `equals`, `not_equals`, `greater_than`, `greater_or_equal`, `less_than`, `less_or_equal`, `contains`, and `approx`. Performance monitors are `fps`, `process_time`, `physics_process_time`, `static_memory`, `node_count`, `resource_count`, `draw_calls`, `primitives`, and `video_memory`; statistics are `average`, `minimum`, and `maximum`.

The root viewport is always sized before the scene is added: to `viewport_size` when given, otherwise to the project's own `display/window/size/viewport_width`/`viewport_height`. A headless display server opens a 64x64 window, so without this every anchor, container layout and viewport-space input coordinate would resolve against a viewport no player ever sees.

### Input And Timing Facts

- An `action` step calls `Input.action_press`/`action_release`, so it moves the polled state only and `_input` / `_unhandled_input` / `_gui_input` never run. Player controllers poll and work with it; pause menus, dialog advance and interact prompts need a `key` step, which feeds a real `InputEventKey` through `Input.parse_input_event`.
- Godot's built-in `ui_*` actions are bound by `keycode` (`ui_cancel` 4194305, `ui_accept` 4194309, `ui_down` 4194322); actions this skill creates use `physical_keycode`. Setting the wrong field produces an event matching no action at all.
- `wait_frames` counts *process* frames, and a headless run spins those far faster than the fixed 60 Hz physics tick, so `wait_frames: 60` is a fraction of a second of simulated falling. Use `wait_seconds` or `wait_until` for anything driven by gravity, `move_and_slide`, or a Tween.
- With `display/window/stretch/mode` set to `canvas_items`, a scenario's `viewport_size` resizes the window but the UI still lays out against the project's base viewport, so verifying a menu at "two resolutions" is one layout there. Size the type to the base viewport instead.

### screenshot

Captures the root viewport to a PNG **and** describes it as numbers, so a caller that cannot look at the image still learns whether anything was drawn, where, and in what colour. A screenshot step is the only thing that forces a rendered (non-headless) window.

```json
{"type": "screenshot", "path": "/absolute/output/menu.png",
 "expect": {"not_blank": true, "min_opaque_ratio": 0.1, "max_diff_ratio": 0.02, "compare_to": "res://tests/reference/menu.png"},
 "describe": {"ascii": true, "ascii_width": 80, "ascii_color": true}}
```

- `path` (required): `res://`, `user://`, or absolute. Parent directories are created.
- `describe` (optional): options handed to `image_describe.describe`. `ascii` adds a luminance-ramp rendering of the capture to the summary and prints it; `ascii_width` (default 64) sets its column count; `ascii_color` adds the `K W R G B Y C M` colour grid.
- `expect` (optional): each key that is violated fails the scenario the way a failed assertion does — the run continues, `ok` becomes false, and the message names the number that was actually measured.
  - `not_blank`: fails when every pixel is identical or everything is transparent. The message reports the unique-colour count, `opaque_ratio` and `mean_color`.
  - `min_opaque_ratio`: fails when the share of pixels with alpha > 0 is below the value.
  - `compare_to` + `max_diff_ratio`: loads that PNG and fails when more than `max_diff_ratio` of the pixels differ from it. A size mismatch is reported as its own failure — capture the reference at the same `viewport_size`.

An unknown key in either object is rejected with the accepted list rather than silently checking nothing.

Every capture appends to `screenshots` on the result JSON:

```json
{"path": "/absolute/output/menu.png", "width": 640, "height": 320, "passed": true,
 "summary": {"width": 640, "height": 320, "has_alpha": false, "blank": false, "opaque_ratio": 1.0,
             "content_bbox": {"x": 24, "y": 16, "w": 576, "h": 284},
             "content_bbox_normalized": {"x": 0.04, "y": 0.05, "w": 0.9, "h": 0.89},
             "mean_color": "#1a1a26", "dominant_colors": [{"hex": "#111122", "ratio": 0.82}],
             "unique_colors": 37, "quadrants": {"top_left": 0.31, "top_right": 0.2, "bottom_left": 0.29, "bottom_right": 0.2},
             "ascii": ["....====#####...", "..."]}}
```

and prints one grep-able line (plus the ASCII rows when asked for):

```
[SCENARIO] screenshot /absolute/output/menu.png blank=false opaque=1 bbox=24,16,576,284 dominant=#111122
```

`blank=true` on a scene you believe draws something is the single most useful signal here: it means the capture is one flat colour, so the node is hidden, outside the viewport, or was never added to the tree.

### ui_report

Walks the scene tree and reports every visible Control's post-layout global rect, then machine-checks the layout. It is how to see the UI without looking at an image, and it is what catches the failure mode where controls authored with `layout_mode = 0` and no offsets all land on each other at (0, 0) — a screenshot shows that instantly, no other text check shows it at all. Rects resolve identically headless, and `ui_report` alone never forces a rendered window.

- `node_path` (default `"."`): subtree to walk. Report paths stay relative to the **scene root** either way, so they paste straight into a later `node_path`.
- `include_hidden` (default `false`): also list controls that are not visible in tree. Hidden controls are described but never produce findings.
- `path` (optional): also write the report to a JSON file (`res://`, `user://`, or absolute).
- `label` (optional): names the report in the result; defaults to `steps[<index>]`.
- `ascii` (default `false`): also render the layout as a character map (see below).
- `ascii_width` (default `80`, clamped to 8–400): column count for that map.
- `fail_on` (optional): array of finding kinds that fail the scenario the way a failed assertion does, or `["any"]`. An unknown kind is rejected instead of silently gating on nothing.
- `min_overlap_ratio` (default `0.1`): the share of the smaller rect two siblings must share before the overlap is reported. Keeps 1px seams quiet.
- `strict_overlap` (default `false`): set to also report the backdrop case below.
- `settle_frames` (default `2`, minimum 1): frames awaited before sampling. Containers place their children through a deferred sort, so rects read in the same frame the tree changed still say (0, 0) and every child would look stacked. The step waits so callers never have to.

Reports arrive in `ui_reports` on the result JSON, in step order, and are written verbatim to `path`:

```json
{
  "label": "boot",
  "node_path": ".",
  "passed": false,
  "rect_format": "[x, y, width, height]",
  "viewport": {"width": 1280, "height": 720},
  "counts": {"controls": 4, "visible": 4, "hidden": 0, "findings": 1},
  "controls": [
    {"path": ".", "class": "Control", "rect": [0, 0, 1280, 720]},
    {"path": "Backdrop", "class": "ColorRect", "rect": [0, 0, 1280, 720]},
    {"path": "Panel/Title", "class": "Label", "rect": [0, 0, 160, 30], "text": "Inventory"},
    {"path": "Panel/Close", "class": "Button", "rect": [0, 0, 160, 31], "text": "Close"}
  ],
  "findings": [
    {"kind": "overlap", "nodes": ["Panel/Title", "Panel/Close"],
     "rects": [[0, 0, 160, 30], [0, 0, 160, 31]], "parent": "Panel",
     "overlap_rect": [0, 0, 160, 30], "ratio": 1,
     "message": "Panel/Title (Label) [0, 0, 160, 30] and Panel/Close (Button) [0, 0, 160, 31] cover 100% of the smaller rect, but their parent Panel (Control) leaves placement to the author"}
  ],
  "file": "/absolute/output/boot_ui.json"
}
```

Control entries carry `text` when the node has a non-empty text property (trimmed to 60 characters), `top_level: true` when the node opts out of its parent's transform, and — only when `include_hidden` is set — `visible` plus `self_hidden` for the node that actually holds the `visible = false`. Findings always carry `kind`, `nodes`, `rects`, and a one-line `message`:

- `zero_size`: a visible Control whose width or height is zero. Godot clamps a negative size to zero, so this covers inverted offsets too.
- `offscreen`: a visible Control whose rect lies **entirely** outside its viewport (partially clipped controls are not reported).
- `overlap`: two visible sibling Controls sharing at least `min_overlap_ratio` of the smaller rect under a parent that was not supposed to stack them. Also carries `parent`, `overlap_rect`, and `ratio`.

The overlap rule, precisely. A pair is reported when the parent is **not** a `Container` (placement came from the author's anchors and offsets) or is one of the containers documented to lay children out side by side — `BoxContainer` (`HBoxContainer`/`VBoxContainer`), `GridContainer`, `FlowContainer`, `SplitContainer` — where an overlap really is a defect. Every other `Container` is skipped: `MarginContainer`, `PanelContainer`, `CenterContainer`, `AspectRatioContainer`, `ScrollContainer`, `SubViewportContainer` and `TabContainer` hand every child the same slot, so overlap there is the engine doing its job, and a custom `Container`'s sort rule is unknown so it is not second-guessed. Two further exemptions: a `top_level` control places itself in screen space and is left out of sibling pairing, and a `ColorRect`, `Panel`, `TextureRect`, `NinePatchRect` or `ReferenceRect` whose rect fully covers a sibling is treated as a background layer rather than an overlap — that last one is the only heuristic in the rule, and `strict_overlap: true` turns it off.

There is deliberately no `text_clipped` finding: Godot clamps `Control.size` up to `get_combined_minimum_size()`, so a Label or Button rect is never smaller than its own text unless `clip_text`/`text_overrun_behavior` asked for truncation. Any check would have reported only deliberate elisions.

With `"ascii": true` the report carries an extra `ascii` array of equal-length rows, printed after the summary line. Every visible Control's global rect is drawn as a box — `+` corners, `-` and `|` edges — with the node's name written into its top edge, truncated to the box width. The walk is pre-order, so parents are drawn first and children overwrite them: two controls that landed on each other visibly collide instead of hiding behind two similar-looking rect arrays. The row count is `ascii_width × viewport_height / viewport_width × 0.5`, because character cells are about twice as tall as they are wide, so the map keeps the screen's proportions.

```
[SCENARIO] ui_report boot ascii 72x18
+B+Title---------------------+-----------------------------------------+
| |                          |                                         |
| +--------------------------+                                         |
| +Slot1-+-------------------------+                                   |
| |      |                         |                                   |
| +------+                         |                                   |
| |                                |                                   |
| +--------------------------------+                  +Close-------+   |
|                                                     |            |   |
|                                                     +------------+   |
+----------------------------------------------------------------------+
```

Nothing else about `ui_report` changes: the same rects, counts and findings are produced with or without `ascii`, and it still never forces a rendered window.

A UI regression scenario, gated end to end:

```json
{
  "scene_path": "scenes/hud.tscn",
  "viewport_size": {"width": 1280, "height": 720},
  "steps": [
    {"type": "ui_report", "label": "boot", "path": "/absolute/output/boot_ui.json",
     "fail_on": ["overlap", "zero_size", "offscreen"]},
    {"type": "action", "action_name": "ui_accept", "pressed": true, "release_after": true},
    {"type": "wait_until", "node_path": "Panels/Inventory", "property": "visible", "expected": true},
    {"type": "ui_report", "label": "inventory-open", "node_path": "Panels/Inventory", "fail_on": ["any"]},
    {"type": "log_marker", "message": "inventory-verified"}
  ],
  "assertions": [
    {"assertion": "property", "node_path": "Panels/Inventory/Grid", "property": "columns", "expected": 4}
  ],
  "log_assertions": [{"regex": "ui_report inventory-open .* overlap=0"}]
}
```

### dump_tree

Prints the live node tree, indented, with only the properties you asked for — and returns the same thing as data. It is the discovery step: dump once, read the real node paths and values, then write precise `assert` steps against them.

```json
{"type": "dump_tree", "node_path": "/root/Main", "label": "after_click",
 "properties": ["visible", "position", "global_position", "text", "modulate", "scale"],
 "max_depth": 6, "include_internal": false}
```

- `node_path` (default: the current scene root, falling back to `/root`): `"."`, a path relative to the scene root, or an absolute `/root/...` path. A path that resolves to nothing is an error naming all three forms.
- `properties` (default `["visible", "position", "text"]`): only the ones a node actually has are read — a `Sprite2D` asked for `text` simply omits it, never errors. Works for script `@export` vars too.
- `max_depth` (default `6`): `0` dumps only the starting node, `1` adds its direct children, and so on.
- `include_internal` (default `false`): include the internal children engine nodes add for themselves (a `ScrollContainer`'s scrollbars, a `LineEdit`'s caret timer).
- `label` (optional): names the dump in the result; defaults to `steps[<index>]`.

Values are formatted compactly: `Vector2` as `(x, y)`, `Color` as `#rrggbb` (`#rrggbbaa` when translucent), `String` quoted and trimmed to 40 characters, a `Resource` as its `resource_path` or `<ClassName>`, arrays and dictionaries as `[n items]` / `{n keys}`.

```
[SCENARIO] dump_tree boot node_path=. nodes=6 max_depth=6
Hud (Control) visible=true position=(0, 0) size=(640, 320) modulate=#ffffff
  Backdrop (ColorRect) visible=true position=(0, 0) size=(640, 320) modulate=#ffffff
  Title (Label) visible=true position=(24, 16) size=(236, 32) text="Inventory" modulate=#ffffff
  Grid (GridContainer) visible=true position=(24, 64) size=(296, 196) modulate=#ffffff
    Slot1 (Button) visible=true position=(0, 0) size=(57, 31) text="Sword" modulate=#ffffff
  Close (Button) visible=true position=(480, 260) size=(120, 40) text="Close" modulate=#ffffff
```

Each dump appends to a `tree_dumps` array on the result JSON. `lines` is the text above; `nodes` is the machine-readable form, with `path` relative to the dumped root (so it pastes straight into a later `node_path`) and `props` encoded through the shared typed-JSON codec:

```json
{"label": "boot", "node_path": ".", "node_count": 6,
 "lines": ["Hud (Control) visible=true position=(0, 0)", "  Title (Label) ..."],
 "nodes": [{"path": ".", "type": "Control", "props": {"visible": true, "position": {"__type": "Vector2", "x": 0, "y": 0}}},
           {"path": "Title", "type": "Label", "props": {"visible": true, "text": "Inventory"}}]}
```

### Verification Without Vision

Everything the runner produces is text, including the screenshots. A model that cannot look at an image loses nothing by running this loop:

1. **Instrument the gameplay path.** Print one line per decision that matters (`print("[HUD] wave=%d hp=%d" % [wave, hp])`), and separate phases with `log_marker` steps so the log has section boundaries to search between.
2. **Script the session**: `python3 scripts/debug/run_scenario.py PROJECT SCENARIO --log-file /tmp/run.log --pretty`. Input steps drive it deterministically and `wait_until` waits on state instead of guessed frame counts, so one run reaches the state worth checking.
3. **Find out what is actually there with `dump_tree`.** One dump after boot gives the real node paths, classes and property values; every later `assert`, `set_property` and `ui_report` `node_path` can then be written against names that exist instead of guessed ones. Dump again after an interaction and diff the `lines` to see exactly what the click changed.
4. **Read the UI with `ui_report`** at every moment worth checking — after boot, after a panel opens, after a resolution change. Gate it with `fail_on` so a stacked, zero-sized or offscreen layout fails the run instead of waiting to be noticed, and add `"ascii": true` when the rect list alone is not telling you where things sit. Scope big screens with `node_path`, and pass `path` when the report should outlive the run.
5. **Assert the properties that carry the meaning**: `{"assertion": "property", "node_path": "HUD/Score", "property": "text", "expected": "1200"}`, plus `visible` and `node_exists` for the nodes a state change is supposed to add or reveal. Report and dump paths are already in the right form to paste into `node_path`.
6. **Make the screenshot itself a text check.** `{"type": "screenshot", "path": "…", "expect": {"not_blank": true, "min_opaque_ratio": 0.1}}` catches the render that produced nothing — the case `ui_report` cannot see, because a correctly laid-out Control still draws nothing when its texture, material or camera is wrong. Add `"compare_to"` plus `"max_diff_ratio"` once a good capture exists to gate visual regressions, and `"describe": {"ascii": true}` when you want to see the frame.
7. **Parse the captured log**: `python3 scripts/debug/godot_log_parser.py /tmp/run.log --pretty` turns it into structured errors and warnings. The wrapper keeps `-d --ignore-error-breaks` on by default, so GDScript warnings the editor would show actually reach the log; `log_assertions` gate on the prints from step 1.
8. **Read the exit code**: `0` only when every assertion, log assertion, performance assertion, gated `ui_report` finding and screenshot `expect` passed.
9. **Read levels back as text.** After any `paint_tilemap` / `paint_gridmap`, run `inspect_tilemap '{"scene_path": "scenes/level.tscn", "format": "text"}'` and compare the rows with what you meant to paint. This is the only check that catches an off-by-one `origin`, a legend character mapped to the wrong atlas tile, or a terrain fill that matched no tile — the scene still saves and still reports `ok` in all three cases.

Each step also prints one grep-able line, so step 7 can gate on the layout and the render without parsing the payload:

```
[SCENARIO] ui_report inventory-open controls=12 visible=12 hidden=0 findings=0 zero_size=0 offscreen=0 overlap=0
[SCENARIO] dump_tree after_click node_path=. nodes=41 max_depth=6
[SCENARIO] screenshot /tmp/out/inventory.png blank=false opaque=1 bbox=24,16,576,284 dominant=#111122
```

Files are checkable too. `inspect_image` answers, for any PNG on disk, the questions a look would answer:

```bash
godot --headless --path /absolute/project \
  --script /absolute/godot/scripts/core/dispatcher.gd \
  inspect_image '{"image_path":"art/player.png","format":"text","ascii":true,
                  "expect":{"not_blank":true,"has_alpha":true,"max_unique_colors":32}}'
```

- **Did the sprite render at all?** `blank: false` plus `opaque_ratio` above zero. Gate it with `{"not_blank": true, "min_opaque_ratio": 0.1}`; a file that is one flat colour is an empty capture or a failed generation, whatever its size.
- **Did the cutout work?** `has_alpha: true` and `opaque_ratio` below `1.0`. A chroma-key pass that silently did nothing reports `has_alpha: false`, `opaque_ratio: 1.0` and a `dominant_colors` entry at `#00ff00`.
- **Is it centred / where is it?** `content_bbox_normalized`: centred means `x + w/2` and `y + h/2` are both near `0.5`. `quadrants` says the same thing coarsely — one quadrant at `1.0` is content stuck in a corner, four near `0.25` is content spread over the frame. `content_bbox` at `{0,0,1,1}` of the normalized frame means the art fills its canvas with no margin, which is what makes a sprite clip against its collision box.
- **Is the art pixel-art sized?** `unique_colors` — a limited palette is tens of colours, an anti-aliased or resampled export is thousands. Gate with `{"max_unique_colors": 32}`.
- **Are all the frames the same size?** `{"image_paths": ["art/hero_idle"], "expect": {"frames_consistent": true}}` before `build_sprite_frames`; frames that changed canvas size mid-run animate as a jitter no assertion downstream will explain.
- **Did it change?** `compare_to` plus `{"max_diff_ratio": 0.01}` against a known-good capture. `0.0` means byte-identical; print the `ascii` of both when the number says something moved.
- **What does it look like?** `"ascii": true` (add `"ascii_color": true` for hue letters). It is a low-resolution read, not a preview: use it to confirm a shape is where the numbers say it is.

## Typed JSON Values

The shared codec accepts plain JSON plus:

- Resource reference: `{"__resource":"res://theme/main.tres"}`.
- Resource construction: `{"__resource_type":"Gradient","properties":{...}}`, optionally with an ordered `"method_calls":[{"method":"add_point","args":[...],"expect_ok":false}]` for builder-only state.
- Custom resource construction: `{"__script":"res://items/item_data.gd","properties":{...}}` instantiates a project-defined `class_name ItemData extends Resource`, which `__resource_type` cannot reach because ClassDB only knows engine classes. It accepts the same `resource_name`, `properties`, and ordered `method_calls` keys as `__resource_type`, and nests to any depth. The script must resolve to a `Resource` subclass — a `Node` script is refused by name (`… extends Node2D, which is not a Resource`). Passing both `__script` and `__resource_type` in one value is an error; keep `__script`.
- `StringName`, `NodePath`, `Vector2`, `Vector2i`, `Rect2`, `Rect2i`, `Vector3`, `Vector3i`, `Transform2D`, `Vector4`, `Vector4i`, `Plane`, `Quaternion`, `AABB`, `Basis`, `Transform3D`, `Projection`, and `Color` through `{"__type":"TypeName",...}`.
- Packed byte/int/float/string/vector/color arrays through `{"__type":"Packed...Array","values":[...]}`.
- Curve sugar: `{"__curve":{"min_value":0,"max_value":1,"points":[{"x":0,"y":0},{"x":1,"y":1,"left_tangent":0,"right_tangent":0}]}}` builds a `Curve` (its points are otherwise builder-only, so this is the ergonomic way to inline scale/alpha/velocity ramps).
- Gradient sugar: `{"__gradient":{"points":[{"offset":0,"color":"..."},{"offset":1,"color":"..."}]}}` (or `{"offsets":[...],"colors":[...]}`) builds a clean `Gradient` with exactly those stops — unlike `add_point`, which appends to the two default stops.

`Rect2`/`Rect2i` accept either typed `position` plus `size` dictionaries or the compatibility form `x`, `y`, `width`, `height`.

Property writes are type-checked against the target's script variables before they are applied. `Object.set()` drops a mismatched write without raising, so an untyped JSON array is converted into the property's declared `Array[T]` / `Dictionary[K, V]` type, and anything genuinely incompatible fails the operation with the expected type named (`expected Vector2 but got a plain dictionary; tag the value as {"__type": "Vector2", ...}`). A misspelled property lists the script's exported names: `Property does not exist at set_properties.properties: displayname (did you mean display_name?). ItemData script properties: display_name, price, icon, tags, stats`.

## Export Preflight And Patches

```bash
python3 scripts/export/export_project.py PROJECT PRESET OUTPUT --preflight-only
python3 scripts/export/export_project.py PROJECT PRESET update.pck \
  --mode patch --patches base.pck previous_patch.pck
```

Preflight checks the exact preset, matching export-template directory, Godot executable, platform tools, patch inputs, and common output extensions. Dry runs report preflight findings without failing unless `--strict-preflight` is set. Real exports fail on preflight errors unless `--skip-preflight` is explicitly supplied.
