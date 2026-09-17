# Godot 3 → Godot 4.7 Rename Table

Read this when a project (or a snippet you are about to write) uses Godot 3 API.
Every row below is a **hard failure on 4.x** unless its level says `warning`:
the identifier does not exist, so the script does not parse, the scene does not
load, or the call errors the first time it runs. Godot's own message never names
the replacement (`Identifier "onready" not declared`, `Cannot find type
"KinematicBody2D"`), which is what this table is for.

This file is generated from the rule table in
`scripts/debug/lint_project.py`. Regenerate it after changing a rule:

```bash
python3 /absolute/path/to/godot/scripts/debug/lint_project.py --list-rules
```

Run the linter to find these automatically — it needs no Godot binary and
finishes in well under a second:

```bash
python3 /absolute/path/to/godot/scripts/debug/lint_project.py /absolute/project --pretty
python3 /absolute/path/to/godot/scripts/debug/lint_project.py /absolute/project --only godot3_api
```

`Level` is the linter severity, and it means one thing throughout: `error` =
Godot refuses to parse or load the file, so the project does not run; `warning` =
it compiles and runs, but the Godot 3 spelling is deprecated and should be
replaced. The same contract applies to the linter's `inference` rules — `var x :=
$Node` is a *warning* (it compiles, typing `x` as bare `Node`), while `var x :=
data.get("k")` is an *error* (Godot will not parse it). Every level here was
checked against `godot 4.7.stable`, not assumed.

## Unchanged — do not "fix" these

`instance_from_id()`, `Label3D`, `Camera2D`, `Path2D`/`PathFollow2D`,
`RayCast2D`, `CollisionShape2D`, `StaticBody2D`, `RigidBody2D`, `Area2D`,
`AnimationPlayer`, `Timer`, `CanvasLayer`, `TileMapLayer`, `Parallax2D`,
`visible_characters`, and `theme_override_constants/margin_left` (a
MarginContainer theme constant, unrelated to the removed `Control.margin_left`)
are all current 4.7 API.

## The Table

### Syntax and keywords

| Godot 3 | Godot 4.7 | Level | Rule id | Fix |
| --- | --- | --- | --- | --- |
| `onready var` | `@onready var` | error | `onready_var` | Write `@onready var name: Type = $Node`. Keep the type annotation — `$Node` is statically typed `Node`, so `:=` there silently widens the variable. |
| `export var` | `@export var` | error | `export_var` | Write `@export var speed: float = 200.0`. A bare `@export` with no type and no initializer does not compile either. |
| `export(Type) var` | `@export / @export_range` | error | `export_hint` | `export(int) var hp` -> `@export var hp: int = 0`; `export(int, 0, 100) var armor` -> `@export_range(0, 100) var armor: int = 0`; `export(String, "a", "b")` -> `@export_enum("a", "b") var mode: String = "a"`. |
| `tool` | `@tool` | error | `tool_keyword` | Replace the first line with `@tool`. |
| `yield(` | `await` | error | `yield_call` | `yield(get_tree().create_timer(1.0), "timeout")` -> `await get_tree().create_timer(1.0).timeout`; `yield(obj, "sig")` -> `await obj.sig`. |
| `setget` | `set:/get: blocks` | error | `setget` | Use the 4.x property block — `var hp: int = 10:` followed by an indented `set(value):` / `get:` pair — or the short form `var hp: int = 10: set = _set_hp, get = _get_hp`. |
| `.instance(` | `.instantiate()` | error | `instance_call` | `scene.instance()` -> `scene.instantiate()`. Annotate the result: `var enemy := scene.instantiate() as Enemy` (plus a null guard). |
| `.empty()` | `.is_empty()` | error | `empty_call` | `items.empty()` -> `items.is_empty()`. |
| `move_and_slide(velocity)` | `velocity + move_and_slide()` | error | `move_and_slide_args` | Set `velocity` first, then call it bare: `velocity = dir * speed` then `move_and_slide()`. `move_and_slide(vel, Vector2.UP)` -> `velocity = vel` + `up_direction = Vector2.UP` (a property) + `move_and_slide()`. |
| `move_and_slide_with_snap(` | `move_and_slide() + floor snap` | error | `move_and_slide_with_snap` | Set `floor_snap_length` (and `floor_stop_on_slope`) on the CharacterBody, then call `move_and_slide()` with no arguments. |
| `get_tree().change_scene(` | `change_scene_to_file(` | error | `change_scene` | `get_tree().change_scene("res://x.tscn")` -> `get_tree().change_scene_to_file("res://x.tscn")`; for a loaded PackedScene use `change_scene_to_packed(packed)`. (A project's own `func change_scene()` on an autoload is not this rule and is not reported.) |
| `interpolate_property(` | `create_tween().tween_property()` | error | `tween_interpolate_property` | `var t := create_tween()` then `t.tween_property(node, "position", target, 0.4).set_trans(Tween.TRANS_SINE)`. Tweens are created in code and run themselves — no Tween node, no `start()`. |
| `Tween (node)` | `create_tween()` | error | `tween_node` | Delete the Tween node and call `create_tween()` in the script that animates. See references/tween.md. |

### Signals

| Godot 3 | Godot 4.7 | Level | Rule id | Fix |
| --- | --- | --- | --- | --- |
| `connect("sig", obj, "method")` | `sig.connect(obj.method)` | error | `connect_string` | `button.connect("pressed", self, "_on_pressed")` -> `button.pressed.connect(_on_pressed)`. With binds: `button.pressed.connect(_on_pressed.bind("arg"))`. |
| `is_connected("sig", obj, "m")` | `sig.is_connected(obj.m)` | error | `is_connected_string` | `obj.is_connected("sig", self, "_on")` -> `obj.sig.is_connected(_on)`. |
| `disconnect("sig", obj, "m")` | `sig.disconnect(obj.m)` | error | `disconnect_string` | `obj.disconnect("sig", self, "_on")` -> `obj.sig.disconnect(_on)`. |
| `emit_signal("x")` | `x.emit()` | warning | `emit_signal_string` | `emit_signal("died", score)` -> `died.emit(score)`. |

### Nodes (2D)

| Godot 3 | Godot 4.7 | Level | Rule id | Fix |
| --- | --- | --- | --- | --- |
| `KinematicBody2D` | `CharacterBody2D` | error | `kinematicbody2d_class` | `KinematicBody2D` -> `CharacterBody2D`. Set the `velocity` property, then call `move_and_slide()` with no arguments. |
| `Sprite` | `Sprite2D` | error | `sprite_class` | `Sprite` -> `Sprite2D`. |
| `AnimatedSprite` | `AnimatedSprite2D` | error | `animatedsprite_class` | `AnimatedSprite` -> `AnimatedSprite2D`. |
| `Particles2D` | `GPUParticles2D` | error | `particles2d_class` | `Particles2D` -> `GPUParticles2D`. `CPUParticles2D` is the no-GPU alternative. |
| `Position2D` | `Marker2D` | error | `position2d_class` | `Position2D` -> `Marker2D`. |
| `TextureProgress` | `TextureProgressBar` | error | `textureprogress_class` | `TextureProgress` -> `TextureProgressBar`. |
| `VisibilityNotifier2D` | `VisibleOnScreenNotifier2D` | error | `visibilitynotifier2d_class` | `VisibilityNotifier2D` -> `VisibleOnScreenNotifier2D`. |
| `VisibilityEnabler2D` | `VisibleOnScreenEnabler2D` | error | `visibilityenabler2d_class` | `VisibilityEnabler2D` -> `VisibleOnScreenEnabler2D`. |
| `Navigation2D` | `NavigationRegion2D` | error | `navigation2d_class` | `Navigation2D` -> `NavigationRegion2D`. Pathfinding queries moved to the `NavigationServer2D` singleton. |
| `YSort` | `Node2D with y_sort_enabled = true` | error | `ysort_class` | `YSort` -> `Node2D with y_sort_enabled = true`. `y_sort_enabled` is a CanvasItem property in 4.x; the node type was removed. |
| `ParallaxBackground` | `Parallax2D` | warning | `parallaxbackground_class` | `ParallaxBackground` -> `Parallax2D`. `Parallax2D` replaces the ParallaxBackground/ParallaxLayer pair (4.3+). |
| `TileMap` | `TileMapLayer` | warning | `tilemap_class` | `TileMap` -> `TileMapLayer`. One TileMapLayer node per layer; `paint_tilemap` targets TileMapLayer. |

### Nodes (3D)

| Godot 3 | Godot 4.7 | Level | Rule id | Fix |
| --- | --- | --- | --- | --- |
| `KinematicBody` | `CharacterBody3D` | error | `kinematicbody_class` | `KinematicBody` -> `CharacterBody3D`. Set `velocity`, then call `move_and_slide()` with no arguments. |
| `Spatial` | `Node3D` | error | `spatial_class` | `Spatial` -> `Node3D`. |
| `Area` | `Area3D` | error | `area_class` | `Area` -> `Area3D`. |
| `RigidBody` | `RigidBody3D` | error | `rigidbody_class` | `RigidBody` -> `RigidBody3D`. |
| `StaticBody` | `StaticBody3D` | error | `staticbody_class` | `StaticBody` -> `StaticBody3D`. |
| `CollisionShape` | `CollisionShape3D` | error | `collisionshape_class` | `CollisionShape` -> `CollisionShape3D`. |
| `CollisionPolygon` | `CollisionPolygon3D` | error | `collisionpolygon_class` | `CollisionPolygon` -> `CollisionPolygon3D`. |
| `Particles` | `GPUParticles3D` | error | `particles_class` | `Particles` -> `GPUParticles3D`. |
| `Position3D` | `Marker3D` | error | `position3d_class` | `Position3D` -> `Marker3D`. |
| `Navigation` | `NavigationRegion3D` | error | `navigation_class` | `Navigation` -> `NavigationRegion3D`. Pathfinding queries moved to the `NavigationServer3D` singleton. |
| `RayCast` | `RayCast3D` | error | `raycast_class` | `RayCast` -> `RayCast3D`. |
| `Camera` | `Camera3D` | error | `camera_class` | `Camera` -> `Camera3D`. |
| `Light` | `Light3D` | error | `light_class` | `Light` -> `Light3D`. Light3D is abstract — use OmniLight3D / SpotLight3D / DirectionalLight3D. |
| `OmniLight` | `OmniLight3D` | error | `omnilight_class` | `OmniLight` -> `OmniLight3D`. |
| `SpotLight` | `SpotLight3D` | error | `spotlight_class` | `SpotLight` -> `SpotLight3D`. |
| `DirectionalLight` | `DirectionalLight3D` | error | `directionallight_class` | `DirectionalLight` -> `DirectionalLight3D`. |
| `MeshInstance` | `MeshInstance3D` | error | `meshinstance_class` | `MeshInstance` -> `MeshInstance3D`. |
| `Listener` | `AudioListener3D` | error | `listener_class` | `Listener` -> `AudioListener3D`. |
| `Path` | `Path3D` | error | `path_class` | `Path` -> `Path3D`. 2D curves use `Path2D`. |
| `PathFollow` | `PathFollow3D` | error | `pathfollow_class` | `PathFollow` -> `PathFollow3D`. |
| `Skeleton` | `Skeleton3D` | error | `skeleton_class` | `Skeleton` -> `Skeleton3D`. |
| `BoneAttachment` | `BoneAttachment3D` | error | `boneattachment_class` | `BoneAttachment` -> `BoneAttachment3D`. |
| `ImmediateGeometry` | `MeshInstance3D + ImmediateMesh` | error | `immediategeometry_class` | `ImmediateGeometry` -> `MeshInstance3D + ImmediateMesh`. Build the geometry into an `ImmediateMesh` resource and assign it to a MeshInstance3D. |
| `ClippedCamera` | `SpringArm3D` | error | `clippedcamera_class` | `ClippedCamera` -> `SpringArm3D`. SpringArm3D (or a ShapeCast3D) does the collision-clipping the node used to do. |
| `InterpolatedCamera` | `Camera3D + a Tween` | error | `interpolatedcamera_class` | `InterpolatedCamera` -> `Camera3D + a Tween`. Tween `global_transform` on a plain Camera3D. |
| `GIProbe` | `VoxelGI` | error | `giprobe_class` | `GIProbe` -> `VoxelGI`. |
| `BakedLightmap` | `LightmapGI` | error | `bakedlightmap_class` | `BakedLightmap` -> `LightmapGI`. Baking LightmapGI is editor-only; it cannot be done headlessly. |
| `ARVR*` | `XR*` | error | `arvr_classes` | `ARVRCamera` -> `XRCamera3D`, `ARVRController` -> `XRController3D`, `ARVROrigin` -> `XROrigin3D`, `ARVRAnchor` -> `XRAnchor3D`, `ARVRServer` -> `XRServer`, `ARVRInterface` -> `XRInterface`. |

### Resources and types

| Godot 3 | Godot 4.7 | Level | Rule id | Fix |
| --- | --- | --- | --- | --- |
| `Reference` | `RefCounted` | error | `reference_class` | `Reference` -> `RefCounted`. `extends Reference` -> `extends RefCounted`. |
| `PoolStringArray` | `PackedStringArray` | error | `poolstringarray_class` | `PoolStringArray` -> `PackedStringArray`. |
| `PoolIntArray` | `PackedInt32Array` | error | `poolintarray_class` | `PoolIntArray` -> `PackedInt32Array`. |
| `PoolRealArray` | `PackedFloat32Array` | error | `poolrealarray_class` | `PoolRealArray` -> `PackedFloat32Array`. |
| `PoolVector2Array` | `PackedVector2Array` | error | `poolvector2array_class` | `PoolVector2Array` -> `PackedVector2Array`. |
| `PoolVector3Array` | `PackedVector3Array` | error | `poolvector3array_class` | `PoolVector3Array` -> `PackedVector3Array`. |
| `PoolColorArray` | `PackedColorArray` | error | `poolcolorarray_class` | `PoolColorArray` -> `PackedColorArray`. |
| `PoolByteArray` | `PackedByteArray` | error | `poolbytearray_class` | `PoolByteArray` -> `PackedByteArray`. |
| `StreamTexture` | `CompressedTexture2D` | error | `streamtexture_class` | `StreamTexture` -> `CompressedTexture2D`. |
| `DynamicFont` | `FontFile` | error | `dynamicfont_class` | `DynamicFont` -> `FontFile`. Set `Label`'s `theme_override_fonts/font` to the FontFile; size is `theme_override_font_sizes/font_size`. |
| `BitmapFont` | `FontFile` | error | `bitmapfont_class` | `BitmapFont` -> `FontFile`. |
| `PanoramaSky` | `PanoramaSkyMaterial` | error | `panoramasky_class` | `PanoramaSky` -> `PanoramaSkyMaterial`. Assign it to `Sky.sky_material` on the Environment. |
| `ProceduralSky` | `ProceduralSkyMaterial` | error | `proceduralsky_class` | `ProceduralSky` -> `ProceduralSkyMaterial`. Assign it to `Sky.sky_material` on the Environment. |
| `CubeMesh` | `BoxMesh` | error | `cubemesh_class` | `CubeMesh` -> `BoxMesh`. |

### Math and utility functions

| Godot 3 | Godot 4.7 | Level | Rule id | Fix |
| --- | --- | --- | --- | --- |
| `rand_range(` | `randf_range(` | error | `rand_range` | `rand_range(a, b)` -> `randf_range(a, b)` for floats, `randi_range(a, b)` for ints. |
| `deg2rad(` | `deg_to_rad(` | error | `deg2rad` | `deg2rad(x)` -> `deg_to_rad(x)`. |
| `rad2deg(` | `rad_to_deg(` | error | `rad2deg` | `rad2deg(x)` -> `rad_to_deg(x)`. |
| `stepify(` | `snappedf(` | error | `stepify` | `stepify(x, 0.5)` -> `snappedf(x, 0.5)` (`snapped()` for Vector2/Vector3). |
| `.linear_interpolate(` | `.lerp(` | error | `linear_interpolate` | `a.linear_interpolate(b, t)` -> `a.lerp(b, t)`. |
| `.xform(` | `transform * value` | error | `xform` | `t.xform(v)` -> `t * v`; `t.xform_inv(v)` -> `v * t` (or `t.affine_inverse() * v`). |
| `TYPE_REAL` | `TYPE_FLOAT` | error | `type_real` | `TYPE_REAL` -> `TYPE_FLOAT`. |
| `Color.white` | `Color.WHITE` | error | `color_lowercase` | `Color.white` -> `Color.WHITE`, `Color.red` -> `Color.RED`, `Color.dodger_blue` -> `Color.DODGER_BLUE`. |

### Control properties

| Godot 3 | Godot 4.7 | Level | Rule id | Fix |
| --- | --- | --- | --- | --- |
| `rect_position` | `position` | error | `rect_position` | `rect_position` -> `position`. |
| `rect_size` | `size` | error | `rect_size` | `rect_size` -> `size`. |
| `rect_min_size` | `custom_minimum_size` | error | `rect_min_size` | `rect_min_size` -> `custom_minimum_size` (a Vector2; `configure_control` sets it directly). |
| `rect_global_position` | `global_position` | error | `rect_global_position` | `rect_global_position` -> `global_position`. |
| `rect_scale` | `scale` | error | `rect_scale` | `rect_scale` -> `scale`. |
| `rect_rotation` | `rotation` | error | `rect_rotation` | `rect_rotation` -> `rotation` (radians; `rotation_degrees` for degrees). |
| `rect_pivot_offset` | `pivot_offset` | error | `rect_pivot_offset` | `rect_pivot_offset` -> `pivot_offset`. |
| `margin_left / margin_top / margin_right / margin_bottom` | `offset_left / offset_top / offset_right / offset_bottom` | error | `margin_sides` | `margin_left` -> `offset_left`, `margin_top` -> `offset_top`, `margin_right` -> `offset_right`, `margin_bottom` -> `offset_bottom`. Prefer containers plus `configure_control` presets over hand-set offsets. |
| `hint_tooltip` | `tooltip_text` | error | `hint_tooltip` | `hint_tooltip` -> `tooltip_text`. |
| `percent_visible` | `visible_ratio` | error | `percent_visible` | `percent_visible` -> `visible_ratio` (`visible_characters` still exists). |

### File, OS, and engine

| Godot 3 | Godot 4.7 | Level | Rule id | Fix |
| --- | --- | --- | --- | --- |
| `File.new()` | `FileAccess.open()` | error | `file_new` | `var f := File.new(); f.open(path, File.READ)` -> `var f := FileAccess.open(path, FileAccess.READ)` (returns null on failure; check `FileAccess.get_open_error()`). Files close themselves when the reference is freed. |
| `Directory.new()` | `DirAccess.open()` | error | `directory_new` | `var d := Directory.new(); d.open(path)` -> `var d := DirAccess.open(path)`; listing is `DirAccess.get_files_at(path)` / `get_directories_at(path)`. |
| `OS.get_ticks_msec()` | `Time.get_ticks_msec()` | error | `os_get_ticks` | `OS.get_ticks_msec()` -> `Time.get_ticks_msec()`; `OS.get_ticks_usec()` -> `Time.get_ticks_usec()`; `OS.get_datetime()` -> `Time.get_datetime_dict_from_system()`. |
| `OS.window_size` | `DisplayServer.window_get_size()` | error | `os_window_size` | `OS.window_size` -> `get_window().size` (or `DisplayServer.window_get_size()`); `OS.window_fullscreen = true` -> `get_window().mode = Window.MODE_FULLSCREEN`. |
| `Engine.editor_hint` | `Engine.is_editor_hint()` | error | `engine_editor_hint` | `if Engine.editor_hint:` -> `if Engine.is_editor_hint():`. |

## Migration Order

1. **Class names first** (`type="..."` in `.tscn`/`.tres`, `extends`, type
   annotations). A scene whose root type does not exist fails to load, and every
   diagnostic about the script attached to it is downstream noise.
2. **Then the syntax keywords** (`onready`, `export`, `tool`, `setget`,
   `yield`). One of these stops the whole script from parsing, which cascades
   into `Failed to load script` and null-instance errors everywhere it is used.
3. **Then the renamed calls and properties** — these are per-line and
   independent.
4. **Re-run the linter, then `validate_project.py`.** The linter is text-only
   and cannot see a type error the analyzer will catch; the Godot pass is still
   the gate. See `references/gdscript_conventions.md` for the typing rules that
   apply to the code you just rewrote.
