---
name: godot
description: Godot project development and debugging skill for inspecting projects, creating or editing scenes, adding nodes, assigning assets, exporting mesh libraries, running the project, reading debug output, and repairing Godot 4.4+ resource UIDs. Use when Codex needs to work inside a Godot project and should follow the bundled Godot workflows and automation tools.
compatibility: Requires a local godot CLI with shell access for the bundled dispatcher fallback. Godot 4.4+ is recommended. Install this skill in a folder named godot so the directory matches the skill name in environments that validate folder naming.
---

# Godot

Use this skill to inspect, modify, run, and debug Godot projects with the bundled workflows, scripts, and available Godot automation tooling.

## Start

- Verify which Godot automation path is available before planning edits. Prefer any native or mapped Godot tools in the host agent, otherwise use the bundled headless dispatcher directly.
- Resolve `projectPath` to an absolute project directory.
- Normalize scene and resource paths to `res://...` when working directly with the bundled Godot scripts in this skill.
- Inspect unfamiliar projects with any available project-discovery tools, or fall back to reading `project.godot`, scene files, and scripts directly.

## Portable CLI Fallback

Use this path in shell-capable environments such as Claude Antigravity when dedicated Godot tools are not exposed:

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/skill/scripts/core/dispatcher.gd \
  create_scene '{"scene_path":"scenes/main.tscn","root_node_type":"Node2D"}'
```

- Replace `create_scene` with any supported operation: `create_scene`, `add_node`, `load_sprite`, `save_scene`, `export_mesh_library`, `get_uid`, or `resave_resources`.
- Pass parameters as a single JSON object using the snake_case field names expected by the bundled GDScript.

## Follow The Main Workflows

### Create Or Modify A Scene

1. Call `create_scene` to create the root scene.
2. Call `add_node` to build the node tree from the root downward.
3. Call `load_sprite` only after the target `Sprite2D`, `Sprite3D`, or `TextureRect` node exists.
4. Call `save_scene` after structural changes, or use its alternate save path support when duplicating a scene.
5. Run the project after non-trivial edits instead of assuming the scene still loads.

### Run And Debug

1. Call `run_project` after scene, script, or resource changes.
2. Poll `get_debug_output` until startup succeeds or the failing script is clear.
3. Call `stop_project` before relaunching when a prior run is still active.

### Use The Specialized Operations

- Use `export_mesh_library` to build a `MeshLibrary` from a 3D scene for `GridMap`.
- Use `get_uid` to inspect a resource UID on Godot 4.4+ projects.
- Use `resave_resources` or the server's equivalent project-wide UID refresh operation when missing `.uid` files break references.

## Respect The Bundled Implementation

- Read `scripts/core/dispatcher.gd` when adding or changing Godot-side operations.
- Add scene operations under `scripts/scene/`, mesh operations under `scripts/mesh/`, and shared utilities under `scripts/utils/`.
- Keep Godot-side parameter names in snake_case when editing these scripts, for example `scene_path`, `root_node_type`, `parent_node_path`, `node_type`, and `node_name`.
- Preserve the current relative import pattern inside the GDScript files so the headless dispatcher keeps working.

## Check Before You Finish

- Confirm that every write target is inside the intended Godot project.
- Confirm that the scene still loads and that the project boots after structural edits.
- Prefer incremental scene changes over rewriting `.tscn` files manually.
