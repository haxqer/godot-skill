class_name GodotSkillExportMeshLibrary
extends RefCounted

var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    utils_script.log_info("Exporting MeshLibrary from scene: " + params.scene_path)
    
    var full_scene_path = params.scene_path
    if not full_scene_path.begins_with("res://"):
        full_scene_path = "res://" + full_scene_path
        
    var full_output_path = params.output_path
    if not full_output_path.begins_with("res://"):
        full_output_path = "res://" + full_output_path
        
    if not FileAccess.file_exists(full_scene_path):
        utils_script.log_error("Scene file does not exist at: " + full_scene_path)
        return
        
    var scene = load(full_scene_path)
    if not scene:
        utils_script.log_error("Failed to load scene: " + full_scene_path)
        return
        
    var scene_root = scene.instantiate()
    var mesh_library = MeshLibrary.new()
    
    var mesh_item_names = params.mesh_item_names if params.has("mesh_item_names") else []
    var use_specific_items = mesh_item_names.size() > 0
    
    var item_id = 0
    
    for child in scene_root.get_children():
        if use_specific_items and not (child.name in mesh_item_names):
            continue
            
        var mesh_instance = null
        if child is MeshInstance3D:
            mesh_instance = child
        else:
            for descendant in child.get_children():
                if descendant is MeshInstance3D:
                    mesh_instance = descendant
                    break
                    
        if mesh_instance and mesh_instance.mesh:
            mesh_library.create_item(item_id)
            mesh_library.set_item_name(item_id, child.name)
            mesh_library.set_item_mesh(item_id, mesh_instance.mesh)
            
            for collision_child in child.get_children():
                if collision_child is CollisionShape3D and collision_child.shape:
                    mesh_library.set_item_shapes(item_id, [collision_child.shape])
                    break
                    
            if mesh_instance.mesh:
                mesh_library.set_item_preview(item_id, mesh_instance.mesh)
                
            item_id += 1
            
    var dir = DirAccess.open("res://")
    if dir == null:
        utils_script.log_error("Failed to open res:// directory")
        return
        
    var output_dir = full_output_path.get_base_dir()
    if output_dir != "res://" and not dir.dir_exists(output_dir.substr(6)):
        var error = dir.make_dir_recursive(output_dir.substr(6))
        if error != OK:
            utils_script.log_error("Failed to create directory: " + output_dir)
            return
            
    if item_id > 0:
        var error = ResourceSaver.save(mesh_library, full_output_path)
        if error == OK:
            utils_script.log_info("MeshLibrary exported successfully with " + str(item_id) + " items to: " + full_output_path)
        else:
            utils_script.log_error("Failed to save MeshLibrary: " + str(error))
    else:
        utils_script.log_error("No valid meshes found in the scene")
