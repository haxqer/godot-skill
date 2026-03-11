class_name GodotSkillGetUID
extends RefCounted

var utils_script = preload("../core/utils.gd")

func execute(params: Dictionary) -> void:
    if not params.has("file_path"):
        utils_script.log_error("File path is required")
        return
        
    var file_path = params.file_path
    if not file_path.begins_with("res://"):
        file_path = "res://" + file_path
        
    var absolute_path = ProjectSettings.globalize_path(file_path)
    var file_check = FileAccess.file_exists(file_path)
    
    if not file_check:
        utils_script.log_error("File does not exist at: " + file_path)
        return
        
    var uid_path = file_path + ".uid"
    var f = FileAccess.open(uid_path, FileAccess.READ)
    
    if f:
        var uid_content = f.get_as_text()
        f.close()
        
        var result = {
            "file": file_path,
            "absolutePath": absolute_path,
            "uid": uid_content.strip_edges(),
            "exists": true
        }
        print(JSON.stringify(result))
    else:
        var result = {
            "file": file_path,
            "absolutePath": absolute_path,
            "exists": false,
            "message": "UID file does not exist for this file. Use resave_resources to generate UIDs."
        }
        print(JSON.stringify(result))
