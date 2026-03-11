class_name GodotSkillSceneBatch
extends RefCounted

var scene_editor_script = preload("../core/scene_editor.gd")
var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    utils_script.log_info("Running scene_batch on: " + str(params.get("scene_path", "")))

    var editor = scene_editor_script.new()
    var success = editor.open_or_create_scene(params)
    if success:
        success = editor.run_batch(params)
    if success:
        success = editor.save_scene(params.get("save_path", ""))
    if success:
        var target_path = params.get("save_path", params.get("scene_path", ""))
        utils_script.log_info("scene_batch saved successfully to: " + str(target_path))
    editor.cleanup()
