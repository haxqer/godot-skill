# Authoring Recipes And Non-Goals

Recipes for Godot 4.7 features that the generic ops already cover (so they need no dedicated operation), plus the workflows that are **not** headless-automatable and must be handled in the editor. Read this when a task touches shaders, materials, particles, environment/sky, fonts, multiplayer replication, 3D import, GDExtension, or feature-tag configuration.

## Text Shaders And ShaderMaterial

`.gdshader` is a native resource — there is no `.import` sidecar and no import step. Write the file, then wire it up:

1. Write `res://shaders/tint.gdshader` with an ordinary file write.
2. Build the material and set uniforms with `resource_batch` (uniforms live under the indexed path `shader_parameter/<name>`):

```json
{
  "resource_path": "materials/tint.tres",
  "create_if_missing": true,
  "resource_type": "ShaderMaterial",
  "actions": [
    {"type": "set_properties", "properties": {"shader": {"__resource": "res://shaders/tint.gdshader"}}},
    {"type": "set_indexed_properties", "properties": {
      "shader_parameter/tint": {"__type": "Color", "r": 1, "g": 0.5, "b": 0.2, "a": 1},
      "shader_parameter/mask": {"__resource": "res://art/mask.png"}
    }}
  ]
}
```

3. Assign it with `configure_node` (`material`). Uniform names are case-sensitive and must match the shader source. `CanvasItemMaterial`, `StandardMaterial3D`, `ORMMaterial3D`, and `next_pass` chaining are plain resources — build them the same way. Overlapping 2D screen-reading shaders need a `BackBufferCopy` node (`add_node`).

Shader automation is **text-`.gdshader` only**. Do not build `VisualShader` node graphs programmatically.

Project-wide `global uniform` values go in `[shader_globals]` — use `project_batch` `set_shader_global` (see `automation_api.md`).

## Particles

`GPUParticles2D`/`GPUParticles3D` are nodes (`add_node`); the behavior lives in a `ParticleProcessMaterial`. Color ramps and scale/velocity curves are the fiddly part — inline them with the codec `__gradient`/`__curve` sugar so no extra files are needed:

```json
{
  "type": "configure_node",
  "node_path": "root/GPUParticles2D",
  "properties": {
    "amount": 64,
    "process_material": {
      "__resource_type": "ParticleProcessMaterial",
      "properties": {
        "gravity": {"__type": "Vector3", "x": 0, "y": 98, "z": 0},
        "scale_min": 0.5, "scale_max": 1.5,
        "color_ramp": {"__resource_type": "GradientTexture1D", "properties": {
          "gradient": {"__gradient": {"points": [
            {"offset": 0, "color": "#ffffffff"}, {"offset": 1, "color": "#ffffff00"}]}}}},
        "scale_curve": {"__resource_type": "CurveTexture", "properties": {
          "curve": {"__curve": {"points": [{"x": 0, "y": 0}, {"x": 0.2, "y": 1}, {"x": 1, "y": 0}]}}}}
      }
    }
  }
}
```

Rendered particle output cannot be visually verified headless, but the resources author correctly.

## Environment And Sky

`WorldEnvironment` is a node holding an `Environment` resource; both are plain resources. A cinematic preset is two nested constructions:

```json
{
  "type": "configure_node",
  "node_path": "root/WorldEnvironment",
  "properties": {
    "environment": {
      "__resource_type": "Environment",
      "properties": {
        "background_mode": 2,
        "glow_enabled": true,
        "ssao_enabled": true,
        "tonemap_mode": 3,
        "sky": {"__resource_type": "Sky", "properties": {
          "sky_material": {"__resource_type": "ProceduralSkyMaterial", "properties": {
            "sky_top_color": "#3a6ea5", "ground_bottom_color": "#20222a"}}}}
      }
    }
  }
}
```

`glow_levels/1`… are indexed properties (`set_indexed_properties`). `Gradient`, `GradientTexture`, `FastNoiseLite`, `NoiseTexture2D`, and `CameraAttributes*` are all plain resources.

## Fonts

Importing a `.ttf`/`.otf` has an ordering trap: a freshly dropped font has **no `.import` sidecar** until Godot scans it.

1. Place `res://fonts/inter.ttf`.
2. Run `import_project.py` (or `godot --headless --import`) to generate the sidecar and rasterize glyphs — **this must come first**.
3. Only then patch MSDF / antialiasing / fallbacks with `set_import_options` (which reports `reimport_required`), and reimport.
4. Reference the font by its source path (`{"__resource": "res://fonts/inter.ttf"}`). `FontVariation` and `SystemFont` are plain resources (`resource_batch`).

