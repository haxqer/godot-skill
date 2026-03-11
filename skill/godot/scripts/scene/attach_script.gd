class_name GodotSkillAttachScript
extends RefCounted

var scene_editor_script = preload("../core/scene_editor.gd")
var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    utils_script.log_info("Attaching script in scene: " + str(params.get("scene_path", "")))

    var editor = scene_editor_script.new()
    var success = editor.open_existing_scene(params.get("scene_path", ""))
    if success:
        success = editor.attach_script(params)
    if success:
        success = editor.save_scene()
    if success:
        utils_script.log_info("Script attached successfully")
    editor.cleanup()
