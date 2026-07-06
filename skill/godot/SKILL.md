---
name: godot
description: Godot project development, debugging, runtime validation, architecture design, creative content integration, animation integration, and export skill for inspecting projects, building and fully configuring scenes, wiring scripts and signals, configuring UI, designing or refactoring modular Controller or System or Model style feature boundaries, adding art, integrating provided or separately generated music and story content through project-native flows, integrating frame animations, running projects to capture and fix runtime debugger errors, validating scripts and scenes, exporting mobile (iOS and Android), web, and desktop (Windows and macOS) builds, exporting mesh libraries, and repairing resource UIDs. Designed for Godot 4.7 and compatible with Godot 4.x. Use when Codex needs to work inside a Godot project and should follow the bundled Godot workflows; if the host exposes native Godot runtime tools, use them to run the project, validate implemented features, capture the debugger's errors, and fix them.
---

# Godot

Use this skill to inspect and modify Godot projects with the bundled workflows, scripts, and any available host-native Godot automation tooling, including gameplay presentation work such as art generation, frame animation integration, and project-native integration of provided or separately generated music and story content.

## Start

- Verify which Godot automation path is available before planning edits. Prefer any native or mapped Godot tools in the host agent. Use the bundled headless dispatcher only for the supported file and scene operations listed below.
- Resolve `project_path` to an absolute project directory when a host tool requires it.
- Normalize scene and resource paths to `res://...` when working directly with the bundled Godot scripts in this skill.
- Inspect unfamiliar projects with any available project-discovery tools, or fall back to reading `project.godot`, scene files, and scripts directly.
- When the task involves art, music, or story, inspect the existing visual style, palette, audio direction, and narrative format before creating new content.
- If the user does not specify a style, preserve any clearly established project direction first. If there is no established direction to follow, default new visual work to a pixel-art style and keep related presentation choices consistent with it.
- Read `references/asset_pipeline.md` only when the task involves generated art, cutouts, or frame animation assets.
- Read `references/architecture_qframework_lite.md` only when the task involves Godot architecture design, modular refactoring, feature boundaries, controller or system or model responsibilities, command and query separation, or QFramework-style structure.
- Read `references/architecture_templates.md` only when you need a ready folder layout or starter skeletons for Godot `GDScript` or `C#` architecture work.
- Read `export_presets.cfg` before planning export work. Reuse the preset names, bundle identifiers, signing settings, and feature tags that already exist instead of inventing replacements.
- Require a local `godot` CLI with shell access before using the bundled dispatcher fallback, runtime runner, or CLI export wrapper. The bundled APIs are designed against the current stable Godot docs and verified on Godot `4.7` (compatible with Godot 4.x).
- Read `references/export_targets.md` only when the task involves packaging, signing, or shipping builds for Android, iOS, Web, Windows, or macOS.
- Read `references/debugging.md` when the task involves running the project, reading the Godot debugger's errors, and fixing them.
- Install this skill in a folder named `godot` so the folder name matches `name: godot` in hosts that validate skill naming.

## Godot 4.7 Notes

- Verified on `godot 4.7.stable`. The scene and control operations set node properties and instantiate node classes through `ClassDB`, so Godot 4.7 additions work with the existing operations without special-casing: new node types such as `AreaLight3D`, `VirtualJoystick`, and `DrawableTexture2D` can be added with `add_node`/`scene_batch`, and new properties such as the `Control` offset transforms (`offset_transform_enabled`, `offset_transform_position`, `offset_transform_rotation`, `offset_transform_scale`, `offset_transform_pivot` — translate/rotate/scale a control without disturbing container layout) and `CollisionShape2D.one_way_collision_direction` can be set with `configure_node`/`configure_control` using the typed-value format below.
- The runtime runner and log parser key off the stable `SCRIPT ERROR:` / `ERROR:` / `WARNING:` / `Parse Error:` output shapes, so they keep working across Godot 4.x while being verified against 4.7.

## Portable CLI Fallback

Use these paths in shell-capable environments such as Claude Antigravity when dedicated Godot tools are not exposed.
Replace `/absolute/path/to/godot` with the absolute path to the installed `godot` Skill root.

