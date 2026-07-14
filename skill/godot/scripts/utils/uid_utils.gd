class_name GodotSkillUIDUtils
extends RefCounted

static func find_files(path: String, extension: String) -> Array:
    var files = []
    var dir = DirAccess.open(path)
    
    if dir:
        dir.list_dir_begin()
        var file_name = dir.get_next()
        
        while file_name != "":
            if dir.current_is_dir() and not file_name.begins_with("."):
                files.append_array(find_files(path + file_name + "/", extension))
            elif file_name.ends_with(extension):
                files.append(path + file_name)
            
            file_name = dir.get_next()
            
    return files

static func find_all_files(path: String, include_hidden: bool = false) -> Array[String]:
    var files: Array[String] = []
    var dir := DirAccess.open(path)
    if not dir:
        return files

    dir.list_dir_begin()
    var file_name := dir.get_next()
    while file_name != "":
        var is_hidden := file_name.begins_with(".")
        if dir.current_is_dir():
            if (include_hidden or not is_hidden) and file_name != ".godot":
                files.append_array(find_all_files(path.path_join(file_name), include_hidden))
        elif include_hidden or not is_hidden or file_name.ends_with(".import"):
            files.append(path.path_join(file_name))
        file_name = dir.get_next()
    dir.list_dir_end()
    files.sort()
    return files
