class_name GodotSkillSceneEditor
extends RefCounted

var utils_script = preload("./utils.gd")
var variant_codec = preload("./variant_codec.gd").new()

const CONTROL_SIDE_MAP = {
    "left": 0,
    "top": 1,
    "right": 2,
    "bottom": 3
}
const FRAME_IMAGE_EXTENSIONS = ["png", "webp", "jpg", "jpeg"]

var scene_path := ""
var scene_root: Node = null

func open_existing_scene(scene_path_value: Variant) -> bool:
    scene_path = _normalize_res_path(scene_path_value)
    if scene_path.is_empty():
        utils_script.log_error("scene_path is required")
        return false
    if not FileAccess.file_exists(scene_path):
        utils_script.log_error("Scene file does not exist at: " + scene_path)
        return false

    var scene = load(scene_path)
    if not scene:
        utils_script.log_error("Failed to load scene: " + scene_path)
        return false

    scene_root = scene.instantiate()
    if not scene_root:
        utils_script.log_error("Failed to instantiate scene: " + scene_path)
        return false
    return true

func create_new_scene(scene_path_value: Variant, root_node_type: Variant = "Node2D", root_node_name: Variant = "root") -> bool:
    scene_path = _normalize_res_path(scene_path_value)
    if scene_path.is_empty():
        utils_script.log_error("scene_path is required")
        return false

    var root = utils_script.instantiate_class(str(root_node_type))
    if not (root is Node):
        utils_script.log_error("Failed to instantiate node of type: " + str(root_node_type))
        return false

    scene_root = root
    scene_root.name = str(root_node_name)
    return true

func open_or_create_scene(params: Dictionary) -> bool:
    var target_scene_path = _normalize_res_path(params.get("scene_path", ""))
    if target_scene_path.is_empty():
        utils_script.log_error("scene_path is required")
        return false
    if FileAccess.file_exists(target_scene_path):
        return open_existing_scene(target_scene_path)
    if not bool(params.get("create_if_missing", false)):
        utils_script.log_error("Scene file does not exist at: " + target_scene_path)
        return false
    return create_new_scene(
        target_scene_path,
        params.get("root_node_type", "Node2D"),
        params.get("root_node_name", "root")
    )

func cleanup() -> void:
    if is_instance_valid(scene_root):
        scene_root.free()
    scene_root = null

func save_scene(save_path_value: Variant = "") -> bool:
    if not is_instance_valid(scene_root):
        utils_script.log_error("No scene is loaded")
        return false

    var target_path = scene_path
    if not str(save_path_value).is_empty():
        target_path = _normalize_res_path(save_path_value)

    if target_path.is_empty():
        utils_script.log_error("Could not determine save path")
        return false

    if not _ensure_directory_for_path(target_path):
        return false

    var packed_scene = PackedScene.new()
    var pack_error = packed_scene.pack(scene_root)
    if pack_error != OK:
        utils_script.log_error("Failed to pack scene: " + str(pack_error))
        return false

    var save_error = ResourceSaver.save(packed_scene, target_path)
    if save_error != OK:
        utils_script.log_error("Failed to save scene: " + str(save_error))
        return false

    return true

func run_batch(params: Dictionary) -> bool:
    var actions = params.get("actions", [])
    if not (actions is Array) or actions.is_empty():
        utils_script.log_error("scene_batch requires a non-empty actions array")
        return false

    for raw_action in actions:
        if not (raw_action is Dictionary):
            utils_script.log_error("scene_batch actions must be dictionaries")
            return false
        var action = raw_action as Dictionary
        var action_type = str(action.get("type", ""))
        if action_type.is_empty():
            utils_script.log_error("scene_batch action type is required")
            return false
        if not dispatch_action(action_type, action):
            utils_script.log_error("scene_batch aborted at action: " + action_type)
            return false
    return true

func dispatch_action(action_type: String, params: Dictionary) -> bool:
    match action_type:
        "add_node":
            return add_node(params)
        "instantiate_scene":
            return instantiate_scene(params)
        "configure_node":
            return configure_node(params)
        "configure_control":
            return configure_control(params)
        "attach_script":
            return attach_script(params)
        "connect_signal":
            return connect_signal(params)
        "disconnect_signal":
            return disconnect_signal(params)
        "remove_node":
            return remove_node(params)
        "reparent_node":
            return reparent_node(params)
        "reorder_node":
            return reorder_node(params)
        "load_sprite":
            return load_sprite(params)
        "build_sprite_frames":
            return build_sprite_frames(params)
        "paint_tilemap":
            return paint_tilemap(params)
        _:
            utils_script.log_error("Unsupported scene action: " + action_type)
            return false

func add_node(params: Dictionary) -> bool:
    var parent = _resolve_node(params.get("parent_node_path", "root"), "parent_node_path")
    if not parent:
        return false

    var node_type = str(params.get("node_type", ""))
    var node_name = str(params.get("node_name", ""))
    if node_type.is_empty() or node_name.is_empty():
        utils_script.log_error("add_node requires node_type and node_name")
        return false

    var new_node = utils_script.instantiate_class(node_type)
    if not (new_node is Node):
        utils_script.log_error("Failed to instantiate node of type: " + node_type)
        return false

    new_node.name = node_name
    _insert_child(parent, new_node, int(params.get("index", -1)))
    _set_owner_recursive(new_node, scene_root)

    if not _apply_common_node_configuration(new_node, params):
        return false

    return true

