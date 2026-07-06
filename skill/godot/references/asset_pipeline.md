# Asset Pipeline

Load this reference only when the task involves generated art, cutouts, or frame animation assets.

## Default image pipeline

1. Use the `imagegen` skill first for generated art.
2. Request `png` output with `background=transparent` whenever the subject should become a sprite, prop, UI element, or animation frame.
3. If transparent output is unavailable or edge quality is poor, fall back to a flat chroma-key background and strip it locally with `scripts/assets/chroma_key_cutout.py`.

## Best fallback background for Python cutout

- Default background: pure green `#00FF00`.
- If the subject already contains strong green regions, switch to pure magenta `#FF00FF`.
- Do not use white, black, gradients, textured scenes, shadows, or contact shadows as the default cutout background.
- Keep the background flat and uniform across every frame in the sequence. For batches, prefer an explicit `00ff00` or `ff00ff` value instead of guessing.

## Prompt constraints for cutout-friendly assets

- Subject centered and fully inside frame.
- Clean silhouette with readable hard edges.
- No text, watermark, motion blur, bloom, or depth-of-field effects.
- No cast shadow on the background unless the user explicitly asks for it.
- For pixel-art defaults: limited palette, crisp edges, no painterly gradients, no soft airbrush rendering.

## Frame animation defaults

- Default delivery format: independent frame files, not a sprite sheet.
- `build_sprite_frames` auto-discovers raster image frames from `frames_dir` with natural filename sorting. If exact order matters or the inputs are texture resources, use explicit `frame_paths` instead.
- Keep the same canvas size, camera distance, viewing angle, and anchor point across frames.
- Change only pose or timing from frame to frame; do not redesign the character or prop mid-sequence.
- Generate or repair frames individually, then build `SpriteFrames` in Godot with `build_sprite_frames`.
- Export a sprite sheet only when the user explicitly asks for one.

## Local cutout tool

The bundled fallback script handles flat chroma-key backgrounds only. It is not a general-purpose segmenter.
Write cutout outputs into the Godot project tree so the next step can reference them as `res://...` paths.

Single image:

```bash
python3 /absolute/path/to/godot/scripts/assets/chroma_key_cutout.py \
  --input /absolute/path/to/project/source/frame.png \
  --output /absolute/path/to/project/textures/frame-cutout.png \
  --bg-color 00ff00
```

Directory batch:

```bash
python3 /absolute/path/to/godot/scripts/assets/chroma_key_cutout.py \
  --input /absolute/path/to/project/source/hero_idle_raw \
  --output-dir /absolute/path/to/project/textures/hero_idle_cutout \
  --bg-color 00ff00
```

Then build the animation from the project-relative frame directory:

```bash
godot --headless --path /absolute/path/to/project \
  --script /absolute/path/to/godot/scripts/core/dispatcher.gd \
  build_sprite_frames '{
    "scene_path":"scenes/player.tscn",
    "node_path":"root/AnimatedSprite2D",
    "frames_dir":"textures/hero_idle_cutout",
    "animation_name":"idle",
    "fps":12,
    "loop":true,
    "resource_save_path":"animations/hero_idle_frames.tres"
  }'
```

## Dependencies

- `imagegen` for generation or edit requests.
- `Pillow` and `NumPy` for `scripts/assets/chroma_key_cutout.py`.

Create a virtualenv when the system Python is externally managed:

```bash
python3 -m venv .godot-skill-venv
. .godot-skill-venv/bin/activate
python -m pip install pillow numpy
```

If your environment already allows direct installs, `python3 -m pip install pillow numpy` also works.
