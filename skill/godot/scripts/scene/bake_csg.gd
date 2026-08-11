class_name GodotSkillBakeCsg
extends RefCounted

# Bakes a CSGShape3D tree into a static ArrayMesh (+ optional collision) via
# CSGShape3D.bake_static_mesh / bake_collision_shape. CSG geometry updates are
# deferred one frame, so this op runs inside the dispatcher's live SceneTree and
# awaits a couple of frames before baking — orchestration the generic ops cannot
# express. execute() is a coroutine; the dispatcher awaits it.

var scene_editor_script = preload("../core/scene_editor.gd")
var utils_script = preload("../core/utils.gd")

# execute() is a coroutine (it awaits frames while the CSG geometry updates). The
# dispatcher runs every op through a deferred `await`, so this is handled uniformly.
func execute(params: Dictionary) -> void:
    utils_script.log_info("Baking CSG in scene: " + str(params.get("scene_path", "")))

    var editor = scene_editor_script.new()
    var success = editor.open_existing_scene(params.get("scene_path", ""))
    if success:
        success = await editor.bake_csg(params)
    if success:
        # Only rewrite the scene when the CSG tree was replaced in place.
        if bool(params.get("replace_with_meshinstance", false)):
            success = editor.save_scene(params.get("save_path", ""))
    if success:
        utils_script.log_info("CSG baked successfully")
        print(JSON.stringify({
            "ok": true,
            "scene_path": str(params.get("scene_path", "")),
            "node_path": str(params.get("node_path", "root")),
            "out_mesh": str(params.get("out_mesh", "")),
            "replaced": bool(params.get("replace_with_meshinstance", false))
        }))
    editor.cleanup()
