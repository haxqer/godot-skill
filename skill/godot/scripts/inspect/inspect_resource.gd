class_name GodotSkillInspectResource
extends RefCounted

var utils_script = preload("../core/utils.gd")
var codec_script = preload("../core/variant_codec.gd")

func execute(params: Dictionary) -> void:
    var resource_path := _normalize_res_path(params.get("resource_path", ""))
    if resource_path.is_empty():
        utils_script.log_error("inspect_resource requires resource_path")
        return

    var resource = load(resource_path)
    if not (resource is Resource):
        utils_script.log_error("Failed to load resource: " + resource_path)
        return

    var codec = codec_script.new()
    var max_depth: int = max(int(params.get("max_resource_depth", 2)), 0)
    var include_non_storage := bool(params.get("include_non_storage", false))
    var include_schema := bool(params.get("include_schema", false))
    var properties := {}
    var property_schema: Array = []

    for property_info in resource.get_property_list():
        var property_name := str(property_info.get("name", ""))
        var usage := int(property_info.get("usage", 0))
        if property_name.is_empty():
            continue
        if include_schema:
            property_schema.append(codec.encode(property_info, 1))
        if include_non_storage or usage & PROPERTY_USAGE_STORAGE != 0:
            properties[property_name] = codec.encode(resource.get(property_name), max_depth)

    var result := {
        "resource_path": resource_path,
        "resource_type": resource.get_class(),
        "resource_name": resource.resource_name,
        "local_to_scene": resource.resource_local_to_scene,
        "dependencies": Array(ResourceLoader.get_dependencies(resource_path)),
        "properties": properties,
        "property_schema": property_schema
    }
    var uid := ResourceLoader.get_resource_uid(resource_path)
    result["uid"] = ResourceUID.id_to_text(uid) if uid != ResourceUID.INVALID_ID else ""

    if resource is Script:
        var script := resource as Script
        result["script"] = {
            "global_name": str(script.get_global_name()),
            "instance_base_type": str(script.get_instance_base_type()),
            "can_instantiate": script.can_instantiate(),
            "methods": codec.encode(script.get_script_method_list(), 2),
            "signals": codec.encode(script.get_script_signal_list(), 2),
            "properties": codec.encode(script.get_script_property_list(), 2)
        }

    print(JSON.stringify(result))

func _normalize_res_path(path_value: Variant) -> String:
    var path := str(path_value).strip_edges().replace("\\", "/")
    if path.is_empty():
        return ""
    if path.begins_with("res://"):
        return path
    return "res://" + path.trim_prefix("/")
