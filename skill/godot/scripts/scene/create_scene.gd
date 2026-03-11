class_name GodotSkillCreateScene
extends RefCounted

var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    utils_script.log_info("Creating scene: " + params.scene_path)
    
    var project_res_path = "res://"
    var project_user_path = "user://"
    var global_res_path = ProjectSettings.globalize_path(project_res_path)
    var global_user_path = ProjectSettings.globalize_path(project_user_path)
    
    var full_scene_path = params.scene_path
    if not full_scene_path.begins_with("res://"):
        full_scene_path = "res://" + full_scene_path
        
    var absolute_scene_path = ProjectSettings.globalize_path(full_scene_path)
    var scene_dir_res = full_scene_path.get_base_dir()
    var scene_dir_abs = absolute_scene_path.get_base_dir()
    
    var root_node_type = "Node2D"
    if params.has("root_node_type"):
        root_node_type = params.root_node_type
        
    var scene_root = utils_script.instantiate_class(root_node_type)
    if not scene_root:
        utils_script.log_error("Failed to instantiate node of type: " + root_node_type)
        return
        
    scene_root.name = "root"
    
    var packed_scene = PackedScene.new()
    var result = packed_scene.pack(scene_root)
    
    if result == OK:
        var scene_dir_relative = scene_dir_res.substr(6)
        if not scene_dir_relative.is_empty():
            var dir_exists = DirAccess.dir_exists_absolute(scene_dir_abs)
            if not dir_exists:
                var dir = DirAccess.open("res://")
                if dir == null:
                    var make_dir_error = DirAccess.make_dir_recursive_absolute(scene_dir_abs)
                    if make_dir_error != OK:
                        utils_script.log_error("Failed to create directory using absolute path")
                        return
                else:
                    var make_dir_error = dir.make_dir_recursive(scene_dir_relative)
                    if make_dir_error != OK:
                        utils_script.log_error("Failed to create directory: " + scene_dir_relative)
                        return
        
        var save_error = ResourceSaver.save(packed_scene, full_scene_path)
        if save_error == OK:
            utils_script.log_info("Scene created successfully at: " + params.scene_path)
        else:
            utils_script.log_error("Failed to save scene. Error code: " + str(save_error))
    else:
        utils_script.log_error("Failed to pack scene: " + str(result))
