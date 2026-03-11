# Godot Skill

Portable Godot project development and debugging skill for agentic coding tools that support the `SKILL.md` format.

This repository packages a single skill named `godot`. It helps an agent inspect Godot projects, create or modify scenes, add nodes, assign textures, export `MeshLibrary` assets, and repair Godot 4.4+ resource UIDs with bundled headless GDScript helpers.

## What's Included

- `SKILL.md`: the skill instructions and trigger metadata
- `scripts/core/dispatcher.gd`: headless entry point for bundled operations
- `scripts/scene/`: scene creation and editing helpers
- `scripts/mesh/`: mesh library export helper
- `scripts/utils/`: UID and resource maintenance helpers
- `agents/openai.yaml`: OpenAI/Codex UI metadata

## Requirements

- Local `godot` CLI available on `PATH`
- Godot 4.4+ recommended
- Shell access if your agent does not expose dedicated Godot tools

Tested locally with `godot 4.5.1`.

## Install

The skill name in frontmatter is `godot`, so install it into a folder named `godot` for the best compatibility with Claude-family skill loaders.

```bash
git clone https://github.com/haxqer/godot-skill.git ~/.claude/skills/godot
```

If you use another skill host, copy or clone this repository into that host's skills directory with the final folder name `godot`.

## Direct Dispatcher Usage

If your agent can run shell commands but does not expose named Godot tools, call the bundled dispatcher directly:

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/skill/scripts/core/dispatcher.gd \
  create_scene '{"scene_path":"scenes/main.tscn","root_node_type":"Node2D"}'
```

Supported operations:

- `create_scene`
- `add_node`
- `load_sprite`
- `save_scene`
- `export_mesh_library`
- `get_uid`
- `resave_resources`

## Claude Antigravity Compatibility

Status: usable with caveats.

- The repository already matches the core Agent Skills shape: a skill folder with `SKILL.md` plus optional `scripts/`.
- The bundled GDScript helpers are portable because they run through the `godot --headless --script ...` dispatcher.
- `agents/openai.yaml` is optional metadata and should be ignored by non-OpenAI hosts.
- The main compatibility caveat is installation path: keep the final folder name as `godot`, not `godot-skill`, so it matches `name: godot`.
- The second caveat is runtime environment: without a local `godot` binary and shell access, Antigravity will be able to read the skill but not execute the bundled helpers.
- `README.md` is included for GitHub users. If a strict importer expects a minimal skill folder, copy only `SKILL.md`, `scripts/`, and optional host-specific metadata files into the final `godot` skill directory.

## Development Notes

- Keep `SKILL.md` concise. Put implementation details in `scripts/` rather than expanding the skill body.
- Preserve the relative preload/import pattern inside the bundled GDScript files so the dispatcher keeps working.
- When adding operations, update `scripts/core/dispatcher.gd` and document the new operation in `SKILL.md`.
