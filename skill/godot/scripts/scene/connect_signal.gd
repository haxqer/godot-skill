class_name GodotSkillConnectSignal
extends RefCounted

var scene_editor_script = preload("../core/scene_editor.gd")
var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    utils_script.log_info("Connecting signal in scene: " + str(params.get("scene_path", "")))

    var editor = scene_editor_script.new()
    var success = editor.open_existing_scene(params.get("scene_path", ""))
    if success:
        success = editor.connect_signal(params)
    if success:
        success = editor.save_scene()
    if success:
        utils_script.log_info("Signal connected successfully")
    editor.cleanup()