func instantiate_scene(params: Dictionary) -> bool:
    var parent = _resolve_node(params.get("parent_node_path", "root"), "parent_node_path")
    if not parent:
        return false

    var instance_scene_path = _normalize_res_path(params.get("instance_scene_path", ""))
    if instance_scene_path.is_empty():
        utils_script.log_error("instantiate_scene requires instance_scene_path")
        return false

    var packed_scene = load(instance_scene_path)
    if not packed_scene:
        utils_script.log_error("Failed to load packed scene: " + instance_scene_path)
        return false

    var instance_root = packed_scene.instantiate()
    if not (instance_root is Node):
        utils_script.log_error("Failed to instantiate packed scene: " + instance_scene_path)
        return false

    if params.has("node_name"):
        instance_root.name = str(params.get("node_name"))

    _insert_child(parent, instance_root, int(params.get("index", -1)))
    # Only the instance ROOT is owned by the editing scene. Recursively
    # re-owning the instance's internal children would serialize duplicates of
    # them into the parent scene alongside the instanced scene itself.
    instance_root.owner = scene_root

    if params.has("unique_name_in_owner"):
        instance_root.set_unique_name_in_owner(bool(params.get("unique_name_in_owner")))

    if not _apply_properties(instance_root, params.get("properties", {}), false, "instantiate_scene.properties"):
        return false
    if not _apply_properties(instance_root, params.get("indexed_properties", {}), true, "instantiate_scene.indexed_properties"):
        return false

    return true

func configure_node(params: Dictionary) -> bool:
    var node = _resolve_node(params.get("node_path", "root"), "node_path")
    if not node:
        return false

    if not _apply_common_node_configuration(node, params):
        return false

    if params.has("unique_name_in_owner"):
        node.set_unique_name_in_owner(bool(params.get("unique_name_in_owner")))

    return true

func configure_control(params: Dictionary) -> bool:
    var node = _resolve_node(params.get("node_path", "root"), "node_path")
    if not node:
        return false
    if not (node is Control):
        utils_script.log_error("Node is not a Control: " + str(params.get("node_path", "root")))
        return false

    var control := node as Control

    if params.has("layout_preset"):
        var layout_preset = _resolve_class_constant("Control", params.get("layout_preset"), "PRESET_", "layout_preset")
        if layout_preset == null:
            return false
        var preset_mode = _resolve_class_constant(
            "Control",
            params.get("layout_preset_mode", "MODE_MINSIZE"),
            "PRESET_",
            "layout_preset_mode"
        )
        if preset_mode == null:
            return false
        control.set_anchors_and_offsets_preset(int(layout_preset), int(preset_mode))

    if params.has("anchors_preset"):
        var anchors_preset = _resolve_class_constant("Control", params.get("anchors_preset"), "PRESET_", "anchors_preset")
        if anchors_preset == null:
            return false
        control.set_anchors_preset(int(anchors_preset))

    if params.has("offsets_preset"):
        var offsets_preset = _resolve_class_constant("Control", params.get("offsets_preset"), "PRESET_", "offsets_preset")
        if offsets_preset == null:
            return false
        var offsets_mode = _resolve_class_constant(
            "Control",
            params.get("offsets_preset_mode", "MODE_MINSIZE"),
            "PRESET_",
            "offsets_preset_mode"
        )
        if offsets_mode == null:
            return false
        control.set_offsets_preset(int(offsets_preset), int(offsets_mode))

    if params.has("anchor_overrides"):
        if not _apply_side_values(control, params.get("anchor_overrides"), true):
            return false
    if params.has("offset_overrides"):
        if not _apply_side_values(control, params.get("offset_overrides"), false):
            return false

    if params.has("position"):
        var position_value = _coerce_vector2(params.get("position"), "position")
        if position_value == null:
            return false
        control.position = position_value

    if params.has("size"):
        var size_value = _coerce_vector2(params.get("size"), "size")
        if size_value == null:
            return false
        control.size = size_value

    if params.has("custom_minimum_size"):
        var minimum_size = _coerce_vector2(params.get("custom_minimum_size"), "custom_minimum_size")
        if minimum_size == null:
            return false
        control.custom_minimum_size = minimum_size

    if params.has("size_flags_horizontal"):
        var horizontal_flags = _resolve_class_constant(
            "Control",
            params.get("size_flags_horizontal"),
            "SIZE_",
            "size_flags_horizontal"
        )
        if horizontal_flags == null:
            return false
        control.set_h_size_flags(int(horizontal_flags))

    if params.has("size_flags_vertical"):
        var vertical_flags = _resolve_class_constant(
            "Control",
            params.get("size_flags_vertical"),
            "SIZE_",
            "size_flags_vertical"
        )
        if vertical_flags == null:
            return false
        control.set_v_size_flags(int(vertical_flags))

    if params.has("stretch_ratio"):
        control.size_flags_stretch_ratio = float(params.get("stretch_ratio"))

    if params.has("theme_overrides"):
        if not _apply_theme_overrides(control, params.get("theme_overrides")):
            return false

    return true

func attach_script(params: Dictionary) -> bool:
    var node = _resolve_node(params.get("node_path", "root"), "node_path")
    if not node:
        return false

    var script_path = _normalize_res_path(params.get("script_path", ""))
    if script_path.is_empty():
        utils_script.log_error("attach_script requires script_path")
        return false

    var script_resource = load(script_path)
    if not (script_resource is Script):
        utils_script.log_error("Failed to load script: " + script_path)
        return false

    var existing_script = node.get_script()
    var replace_existing = bool(params.get("replace_existing", true))
    if existing_script and existing_script != script_resource and not replace_existing:
        utils_script.log_error("Node already has a different script and replace_existing is false")
        return false

    if existing_script != script_resource:
        node.set_script(script_resource)

    if not _apply_properties(node, params.get("script_properties", {}), false, "attach_script.script_properties"):
        return false
    if not _apply_properties(node, params.get("indexed_script_properties", {}), true, "attach_script.indexed_script_properties"):
        return false

    return true

