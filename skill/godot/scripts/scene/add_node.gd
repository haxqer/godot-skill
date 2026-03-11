class_name GodotSkillAddNode
extends RefCounted

var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    utils_script.log_info("Adding node to scene: " + params.scene_path)
    
    var full_scene_path = params.scene_path
    if not full_scene_path.begins_with("res://"):
        full_scene_path = "res://" + full_scene_path
        
    var absolute_scene_path = ProjectSettings.globalize_path(full_scene_path)
    
    if not FileAccess.file_exists(absolute_scene_path):
        utils_script.log_error("Scene file does not exist at: " + absolute_scene_path)
        return
        
    var scene = load(full_scene_path)
    if not scene:
        utils_script.log_error("Failed to load scene: " + full_scene_path)
        return
        
    var scene_root = scene.instantiate()
    var parent_path = "root"
    if params.has("parent_node_path"):
        parent_path = params.parent_node_path
        
    var parent = scene_root
    if parent_path != "root":
        parent = scene_root.get_node(parent_path.replace("root/", ""))
        if not parent:
            utils_script.log_error("Parent node not found: " + parent_path)
            return
            
    var new_node = utils_script.instantiate_class(params.node_type)
    if not new_node:
        utils_script.log_error("Failed to instantiate node of type: " + params.node_type)
        return
        
    new_node.name = params.node_name
    
    if params.has("properties"):
        var properties = params.properties
        for property in properties:
            new_node.set(property, properties[property])
            
    parent.add_child(new_node)
    new_node.owner = scene_root
    
    var packed_scene = PackedScene.new()
    var result = packed_scene.pack(scene_root)
    
    if result == OK:
        var save_error = ResourceSaver.save(packed_scene, absolute_scene_path)
        if save_error == OK:
            utils_script.log_info("Node '" + params.node_name + "' of type '" + params.node_type + "' added successfully")
        else:
            utils_script.log_error("Failed to save scene: " + str(save_error))
    else:
        utils_script.log_error("Failed to pack scene: " + str(result))
