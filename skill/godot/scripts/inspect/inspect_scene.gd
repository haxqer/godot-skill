class_name GodotSkillInspectScene
extends RefCounted

var utils_script = preload("../core/utils.gd")
var codec_script = preload("../core/variant_codec.gd")

func execute(params: Dictionary) -> void:
    var scene_path := _normalize_res_path(params.get("scene_path", ""))
    if scene_path.is_empty():
        utils_script.log_error("inspect_scene requires scene_path")
        return

    var packed_scene = load(scene_path)
    if not (packed_scene is PackedScene):
        utils_script.log_error("Failed to load PackedScene: " + scene_path)
        return

    var state := (packed_scene as PackedScene).get_state()
    var codec = codec_script.new()
    var max_depth: int = max(int(params.get("max_resource_depth", 2)), 0)
    var include_properties := bool(params.get("include_properties", true))
    var nodes: Array = []

    for node_index in range(state.get_node_count()):
        var node_info := {
            "index": node_index,
            "path": str(state.get_node_path(node_index)),
            "name": str(state.get_node_name(node_index)),
            "type": str(state.get_node_type(node_index)),
            "owner_path": str(state.get_node_owner_path(node_index)),
            "sibling_index": state.get_node_index(node_index),
            "groups": Array(state.get_node_groups(node_index)),
            "instance_placeholder": state.get_node_instance_placeholder(node_index)
        }
        var instance = state.get_node_instance(node_index)
        if instance:
            node_info["instance"] = codec.encode(instance, max_depth)
        if include_properties:
            var properties := {}
            for property_index in range(state.get_node_property_count(node_index)):
                var property_name := str(state.get_node_property_name(node_index, property_index))
                properties[property_name] = codec.encode(
                    state.get_node_property_value(node_index, property_index),
                    max_depth
                )
            node_info["properties"] = properties
        nodes.append(node_info)

    var connections: Array = []
    for connection_index in range(state.get_connection_count()):
        connections.append({
            "source": str(state.get_connection_source(connection_index)),
            "signal": str(state.get_connection_signal(connection_index)),
            "target": str(state.get_connection_target(connection_index)),
            "method": str(state.get_connection_method(connection_index)),
            "flags": state.get_connection_flags(connection_index),
            "unbinds": state.get_connection_unbinds(connection_index),
            "binds": codec.encode(state.get_connection_binds(connection_index), max_depth)
        })

    var base_state := state.get_base_scene_state()
    var uid := ResourceLoader.get_resource_uid(scene_path)
    print(JSON.stringify({
        "scene_path": scene_path,
        "uid": ResourceUID.id_to_text(uid) if uid != ResourceUID.INVALID_ID else "",
        "base_scene_path": base_state.get_path() if base_state else "",
        "node_count": nodes.size(),
        "connection_count": connections.size(),
        "dependencies": Array(ResourceLoader.get_dependencies(scene_path)),
        "nodes": nodes,
        "connections": connections
    }))

func _normalize_res_path(path_value: Variant) -> String:
    var path := str(path_value).strip_edges().replace("\\", "/")
    if path.is_empty():
        return ""
    if path.begins_with("res://"):
        return path
    return "res://" + path.trim_prefix("/")
