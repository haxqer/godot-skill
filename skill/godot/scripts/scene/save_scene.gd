class_name GodotSkillSaveScene
extends RefCounted

var scene_editor_script = preload("../core/scene_editor.gd")
var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    utils_script.log_info("Saving scene: " + str(params.get("scene_path", "")))

    var editor = scene_editor_script.new()
    var target_override = ""
    if params.has("save_path"):
        target_override = str(params.get("save_path", ""))
    elif params.has("new_path"):
        target_override = str(params.get("new_path", ""))

    var success = editor.open_existing_scene(params.get("scene_path", ""))
    if success:
        success = editor.save_scene(target_override)
    if success:
        var target_path = target_override if not target_override.is_empty() else str(params.get("scene_path", ""))
        utils_script.log_info("Scene saved successfully to: " + str(target_path))
    editor.cleanup()
