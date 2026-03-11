# Godot Skill

Portable Godot project development and debugging skill for Codex-style skill loaders.

The distributable skill payload lives in [`skill/godot/`](skill/godot/). That folder is kept minimal on purpose so it can be copied directly into a skills directory or packaged for release without GitHub-specific files.

## Repository Layout

- `skill/godot/`: the actual skill payload
- `scripts/package_skill.sh`: builds a release zip with a top-level `godot/` folder
- `README.md`: repository documentation for GitHub users

## Build A Release Package

```bash
./scripts/package_skill.sh
```

This writes:

- `dist/godot/`: staged skill payload
- `dist/godot.zip`: release archive ready to install

## Install

### From Source

Copy [`skill/godot/`](skill/godot/) into your skills directory so the final installed folder name is `godot`.

### From A Release Zip

Unzip `dist/godot.zip` into your skills directory. The archive already contains a top-level `godot/` folder.

## Notes

- The skill payload itself intentionally excludes a `README.md` so it stays aligned with skill packaging guidance.
- The bundled dispatcher fallback requires a local `godot` CLI with shell access.
