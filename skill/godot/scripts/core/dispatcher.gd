#!/usr/bin/env -S godot --headless --script
extends SceneTree

# We map the global classes to objects or just hardload the utilities to avoid class_name resolution issues.
var utils_script = preload("./utils.gd")

# This script acts as the main entry point (dispatcher) for the Godot skill toolset.
# It delegates each operation to a specific script under the bundled `scripts/` tree.

func _init():
    var args = OS.get_cmdline_args()
    utils_script.debug_mode = "--debug-godot" in args

    var script_index = args.find("--script")
    if script_index == -1:
        utils_script.log_error("Could not find --script argument")
        quit(1)
        return

    var operation_index = script_index + 2
    var params_index = script_index + 3

    if args.size() <= params_index:
        utils_script.log_error("Usage: godot --headless --script dispatcher.gd <operation> <json_params>")
        quit(1)
        return

    var operation = args[operation_index]
    var params_json = args[params_index]

    utils_script.log_info("Operation: " + operation)

    var json = JSON.new()
    var error = json.parse(params_json)
    if error != OK:
        utils_script.log_error("Failed to parse JSON parameters: " + params_json)
        quit(1)
        return

    var params = json.get_data()
    if not (params is Dictionary):
        utils_script.log_error("JSON parameters must be an object: " + params_json)
        quit(1)
        return

    var instance = _instantiate_operation(operation)
    if instance == null:
        quit(1)
        return
    if not instance.has_method("execute"):
        utils_script.log_error("Operation script has no execute(params) method: " + operation)
        quit(1)
        return

    # Defer so the SceneTree finishes initialization — which registers the
    # project's autoload singletons as global identifiers — before the op loads
    # scripts. Without this, ops like check_project that compile scripts
    # referencing an autoload get false "Identifier not found" failures. The
    # deferred coroutine also lets bake_csg await frames; `await` on a
    # non-coroutine execute() returns immediately, so sync ops are unaffected.
    _run.call_deferred(instance, params)

func _run(instance: Object, params: Dictionary) -> void:
    await instance.execute(params)
    # Any op that logged an error exits 1 so shell callers and CI can gate on the
    # exit code instead of parsing stderr.
    quit(1 if utils_script.had_errors else 0)

func _instantiate_operation(operation: String) -> Object:
    var script_path := _script_path_for(operation)
    if script_path.is_empty():
        utils_script.log_error("Unknown operation: " + operation)
        return null
    var operation_script = load(script_path)
    if not (operation_script is GDScript):
        utils_script.log_error("Could not load script for operation at path: " + script_path)
        return null
    var instance = operation_script.new()
    if instance == null:
        utils_script.log_error("Operation script failed to instantiate (parse error?): " + script_path)
        return null
    return instance

func _script_path_for(operation: String) -> String:
    # Map operations to their specific files based on the dispatcher script's location.
    var local_dir = get_script().resource_path.get_base_dir()
    match operation:
        "create_scene":
            return local_dir.path_join("../scene/create_scene.gd")
        "add_node":
            return local_dir.path_join("../scene/add_node.gd")
        "scene_batch":
            return local_dir.path_join("../scene/scene_batch.gd")
        "instantiate_scene":
            return local_dir.path_join("../scene/instantiate_scene.gd")
        "configure_node":
            return local_dir.path_join("../scene/configure_node.gd")
        "configure_control":
            return local_dir.path_join("../scene/configure_control.gd")
        "attach_script":
            return local_dir.path_join("../scene/attach_script.gd")
        "connect_signal":
            return local_dir.path_join("../scene/connect_signal.gd")
        "disconnect_signal":
            return local_dir.path_join("../scene/disconnect_signal.gd")
        "remove_node":
            return local_dir.path_join("../scene/remove_node.gd")
        "reparent_node":
            return local_dir.path_join("../scene/reparent_node.gd")
        "reorder_node":
            return local_dir.path_join("../scene/reorder_node.gd")
        "load_sprite":
            return local_dir.path_join("../scene/load_sprite.gd")
        "build_sprite_frames":
            return local_dir.path_join("../scene/build_sprite_frames.gd")
        "save_scene":
            return local_dir.path_join("../scene/save_scene.gd")
        "export_mesh_library":
            return local_dir.path_join("../mesh/export_mesh_library.gd")
        "get_uid":
            return local_dir.path_join("../utils/get_uid.gd")
        "resave_resources":
            return local_dir.path_join("../utils/resave_resources.gd")
        "check_project":
            return local_dir.path_join("../debug/check_project.gd")
        "inspect_project":
            return local_dir.path_join("../inspect/inspect_project.gd")
        "inspect_scene":
            return local_dir.path_join("../inspect/inspect_scene.gd")
        "inspect_resource":
            return local_dir.path_join("../inspect/inspect_resource.gd")
        "resource_batch":
            return local_dir.path_join("../resource/resource_batch.gd")
        "build_tileset":
            return local_dir.path_join("../resource/build_tileset.gd")
        "paint_tilemap":
            return local_dir.path_join("../scene/paint_tilemap.gd")
        "paint_gridmap":
            return local_dir.path_join("../scene/paint_gridmap.gd")
        "bake_collision":
            return local_dir.path_join("../scene/bake_collision.gd")
        "collision_from_sprite":
            return local_dir.path_join("../scene/collision_from_sprite.gd")
        "bake_csg":
            return local_dir.path_join("../scene/bake_csg.gd")
        "build_theme":
            return local_dir.path_join("../resource/build_theme.gd")
        "gltf_export":
            return local_dir.path_join("../export/gltf_export.gd")
        "build_replication_config":
            return local_dir.path_join("../resource/build_replication_config.gd")
        "build_animation":
            return local_dir.path_join("../scene/build_animation.gd")
        "build_animation_tree":
            return local_dir.path_join("../scene/build_animation_tree.gd")
        "setup_audio_buses":
            return local_dir.path_join("../audio/setup_audio_buses.gd")
        "set_import_options":
            return local_dir.path_join("../import/set_import_options.gd")
        "project_batch":
            return local_dir.path_join("../project/project_batch.gd")
        "audit_imports":
            return local_dir.path_join("../import/audit_imports.gd")
        _:
            return ""
