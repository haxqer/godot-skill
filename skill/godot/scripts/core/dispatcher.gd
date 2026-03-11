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
        
    var operation_index = script_index + 2
    var params_index = script_index + 3
    
    if args.size() <= params_index:
        utils_script.log_error("Usage: godot --headless --script dispatcher.gd <operation> <json_params>")
        quit(1)
        
    var operation = args[operation_index]
    var params_json = args[params_index]
    
    utils_script.log_info("Operation: " + operation)
    
    var json = JSON.new()
    var error = json.parse(params_json)
    var params = null
    
    if error == OK:
        params = json.get_data()
    else:
        utils_script.log_error("Failed to parse JSON parameters: " + params_json)
        quit(1)
        
    _delegate_operation(operation, params)
    quit()

func _delegate_operation(operation: String, params: Dictionary) -> void:
    var script_path = ""
    var local_dir = get_script().resource_path.get_base_dir()
    
    # Map operations to their specific files based on the dispatcher script's location
    match operation:
        "create_scene":
            script_path = local_dir.path_join("../scene/create_scene.gd")
        "add_node":
            script_path = local_dir.path_join("../scene/add_node.gd")
        "scene_batch":
            script_path = local_dir.path_join("../scene/scene_batch.gd")
        "instantiate_scene":
            script_path = local_dir.path_join("../scene/instantiate_scene.gd")
        "configure_node":
            script_path = local_dir.path_join("../scene/configure_node.gd")
        "configure_control":
            script_path = local_dir.path_join("../scene/configure_control.gd")
        "attach_script":
            script_path = local_dir.path_join("../scene/attach_script.gd")
        "connect_signal":
            script_path = local_dir.path_join("../scene/connect_signal.gd")
        "disconnect_signal":
            script_path = local_dir.path_join("../scene/disconnect_signal.gd")
        "remove_node":
            script_path = local_dir.path_join("../scene/remove_node.gd")
        "reparent_node":
            script_path = local_dir.path_join("../scene/reparent_node.gd")
        "reorder_node":
            script_path = local_dir.path_join("../scene/reorder_node.gd")
        "load_sprite":
            script_path = local_dir.path_join("../scene/load_sprite.gd")
        "save_scene":
            script_path = local_dir.path_join("../scene/save_scene.gd")
        "export_mesh_library":
            script_path = local_dir.path_join("../mesh/export_mesh_library.gd")
        "get_uid":
            script_path = local_dir.path_join("../utils/get_uid.gd")
        "resave_resources":
            script_path = local_dir.path_join("../utils/resave_resources.gd")
        _:
            utils_script.log_error("Unknown operation: " + operation)
            quit(1)
            
    var operation_script = load(script_path)
    if operation_script and operation_script is GDScript:
        var instance = operation_script.new()
        if instance.has_method("execute"):
            instance.execute(params)
        else:
            utils_script.log_error("Script " + script_path + " does not have an execute(params) method.")
    else:
        utils_script.log_error("Could not load script for operation at path: " + script_path)
