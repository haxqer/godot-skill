class_name GodotSkillSceneEditor
extends RefCounted

var utils_script = preload("./utils.gd")

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
    _set_owner_recursive(instance_root, scene_root)

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

    var animation_name = str(params.get("animation_name", "")).strip_edges()
    if animation_name.is_empty():
        utils_script.log_error("build_sprite_frames requires animation_name")
        return false

    var frame_paths = _collect_frame_paths(params)
    if frame_paths.is_empty():
        utils_script.log_error("build_sprite_frames requires at least one valid frame")
        return false

    var sprite_frames: SpriteFrames = null
    var existing_frames = (node as AnimatedSprite2D).sprite_frames
    if existing_frames:
        var duplicated = existing_frames.duplicate(true)
        if duplicated is SpriteFrames:
            sprite_frames = duplicated
    if sprite_frames == null:
        sprite_frames = SpriteFrames.new()
        if sprite_frames.has_animation("default") and animation_name != "default" and sprite_frames.get_frame_count("default") == 0:
            sprite_frames.remove_animation("default")

    if sprite_frames.has_animation(animation_name):
        sprite_frames.clear(animation_name)
    else:
        sprite_frames.add_animation(animation_name)

    var fps = max(float(params.get("fps", 8.0)), 0.01)
    sprite_frames.set_animation_speed(animation_name, fps)
    sprite_frames.set_animation_loop(animation_name, bool(params.get("loop", false)))

    for frame_path in frame_paths:
        var texture = _load_texture(frame_path, "build_sprite_frames")
        if not texture:
            return false
        sprite_frames.add_frame(animation_name, texture)

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

    var animated_sprite := node as AnimatedSprite2D
    animated_sprite.sprite_frames = sprite_frames
    animated_sprite.animation = StringName(animation_name)
    return true

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
    match typeof(value):
        TYPE_DICTIONARY:
            var dictionary = value as Dictionary
            if dictionary.has("__resource"):
                return _load_resource_reference(dictionary["__resource"], context)
            if dictionary.has("__type"):
                return _convert_typed_value(dictionary, context)
            var converted_dictionary := {}
            for key in dictionary.keys():
                var converted = _convert_json_value(dictionary[key], "%s.%s" % [context, str(key)])
                if converted == null and dictionary[key] != null:
                    return null
                converted_dictionary[key] = converted
            return converted_dictionary
        TYPE_ARRAY:
            var converted_array: Array = []
            for index in range(value.size()):
                var converted_item = _convert_json_value(value[index], "%s[%d]" % [context, index])
                if converted_item == null and value[index] != null:
                    return null
                converted_array.append(converted_item)
            return converted_array
        _:
            return value

func _convert_typed_value(dictionary: Dictionary, context: String) -> Variant:
    var type_name = str(dictionary.get("__type", ""))
    match type_name:
        "Vector2":
            return Vector2(float(dictionary.get("x", 0.0)), float(dictionary.get("y", 0.0)))
        "Vector2i":
            return Vector2i(int(dictionary.get("x", 0)), int(dictionary.get("y", 0)))
        "Vector3":
            return Vector3(float(dictionary.get("x", 0.0)), float(dictionary.get("y", 0.0)), float(dictionary.get("z", 0.0)))
        "Vector3i":
            return Vector3i(int(dictionary.get("x", 0)), int(dictionary.get("y", 0)), int(dictionary.get("z", 0)))
        "Vector4":
            return Vector4(
                float(dictionary.get("x", 0.0)),
                float(dictionary.get("y", 0.0)),
                float(dictionary.get("z", 0.0)),
                float(dictionary.get("w", 0.0))
            )
        "Vector4i":
            return Vector4i(
                int(dictionary.get("x", 0)),
                int(dictionary.get("y", 0)),
                int(dictionary.get("z", 0)),
                int(dictionary.get("w", 0))
            )
        "Rect2":
            return Rect2(
                float(dictionary.get("x", 0.0)),
                float(dictionary.get("y", 0.0)),
                float(dictionary.get("width", 0.0)),
                float(dictionary.get("height", 0.0))
            )
        "Rect2i":
            return Rect2i(
                int(dictionary.get("x", 0)),
                int(dictionary.get("y", 0)),
                int(dictionary.get("width", 0)),
                int(dictionary.get("height", 0))
            )
        "Color":
            return Color(
                float(dictionary.get("r", 0.0)),
                float(dictionary.get("g", 0.0)),
                float(dictionary.get("b", 0.0)),
                float(dictionary.get("a", 1.0))
            )
        "NodePath":
            return NodePath(str(dictionary.get("value", "")))
        "StringName":
            return StringName(str(dictionary.get("value", "")))
        _:
            utils_script.log_error("Unsupported typed JSON value at %s: %s" % [context, type_name])
            return null

func _load_resource_reference(raw_path: Variant, context: String) -> Variant:
    var resource_path = _normalize_res_path(raw_path)
    if resource_path.is_empty():
        utils_script.log_error("Empty resource reference at " + context)
        return null

    var resource = load(resource_path)
    if not resource:
        utils_script.log_error("Failed to load resource at %s: %s" % [context, resource_path])
        return null

    return resource

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
