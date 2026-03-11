class_name GodotSkillResaveResources
extends RefCounted

var utils_script = preload("../core/utils.gd")
var uid_utils_script = preload("./uid_utils.gd")

func execute(params: Dictionary) -> void:
    utils_script.log_info("Resaving all resources to update UID references...")
    
    var project_path = "res://"
    if params.has("project_path"):
        project_path = params.project_path
        if not project_path.begins_with("res://"):
            project_path = "res://" + project_path
        if not project_path.ends_with("/"):
            project_path += "/"
            
    var scenes = uid_utils_script.find_files(project_path, ".tscn")
    var success_count = 0
    var error_count = 0
    
    for scene_path in scenes:
        var file_check = FileAccess.file_exists(scene_path)
        if not file_check:
            utils_script.log_error("Scene file does not exist at: " + scene_path)
            error_count += 1
            continue
            
        var scene = load(scene_path)
        if scene:
            var error = ResourceSaver.save(scene, scene_path)
            if error == OK:
                success_count += 1
            else:
                error_count += 1
                utils_script.log_error("Failed to save: " + scene_path + ", error: " + str(error))
        else:
            error_count += 1
            utils_script.log_error("Failed to load: " + scene_path)
            
    var scripts = uid_utils_script.find_files(project_path, ".gd") + uid_utils_script.find_files(project_path, ".shader") + uid_utils_script.find_files(project_path, ".gdshader")
    var missing_uids = 0
    var generated_uids = 0
    
    for script_path in scripts:
        var uid_path = script_path + ".uid"
        var f = FileAccess.open(uid_path, FileAccess.READ)
        
        if not f:
            missing_uids += 1
            var res = load(script_path)
            if res:
                var error = ResourceSaver.save(res, script_path)
                if error == OK:
                    generated_uids += 1
                else:
                    utils_script.log_error("Failed to generate UID for: " + script_path)
            else:
                utils_script.log_error("Failed to load resource: " + script_path)
                
    utils_script.log_info("Resave operation complete. Scenes: " + str(success_count) + ", UIDs generated: " + str(generated_uids))