### Scene Operations Through The Dispatcher

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{"scene_path":"scenes/main.tscn","create_if_missing":true,"root_node_type":"Node2D","actions":[{"type":"add_node","node_type":"Camera2D","node_name":"Camera"}]}'
```

- Replace `scene_batch` with any supported operation: `scene_batch`, `create_scene`, `add_node`, `instantiate_scene`, `configure_node`, `configure_control`, `attach_script`, `connect_signal`, `disconnect_signal`, `remove_node`, `reparent_node`, `reorder_node`, `load_sprite`, `build_sprite_frames`, `save_scene`, `export_mesh_library`, `get_uid`, `resave_resources`, or `check_project`.
- Pass parameters as a single JSON object using the snake_case field names expected by the bundled GDScript.
- The dispatcher covers file, scene, and static-validation operations. It does not run gameplay or export builds: use the runtime runner (`scripts/debug/run_project.py`) to run and capture debugger errors, and the export wrapper (`scripts/export/export_project.py`) for builds.

### Run And Capture Debugger Errors

```bash
python3 /absolute/path/to/godot/scripts/debug/run_project.py \
  /absolute/path/to/project \
  --quit-after 120 --timeout 60
```

- Runs the project headlessly for a bounded number of frames, captures the exact stdout/stderr the Godot debugger prints, and returns JSON: `ok`, `counts`, and a `diagnostics` array where each entry has `severity`, `category`, `message`, `file`, `line`, `function`, `stack`, and a `suggested_fix`.
- Pass an optional scene as the second positional argument (`res://scenes/level.tscn`) to run and debug just that scene. Add `--no-headless` when an error only appears with real rendering, `--log-file <path>` to persist the raw log, and `--no-warnings` to drop warnings.
- Never runs Godot with `-d`; that flag opens an interactive debugger prompt that blocks on stdin. See `references/debugging.md` for the full run→diagnose→fix→re-run loop and a message→cause→fix table.

### Validate Scripts And Scenes Without Running

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  check_project '{}' 2>&1 \
  | python3 /absolute/path/to/godot/scripts/debug/godot_log_parser.py -
```

- `check_project` statically loads every script, scene, shader, and resource (or just a `{"project_path":"subdir"}` subtree) and prints a JSON summary of which files fail to compile or load. Piping its combined output through `godot_log_parser.py` yields line-level parse-error diagnostics.
- Use `godot_log_parser.py` on its own to structure any Godot log you already have: `python3 /absolute/path/to/godot/scripts/debug/godot_log_parser.py path/to/run.log`.

### Project Export Through The Wrapper

```bash
python3 /absolute/path/to/godot/scripts/export/export_project.py \
  /absolute/path/to/project \
  "Windows Desktop" \
  /absolute/path/to/build/windows/game.exe
