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
    var absolute_uid_path = ProjectSettings.globalize_path(uid_path)
    var sidecar_exists = FileAccess.file_exists(uid_path)
    var uid_content = ""

    if sidecar_exists:
        var f = FileAccess.open(uid_path, FileAccess.READ)
        if f:
            uid_content = f.get_as_text().strip_edges()
            f.close()

    var raw_engine_uid = ResourceLoader.get_resource_uid(file_path)
    var engine_uid = ""
    if raw_engine_uid != ResourceUID.INVALID_ID:
        engine_uid = ResourceUID.id_to_text(raw_engine_uid)

    var result = {
        "file": file_path,
        "absolutePath": absolute_path,
        "uidPath": uid_path,
        "absoluteUidPath": absolute_uid_path,
        "uid": uid_content,
        "exists": sidecar_exists,
        "engineUid": engine_uid,
        "engineUidExists": not engine_uid.is_empty()
    }

    if not sidecar_exists:
        result["message"] = "UID sidecar does not exist for this file. Use resave_resources to attempt regeneration on projects that emit .uid files."

    print(JSON.stringify(result))
