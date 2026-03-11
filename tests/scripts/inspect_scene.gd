extends SceneTree

func _init() -> void:
    var args = OS.get_cmdline_args()
    var script_index = args.find("--script")
    if script_index == -1 or args.size() <= script_index + 2:
        printerr("[ERROR] Usage: godot --headless --path <project> --script inspect_scene.gd <json_params>")
        quit(1)
        return

    var params_json = args[script_index + 2]
    var json = JSON.new()
    if json.parse(params_json) != OK:
        printerr("[ERROR] Failed to parse JSON params")
        quit(1)
        return

    var params = json.get_data()
    var scene_path = str(params.get("scene_path", ""))
    if scene_path.is_empty():
        printerr("[ERROR] scene_path is required")
        quit(1)
        return
    if not scene_path.begins_with("res://"):
        scene_path = "res://" + scene_path

    var packed_scene = load(scene_path)
    if not packed_scene:
        printerr("[ERROR] Failed to load scene: " + scene_path)
        quit(1)
        return

    var root = packed_scene.instantiate()
    if not root:
        printerr("[ERROR] Failed to instantiate scene: " + scene_path)
        quit(1)
        return

    var id_to_path := {}
    var order := {}
    _collect_paths(root, "root", id_to_path, order)

    var nodes := {}
    var connections: Array = []
    _collect_nodes(root, "root", id_to_path, nodes, connections)
    connections.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if a["source_path"] != b["source_path"]:
            return a["source_path"] < b["source_path"]
        if a["signal"] != b["signal"]:
            return a["signal"] < b["signal"]
        if a["target_path"] != b["target_path"]:
            return a["target_path"] < b["target_path"]
        return a["method"] < b["method"]
    )

    print(JSON.stringify({
        "scene_path": scene_path,
        "nodes": nodes,
        "order": order,
        "connections": connections
    }))

    root.free()
    quit()

func _collect_paths(node: Node, path: String, id_to_path: Dictionary, order: Dictionary) -> void:
    id_to_path[node.get_instance_id()] = path
    var child_paths: Array = []
    for child in node.get_children():
        if child is Node:
            var child_path = path + "/" + child.name
            child_paths.append(child_path)
            _collect_paths(child, child_path, id_to_path, order)
    order[path] = child_paths

func _collect_nodes(node: Node, path: String, id_to_path: Dictionary, nodes: Dictionary, connections: Array) -> void:
    nodes[path] = _snapshot_node(node)
    for signal_info in node.get_signal_list():
        var signal_name = str(signal_info["name"])
        var signal_ref = Signal(node, signal_name)
        for connection in signal_ref.get_connections():
            var callable = connection["callable"]
            connections.append({
                "source_path": path,
                "signal": signal_name,
                "target_path": id_to_path.get(callable.get_object_id(), ""),
                "method": callable.get_method(),
                "flags": int(connection["flags"]),
                "binds": _jsonify_variant(callable.get_bound_arguments())
            })
    for child in node.get_children():
        if child is Node:
            _collect_nodes(child, path + "/" + child.name, id_to_path, nodes, connections)

func _snapshot_node(node: Node) -> Dictionary:
    var groups: Array = []
    for group_name in node.get_groups():
        groups.append(str(group_name))
    groups.sort()

    var metadata := {}
    for meta_key in node.get_meta_list():
        metadata[str(meta_key)] = _jsonify_variant(node.get_meta(meta_key))

    var snapshot := {
        "name": node.name,
        "type": node.get_class(),
        "groups": groups,
        "metadata": metadata,
        "unique_name_in_owner": node.is_unique_name_in_owner()
    }

    var script_resource = node.get_script()
    snapshot["script_path"] = script_resource.resource_path if script_resource else ""

    for property_name in ["text", "menu_title", "click_count", "screen_id"]:
        if _has_property(node, property_name):
            snapshot[property_name] = _jsonify_variant(node.get(property_name))

    if node is Control:
        var control := node as Control
        snapshot["position"] = _vector2_to_json(control.position)
        snapshot["size"] = _vector2_to_json(control.size)
        snapshot["custom_minimum_size"] = _vector2_to_json(control.custom_minimum_size)
        snapshot["size_flags_horizontal"] = control.size_flags_horizontal
        snapshot["size_flags_vertical"] = control.size_flags_vertical
        snapshot["size_flags_stretch_ratio"] = control.size_flags_stretch_ratio

        var theme_colors := {}
        for color_name in ["font_color"]:
            if control.has_theme_color_override(color_name):
                theme_colors[color_name] = _color_to_json(control.get_theme_color(color_name))
        snapshot["theme_colors"] = theme_colors

        var theme_constants := {}
        for constant_name in ["outline_size"]:
            if control.has_theme_constant_override(constant_name):
                theme_constants[constant_name] = control.get_theme_constant(constant_name)
        snapshot["theme_constants"] = theme_constants

        var theme_styleboxes := {}
        for stylebox_name in ["panel"]:
            if control.has_theme_stylebox_override(stylebox_name):
                var stylebox = control.get_theme_stylebox(stylebox_name)
                theme_styleboxes[stylebox_name] = stylebox.resource_path if stylebox else ""
        snapshot["theme_styleboxes"] = theme_styleboxes

    return snapshot

func _has_property(node: Object, property_name: String) -> bool:
    for property_info in node.get_property_list():
        if str(property_info.get("name", "")) == property_name:
            return true
    return false

func _vector2_to_json(value: Vector2) -> Dictionary:
    return {
        "x": value.x,
        "y": value.y
    }

func _color_to_json(color: Color) -> Dictionary:
    return {
        "r": color.r,
        "g": color.g,
        "b": color.b,
        "a": color.a
    }

func _jsonify_variant(value: Variant) -> Variant:
    match typeof(value):
        TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_NIL:
            return value
        TYPE_VECTOR2:
            return _vector2_to_json(value)
        TYPE_VECTOR2I:
            return {
                "x": value.x,
                "y": value.y
            }
        TYPE_COLOR:
            return _color_to_json(value)
        TYPE_ARRAY:
            var items: Array = []
            for item in value:
                items.append(_jsonify_variant(item))
            return items
        TYPE_DICTIONARY:
            var result := {}
            for key in value.keys():
                result[str(key)] = _jsonify_variant(value[key])
            return result
        _:
            return str(value)
