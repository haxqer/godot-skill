# 2D VFX, Lighting, And World-Building Recipes

Read this reference when the task involves 2D lighting, particles, parallax
backgrounds, trails/shapes, tile-based levels, or blend/glow effects. Every
node here is buildable with the existing `add_node`/`configure_node`/
`scene_batch` operations; standalone material and occluder resources come from
`resource_batch`, tilesets from `build_tileset`.

## Deprecation Steering (Godot 4.3+)

| Deprecated | Use instead |
| --- | --- |
| `TileMap` (monolithic node) | One `TileMapLayer` node per layer, sharing a `TileSet` (`build_tileset` + `paint_tilemap`) |
| `ParallaxBackground` + `ParallaxLayer` | `Parallax2D` (plain Node2D, no CanvasLayer wrapper needed) |

## 2D Lighting

The standard recipe: darken the whole canvas, then punch light through it.

1. `add_node` a `CanvasModulate` with `color` around `{"r":0.12,"g":0.12,"b":0.2,"a":1}` — the darkness base. Only one active per canvas.
2. `add_node` `PointLight2D` per light. Key properties: `texture` (defines the light's shape — a radial-gradient texture), `texture_scale`, `energy`, `color`, `shadow_enabled`.
3. `DirectionalLight2D` models sun/moon: emits along its +Y basis, position is ignored; `height` affects normal-map response, `max_distance` bounds coverage.
4. Shadow casters: create an `OccluderPolygon2D` via `resource_batch` (`properties: {"polygon": [...Vector2 points...], "closed": true}`), then `add_node` a `LightOccluder2D` with `occluder` → `{"__resource": "..."}`.

## Particles

1. Create the process material once: `resource_batch` with `resource_type: "ParticleProcessMaterial"` — key properties: `direction` (Vector3), `spread`, `initial_velocity_min`/`max`, `gravity` (Vector3), `scale_min`/`max`, `color`, `color_ramp` (a `GradientTexture1D` built from a `Gradient`).
2. `add_node` a `GPUParticles2D` with `process_material` → `{"__resource": "..."}`, plus `amount`, `lifetime`, `one_shot`, `explosiveness`, `texture`.
3. Additive glow: `resource_batch` a `CanvasItemMaterial` with `blend_mode: 1` (ADD) and assign it to the particles node's `material`.
4. 2D particles collide only with `LightOccluder2D`-style SDF colliders, not physics bodies.

## Parallax Backgrounds

`Parallax2D` is an ordinary Node2D — place one per depth layer with a Sprite2D
child. Key properties: `scroll_scale` (per-axis depth factor; <1 = far),
`repeat_size` (tile size for infinite horizontal repeat), `repeat_times`,
`autoscroll` (px/s for clouds), `follow_viewport`.

## Trails, Shapes, Paths

- `Line2D`: `points` (array of Vector2), `width`, `width_curve`, `default_color`, `gradient`, cap/joint modes. Lasers, trails, rope.
- `Polygon2D`: `polygon` points, `color`, `texture`, per-vertex `vertex_colors`. Filled shapes without art assets.
- `Path2D` + `PathFollow2D` for patrols/rails: build the `Curve2D` with `resource_batch` `call_method` `add_point` calls, assign to `Path2D.curve`, put the moving node under a `PathFollow2D` and drive `progress` from a script or `build_animation` value track.

## Grouped Transparency And Screen Effects

- `CanvasGroup` renders children into one buffer so overlapping translucent parts fade as a unit (`fit_margin`, `clear_margin`).
- `BackBufferCopy` exposes what is behind a node to shaders (`rect`, `copy_mode`) for distortion/glass.
- `CanvasItemMaterial.blend_mode`: `0` mix, `1` add, `2` subtract, `3` multiply, `4` premultiplied alpha.
