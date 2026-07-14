class_name GodotSkillProjectBatch
extends RefCounted

var utils_script = preload("../core/utils.gd")
var codec_script = preload("../core/variant_codec.gd")

const LAYER_TYPES = {
    "2d_physics": "2d_physics",
    "3d_physics": "3d_physics",
    "2d_render": "2d_render",
    "3d_render": "3d_render",
    "2d_navigation": "2d_navigation",
    "3d_navigation": "3d_navigation"
}

func execute(params: Dictionary) -> void:
    var actions = params.get("actions", [])
    if not (actions is Array) or actions.is_empty():
        utils_script.log_error("project_batch requires a non-empty actions array")
        return

    var codec = codec_script.new()
    for index in range(actions.size()):
        var raw_action = actions[index]
        if not (raw_action is Dictionary):
            utils_script.log_error("project_batch action %d must be a dictionary" % index)
            return
        if not _apply_action(raw_action, codec):
            utils_script.log_error("project_batch aborted at action %d" % index)
            return

    # ProjectSettings.save() rewrites project.godot wholesale: comments are
    # dropped and keys re-sorted. Offer an opt-in pre-save backup for
    # non-version-controlled projects.
    var backup_path := ""
    if params.has("backup_path"):
        backup_path = str(params.get("backup_path"))
        var source := FileAccess.get_file_as_string("res://project.godot")
        var backup := FileAccess.open(backup_path if backup_path.begins_with("res://") else "res://" + backup_path, FileAccess.WRITE)
        if backup == null:
            utils_script.log_error("Failed to write project.godot backup: " + backup_path)
            return
        backup.store_string(source)
        backup.close()

    var save_error := ProjectSettings.save()
    if save_error != OK:
        utils_script.log_error("Failed to save project settings: " + error_string(save_error))
        return
    print(JSON.stringify({
        "ok": true,
        "actions_applied": actions.size(),
        "project_file": "res://project.godot",
        "file_rewritten": true,
        "backup_path": backup_path
    }))

func _apply_action(action: Dictionary, codec: RefCounted) -> bool:
    var action_type := str(action.get("type", ""))
    match action_type:
        "set_setting":
            var setting_name := str(action.get("name", ""))
            if setting_name.is_empty() or not action.has("value"):
                utils_script.log_error("set_setting requires name and value")
                return false
            var raw_value = action.get("value")
            var value = codec.decode(raw_value, "set_setting.value")
            if value == null and raw_value != null:
                return false
            ProjectSettings.set_setting(setting_name, value)
            return true
        "clear_setting":
            var setting_name := str(action.get("name", ""))
            if setting_name.is_empty():
                utils_script.log_error("clear_setting requires name")
                return false
            if ProjectSettings.has_setting(setting_name):
                ProjectSettings.clear(setting_name)
            return true
        "add_input_action":
            return _add_input_action(action)
        "remove_input_action":
            return _remove_input_action(action)
        "add_input_event":
            return _add_input_event(action, codec)
        "remove_input_event":
            return _remove_input_event(action)
        "add_autoload":
            return _add_autoload(action)
        "remove_autoload":
            return _remove_autoload(action)
        "set_layer_name":
            return _set_layer_name(action)
        "set_main_scene":
            return _set_main_scene(action)
        "add_translation":
            return _change_translation(action, true)
        "remove_translation":
            return _change_translation(action, false)
        "set_shader_global":
            return _set_shader_global(action, codec)
        "clear_shader_global":
            return _clear_shader_global(action)
        _:
            utils_script.log_error("Unsupported project_batch action: " + action_type)
            return false

func _set_shader_global(action: Dictionary, codec: RefCounted) -> bool:
    var global_name := str(action.get("name", ""))
    var global_type := str(action.get("global_type", ""))
    if global_name.is_empty() or global_type.is_empty():
        utils_script.log_error("set_shader_global requires name and global_type (e.g. color, vec3, float)")
        return false
    if not action.has("value"):
        utils_script.log_error("set_shader_global requires value")
        return false
    var value = codec.decode(action.get("value"), "set_shader_global.value")
    if value == null and action.get("value") != null:
        return false
    # Global shader parameters persist as a {type, value} dictionary under the
    # [shader_globals] section of project.godot.
    ProjectSettings.set_setting("shader_globals/" + global_name, {"type": global_type, "value": value})
    return true

func _clear_shader_global(action: Dictionary) -> bool:
    var global_name := str(action.get("name", ""))
    if global_name.is_empty():
        utils_script.log_error("clear_shader_global requires name")
        return false
    if ProjectSettings.has_setting("shader_globals/" + global_name):
        ProjectSettings.clear("shader_globals/" + global_name)
    return true

func _add_input_action(action: Dictionary) -> bool:
    var action_name := str(action.get("action_name", ""))
    if action_name.is_empty():
        utils_script.log_error("add_input_action requires action_name")
        return false
    var setting_key := "input/" + action_name
    if ProjectSettings.has_setting(setting_key) and not bool(action.get("replace", false)):
        utils_script.log_error("Input action already exists: " + action_name)
        return false
    ProjectSettings.set_setting(setting_key, {
        "deadzone": float(action.get("deadzone", 0.5)),
        "events": []
    })
    return true