func connect_signal(params: Dictionary) -> bool:
    if str(params.get("node_path", "")).strip_edges().is_empty():
        utils_script.log_error("connect_signal requires node_path")
        return false
    if str(params.get("target_node_path", "")).strip_edges().is_empty():
        utils_script.log_error("connect_signal requires target_node_path")
        return false

    var source = _resolve_node(params.get("node_path", ""), "node_path")
    if not source:
        return false
    var target = _resolve_node(params.get("target_node_path", ""), "target_node_path")
    if not target:
        return false

    var signal_name = str(params.get("signal_name", ""))
    var method_name = str(params.get("method_name", ""))
    if signal_name.is_empty() or method_name.is_empty():
        utils_script.log_error("connect_signal requires signal_name and method_name")
        return false
    if not source.has_signal(signal_name):
        utils_script.log_error("Source node does not have signal: " + signal_name)
        return false
    if not target.has_method(method_name):
        utils_script.log_error("Target node does not have method: " + method_name)
        return false

    var signal_ref = Signal(source, signal_name)
    var callable = Callable(target, method_name)
    if params.has("binds"):
        var converted_binds = _convert_json_value(params.binds, "connect_signal.binds")
        if converted_binds == null and params.binds != null:
            return false
        if not (converted_binds is Array):
            utils_script.log_error("connect_signal.binds must resolve to an array")
            return false
        callable = callable.bindv(converted_binds)

    var flags = 0
    if bool(params.get("persist", true)):
        flags |= Object.CONNECT_PERSIST
    if bool(params.get("deferred", false)):
        flags |= Object.CONNECT_DEFERRED
    if bool(params.get("one_shot", false)):
        flags |= Object.CONNECT_ONE_SHOT
    if bool(params.get("reference_counted", false)):
        flags |= Object.CONNECT_REFERENCE_COUNTED

    if bool(params.get("replace_existing", true)):
        _disconnect_matching_connections(signal_ref, target, method_name)
    elif _has_exact_connection(signal_ref, callable, flags):
        return true

    if _has_exact_connection(signal_ref, callable, flags):
        return true

    var connect_error = signal_ref.connect(callable, flags)
    if connect_error != OK:
        utils_script.log_error("Failed to connect signal: " + str(connect_error))
        return false

    return true

func disconnect_signal(params: Dictionary) -> bool:
    if str(params.get("node_path", "")).strip_edges().is_empty():
        utils_script.log_error("disconnect_signal requires node_path")
        return false
    if str(params.get("target_node_path", "")).strip_edges().is_empty():
        utils_script.log_error("disconnect_signal requires target_node_path")
        return false

    var source = _resolve_node(params.get("node_path", ""), "node_path")
    if not source:
        return false
    var target = _resolve_node(params.get("target_node_path", ""), "target_node_path")
    if not target:
        return false

    var signal_name = str(params.get("signal_name", ""))
    var method_name = str(params.get("method_name", ""))
    if signal_name.is_empty() or method_name.is_empty():
        utils_script.log_error("disconnect_signal requires signal_name and method_name")
        return false
    if not source.has_signal(signal_name):
        return true

    var signal_ref = Signal(source, signal_name)
    _disconnect_matching_connections(signal_ref, target, method_name)
    return true

func remove_node(params: Dictionary) -> bool:
    var node = _resolve_node(params.get("node_path", ""), "node_path")
    if not node:
        return false
    if node == scene_root:
        utils_script.log_error("remove_node cannot remove the scene root")
        return false

    var parent = node.get_parent()
    if parent:
        parent.remove_child(node)
    node.free()
    return true

func reparent_node(params: Dictionary) -> bool:
    var node = _resolve_node(params.get("node_path", ""), "node_path")
    if not node:
        return false
    if node == scene_root:
        utils_script.log_error("reparent_node cannot move the scene root")
        return false

    var new_parent = _resolve_node(params.get("new_parent_node_path", ""), "new_parent_node_path")
    if not new_parent:
        return false
    if node.is_ancestor_of(new_parent):
        utils_script.log_error("Cannot reparent a node into its own descendant")
        return false

    _clear_owner_recursive(node)
    node.reparent(new_parent, bool(params.get("keep_global_transform", true)))
    _set_owner_recursive(node, scene_root)

    var target_index = int(params.get("index", -1))
    if target_index >= 0:
        new_parent.move_child(node, clamp(target_index, 0, max(new_parent.get_child_count() - 1, 0)))

    return true

func reorder_node(params: Dictionary) -> bool:
    var node = _resolve_node(params.get("node_path", ""), "node_path")
    if not node:
        return false
    if node == scene_root:
        utils_script.log_error("reorder_node cannot move the scene root")
        return false

    var parent = node.get_parent()
    if not parent:
        utils_script.log_error("Node does not have a parent: " + node.name)
        return false

    var target_index = int(params.get("index", -1))
    if target_index < 0:
        utils_script.log_error("reorder_node requires a non-negative index")
        return false

    parent.move_child(node, clamp(target_index, 0, max(parent.get_child_count() - 1, 0)))
    return true

func load_sprite(params: Dictionary) -> bool:
    var node = _resolve_node(params.get("node_path", "root"), "node_path")
    if not node:
        return false
    if not (node is Sprite2D or node is Sprite3D or node is TextureRect):
        utils_script.log_error("Node is not a sprite-compatible type: " + node.get_class())
        return false

    var texture_path = _normalize_res_path(params.get("texture_path", ""))
    if texture_path.is_empty():
        utils_script.log_error("load_sprite requires texture_path")
        return false

    var texture = load(texture_path)
    if not texture:
        utils_script.log_error("Failed to load texture: " + texture_path)
        return false

    node.texture = texture
    return true