```

- The wrapper resolves absolute paths, creates the output directory, and shells out to `godot --headless --path ... --export-release ...`.
- Pass `--mode debug` for smoke builds and `--mode pack` only when the user explicitly asks for a `.pck` style export.
- Platform support comes from the preset name already defined in `export_presets.cfg`, not from the wrapper itself. Typical preset names are `Android`, `iOS`, `Web`, `Windows Desktop`, and `macOS`.

## Follow The Main Workflows

### Design Or Refactor Architecture

1. Identify the bounded context or feature slice before moving files. Name it by business capability, not by scene title or widget name.
2. Inspect the current scripting language, autoloads, scene tree, and feature directories before proposing a new structure. Adapt to an existing architecture when one is already coherent.
3. In Godot projects, treat scene scripts, input handlers, and UI binding code as `Controller`-edge work; keep domain state in `Model` types or state-owning services; keep reusable workflows in `System`; and keep persistence, HTTP, SDK, serialization, clocks, or platform adapters in `Utility`.
4. For non-trivial features, put writes behind explicit commands or command-like use cases and keep complex reads in queries or read services instead of bloating node scripts.
5. Prefer typed signals, events, or observable state for upward notification after state changes. Do not use global singletons as catch-all mutable state bags.
6. Read `references/architecture_qframework_lite.md` for the responsibility map and review rules, then `references/architecture_templates.md` for Godot-oriented skeletons and folder layouts when you need concrete scaffolding.
7. After refactors, run the project or the deepest available smoke test and confirm scene scripts, autoload wiring, and feature entrypoints still load cleanly.

### Build Or Modify A Scene

1. Prefer `scene_batch` for multi-step work so the scene loads once, actions run in memory, and the scene saves only if every action succeeds.
2. Use `create_scene` when you only need a root scene, then follow with standalone operations if batching is unnecessary.
3. Use `add_node` or `instantiate_scene` to build structure, `configure_node` for general properties and metadata, `configure_control` for `Control` layout and theme overrides, and `attach_script` plus `connect_signal` to finish behavior wiring.
4. Keep `load_sprite` for compatibility, but prefer `configure_node` for direct `texture` assignment on sprite-compatible nodes.
5. Run the project after non-trivial edits instead of assuming the scene still loads.
6. After any functional change, actively open the game and exercise the changed feature or flow instead of stopping at a successful boot. Check whether the behavior matches the request, whether the UI or gameplay state updates correctly, and whether obvious regressions or bugs appear.
7. After the validation run, inspect the logs for `error` and `warning` output. If the feature misbehaves or either log level appears, treat the task as unfinished, fix the issue, and rerun until the behavior and logs are both clean.

### Add Art, Music, Or Story

1. Reuse the project's existing art pipeline, palette, sprite sizing, font choices, audio buses, dialogue system, localization format, and cutscene structure before inventing new conventions.
2. If the request does not specify a style and the project does not already establish one, default new visual content to pixel art. Keep sprites, tiles, UI embellishments, VFX, and promo-style mockups coherent with that direction.
3. For generated sprite-like art, use the `imagegen` skill first and request transparent `png` output. If transparent output is unavailable or unreliable, fall back to a flat chroma-key background and remove it locally with `scripts/assets/chroma_key_cutout.py`.
4. Use pure green `#00FF00` as the default chroma-key background so AI-generated assets are easier to cut out locally. If the subject itself contains strong green regions, switch to pure magenta `#FF00FF`. Avoid gradients, shadows, white, or black backgrounds when the next step is Python cutout.
5. After local cutout or repair work, write the final PNG frames back into the Godot project tree and reference them with project-relative paths such as `res://textures/...` before calling `load_sprite` or `build_sprite_frames`.
6. For music and SFX, prefer integrating provided or separately generated audio through the project's existing import settings, audio buses, and player nodes instead of inventing a new audio pipeline.
7. Implement story content through the project's existing dialogue, quest, event, or cutscene data flow when possible. This skill guides integration, not open-ended narrative system generation. If none exists, add only the smallest linear dialogue or event path needed to make the request playable unless the user explicitly asks for a larger system.
8. Default frame animation delivery to independent frame files instead of sprite sheets so frames are easier to cut out, repair, and validate individually.
9. Wire new assets and narrative content into a reachable gameplay path instead of leaving them as unused files in the repository.
10. Run the game and verify that visual assets render at the intended scale, music and SFX trigger correctly, and story content is reachable and readable without runtime errors.

### Run And Debug

1. Use host-native runtime tools such as `run_project`, `get_debug_output`, or `stop_project` when the host agent exposes them. Otherwise use the bundled runner to capture the debugger's errors as structured diagnostics: `python3 /absolute/path/to/godot/scripts/debug/run_project.py /absolute/path/to/project --quit-after 120 --timeout 60`.
2. Read the returned `diagnostics` and fix in order: parse errors first, then resource/load errors, then runtime script errors, then warnings — a single parse error usually cascades into several later errors. For each entry, open `file` at `line`, use `function`/`stack` for context, and apply the fix indicated by `category`/`suggested_fix` (details and a message→cause→fix table are in `references/debugging.md`).
3. When the host exposes input, browser, window, screenshot, or desktop automation tools, use them to interact with the running game so you can verify the changed feature in a live session instead of relying only on static inspection.
4. Re-run the same command after fixing and confirm `"ok": true` with `counts.errors == 0` and `counts.parse_errors == 0`. Do not assume the fix worked — the runner is the check. A `"timed_out": true` result is itself a finding (a hang or infinite loop).
5. Do not stop at a successful launch. Verify the implemented behavior in the running game, then read the diagnostics from the validation run and fix any reported `error` or `warning` before you finish. For a fast whole-project sanity pass without running gameplay, use the `check_project` operation to load every script and scene and surface parse/load failures; widen coverage for code paths a short boot never reaches by running the specific scene or raising `--quit-after`.
6. Never launch Godot with `-d` for automation; its interactive debugger prompt blocks on stdin (the runner already avoids this). If a full interactive test is not possible in the current environment, still launch the project when feasible, perform the deepest smoke test available, and state exactly what you could not verify.

### Prepare And Export Builds

