class_name GodotSkillResourceBatch
extends RefCounted

var utils_script = preload("../core/utils.gd")
var codec_script = preload("../core/variant_codec.gd")

func execute(params: Dictionary) -> void:
    var target_path := _normalize_res_path(params.get("resource_path", params.get("save_path", "")))
    if target_path.is_empty():
        utils_script.log_error("resource_batch requires resource_path or save_path")
        return

    var resource := _open_resource(params, target_path)
    if resource == null:
        return

    var actions = params.get("actions", [])
    if not (actions is Array):
        utils_script.log_error("resource_batch actions must be an array")
        return

    var codec = codec_script.new()
    for index in range(actions.size()):
        var raw_action = actions[index]
        if not (raw_action is Dictionary):
            utils_script.log_error("resource_batch action %d must be a dictionary" % index)
            return
        if not _apply_action(resource, raw_action, codec):
            utils_script.log_error("resource_batch aborted at action %d" % index)
            return

    if not _ensure_parent_directory(target_path):
        return
    var save_error := ResourceSaver.save(resource, target_path)
    if save_error != OK:
        utils_script.log_error("Failed to save resource %s: %s" % [target_path, error_string(save_error)])
        return

    print(JSON.stringify({
        "ok": true,
        "resource_path": target_path,
        "resource_type": resource.get_class(),
        "actions_applied": actions.size()
    }))

func _open_resource(params: Dictionary, target_path: String) -> Resource:
    var duplicate_from := _normalize_res_path(params.get("duplicate_from", ""))
    if not duplicate_from.is_empty():
        var source = ResourceLoader.load(duplicate_from, "", ResourceLoader.CACHE_MODE_IGNORE)
        if not (source is Resource):
            utils_script.log_error("Failed to load duplicate_from resource: " + duplicate_from)
            return null
        return (source as Resource).duplicate(bool(params.get("duplicate_subresources", true)))

    if FileAccess.file_exists(target_path):
        var existing = ResourceLoader.load(target_path, "", ResourceLoader.CACHE_MODE_IGNORE)
        if not (existing is Resource):
            utils_script.log_error("Failed to load resource: " + target_path)
            return null
        return existing

    if not bool(params.get("create_if_missing", false)):
        utils_script.log_error("Resource does not exist: " + target_path)
        return null

    var resource_type := str(params.get("resource_type", "Resource"))
    var candidate = utils_script.instantiate_class(resource_type)
    if not (candidate is Resource):
        utils_script.log_error("Resource type cannot be instantiated: " + resource_type)
        return null
    return candidate

func _apply_action(resource: Resource, action: Dictionary, codec: RefCounted) -> bool:
    var action_type := str(action.get("type", ""))
    match action_type:
        "set_properties":
            return codec.apply_properties(resource, action.get("properties", {}), "set_properties.properties")
        "set_indexed_properties":
            return codec.apply_properties(resource, action.get("properties", {}), "set_indexed_properties.properties", true)
        "set_metadata":
            var metadata = action.get("metadata", {})
            if not (metadata is Dictionary):
                utils_script.log_error("set_metadata.metadata must be a dictionary")
                return false
            for key in metadata.keys():
                var raw_value = metadata[key]
                var value = codec.decode(raw_value, "set_metadata.%s" % str(key))
                if value == null and raw_value != null:
                    return false
                resource.set_meta(StringName(str(key)), value)
            return true
        "remove_metadata":
            var names = action.get("names", [])
            if not (names is Array):
                utils_script.log_error("remove_metadata.names must be an array")
                return false
            for name in names:
                resource.remove_meta(StringName(str(name)))
            return true
        "set_resource_name":
            resource.resource_name = str(action.get("resource_name", ""))
            return true
        "call_method":
            return _call_method(resource, action, codec)
        _:
            utils_script.log_error("Unsupported resource_batch action: " + action_type)
            return false

func _call_method(resource: Resource, action: Dictionary, codec: RefCounted) -> bool:
    var method_name := str(action.get("method", ""))
    if method_name.is_empty():
        utils_script.log_error("call_method requires method")
        return false
    if not resource.has_method(method_name):
        utils_script.log_error("Resource %s does not have method: %s" % [resource.get_class(), method_name])
        return false

    var raw_args = action.get("args", [])
    if not (raw_args is Array):
        utils_script.log_error("call_method.args must be an array")
        return false
    var args = codec.decode(raw_args, "call_method.args")
    if not (args is Array):
        return false

    var result = resource.callv(method_name, args)
    if bool(action.get("expect_ok", false)) and (not (result is int) or result != OK):
        utils_script.log_error("call_method %s expected OK but returned: %s" % [method_name, str(result)])
        return false
    return true

func _ensure_parent_directory(path: String) -> bool:
    var absolute_parent := ProjectSettings.globalize_path(path.get_base_dir())
    var error := DirAccess.make_dir_recursive_absolute(absolute_parent)
    if error != OK and error != ERR_ALREADY_EXISTS:
        utils_script.log_error("Failed to create resource directory: " + absolute_parent)
        return false
    return true

func _normalize_res_path(path_value: Variant) -> String:
    var path := str(path_value).strip_edges().replace("\\", "/")
    if path.is_empty():
        return ""
    if path.begins_with("res://"):
        return path
    return "res://" + path.trim_prefix("/")