func build_sprite_frames(params: Dictionary) -> bool:
    var node = _resolve_node(params.get("node_path", "root"), "node_path")
    if not node:
        return false
    if not (node is AnimatedSprite2D):
        utils_script.log_error("Node is not an AnimatedSprite2D: " + str(params.get("node_path", "root")))
        return false

    if params.has("animations"):
        return _build_sprite_frames_multi(node as AnimatedSprite2D, params)

    var animation_name = str(params.get("animation_name", "")).strip_edges()
    if animation_name.is_empty():
        utils_script.log_error("build_sprite_frames requires animation_name or animations")
        return false

    var frame_paths = _collect_frame_paths(params)
    if frame_paths.is_empty():
        utils_script.log_error("build_sprite_frames requires at least one valid frame")
        return false

    var sprite_frames := _prepare_sprite_frames(node as AnimatedSprite2D, animation_name)
    _reset_animation(sprite_frames, animation_name, params)

    for frame_path in frame_paths:
        var texture = _load_texture(frame_path, "build_sprite_frames")
        if not texture:
            return false
        sprite_frames.add_frame(animation_name, texture)

    return _finalize_sprite_frames(node as AnimatedSprite2D, sprite_frames, params, animation_name)

func _build_sprite_frames_multi(node: AnimatedSprite2D, params: Dictionary) -> bool:
    var animations = params.get("animations", [])
    if not (animations is Array) or animations.is_empty():
        utils_script.log_error("build_sprite_frames.animations must be a non-empty array")
        return false

    var sheet_texture: Texture2D = null
    if params.has("spritesheet"):
        sheet_texture = _load_texture(str(params.get("spritesheet", "")), "build_sprite_frames.spritesheet")
        if not sheet_texture:
            return false

    var grid = params.get("grid", {})
    if not (grid is Dictionary):
        utils_script.log_error("build_sprite_frames.grid must be a dictionary")
        return false
    if not grid.is_empty() and (int(grid.get("cell_width", 0)) <= 0 or int(grid.get("cell_height", 0)) <= 0):
        utils_script.log_error("build_sprite_frames.grid requires positive cell_width and cell_height")
        return false

    var first_name := ""
    var sprite_frames: SpriteFrames = null
    for raw_animation in animations:
        if not (raw_animation is Dictionary):
            utils_script.log_error("build_sprite_frames.animations entries must be dictionaries")
            return false
        var animation = raw_animation as Dictionary
        var animation_name = str(animation.get("name", "")).strip_edges()
        if animation_name.is_empty():
            utils_script.log_error("build_sprite_frames.animations entries require name")
            return false
        if first_name.is_empty():
            first_name = animation_name
            sprite_frames = _prepare_sprite_frames(node, animation_name)
        _reset_animation(sprite_frames, animation_name, animation)

        var frame_specs = animation.get("frames", [])
        if not (frame_specs is Array) or frame_specs.is_empty():
            utils_script.log_error("Animation '%s' requires a non-empty frames array" % animation_name)
            return false
        for raw_spec in frame_specs:
            if not (raw_spec is Dictionary):
                utils_script.log_error("Frame specs must be dictionaries in animation: " + animation_name)
                return false
            if not _append_frames_from_spec(sprite_frames, animation_name, raw_spec, sheet_texture, grid):
                return false

    return _finalize_sprite_frames(node, sprite_frames, params, first_name)

func _append_frames_from_spec(sprite_frames: SpriteFrames, animation_name: String, spec: Dictionary, sheet: Texture2D, grid: Dictionary) -> bool:
    var duration = max(float(spec.get("duration", 1.0)), 0.01)

    if spec.has("path"):
        var texture = _load_texture(str(spec.get("path", "")), "frames.path")
        if not texture:
            return false
        sprite_frames.add_frame(animation_name, texture, duration)
        return true

    if spec.has("region"):
        var region_texture := _make_atlas_frame(sheet, spec.get("region"), "frames.region")
        if not region_texture:
            return false
        sprite_frames.add_frame(animation_name, region_texture, duration)
        return true

    if grid.is_empty() or sheet == null:
        utils_script.log_error("Grid frame specs require spritesheet and grid on animation: " + animation_name)
        return false

    var columns := _grid_columns(sheet, grid)
    if columns <= 0:
        return false

    var cells: Array[Vector2i] = []
    if spec.has("index"):
        var index = int(spec.get("index", 0))
        cells.append(Vector2i(index % columns, int(index / float(columns))))
    elif spec.has("row") and spec.has("cols"):
        var row = int(spec.get("row", 0))
        var cols = spec.get("cols")
        if not (cols is Array) or cols.is_empty():
            utils_script.log_error("frames.cols must be a non-empty array")
            return false
        for col in cols:
            cells.append(Vector2i(int(col), row))
    elif spec.has("row") and spec.has("col"):
        cells.append(Vector2i(int(spec.get("col", 0)), int(spec.get("row", 0))))
    else:
        utils_script.log_error("Frame spec needs path, region, index, or row/col in animation: " + animation_name)
        return false

    for cell in cells:
        var atlas := _make_atlas_frame(sheet, _grid_cell_region(cell, grid), "frames.cell")
        if not atlas:
            return false
        sprite_frames.add_frame(animation_name, atlas, duration)
    return true

func _grid_columns(sheet: Texture2D, grid: Dictionary) -> int:
    var cell_width = int(grid.get("cell_width", 0))
    var separation_x = int(grid.get("separation_x", 0))
    var margin_x = int(grid.get("margin_x", 0))
    var usable = sheet.get_width() - margin_x + separation_x
    var columns = int(usable / float(cell_width + separation_x)) if cell_width + separation_x > 0 else 0
    if columns <= 0:
        utils_script.log_error("Spritesheet is narrower than one grid cell")
    return columns

