class_name GodotSkillGltfExport
extends RefCounted

# Exports an edited Godot scene (or a subtree) to .glb/.gltf via GLTFDocument.
# Nothing else in the op set can emit glTF from a Godot scene. Import stays with
# the standard --import pipeline.

var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    var scene_path := _normalize_res_path(params.get("scene_path", ""))
    if scene_path.is_empty() or not FileAccess.file_exists(scene_path):
        utils_script.log_error("gltf_export requires an existing scene_path")
        return

    var out_raw := str(params.get("out", "")).strip_edges()
    if out_raw.is_empty():
        utils_script.log_error("gltf_export requires an out path (.glb or .gltf)")
        return
    var extension := out_raw.get_extension().to_lower()
    if extension != "glb" and extension != "gltf":
        utils_script.log_error("gltf_export.out must end in .glb or .gltf")
        return

    var packed = load(scene_path)
    if not (packed is PackedScene):
        utils_script.log_error("Failed to load scene: " + scene_path)
        return
    var root = packed.instantiate()
    if not (root is Node):
        utils_script.log_error("Failed to instantiate scene: " + scene_path)
        return

    var node: Node = root
    var node_path := str(params.get("node_path", "root"))
    if not (node_path.is_empty() or node_path == "root" or node_path == "."):
        var relative := node_path.trim_prefix("root/").trim_prefix("/")
        var resolved = root.get_node_or_null(NodePath(relative))
        if resolved == null:
            utils_script.log_error("gltf_export node_path not found: " + node_path)
            root.free()
            return
        node = resolved

    # Absolute paths (build dirs) pass through; res://user:// globalize; a bare
    # relative path is treated as project-relative (res://).
    var out_path := out_raw
    if not (out_path.begins_with("res://") or out_path.begins_with("user://") or out_path.begins_with("/")):
        out_path = "res://" + out_path
    var absolute_out := out_path
    if out_path.begins_with("res://") or out_path.begins_with("user://"):
        absolute_out = ProjectSettings.globalize_path(out_path)
    if not _ensure_directory_for_absolute(absolute_out):
        root.free()
        return

    var document := GLTFDocument.new()
    var state := GLTFState.new()
    var append_error := document.append_from_scene(node, state, int(params.get("flags", 0)))
    if append_error != OK:
        utils_script.log_error("gltf_export failed to read scene: " + error_string(append_error))
        root.free()
        return
    var write_error := document.write_to_filesystem(state, absolute_out)
    root.free()
    if write_error != OK:
        utils_script.log_error("gltf_export failed to write %s: %s" % [absolute_out, error_string(write_error)])
        return

    print(JSON.stringify({
        "ok": true,
        "scene_path": scene_path,
        "node_path": node_path,
        "out": absolute_out
    }))

func _ensure_directory_for_absolute(absolute_path: String) -> bool:
    var directory := absolute_path.get_base_dir()
    var error := DirAccess.make_dir_recursive_absolute(directory)
    if error != OK and error != ERR_ALREADY_EXISTS:
        utils_script.log_error("gltf_export could not create output directory: " + directory)
        return false
    return true

func _normalize_res_path(path_value: Variant) -> String:
    var path := str(path_value).strip_edges().replace("\\", "/")
    if path.is_empty():
        return ""
    if path.begins_with("res://") or path.begins_with("user://"):
        return path
    return "res://" + path.trim_prefix("/")
