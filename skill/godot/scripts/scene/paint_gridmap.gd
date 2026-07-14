class_name GodotSkillPaintGridmap
extends RefCounted

# Paints cells into a GridMap node headlessly (the 3D parallel to paint_tilemap).
# GridMap cells are populated only through set_cell_item(), so there is no bulk
# property that configure_node could set.

var scene_editor_script = preload("../core/scene_editor.gd")
var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    utils_script.log_info("Painting GridMap in scene: " + str(params.get("scene_path", "")))

    var editor = scene_editor_script.new()
    var success = editor.open_existing_scene(params.get("scene_path", ""))
    if success:
        success = editor.paint_gridmap(params)
    if success:
        success = editor.save_scene(params.get("save_path", ""))
    if success:
        utils_script.log_info("GridMap painted successfully")
        print(JSON.stringify({
            "ok": true,
            "scene_path": str(params.get("scene_path", "")),
            "node_path": str(params.get("node_path", "root"))
        }))
    editor.cleanup()