func _grid_cell_region(cell: Vector2i, grid: Dictionary) -> Dictionary:
    var cell_width = int(grid.get("cell_width", 0))
    var cell_height = int(grid.get("cell_height", 0))
    var separation_x = int(grid.get("separation_x", 0))
    var separation_y = int(grid.get("separation_y", 0))
    var margin_x = int(grid.get("margin_x", 0))
    var margin_y = int(grid.get("margin_y", 0))
    return {
        "x": margin_x + cell.x * (cell_width + separation_x),
        "y": margin_y + cell.y * (cell_height + separation_y),
        "width": cell_width,
        "height": cell_height
    }

func _make_atlas_frame(sheet: Texture2D, raw_region: Variant, context: String) -> AtlasTexture:
    if sheet == null:
        utils_script.log_error("Region frame specs require spritesheet at " + context)
        return null
    if not (raw_region is Dictionary):
        utils_script.log_error(context + " must be a dictionary with x, y, width, height")
        return null
    var region = raw_region as Dictionary
    var rect := Rect2(
        float(region.get("x", 0.0)),
        float(region.get("y", 0.0)),
        float(region.get("width", 0.0)),
        float(region.get("height", 0.0))
    )
    if rect.size.x <= 0 or rect.size.y <= 0:
        utils_script.log_error(context + " requires positive width and height")
        return null
    if rect.position.x + rect.size.x > sheet.get_width() or rect.position.y + rect.size.y > sheet.get_height():
        utils_script.log_error("%s region %s exceeds spritesheet bounds %dx%d" % [context, str(rect), sheet.get_width(), sheet.get_height()])
        return null
    var atlas := AtlasTexture.new()
    atlas.atlas = sheet
    atlas.region = rect
    return atlas

func _prepare_sprite_frames(node: AnimatedSprite2D, first_animation_name: String) -> SpriteFrames:
    var sprite_frames: SpriteFrames = null
    var existing_frames = node.sprite_frames
    if existing_frames:
        var duplicated = existing_frames.duplicate(true)
        if duplicated is SpriteFrames:
            sprite_frames = duplicated
    if sprite_frames == null:
        sprite_frames = SpriteFrames.new()
        if sprite_frames.has_animation("default") and first_animation_name != "default" and sprite_frames.get_frame_count("default") == 0:
            sprite_frames.remove_animation("default")
    return sprite_frames

func _reset_animation(sprite_frames: SpriteFrames, animation_name: String, options: Dictionary) -> void:
    if sprite_frames.has_animation(animation_name):
        sprite_frames.clear(animation_name)
    else:
        sprite_frames.add_animation(animation_name)
    sprite_frames.set_animation_speed(animation_name, max(float(options.get("fps", 8.0)), 0.01))
    sprite_frames.set_animation_loop(animation_name, bool(options.get("loop", false)))

func _finalize_sprite_frames(node: AnimatedSprite2D, sprite_frames: SpriteFrames, params: Dictionary, active_animation: String) -> bool:
    if params.has("resource_save_path"):
        var resource_save_path = _normalize_res_path(params.get("resource_save_path", ""))
        if resource_save_path.is_empty():
            utils_script.log_error("resource_save_path cannot be empty")
            return false
        if not _ensure_directory_for_path(resource_save_path):
            return false
        var save_error = ResourceSaver.save(sprite_frames, resource_save_path)
        if save_error != OK:
            utils_script.log_error("Failed to save SpriteFrames resource: " + str(save_error))
            return false
        var reloaded_frames = load(resource_save_path)
        if not (reloaded_frames is SpriteFrames):
            utils_script.log_error("Failed to reload SpriteFrames resource: " + resource_save_path)
            return false
        sprite_frames = reloaded_frames

    node.sprite_frames = sprite_frames
    node.animation = StringName(active_animation)
    return true