1. Read `export_presets.cfg`, `project.godot`, and any existing CI scripts before editing build settings. Preserve the project's preset names and signing flow whenever possible.
2. Confirm that the local Godot version matches the project's export templates and that the required platform SDKs or certificates are already configured for the target preset.
3. Prefer the bundled wrapper at `scripts/export/export_project.py` for repeatable CLI exports, and use `--mode debug` before `--mode release` when you need a quick device, browser, or desktop smoke test.
4. Keep export outputs outside the project root unless the repository already stores them in a known build directory.
5. When the user asks for Android, iOS, Web, Windows, or macOS builds, read `references/export_targets.md` for the platform-specific checklist before changing presets or signing settings.
6. Do not hand-write a large `export_presets.cfg` from scratch unless there is no safer option. It is usually better to patch the existing preset file or create the baseline preset through Godot first.

### Use The Specialized Operations

- Use `scene_batch` as the default scene editing entrypoint for script and UI work.
- Use `configure_control` when a `Control` node needs presets, anchors, offsets, size flags, minimum size, or theme overrides.
- Use `attach_script`, `connect_signal`, and `disconnect_signal` to wire scene logic without hand-editing `.tscn` files.
- Use `remove_node`, `reparent_node`, and `reorder_node` to refactor hierarchy after the scene already exists.
- Use `build_sprite_frames` to turn a frame directory or explicit frame list into a `SpriteFrames` resource on an `AnimatedSprite2D`.
- Use `export_mesh_library` to build a `MeshLibrary` from a 3D scene for `GridMap`.
- Use `get_uid` to inspect a resource UID sidecar and any engine-reported UID metadata when a project uses `.uid` files.
- Use `resave_resources` or the server's equivalent project-wide resave operation to attempt `.uid` sidecar regeneration, then verify the reported created and still-missing counts instead of assuming every resave produced a UID.
- Use `run_project.py` to run the project and capture the debugger's runtime errors as structured diagnostics, and `check_project` to statically validate that every script, scene, shader, and resource compiles and loads.

## Typed JSON Values

- Use plain JSON scalars, arrays, and objects for ordinary values.
- Use `{"__resource":"res://path/to/resource"}` to load a Godot resource before assignment.
- Use typed wrappers for engine value types when the target property is not plain JSON:
  - `{"__type":"Vector2","x":10,"y":20}`
  - `{"__type":"Color","r":1,"g":0.5,"b":0.25,"a":1}`
  - `{"__type":"NodePath","value":"root/Button"}`
- `configure_node.properties`, `configure_node.indexed_properties`, `attach_script.script_properties`, `configure_control.theme_overrides`, and `scene_batch.actions[*]` all accept the same typed-value format.

## Scene Editing Surface

- `scene_batch`: sequential multi-action transaction with `create_if_missing`, `root_node_type`, `root_node_name`, `save_path`, and `actions`.
- `create_scene`: create and save a root scene with optional `root_node_name`, `properties`, and `indexed_properties`.
- `add_node`: add a new node under `parent_node_path`, optionally at `index`, with typed `properties` and `indexed_properties`.
- `instantiate_scene`: instance a child scene under `parent_node_path`, optionally rename it, move it to an index, and apply root properties.
- `configure_node`: set regular properties, indexed properties, groups, metadata, and `unique_name_in_owner` on an existing node.
- `configure_control`: configure `Control` presets, anchors, offsets, `position`, `size`, `custom_minimum_size`, size flags, stretch ratio, and theme overrides.
- `attach_script`: assign a script and then write exported properties.
- `connect_signal`: connect a signal to a target node method with persistent connection flags by default and optional `binds`.
- `disconnect_signal`: remove persistent scene connections by source node, signal, target node, and method.
- `load_sprite`: load an existing texture resource into a `Sprite2D`, `Sprite3D`, or `TextureRect`.
- `build_sprite_frames`: build or replace an animation on an `AnimatedSprite2D` from `frames_dir` or `frame_paths`, then optionally save the `SpriteFrames` resource to `resource_save_path`.
- `save_scene`: load an existing scene from `scene_path` and save it back to the same path or an alternate `save_path`; keep `new_path` only as a compatibility alias for older callers.
- `remove_node`, `reparent_node`, `reorder_node`: mutate existing hierarchy without rewriting the scene by hand.
- `get_uid`: inspect `file_path`, returning the `.uid` sidecar path, whether that sidecar exists, and any engine-reported UID text when available.
- `resave_resources`: resave scenes plus `.gd`, `.shader`, and `.gdshader` resources under `project_path`, then report how many `.uid` sidecars were actually created versus still missing.
- `check_project`: statically load every script, scene, shader, and resource under `project_path` (default `res://`) and report the checked count plus a `failed` list with each file's `path`, `kind`, and `reason`.

