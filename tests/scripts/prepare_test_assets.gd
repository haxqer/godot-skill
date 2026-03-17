extends SceneTree

func _init() -> void:
    var args = OS.get_cmdline_args()
    var script_index = args.find("--script")
    if script_index == -1 or args.size() <= script_index + 2:
        printerr("[ERROR] Usage: godot --headless --path <project> --script prepare_test_assets.gd <json_params>")
        quit(1)
        return

    var params_json = args[script_index + 2]
    var json = JSON.new()
    if json.parse(params_json) != OK:
        printerr("[ERROR] Failed to parse JSON params")
        quit(1)
        return

    var params = json.get_data()
    var action = str(params.get("action", ""))
    var success = false

    match action:
        "create_sprite_fixture":
            success = _create_sprite_fixture(
                str(params.get("scene_path", "")),
                str(params.get("texture_path", ""))
            )
        "create_mesh_fixture":
            success = _create_mesh_fixture(str(params.get("scene_path", "")))
        _:
            printerr("[ERROR] Unknown action: " + action)
            quit(1)
            return

    if not success:
        quit(1)
        return

    print(JSON.stringify({
        "action": action,
        "ok": true
    }))
    quit()

func _create_sprite_fixture(scene_path: String, texture_path: String) -> bool:
    var full_scene_path = _normalize_res_path(scene_path)
    var full_texture_path = _normalize_res_path(texture_path)
    if full_scene_path.is_empty() or full_texture_path.is_empty():
        printerr("[ERROR] scene_path and texture_path are required")
        return false

    if not _ensure_directory_for_path(full_scene_path) or not _ensure_directory_for_path(full_texture_path):
        return false

    var gradient := Gradient.new()
    gradient.colors = PackedColorArray([Color(0.95, 0.2, 0.1), Color(0.1, 0.35, 0.9)])
    var texture := GradientTexture2D.new()
    texture.gradient = gradient
    texture.width = 16
    texture.height = 16

    var texture_error = ResourceSaver.save(texture, full_texture_path)
    if texture_error != OK:
        printerr("[ERROR] Failed to save texture fixture: " + str(texture_error))
        return false

    var root := Sprite2D.new()
    root.name = "SpriteRoot"

    var packed_scene := PackedScene.new()
    var pack_error = packed_scene.pack(root)
    if pack_error != OK:
        root.free()
        printerr("[ERROR] Failed to pack sprite fixture: " + str(pack_error))
        return false

    var save_error = ResourceSaver.save(packed_scene, full_scene_path)
    root.free()
    if save_error != OK:
        printerr("[ERROR] Failed to save sprite fixture: " + str(save_error))
        return false
    return true

func _create_mesh_fixture(scene_path: String) -> bool:
    var full_scene_path = _normalize_res_path(scene_path)
    if full_scene_path.is_empty():
        printerr("[ERROR] scene_path is required")
        return false

    if not _ensure_directory_for_path(full_scene_path):
        return false

    var root := Node3D.new()
    root.name = "MeshSource"

    var crate := MeshInstance3D.new()
    crate.name = "Crate"
    crate.mesh = BoxMesh.new()
    root.add_child(crate)
    crate.owner = root

    var collision := CollisionShape3D.new()
    collision.name = "Collision"
    collision.shape = BoxShape3D.new()
    crate.add_child(collision)
    collision.owner = root

    var packed_scene := PackedScene.new()
    var pack_error = packed_scene.pack(root)
    if pack_error != OK:
        root.free()
        printerr("[ERROR] Failed to pack mesh fixture: " + str(pack_error))
        return false

    var save_error = ResourceSaver.save(packed_scene, full_scene_path)
    root.free()
    if save_error != OK:
        printerr("[ERROR] Failed to save mesh fixture: " + str(save_error))
        return false
    return true

func _normalize_res_path(path_value: String) -> String:
    var path = path_value.strip_edges()
    if path.is_empty():
        return ""
    if path.begins_with("res://"):
        return path
    if path.begins_with("/"):
        path = path.substr(1)
    return "res://" + path

func _ensure_directory_for_path(target_path: String) -> bool:
    var target_directory = target_path.get_base_dir()
    if target_directory == "res://":
        return true

    var absolute_directory = ProjectSettings.globalize_path(target_directory)
    if DirAccess.dir_exists_absolute(absolute_directory):
        return true

    var error = DirAccess.make_dir_recursive_absolute(absolute_directory)
    if error != OK:
        printerr("[ERROR] Failed to create directory: " + target_directory)
        return false
    return true
