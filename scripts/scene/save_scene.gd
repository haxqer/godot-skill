class_name GodotSkillSaveScene
extends RefCounted

var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    utils_script.log_info("Saving scene: " + params.scene_path)
    
    var full_scene_path = params.scene_path
    if not full_scene_path.begins_with("res://"):
        full_scene_path = "res://" + full_scene_path
        
    if not FileAccess.file_exists(full_scene_path):
        utils_script.log_error("Scene file does not exist at: " + full_scene_path)
        return
        
    var scene = load(full_scene_path)
    if not scene:
        utils_script.log_error("Failed to load scene: " + full_scene_path)
        return
        
    var scene_root = scene.instantiate()
    
    var save_path = params.new_path if params.has("new_path") else full_scene_path
    if params.has("new_path") and not save_path.begins_with("res://"):
        save_path = "res://" + save_path
        
    if params.has("new_path"):
        var dir = DirAccess.open("res://")
        if dir == null:
            utils_script.log_error("Failed to open res:// directory")
            return
            
        var scene_dir = save_path.get_base_dir()
        if scene_dir != "res://" and not dir.dir_exists(scene_dir.substr(6)):
            var error = dir.make_dir_recursive(scene_dir.substr(6))
            if error != OK:
                utils_script.log_error("Failed to create directory: " + scene_dir)
                return
                
    var packed_scene = PackedScene.new()
    var result = packed_scene.pack(scene_root)
    
    if result == OK:
        var error = ResourceSaver.save(packed_scene, save_path)
        if error == OK:
            utils_script.log_info("Scene saved successfully to: " + save_path)
        else:
            utils_script.log_error("Failed to save scene: " + str(error))
    else:
        utils_script.log_error("Failed to pack scene: " + str(result))
