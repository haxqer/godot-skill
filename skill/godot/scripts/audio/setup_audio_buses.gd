class_name GodotSkillSetupAudioBuses
extends RefCounted

# Authors the project's AudioBusLayout (default_bus_layout.tres). AudioServer
# is a singleton, not a Resource, so bus routing cannot be expressed through
# resource_batch: this op mutates the live server, snapshots it with
# generate_bus_layout(), saves the .tres, and optionally points
# audio/buses/default_bus_layout at it. Works headlessly — bus configuration
# is server state and does not depend on the Dummy audio driver.

var utils_script = preload("../core/utils.gd")
var codec_script = preload("../core/variant_codec.gd")

func execute(params: Dictionary) -> void:
    var buses = params.get("buses", [])
    if not (buses is Array) or buses.is_empty():
        utils_script.log_error("setup_audio_buses requires a non-empty buses array")
        return

    var codec = codec_script.new()
    for raw_bus in buses:
        if not (raw_bus is Dictionary):
            utils_script.log_error("buses entries must be dictionaries")
            return
        if not _apply_bus(raw_bus as Dictionary, codec):
            return

    var layout := AudioServer.generate_bus_layout()
    if layout == null:
        utils_script.log_error("AudioServer.generate_bus_layout returned null")
        return

    var save_path := _normalize_res_path(params.get("save_path", "default_bus_layout.tres"))
    if not _ensure_parent_directory(save_path):
        return
    var save_error := ResourceSaver.save(layout, save_path)
    if save_error != OK:
        utils_script.log_error("Failed to save AudioBusLayout %s: %s" % [save_path, error_string(save_error)])
        return

    var registered := false
    if bool(params.get("set_project_setting", true)):
        ProjectSettings.set_setting("audio/buses/default_bus_layout", save_path)
        var settings_error := ProjectSettings.save()
        if settings_error != OK:
            utils_script.log_error("Failed to save project settings: " + error_string(settings_error))
            return
        registered = true

    var bus_names: Array[String] = []
    for index in range(AudioServer.bus_count):
        bus_names.append(AudioServer.get_bus_name(index))
    print(JSON.stringify({
        "ok": true,
        "save_path": save_path,
        "bus_count": AudioServer.bus_count,
        "buses": bus_names,
        "project_setting_updated": registered
    }))

func _apply_bus(bus: Dictionary, codec: RefCounted) -> bool:
    var bus_name := str(bus.get("name", "")).strip_edges()
    if bus_name.is_empty():
        utils_script.log_error("buses entries require name")
        return false

    var index := AudioServer.get_bus_index(bus_name)
    if index < 0:
        AudioServer.add_bus()
        index = AudioServer.bus_count - 1
        AudioServer.set_bus_name(index, bus_name)

    if bus.has("volume_db"):
        AudioServer.set_bus_volume_db(index, float(bus.get("volume_db", 0.0)))
    if bus.has("solo"):
        AudioServer.set_bus_solo(index, bool(bus.get("solo")))
    if bus.has("mute"):
        AudioServer.set_bus_mute(index, bool(bus.get("mute")))
    if bus.has("bypass_effects"):
        AudioServer.set_bus_bypass_effects(index, bool(bus.get("bypass_effects")))
    if bus.has("send"):
        var send_name := str(bus.get("send", "Master"))
        if index == 0:
            utils_script.log_error("The Master bus cannot have a send")
            return false
        if AudioServer.get_bus_index(send_name) < 0:
            utils_script.log_error("Send target bus does not exist yet (order buses before their senders): " + send_name)
            return false
        AudioServer.set_bus_send(index, StringName(send_name))

    if bus.has("effects"):
        var effects = bus.get("effects")
        if not (effects is Array):
            utils_script.log_error("buses effects must be an array")
            return false
        while AudioServer.get_bus_effect_count(index) > 0:
            AudioServer.remove_bus_effect(index, AudioServer.get_bus_effect_count(index) - 1)
        for raw_effect in effects:
            if not (raw_effect is Dictionary):
                utils_script.log_error("effects entries must be dictionaries")
                return false
            var effect_params = raw_effect as Dictionary
            var effect_type := str(effect_params.get("type", ""))
            var candidate = utils_script.instantiate_class(effect_type)
            if not (candidate is AudioEffect):
                utils_script.log_error("Not an AudioEffect type: " + effect_type)
                if candidate != null and candidate is Node:
                    candidate.free()
                return false
            var effect := candidate as AudioEffect
            if effect_params.has("properties") and not codec.apply_properties(effect, effect_params.get("properties"), "effects.properties"):
                return false
            AudioServer.add_bus_effect(index, effect)
            var effect_index := AudioServer.get_bus_effect_count(index) - 1
            AudioServer.set_bus_effect_enabled(index, effect_index, bool(effect_params.get("enabled", true)))
    return true

func _ensure_parent_directory(path: String) -> bool:
    var base_dir := path.get_base_dir()
    if base_dir == "res://":
        return true
    var absolute_parent := ProjectSettings.globalize_path(base_dir)
    var error := DirAccess.make_dir_recursive_absolute(absolute_parent)
    if error != OK and error != ERR_ALREADY_EXISTS:
        utils_script.log_error("Failed to create directory: " + absolute_parent)
        return false
    return true

func _normalize_res_path(path_value: Variant) -> String:
    var path := str(path_value).strip_edges().replace("\\", "/")
    if path.is_empty():
        return ""
    if path.begins_with("res://"):
        return path
    return "res://" + path.trim_prefix("/")