func paint_tilemap(params: Dictionary) -> bool:
    var node = _resolve_node(params.get("node_path", "root"), "node_path")
    if not node:
        return false
    if not (node is TileMapLayer):
        utils_script.log_error("Node is not a TileMapLayer (the TileMap node is deprecated since Godot 4.3): " + str(params.get("node_path", "root")))
        return false

    var layer := node as TileMapLayer

    if params.has("tile_set"):
        var tile_set_value = _convert_json_value(params.get("tile_set"), "paint_tilemap.tile_set")
        if tile_set_value is String:
            tile_set_value = _convert_json_value({"__resource": tile_set_value}, "paint_tilemap.tile_set")
        if not (tile_set_value is TileSet):
            utils_script.log_error("paint_tilemap.tile_set must resolve to a TileSet resource")
            return false
        layer.tile_set = tile_set_value

    if layer.tile_set == null:
        utils_script.log_error("TileMapLayer has no tile_set; assign one before painting cells")
        return false

    if bool(params.get("clear", false)):
        layer.clear()

    var erase_cells = params.get("erase", [])
    if erase_cells is Array:
        for raw_coords in erase_cells:
            var coords: Variant = _coerce_cell_coords(raw_coords, "paint_tilemap.erase")
            if coords == null:
                return false
            layer.erase_cell(coords)

    var cells = params.get("cells", [])
    if not (cells is Array):
        utils_script.log_error("paint_tilemap.cells must be an array")
        return false
    for raw_cell in cells:
        if not (raw_cell is Dictionary):
            utils_script.log_error("paint_tilemap.cells entries must be dictionaries")
            return false
        if not _set_tilemap_cell(layer, raw_cell as Dictionary, _coerce_cell_coords(raw_cell.get("coords"), "paint_tilemap.cells")):
            return false

    var fills = params.get("fills", [])
    if not (fills is Array):
        utils_script.log_error("paint_tilemap.fills must be an array")
        return false
    for raw_fill in fills:
        if not (raw_fill is Dictionary):
            utils_script.log_error("paint_tilemap.fills entries must be dictionaries")
            return false
        var fill = raw_fill as Dictionary
        var from_coords: Variant = _coerce_cell_coords(fill.get("from"), "paint_tilemap.fills.from")
        var to_coords: Variant = _coerce_cell_coords(fill.get("to"), "paint_tilemap.fills.to")
        if from_coords == null or to_coords == null:
            return false
        var start := Vector2i(min(from_coords.x, to_coords.x), min(from_coords.y, to_coords.y))
        var finish := Vector2i(max(from_coords.x, to_coords.x), max(from_coords.y, to_coords.y))
        for y in range(start.y, finish.y + 1):
            for x in range(start.x, finish.x + 1):
                if not _set_tilemap_cell(layer, fill, Vector2i(x, y)):
                    return false

    var terrain_fills = params.get("terrain_fills", [])
    if not (terrain_fills is Array):
        utils_script.log_error("paint_tilemap.terrain_fills must be an array")
        return false
    for raw_terrain_fill in terrain_fills:
        if not (raw_terrain_fill is Dictionary):
            utils_script.log_error("paint_tilemap.terrain_fills entries must be dictionaries")
            return false
        var terrain_fill = raw_terrain_fill as Dictionary
        var terrain_cells: Array[Vector2i] = []
        var raw_cells = terrain_fill.get("cells", [])
        if not (raw_cells is Array) or raw_cells.is_empty():
            utils_script.log_error("terrain_fills entries require a non-empty cells array")
            return false
        for raw_coords in raw_cells:
            var coords: Variant = _coerce_cell_coords(raw_coords, "paint_tilemap.terrain_fills.cells")
            if coords == null:
                return false
            terrain_cells.append(coords)
        layer.set_cells_terrain_connect(
            terrain_cells,
            int(terrain_fill.get("terrain_set", 0)),
            int(terrain_fill.get("terrain", 0)),
            bool(terrain_fill.get("ignore_empty_terrains", true))
        )
    return true

func _set_tilemap_cell(layer: TileMapLayer, cell: Dictionary, coords: Variant) -> bool:
    if not (coords is Vector2i):
        return false
    var source_id := int(cell.get("source_id", 0))
    if not layer.tile_set.has_source(source_id):
        utils_script.log_error("TileSet has no source with id %d" % source_id)
        return false
    var atlas_value = cell.get("atlas_coords", {})
    var atlas_coords := Vector2i.ZERO
    if atlas_value is Dictionary and not atlas_value.is_empty():
        atlas_coords = Vector2i(int(atlas_value.get("x", 0)), int(atlas_value.get("y", 0)))
    var source = layer.tile_set.get_source(source_id)
    if source is TileSetAtlasSource and not (source as TileSetAtlasSource).has_tile(atlas_coords):
        utils_script.log_error("Atlas source %d has no tile at %s; expose it with build_tileset first" % [source_id, str(atlas_coords)])
        return false
    layer.set_cell(coords, source_id, atlas_coords, int(cell.get("alternative", 0)))
    return true

func _coerce_cell_coords(raw_coords: Variant, context: String) -> Variant:
    if raw_coords is Dictionary and raw_coords.has("x") and raw_coords.has("y"):
        return Vector2i(int(raw_coords.get("x")), int(raw_coords.get("y")))
    if raw_coords is Array and raw_coords.size() == 2:
        return Vector2i(int(raw_coords[0]), int(raw_coords[1]))
    utils_script.log_error(context + " requires cell coords as {x,y} or [x,y]")
    return null

func _apply_common_node_configuration(node: Node, params: Dictionary) -> bool:
    if not _apply_properties(node, params.get("properties", {}), false, "properties"):
        return false
    if not _apply_properties(node, params.get("indexed_properties", {}), true, "indexed_properties"):
        return false

    var groups_add = params.get("groups_add", [])
    if groups_add is Array:
        for group_name in groups_add:
            node.add_to_group(str(group_name), true)

    var groups_remove = params.get("groups_remove", [])
    if groups_remove is Array:
        for group_name in groups_remove:
            node.remove_from_group(str(group_name))

    var metadata = params.get("metadata", {})
    if metadata is Dictionary:
        for key in metadata.keys():
            var metadata_value = metadata[key]
            if metadata_value == null:
                node.remove_meta(str(key))
            else:
                var converted_value = _convert_json_value(metadata_value, "metadata.%s" % str(key))
                if converted_value == null and metadata_value != null:
                    return false
                node.set_meta(str(key), converted_value)

    return true

func _apply_properties(target: Object, raw_properties: Variant, use_indexed: bool, context: String) -> bool:
    if not (raw_properties is Dictionary):
        if raw_properties == null:
            return true
        utils_script.log_error(context + " must be a dictionary")
        return false

    var property_map = raw_properties as Dictionary
    for property_name in property_map.keys():
        var property_key = str(property_name)
        var converted_value = _convert_json_value(property_map[property_name], "%s.%s" % [context, property_key])
        if converted_value == null and property_map[property_name] != null:
            return false

        if use_indexed:
            target.set_indexed(NodePath(property_key), converted_value)
        else:
            if not _object_has_property(target, property_key):
                utils_script.log_error("Unknown property '%s' on %s" % [property_key, target.get_class()])
                return false
            target.set(property_key, converted_value)

    return true

