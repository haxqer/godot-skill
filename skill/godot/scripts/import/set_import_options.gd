class_name GodotSkillSetImportOptions
extends RefCounted

# Patches the [params] section of an asset's .import sidecar — the canonical
# home of importer options like audio loop settings (`loop` on Ogg/MP3,
# `edit/loop_mode` on WAV) or texture filters. The change only takes effect
# after a reimport: run scripts/import/import_project.py (or
# `godot --headless --import`) afterwards.

var utils_script = preload("../core/utils.gd")
var codec_script = preload("../core/variant_codec.gd")

func execute(params: Dictionary) -> void:
    var file_path := _normalize_res_path(params.get("file_path", ""))
    if file_path.is_empty():
        utils_script.log_error("set_import_options requires file_path")
        return
    var sidecar_path := file_path + ".import"
    if not FileAccess.file_exists(sidecar_path):
        utils_script.log_error("Import sidecar does not exist (import the project first): " + sidecar_path)
        return

    var options = params.get("options", {})
    if not (options is Dictionary) or options.is_empty():
        utils_script.log_error("set_import_options requires a non-empty options dictionary")
        return

    var config := ConfigFile.new()
    var load_error := config.load(sidecar_path)
    if load_error != OK:
        utils_script.log_error("Cannot parse import sidecar: " + error_string(load_error))
        return

    var codec = codec_script.new()
    var applied := {}
    for key in options.keys():
        var raw_value = options[key]
        var value = codec.decode(raw_value, "options.%s" % str(key))
        if value == null and raw_value != null:
            return
        # JSON numbers always decode as float; importer params are typed, so
        # whole numbers must be written back as int (e.g. enum loop_mode).
        if value is float and is_equal_approx(value, roundf(value)):
            value = int(value)
        config.set_value("params", str(key), value)
        applied[str(key)] = value

    var save_error := config.save(sidecar_path)
    if save_error != OK:
        utils_script.log_error("Failed to save import sidecar: " + error_string(save_error))
        return

    # Drop the imported artifacts so the next `--import` cannot skip this file:
    # a params-only edit does not change the source hash, and the scan may
    # otherwise consider the asset up to date. The .godot/imported cache is
    # regenerable by design.
    var removed_artifacts: Array[String] = []
    for destination in Array(config.get_value("deps", "dest_files", [])):
        var destination_path := str(destination)
        var absolute_destination := ProjectSettings.globalize_path(destination_path)
        if FileAccess.file_exists(absolute_destination):
            DirAccess.remove_absolute(absolute_destination)
            removed_artifacts.append(destination_path)
        var md5_path := absolute_destination.get_basename() + ".md5"
        if FileAccess.file_exists(md5_path):
            DirAccess.remove_absolute(md5_path)

    print(JSON.stringify({
        "ok": true,
        "file_path": file_path,
        "import_path": sidecar_path,
        "options_applied": applied.keys(),
        "invalidated_artifacts": removed_artifacts,
        "reimport_required": true
    }))

func _normalize_res_path(path_value: Variant) -> String:
    var path := str(path_value).strip_edges().replace("\\", "/")
    if path.is_empty():
        return ""
    if path.begins_with("res://"):
        return path
    return "res://" + path.trim_prefix("/")
