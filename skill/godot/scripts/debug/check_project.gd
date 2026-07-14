class_name GodotSkillCheckProject
extends RefCounted

# Static validation pass: try to load every script, scene, shader, and resource
# in the project (or a sub-path) and report which ones fail. This catches parse
# and load errors across the WHOLE project without having to run gameplay to the
# code path that touches each file.
#
# Godot prints the detailed parse errors (with res://file:line) to stderr as each
# broken file is loaded here, so callers can pipe the combined output through
# scripts/debug/godot_log_parser.py to get structured, line-level diagnostics.
# The JSON summary this prints gives the file-level pass/fail list.

var utils_script = preload("../core/utils.gd")
var uid_utils_script = preload("../utils/uid_utils.gd")

func execute(params: Dictionary) -> void:
    var project_path = "res://"
    if params.has("project_path") and str(params.project_path) != "":
        project_path = str(params.project_path)
        if not project_path.begins_with("res://"):
            project_path = "res://" + project_path
        if not project_path.ends_with("/"):
            project_path += "/"

    utils_script.log_info("Checking project resources under: " + project_path)

    var failed: Array = []
    var counts = {
        "scripts": 0,
        "scenes": 0,
        "resources": 0,
        "shaders": 0,
        "extensions": 0,
        "plugins": 0
    }

    _check_group(project_path, ".gd", "script", counts, "scripts", failed)
    _check_group(project_path, ".tscn", "scene", counts, "scenes", failed)
    _check_group(project_path, ".scn", "scene", counts, "scenes", failed)
    _check_group(project_path, ".gdshader", "shader", counts, "shaders", failed)
    _check_group(project_path, ".gdshaderinc", "shader", counts, "shaders", failed)
    _check_group(project_path, ".tres", "resource", counts, "resources", failed)
    _check_group(project_path, ".res", "resource", counts, "resources", failed)
    _check_group(project_path, ".gdextension", "extension", counts, "extensions", failed)
    _check_plugins(project_path, counts, failed)

    var checked = counts.scripts + counts.scenes + counts.shaders + counts.resources + counts.extensions + counts.plugins
    var result = {
        "project_path": project_path,
        "checked": checked,
        "ok": checked - failed.size(),
        "failed_count": failed.size(),
        "failed": failed,
        "counts": counts
    }

    utils_script.log_info(
        "Check complete. Checked " + str(checked) + " files, " + str(failed.size()) + " failed to load."
    )
    print(JSON.stringify(result))

func _check_group(base_path: String, extension: String, kind: String, counts: Dictionary, counter_key: String, failed: Array) -> void:
    var paths = uid_utils_script.find_files(base_path, extension)
    for path in paths:
        counts[counter_key] += 1
        var reason = _load_failure_reason(path, kind)
        if reason != "":
            failed.append({
                "path": path,
                "kind": kind,
                "reason": reason
            })
            utils_script.log_error(kind + " failed to load: " + path + " (" + reason + ")")

func _load_failure_reason(path: String, kind: String) -> String:
    if not FileAccess.file_exists(path):
        return "file does not exist"

    var resource = load(path)
    if resource == null:
        # For scripts this is almost always a parse error (printed to stderr just
        # above by the engine); for scenes/resources it is a broken dependency.
        return "load() returned null (see parse/load errors in stderr)"

    if resource is Script:
        # A script with a parse error still loads as a non-null (invalid) Script,
        # so a null check is not enough. can_instantiate() is true only for a
        # script that compiled; when it is false we confirm with reload() so that
        # a valid abstract/base script is not reported as a failure.
        if not resource.can_instantiate():
            var reload_error = resource.reload()
            if reload_error != OK:
                return "parse/compile error (reload returned " + str(reload_error) + "; see stderr)"

    if kind == "scene":
        if resource is PackedScene and not resource.can_instantiate():
            return "PackedScene cannot be instantiated (missing dependency or broken node)"

    return ""

func _check_plugins(base_path: String, counts: Dictionary, failed: Array) -> void:
    for path in uid_utils_script.find_all_files(base_path):
        if path.get_file() != "plugin.cfg":
            continue
        counts.plugins += 1
        var reason := _plugin_failure_reason(path)
        if not reason.is_empty():
            failed.append({"path": path, "kind": "plugin", "reason": reason})
            utils_script.log_error("plugin failed validation: %s (%s)" % [path, reason])

func _plugin_failure_reason(path: String) -> String:
    var config := ConfigFile.new()
    var config_error := config.load(path)
    if config_error != OK:
        return "plugin.cfg parse error: " + error_string(config_error)
    if not config.has_section("plugin"):
        return "missing [plugin] section"
    var script_value := str(config.get_value("plugin", "script", ""))
    if script_value.is_empty():
        return "missing plugin script"
    var script_path := path.get_base_dir().path_join(script_value)
    if not FileAccess.file_exists(script_path):
        return "plugin script does not exist: " + script_path
    var script = load(script_path)
    if not (script is Script):
        return "plugin script failed to load: " + script_path
    if not script.can_instantiate():
        var reload_error: int = script.reload()
        if reload_error != OK:
            return "plugin script compile error: " + error_string(reload_error)
    var base_type := str(script.get_instance_base_type())
    if base_type != "EditorPlugin" and not ClassDB.is_parent_class(base_type, "EditorPlugin"):
        return "plugin script must extend EditorPlugin (found %s)" % base_type
    return ""
