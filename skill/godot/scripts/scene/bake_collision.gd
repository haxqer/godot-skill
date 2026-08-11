class_name GodotSkillBakeCollision
extends RefCounted

# Generates collision bodies from a MeshInstance3D via the engine's
# create_trimesh/convex/multiple_convex_collision helpers. These are node methods
# that add StaticBody3D + CollisionShape3D children, so add_node/configure_node
# cannot express them; the op also fixes child ownership so the new subtree
# serializes into the scene.

var scene_editor_script = preload("../core/scene_editor.gd")
var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    utils_script.log_info("Baking collision in scene: " + str(params.get("scene_path", "")))

    var editor = scene_editor_script.new()
    var success = editor.open_existing_scene(params.get("scene_path", ""))
    if success:
        success = editor.bake_collision(params)
    if success:
        success = editor.save_scene(params.get("save_path", ""))
    if success:
        utils_script.log_info("Collision baked successfully")
        print(JSON.stringify({
            "ok": true,
            "scene_path": str(params.get("scene_path", "")),
            "node_path": str(params.get("node_path", "root")),
            "mode": str(params.get("mode", "trimesh"))
        }))
    editor.cleanup()