func _remove_input_action(action: Dictionary) -> bool:
    var action_name := str(action.get("action_name", ""))
    if action_name.is_empty():
        utils_script.log_error("remove_input_action requires action_name")
        return false
    if ProjectSettings.has_setting("input/" + action_name):
        ProjectSettings.clear("input/" + action_name)
    return true

func _add_input_event(action: Dictionary, codec: RefCounted) -> bool:
    var action_name := str(action.get("action_name", ""))
    var setting_key := "input/" + action_name
    if action_name.is_empty() or not ProjectSettings.has_setting(setting_key):
        utils_script.log_error("add_input_event requires an existing action_name")
        return false
    if not action.has("event"):
        utils_script.log_error("add_input_event requires event")
        return false
    var event = codec.decode(action.get("event"), "add_input_event.event")
    if not (event is InputEvent):
        utils_script.log_error("add_input_event.event must decode to InputEvent")
        return false
    var data: Dictionary = ProjectSettings.get_setting(setting_key).duplicate(true)
    var events: Array = Array(data.get("events", [])).duplicate()
    events.append(event)
    data["events"] = events
    ProjectSettings.set_setting(setting_key, data)
    return true

func _remove_input_event(action: Dictionary) -> bool:
    var action_name := str(action.get("action_name", ""))
    var setting_key := "input/" + action_name
    if action_name.is_empty() or not ProjectSettings.has_setting(setting_key):
        utils_script.log_error("remove_input_event requires an existing action_name")
        return false
    var data: Dictionary = ProjectSettings.get_setting(setting_key).duplicate(true)
    var events: Array = Array(data.get("events", [])).duplicate()
    var event_index := int(action.get("event_index", -1))
    if event_index < 0 or event_index >= events.size():
        utils_script.log_error("remove_input_event event_index is out of range")
        return false
    events.remove_at(event_index)
    data["events"] = events
    ProjectSettings.set_setting(setting_key, data)
    return true

func _add_autoload(action: Dictionary) -> bool:
    var autoload_name := str(action.get("autoload_name", ""))
    var path := _normalize_res_path(action.get("path", ""))
    if autoload_name.is_empty() or path.is_empty():
        utils_script.log_error("add_autoload requires autoload_name and path")
        return false
    if not FileAccess.file_exists(path):
        utils_script.log_error("Autoload path does not exist: " + path)
        return false
    var value := ("*" if bool(action.get("singleton", true)) else "") + path
    ProjectSettings.set_setting("autoload/" + autoload_name, value)
    return true

func _remove_autoload(action: Dictionary) -> bool:
    var autoload_name := str(action.get("autoload_name", ""))
    if autoload_name.is_empty():
        utils_script.log_error("remove_autoload requires autoload_name")
        return false
    if ProjectSettings.has_setting("autoload/" + autoload_name):
        ProjectSettings.clear("autoload/" + autoload_name)
    return true

func _set_layer_name(action: Dictionary) -> bool:
    var layer_type := str(action.get("layer_type", ""))
    var layer := int(action.get("layer", 0))
    if not LAYER_TYPES.has(layer_type) or layer < 1 or layer > 32:
        utils_script.log_error("set_layer_name requires a supported layer_type and layer from 1 to 32")
        return false
    var key := "layer_names/%s/layer_%d" % [LAYER_TYPES[layer_type], layer]
    var layer_name := str(action.get("layer_name", ""))
    if layer_name.is_empty():
        if ProjectSettings.has_setting(key):
            ProjectSettings.clear(key)
    else:
        ProjectSettings.set_setting(key, layer_name)
    return true

func _set_main_scene(action: Dictionary) -> bool:
    var path := _normalize_res_path(action.get("scene_path", ""))
    if path.is_empty() or not FileAccess.file_exists(path):
        utils_script.log_error("set_main_scene requires an existing scene_path")
        return false
    ProjectSettings.set_setting("application/run/main_scene", path)
    return true

func _change_translation(action: Dictionary, add: bool) -> bool:
    var path := _normalize_res_path(action.get("path", ""))
    if path.is_empty():
        utils_script.log_error("Translation action requires path")
        return false
    var key := "internationalization/locale/translations"
    var values := PackedStringArray(ProjectSettings.get_setting(key, PackedStringArray()))
    if add and path not in values:
        values.append(path)
    elif not add:
        var index := values.find(path)
        if index >= 0:
            values.remove_at(index)
    ProjectSettings.set_setting(key, values)
    return true

func _normalize_res_path(path_value: Variant) -> String:
    var path := str(path_value).strip_edges().replace("\\", "/")
    if path.is_empty():
        return ""
    if path.begins_with("res://"):
        return path
    return "res://" + path.trim_prefix("/")
