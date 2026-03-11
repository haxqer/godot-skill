class_name GodotSkillLoadSprite
extends RefCounted

var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    utils_script.log_info("Loading sprite into scene: " + params.scene_path)
    
    var full_scene_path = params.scene_path
    if not full_scene_path.begins_with("res://"):
        full_scene_path = "res://" + full_scene_path
    
    if not FileAccess.file_exists(full_scene_path):
        utils_script.log_error("Scene file does not exist at: " + full_scene_path)
        return
    
    var full_texture_path = params.texture_path
    if not full_texture_path.begins_with("res://"):
        full_texture_path = "res://" + full_texture_path
    
    var scene = load(full_scene_path)
    if not scene:
        utils_script.log_error("Failed to load scene: " + full_scene_path)
        return
        
    var scene_root = scene.instantiate()
    var node_path = params.node_path
    
    if node_path.begins_with("root/"):
        node_path = node_path.substr(5)
        
    var sprite_node = null
    if node_path == "":
        sprite_node = scene_root
    else:
        sprite_node = scene_root.get_node(node_path)
        
    if not sprite_node:
        utils_script.log_error("Node not found: " + params.node_path)
        return
        
    if not (sprite_node is Sprite2D or sprite_node is Sprite3D or sprite_node is TextureRect):
        utils_script.log_error("Node is not a sprite-compatible type: " + sprite_node.get_class())
        return
        
    var texture = load(full_texture_path)
    if not texture:
        utils_script.log_error("Failed to load texture: " + full_texture_path)
        return
        
    sprite_node.texture = texture
    
    var packed_scene = PackedScene.new()
    var result = packed_scene.pack(scene_root)
    
    if result == OK:
        var error = ResourceSaver.save(packed_scene, full_scene_path)
        if error == OK:
            utils_script.log_info("Sprite loaded successfully with texture: " + full_texture_path)
        else:
            utils_script.log_error("Failed to save scene: " + str(error))
    else:
        utils_script.log_error("Failed to pack scene: " + str(result))
