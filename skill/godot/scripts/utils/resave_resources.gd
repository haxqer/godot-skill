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
    var resources_missing_uid_before = 0
    var uid_regeneration_attempts = 0
    var uid_sidecars_created = 0
    var resources_still_missing_uid = 0
    
    for script_path in scripts:
        var uid_path = script_path + ".uid"
        if FileAccess.file_exists(uid_path):
            continue

        resources_missing_uid_before += 1
        var res = load(script_path)
        if not res:
            resources_still_missing_uid += 1
            utils_script.log_error("Failed to load resource: " + script_path)
            continue

        uid_regeneration_attempts += 1
        var error = ResourceSaver.save(res, script_path)
        if error != OK:
            resources_still_missing_uid += 1
            utils_script.log_error("Failed to resave resource for UID regeneration: " + script_path)
            continue

        if FileAccess.file_exists(uid_path):
            uid_sidecars_created += 1
        else:
            resources_still_missing_uid += 1

    var result = {
        "project_path": project_path,
        "scenes_resaved": success_count,
        "scene_errors": error_count,
        "resources_missing_uid_before": resources_missing_uid_before,
        "uid_regeneration_attempts": uid_regeneration_attempts,
        "uid_sidecars_created": uid_sidecars_created,
        "resources_still_missing_uid": resources_still_missing_uid
    }

    utils_script.log_info(
        "Resave operation complete. Scenes: "
        + str(success_count)
        + ", UID sidecars created: "
        + str(uid_sidecars_created)
        + ", still missing: "
        + str(resources_still_missing_uid)
    )
    print(JSON.stringify(result))
