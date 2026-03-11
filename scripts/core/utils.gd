class_name GodotSkillUtils
extends RefCounted

static var debug_mode: bool = false

static func log_debug(message: String) -> void:
    if debug_mode:
        print("[DEBUG] " + message)

static func log_info(message: String) -> void:
    print("[INFO] " + message)

static func log_error(message: String) -> void:
    printerr("[ERROR] " + message)

static func get_script_by_name(name_of_class: String) -> Script:
    if debug_mode:
        print("Attempting to get script for class: " + name_of_class)
    
    if ResourceLoader.exists(name_of_class, "Script"):
        var script = load(name_of_class) as Script
        if script:
            return script
    
    var global_classes = ProjectSettings.get_global_class_list()
    for global_class in global_classes:
        if global_class["class"] == name_of_class:
            var script = load(global_class["path"]) as Script
            if script:
                return script
    
    printerr("Could not find script for class: " + name_of_class)
    return null

static func instantiate_class(name_of_class: String) -> Object:
    if name_of_class.is_empty():
        return null
    
    var result = null
    if ClassDB.class_exists(name_of_class):
        if ClassDB.can_instantiate(name_of_class):
            result = ClassDB.instantiate(name_of_class)
    else:
        var script = get_script_by_name(name_of_class)
        if script is GDScript:
            result = script.new()
            
    return result
