class_name GodotSkillCollisionFromSprite
extends RefCounted

# Traces a sprite's alpha silhouette into CollisionPolygon2D children using
# BitMap.opaque_to_polygons (marching squares). resource_batch cannot capture the
# returned polygon arrays and route them into scene nodes, so this needs a
# dedicated op.

var scene_editor_script = preload("../core/scene_editor.gd")
var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    utils_script.log_info("Tracing sprite collision in scene: " + str(params.get("scene_path", "")))

    var editor = scene_editor_script.new()
    var success = editor.open_existing_scene(params.get("scene_path", ""))
    if success:
        success = editor.collision_from_sprite(params)
    if success:
        success = editor.save_scene(params.get("save_path", ""))
    if success:
        utils_script.log_info("Sprite collision generated successfully")
        print(JSON.stringify({
            "ok": true,
            "scene_path": str(params.get("scene_path", "")),
            "node_path": str(params.get("node_path", "root"))
        }))
    editor.cleanup()