## Multiplayer Replication

Build a `MultiplayerSynchronizer`'s `SceneReplicationConfig` with `build_replication_config` (or `resource_batch`), then wire the nodes:

1. `build_replication_config` → `res://net/player_repl.tres` (paths are relative to the synchronizer's `root_path`, default its parent — a frequent mistake).
2. `add_node` a `MultiplayerSynchronizer`; `configure_node` its `replication_config` to the `.tres` and set `root_path`.
3. `MultiplayerSpawner.add_spawnable_scene(path)` is method-only — set the spawner up with `resource_batch`-style `call_method` on the node is not available, so populate its spawnable scenes from a small `@tool`/runtime script or in the editor.

The peer/RPC half (`ENetMultiplayerPeer`, `@rpc`, `set_multiplayer_authority`) is runtime GDScript, written with `attach_script`.

## 3D Import Configuration

Reimport options for glTF/scene imports (`ResourceImporterScene`) are patched with `set_import_options` on the model's `.import` file: **Generate LODs**, **Create Shadow Meshes**, **Light Baking** (static lightmap + UV2), embedded-texture handling. Per-node physics/collision/occluder/navmesh generation is driven by **node-name suffixes in the source model**: `-col`, `-convcol`, `-colonly`, `-convcolonly`, `-navmesh`, `-occ`, `-occonly`, `-rigid`, `-vehicle`, `-wheel`, `-noimp`.

## GDExtension And Feature Tags

- A `.gdextension` file is plain INI text — write it directly. Skeleton:

```ini
[configuration]
entry_symbol = "my_extension_library_init"
compatibility_minimum = "4.7"
reloadable = true

[libraries]
macos.debug = "res://bin/libmyext.macos.template_debug.framework"
macos.release = "res://bin/libmyext.macos.template_release.framework"
windows.debug.x86_64 = "res://bin/libmyext.windows.template_debug.x86_64.dll"
linux.debug.x86_64 = "res://bin/libmyext.linux.template_debug.x86_64.so"
```

Building the native library (godot-cpp + a C++ toolchain) is out of scope for headless automation. Library keys must match the export-template names exactly, and `entry_symbol` must match the C++ init function.

- **Feature-tag setting overrides** already work through `project_batch` `set_setting`: append `.<feature>` to any key, e.g. `display/window/size/viewport_width.mobile`. Built-in tags include the platforms, `mobile`/`pc`/`web`, `dedicated_server`, and arch tags. Custom tags only apply to exported/deployed runs, never editor or `--headless` project runs. Read them back at runtime with `ProjectSettings.get_setting_with_override()`.

## Not Headless-Automatable (Editor-Only / GPU-Only)

State these limits instead of attempting them:

- **`LightmapGI.bake()`** — not exposed to scripting at all, and requires a GPU (Forward+/Mobile). Baking is an editor action. You can headlessly prepare UV2 (`ArrayMesh.lightmap_unwrap`) and set `gi_mode = STATIC`, but a human must bake in the editor.
- **`OccluderInstance3D` bake** — only the editor "Bake Occluders" button; no script method. The `-occ`/`-occonly` import suffixes generate occluders at import time as an alternative.
- **`ReflectionProbe`** — GPU-realtime cubemap with no bake-to-disk resource. Place the node with `add_node`; there is nothing to bake headlessly.
- **`VisualShader` graphs** — technically scriptable but hopelessly verbose; use text `.gdshader` instead.
- **`CompositorEffect`** — an experimental `RenderingDevice` callback that does nothing under the headless dummy driver and cannot be verified.
- **`EditorScript`** (`_run()`) — editor-only, not runnable via `--script`. The dispatcher already runs any `SceneTree`/`MainLoop` script headlessly; editor-only one-shots are limited to the existing `--import` and `--build-solutions` wrappers.
- **`ProjectSettings.add_property_info`** — a runtime inspector-UI annotation that does not persist. Set custom-setting *values* with `project_batch`; hints require an `@tool` plugin at runtime.
- **C# from zero** — Godot has no documented headless way to scaffold the first `.csproj`/`.sln` (creating the first C# script in the editor generates them). The *build* is already covered by `validate_project.py --build-solutions` once the project files exist.
