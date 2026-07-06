class_name GodotSkillBuildSpriteFrames
extends RefCounted

var scene_editor_script = preload("../core/scene_editor.gd")
var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    utils_script.log_info("Building sprite frames for scene: " + str(params.get("scene_path", "")))

    var editor = scene_editor_script.new()
    var success = editor.open_existing_scene(params.get("scene_path", ""))
    if success:
        success = editor.build_sprite_frames(params)
    if success:
        success = editor.save_scene()
    if success:
        utils_script.log_info(
            "SpriteFrames animation '%s' built successfully on node '%s'" % [
                str(params.get("animation_name", "")),
                str(params.get("node_path", "root")),
            ]
        )
    editor.cleanup()
