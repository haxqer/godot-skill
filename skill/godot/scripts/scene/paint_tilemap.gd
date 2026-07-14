class_name GodotSkillPaintTilemap
extends RefCounted

var scene_editor_script = preload("../core/scene_editor.gd")
var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    utils_script.log_info("Painting TileMapLayer in scene: " + str(params.get("scene_path", "")))

    var editor = scene_editor_script.new()
    var success = editor.open_existing_scene(params.get("scene_path", ""))
    if success:
        success = editor.paint_tilemap(params)
    if success:
        success = editor.save_scene(params.get("save_path", ""))
    if success:
        utils_script.log_info("TileMapLayer painted successfully")
        print(JSON.stringify({
            "ok": true,
            "scene_path": str(params.get("scene_path", "")),
            "node_path": str(params.get("node_path", "root"))
        }))
    editor.cleanup()