func _apply_side_values(control: Control, raw_values: Variant, anchors: bool) -> bool:
    if not (raw_values is Dictionary):
        utils_script.log_error("Expected a dictionary for side overrides")
        return false

    var values = raw_values as Dictionary
    for key in values.keys():
        var normalized_key = str(key).to_lower()
        if not CONTROL_SIDE_MAP.has(normalized_key):
            utils_script.log_error("Unknown side override: " + normalized_key)
            return false
        var side = CONTROL_SIDE_MAP[normalized_key]
        var numeric_value = float(values[key])
        if anchors:
            control.set_anchor(side, numeric_value)
        else:
            control.set_offset(side, numeric_value)
    return true

func _apply_theme_overrides(control: Control, raw_overrides: Variant) -> bool:
    if not (raw_overrides is Dictionary):
        utils_script.log_error("theme_overrides must be a dictionary")
        return false

    var adders = {
        "colors": "add_theme_color_override",
        "constants": "add_theme_constant_override",
        "fonts": "add_theme_font_override",
        "font_sizes": "add_theme_font_size_override",
        "icons": "add_theme_icon_override",
        "styleboxes": "add_theme_stylebox_override"
    }
    var removers = {
        "colors": "remove_theme_color_override",
        "constants": "remove_theme_constant_override",
        "fonts": "remove_theme_font_override",
        "font_sizes": "remove_theme_font_size_override",
        "icons": "remove_theme_icon_override",
        "styleboxes": "remove_theme_stylebox_override"
    }

    control.begin_bulk_theme_override()
    for category in raw_overrides.keys():
        var category_name = str(category)
        if not adders.has(category_name):
            control.end_bulk_theme_override()
            utils_script.log_error("Unsupported theme override category: " + category_name)
            return false
        var category_values = raw_overrides[category]
        if not (category_values is Dictionary):
            control.end_bulk_theme_override()
            utils_script.log_error("theme_overrides.%s must be a dictionary" % category_name)
            return false

        for override_name in category_values.keys():
            var raw_value = category_values[override_name]
            if raw_value == null:
                control.call(removers[category_name], str(override_name))
                continue

            var converted_value = _convert_json_value(raw_value, "theme_overrides.%s.%s" % [category_name, str(override_name)])
            if converted_value == null and raw_value != null:
                control.end_bulk_theme_override()
                return false
            control.call(adders[category_name], str(override_name), converted_value)
    control.end_bulk_theme_override()
    return true

func _convert_json_value(value: Variant, context: String) -> Variant:
    return variant_codec.decode(value, context)

func _collect_frame_paths(params: Dictionary) -> Array[String]:
    if params.has("frame_paths"):
        var raw_frame_paths = params.get("frame_paths", [])
        if not (raw_frame_paths is Array):
            utils_script.log_error("frame_paths must be an array")
            return []

        var normalized_paths: Array[String] = []
        for raw_path in raw_frame_paths:
            var normalized_path = _normalize_res_path(raw_path)
            if normalized_path.is_empty():
                utils_script.log_error("frame_paths entries cannot be empty")
                return []
            normalized_paths.append(normalized_path)
        return normalized_paths

    var frames_dir = _normalize_res_path(params.get("frames_dir", ""))
    if frames_dir.is_empty():
        utils_script.log_error("build_sprite_frames requires frames_dir or frame_paths")
        return []

    var directory = DirAccess.open(frames_dir)
    if directory == null:
        utils_script.log_error("Failed to open frames_dir: " + frames_dir)
        return []

    var frame_paths: Array[String] = []
    for file_name in directory.get_files():
        var extension = file_name.get_extension().to_lower()
        if extension in FRAME_IMAGE_EXTENSIONS:
            frame_paths.append(frames_dir.path_join(file_name))
    frame_paths.sort_custom(func(a: String, b: String) -> bool:
        return _natural_path_less(a, b)
    )
    return frame_paths

func _load_texture(raw_path: String, context: String) -> Texture2D:
    var texture_path = _normalize_res_path(raw_path)
    if texture_path.is_empty():
        utils_script.log_error("Empty texture path for " + context)
        return null

    # Guard with exists() so an unimported image falls through to the direct
    # Image loader below without the engine printing a loader error.
    if ResourceLoader.exists(texture_path):
        var resource = load(texture_path)
        if resource is Texture2D:
            return resource

    var absolute_path = ProjectSettings.globalize_path(texture_path)
    if not FileAccess.file_exists(absolute_path):
        utils_script.log_error("Texture file does not exist: " + texture_path)
        return null

    var image = Image.load_from_file(absolute_path)
    if image == null or image.is_empty():
        utils_script.log_error("Failed to load image data for texture: " + texture_path)
        return null

    var image_texture = ImageTexture.create_from_image(image)
    image_texture.take_over_path(texture_path)
    return image_texture

func _natural_path_less(left_path: String, right_path: String) -> bool:
    var left_name = left_path.get_file()
    var right_name = right_path.get_file()
    var comparison = _compare_natural_strings(left_name, right_name)
    if comparison == 0:
        return left_path.to_lower() < right_path.to_lower()
    return comparison < 0

func _compare_natural_strings(left_value: String, right_value: String) -> int:
    var left_parts = _split_natural_parts(left_value.to_lower())
    var right_parts = _split_natural_parts(right_value.to_lower())
    var part_count = min(left_parts.size(), right_parts.size())

    for index in range(part_count):
        var left_part = left_parts[index]
        var right_part = right_parts[index]
        var left_is_digit = bool(left_part["is_digit"])
        var right_is_digit = bool(right_part["is_digit"])
        if left_is_digit and right_is_digit:
            var left_number = int(left_part["value"])
            var right_number = int(right_part["value"])
            if left_number != right_number:
                return -1 if left_number < right_number else 1
            var left_width = int(left_part["width"])
            var right_width = int(right_part["width"])
            if left_width != right_width:
                return -1 if left_width < right_width else 1
            continue
        if left_is_digit != right_is_digit:
            return -1 if left_is_digit else 1

        var left_text = str(left_part["value"])
        var right_text = str(right_part["value"])
        if left_text != right_text:
            return -1 if left_text < right_text else 1

    if left_parts.size() == right_parts.size():
        return 0
    return -1 if left_parts.size() < right_parts.size() else 1