## Respect The Bundled Implementation

- Read `scripts/core/dispatcher.gd` when adding or changing Godot-side operations.
- Add scene operations under `scripts/scene/`, asset helpers under `scripts/assets/`, mesh operations under `scripts/mesh/`, diagnostics and the runtime runner/parser under `scripts/debug/`, shared utilities under `scripts/utils/`, and shared scene editing helpers under `scripts/core/`.
- Keep Godot-side parameter names in snake_case when editing these scripts, for example `scene_path`, `root_node_type`, `parent_node_path`, `node_type`, and `node_name`.
- Preserve the current relative import pattern inside the GDScript files so the headless dispatcher keeps working.

## Examples

### Menu UI In One Batch

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path":"scenes/menu.tscn",
    "create_if_missing":true,
    "root_node_type":"Control",
    "root_node_name":"Menu",
    "actions":[
      {"type":"add_node","parent_node_path":"root","node_type":"PanelContainer","node_name":"Panel"},
      {"type":"configure_control","node_path":"root/Panel","layout_preset":"FULL_RECT"},
      {"type":"add_node","parent_node_path":"root/Panel","node_type":"Button","node_name":"StartButton","properties":{"text":"Start"}},
      {"type":"configure_control","node_path":"root/Panel/StartButton","size_flags_horizontal":"EXPAND_FILL","custom_minimum_size":{"__type":"Vector2","x":240,"y":64}}
    ]
  }'
```

### Attach Script And Connect Button Signal

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  scene_batch '{
    "scene_path":"scenes/menu.tscn",
    "actions":[
      {"type":"attach_script","node_path":"root","script_path":"scripts/menu_controller.gd","script_properties":{"menu_title":"Main Menu"}},
      {"type":"connect_signal","node_path":"root/StartButton","signal_name":"pressed","target_node_path":"root","method_name":"_on_start_pressed","binds":["clicked"]}
    ]
  }'
```

### Export A Debug Android Build

```bash
python3 /absolute/path/to/godot/scripts/export/export_project.py \
  /absolute/path/to/project \
  "Android" \
  /absolute/path/to/build/android/game.apk \
  --mode debug
```

### Run And Read The Debugger Errors

```bash
python3 /absolute/path/to/godot/scripts/debug/run_project.py \
  /absolute/path/to/project \
  --quit-after 120 --timeout 60 --pretty
```

Returns JSON with a `diagnostics` array; each entry has `severity`, `category`, `message`, `file`, `line`, `function`, `stack`, and `suggested_fix`. Open the referenced `file:line`, apply the fix, then re-run until `"ok": true`.

### Build AnimatedSprite2D Frames From A Directory

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  build_sprite_frames '{
    "scene_path":"scenes/player.tscn",
    "node_path":"root/AnimatedSprite2D",
    "frames_dir":"art/player_idle",
    "animation_name":"idle",
    "fps":12,
    "loop":true,
    "resource_save_path":"animations/player_idle_frames.tres"
  }'
```

## Check Before You Finish

- Confirm that every write target is inside the intended Godot project.
- Confirm that the scene still loads and that the project boots after structural edits.
- Confirm that the changed feature was exercised in a live run when the environment allowed it, and that the observed behavior matched the request without obvious regressions.
- Confirm that any new art, music, or story content matches the requested direction, or the pixel-art default when no direction was provided and no project style overrode it.
- Confirm that generated sprite-like assets used transparent output first, or a flat pure-green chroma-key background plus local cutout as the fallback.
- Confirm that frame animation work landed as a validated frame sequence or `SpriteFrames` resource, not an unusable loose asset dump.
- Confirm that the final validation run logs contain no `error` or `warning` output. If they do, fix the issue and rerun before finishing. Capture the run with `scripts/debug/run_project.py` (or the host runtime tools) so the check is on structured diagnostics, not a glance at the log.
- Confirm that every exported artifact came from the intended preset and that the artifact path matches the target platform's existing convention.
- Smoke test at least one exported build for the requested targets instead of assuming the preset is valid.
- Confirm architecture work did not collapse unrelated responsibilities into a single node script, autoload, or generic manager.
- Prefer incremental scene changes over rewriting `.tscn` files manually.
