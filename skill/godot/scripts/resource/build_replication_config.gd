class_name GodotSkillBuildReplicationConfig
extends RefCounted

# Authors a SceneReplicationConfig .tres for a MultiplayerSynchronizer. This is
# expressible via resource_batch call_method, but the call ordering (add_property
# before property_set_*) and the deprecated property_set_sync/_watch trap make a
# labeled wrapper safer. Property paths are relative to the synchronizer's
# root_path (default the synchronizer's parent).

var utils_script = preload("../core/utils.gd")

const REPLICATION_MODES = {
    "never": 0,
    "always": 1,
    "on_change": 2
}

func execute(params: Dictionary) -> void:
    var target_path := _normalize_res_path(params.get("resource_path", ""))
    if target_path.is_empty():
        utils_script.log_error("build_replication_config requires resource_path")
        return

    var config := _open_config(params, target_path)
    if config == null:
        return

    var properties = params.get("properties", [])
    if not (properties is Array) or properties.is_empty():
        utils_script.log_error("build_replication_config requires a non-empty properties array")
        return

    for raw_property in properties:
        if not (raw_property is Dictionary):
            utils_script.log_error("build_replication_config.properties entries must be dictionaries")
            return
        var property := raw_property as Dictionary
        var path := str(property.get("path", ""))
        if path.is_empty():
            utils_script.log_error("build_replication_config.properties entries require path")
            return
        var node_path := NodePath(path)
        if not config.has_property(node_path):
            config.add_property(node_path)
        if property.has("spawn"):
            config.property_set_spawn(node_path, bool(property.get("spawn")))
        if property.has("replication_mode"):
            var mode := _resolve_mode(property.get("replication_mode"))
            if mode < 0:
                return
            config.property_set_replication_mode(node_path, mode)

    if not _ensure_parent_directory(target_path):
        return
    var save_error := ResourceSaver.save(config, target_path)
    if save_error != OK:
        utils_script.log_error("Failed to save SceneReplicationConfig %s: %s" % [target_path, error_string(save_error)])
        return

    print(JSON.stringify({
        "ok": true,
        "resource_path": target_path,
        "property_count": config.get_properties().size()
    }))

func _open_config(params: Dictionary, target_path: String) -> SceneReplicationConfig:
    if FileAccess.file_exists(target_path):
        var existing = ResourceLoader.load(target_path, "", ResourceLoader.CACHE_MODE_IGNORE)
        if not (existing is SceneReplicationConfig):
            utils_script.log_error("Existing resource is not a SceneReplicationConfig: " + target_path)
            return null
        return existing
    if not bool(params.get("create_if_missing", true)):
        utils_script.log_error("SceneReplicationConfig does not exist: " + target_path)
        return null
    return SceneReplicationConfig.new()

func _resolve_mode(raw_mode: Variant) -> int:
    if raw_mode is int or raw_mode is float:
        return int(raw_mode)
    var key := str(raw_mode).to_lower()
    if REPLICATION_MODES.has(key):
        return REPLICATION_MODES[key]
    utils_script.log_error("replication_mode must be never, always, on_change, or an int: " + str(raw_mode))
    return -1

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