func _split_natural_parts(value: String) -> Array:
    var parts: Array = []
    var current = ""
    var current_is_digit = false
    var has_current = false

    for index in range(value.length()):
        var character = value.substr(index, 1)
        var is_digit = character >= "0" and character <= "9"
        if not has_current:
            current = character
            current_is_digit = is_digit
            has_current = true
        elif is_digit == current_is_digit:
            current += character
        else:
            parts.append(_make_natural_part(current, current_is_digit))
            current = character
            current_is_digit = is_digit

    if has_current:
        parts.append(_make_natural_part(current, current_is_digit))
    return parts

func _make_natural_part(raw_value: String, is_digit: bool) -> Dictionary:
    if is_digit:
        return {
            "is_digit": true,
            "value": int(raw_value),
            "width": raw_value.length()
        }
    return {
        "is_digit": false,
        "value": raw_value,
        "width": raw_value.length()
    }

func _resolve_node(path_value: Variant, label: String) -> Node:
    if not is_instance_valid(scene_root):
        utils_script.log_error("No scene is loaded")
        return null

    var node_path = str(path_value)
    if node_path.is_empty() or node_path == "." or node_path == "root":
        return scene_root
    if node_path.begins_with("root/"):
        node_path = node_path.substr(5)
    if node_path.begins_with("/"):
        node_path = node_path.substr(1)
    if node_path.is_empty():
        return scene_root

    var resolved_node = scene_root.get_node_or_null(NodePath(node_path))
    if not resolved_node:
        utils_script.log_error("Node not found for %s: %s" % [label, str(path_value)])
    return resolved_node

func _insert_child(parent: Node, child: Node, index: int) -> void:
    parent.add_child(child)
    if index >= 0:
        parent.move_child(child, clamp(index, 0, max(parent.get_child_count() - 1, 0)))

func _set_owner_recursive(node: Node, owner: Node) -> void:
    if node != owner:
        node.owner = owner
    # Do not descend into instanced scenes: their internal children belong to
    # the instance, and re-owning them would serialize duplicates into the
    # editing scene.
    if node != owner and not node.scene_file_path.is_empty():
        return
    for child in node.get_children():
        if child is Node:
            _set_owner_recursive(child, owner)

func _clear_owner_recursive(node: Node) -> void:
    node.owner = null
    for child in node.get_children():
        if child is Node:
            _clear_owner_recursive(child)

func _ensure_directory_for_path(target_path: String) -> bool:
    var target_directory = target_path.get_base_dir()
    if target_directory == "res://":
        return true
    var absolute_directory = ProjectSettings.globalize_path(target_directory)
    if DirAccess.dir_exists_absolute(absolute_directory):
        return true
    var make_error = DirAccess.make_dir_recursive_absolute(absolute_directory)
    if make_error != OK:
        utils_script.log_error("Failed to create directory: " + target_directory)
        return false
    return true

func _normalize_res_path(path_value: Variant) -> String:
    var path = str(path_value).strip_edges()
    if path.is_empty():
        return ""
    if path.begins_with("res://"):
        return path
    if path.begins_with("/"):
        path = path.substr(1)
    return "res://" + path

func _resolve_class_constant(target_class_name: String, raw_value: Variant, prefix: String, field_name: String) -> Variant:
    if raw_value is int:
        return raw_value
    if raw_value is float:
        return int(raw_value)

    var constant_name = str(raw_value).strip_edges().to_upper()
    if constant_name.is_empty():
        utils_script.log_error(field_name + " cannot be empty")
        return null
    if not constant_name.begins_with(prefix):
        constant_name = prefix + constant_name

    if not ClassDB.class_get_integer_constant_list(target_class_name).has(constant_name):
        utils_script.log_error("Unknown %s constant: %s" % [field_name, constant_name])
        return null

    return ClassDB.class_get_integer_constant(target_class_name, constant_name)

func _coerce_vector2(raw_value: Variant, field_name: String) -> Variant:
    var converted_value = _convert_json_value(raw_value, field_name)
    if converted_value is Vector2:
        return converted_value
    if converted_value is Vector2i:
        return Vector2(converted_value.x, converted_value.y)
    if converted_value is Dictionary:
        var dictionary = converted_value as Dictionary
        if dictionary.has("x") and dictionary.has("y"):
            return Vector2(float(dictionary["x"]), float(dictionary["y"]))
    if converted_value is Array and converted_value.size() == 2:
        return Vector2(float(converted_value[0]), float(converted_value[1]))

    utils_script.log_error("Expected a Vector2-compatible value for " + field_name)
    return null

func _object_has_property(target: Object, property_name: String) -> bool:
    for property_info in target.get_property_list():
        if str(property_info.get("name", "")) == property_name:
            return true
    return false

func _disconnect_matching_connections(signal_ref: Signal, target: Object, method_name: String) -> void:
    var target_id = target.get_instance_id()
    for connection in signal_ref.get_connections():
        var callable = connection["callable"]
        if callable.get_object_id() == target_id and callable.get_method() == method_name:
            signal_ref.disconnect(callable)

func _has_exact_connection(signal_ref: Signal, callable: Callable, flags: int) -> bool:
    for connection in signal_ref.get_connections():
        if connection["callable"] == callable and int(connection["flags"]) == flags:
            return true
    return false
