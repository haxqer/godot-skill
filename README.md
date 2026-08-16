# Godot Skill

Portable Godot project development, debugging, architecture, content-integration, and export skill for Codex-style skill loaders. Designed for Godot 4.7 and compatible with Godot 4.x.

The distributable skill payload lives in [`skill/godot/`](skill/godot/). That folder is kept minimal on purpose so it can be copied directly into a skills directory or packaged for release without GitHub-specific files.

## Repository Layout

- `skill/godot/`: the actual skill payload
- `scripts/package_skill.sh`: builds a release zip with a top-level `godot/` folder
- `scripts/run_tests.sh`: runs every module in `tests/`, exiting non-zero if any fails
- `.github/workflows/ci.yml`: installs Godot, runs the suite, and attaches `godot.zip` to a tagged release
- `README.md`: repository documentation for GitHub users

## Build A Release Package

```bash
./scripts/package_skill.sh
```

This writes:

- `dist/godot/`: staged skill payload
- `dist/godot.zip`: release archive ready to install

`dist/` is a build output and is deliberately not tracked in git — it would
duplicate every byte of `skill/godot/` and add a binary that churns on each edit.
The archive is published as a GitHub Release asset instead.

## Continuous Integration

`.github/workflows/ci.yml` runs on pushes to `main`, on pull requests, and on
`v*` tags:

- **test** — installs the pinned Godot build (`GODOT_VERSION` in the workflow),
  confirms it actually runs, then runs `./scripts/run_tests.sh`. The Godot-backed
  tests skip themselves when the binary is missing, so the version check is what
  keeps a broken install from turning the suite into a silent pass.
- **package** — builds the archive and verifies its contents (expected entries
  present, no `__pycache__`/`.pyc`/`.DS_Store`), then uploads it as a workflow
  artifact so a pull request can be checked before tagging.
- **release** — on a `v*` tag only, attaches `dist/godot.zip` to the matching
  GitHub Release, creating the release if it does not exist yet.

To cut a release: push a `v*` tag. Keep `GODOT_VERSION` in step with the version
the skill is verified against.

Run the same checks locally with:

```bash
./scripts/run_tests.sh
```

## Install

### From Source

Copy [`skill/godot/`](skill/godot/) into your skills directory so the final installed folder name is `godot`.

### From A Release Zip

Unzip `dist/godot.zip` into your skills directory. The archive already contains a top-level `godot/` folder.

## Notes

- The skill payload itself intentionally excludes a `README.md` so it stays aligned with skill packaging guidance.
- The bundled dispatcher fallback now supports full scene editing workflows: batch scene transactions, node configuration, `Control` layout and theme overrides, script attachment, signal wiring, hierarchy refactors, and `build_sprite_frames` for `AnimatedSprite2D` frame animation, in addition to the original skeleton-building helpers.
- The skill can run a project headlessly and turn the Godot debugger's runtime errors into structured, fixable diagnostics (`scripts/debug/run_project.py` + `godot_log_parser.py`), plus a `check_project` operation that statically validates every script, scene, shader, and resource. See `skill/godot/references/debugging.md`.
- The skill includes content-integration and architecture guidance: an art/asset pipeline with a chroma-key cutout helper (`scripts/assets/chroma_key_cutout.py`, see `references/asset_pipeline.md`) and QFramework-style architecture references (`references/architecture_qframework_lite.md`, `references/architecture_templates.md`).
- The skill includes structured project/scene/resource inspection, transactional Resource and ProjectSettings editing (including builder-method calls for method-driven resources), import/reimport auditing, and environment capability probes.
- Content authoring ops cover `TileSet` building plus `TileMapLayer` cell painting, spritesheet-sliced `SpriteFrames` with per-frame durations, declarative `AnimationPlayer` keyframe clips, and `AudioBusLayout` routing; `scripts/test/run_tests.py` runs GUT/GdUnit4 suites headlessly.
- Validation covers GDScript, C#, GDExtension, and editor plugins; deterministic scenarios can inject input, assert node state and logs, capture screenshots, and enforce performance thresholds.
- The export wrapper includes preset/environment preflight, pack and patch modes, plus guidance for Android, iOS, Web, Windows, Linux, macOS, dedicated server, and visionOS builds.
- The scene editing, runtime, and diagnostics APIs are designed against the current stable Godot docs and verified locally on Godot `4.7` (compatible with Godot 4.x).
- The bundled dispatcher fallback and runtime runner require a local `godot` CLI with shell access.
