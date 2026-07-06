# Godot Skill

Portable Godot project development, debugging, and export skill for Codex-style skill loaders. Designed for Godot 4.7 and compatible with Godot 4.x.

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
- The bundled dispatcher fallback now supports full scene editing workflows: batch scene transactions, node configuration, `Control` layout and theme overrides, script attachment, signal wiring, and hierarchy refactors in addition to the original skeleton-building helpers.
- The skill can run a project headlessly and turn the Godot debugger's runtime errors into structured, fixable diagnostics (`scripts/debug/run_project.py` + `godot_log_parser.py`), plus a `check_project` operation that statically validates every script, scene, shader, and resource. See `skill/godot/references/debugging.md`.
- The skill also includes a small export wrapper plus platform guidance for Android, iOS, Web, Windows, and macOS builds driven by existing Godot export presets.
- The scene editing, runtime, and diagnostics APIs are designed against the current stable Godot docs and verified locally on Godot `4.7` (compatible with Godot 4.x).
- The bundled dispatcher fallback and runtime runner require a local `godot` CLI with shell access.
