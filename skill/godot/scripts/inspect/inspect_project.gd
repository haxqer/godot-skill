class_name GodotSkillInspectProject
extends RefCounted

var codec_script = preload("../core/variant_codec.gd")
var uid_utils_script = preload("../utils/uid_utils.gd")

const FEATURE_TAGS = [
    "editor", "debug", "release", "template", "double", "single",
    "windows", "macos", "linux", "android", "ios", "web", "visionos",
    "mobile", "pc", "x86_64", "arm64", "dedicated_server", "dotnet", "mono"
]
const PROJECT_SETTING_KEYS = [
    "application/config/name",
    "application/config/features",
    "application/run/main_scene",
    "rendering/renderer/rendering_method",
    "rendering/renderer/rendering_method.mobile",
    "physics/3d/physics_engine",
    "internationalization/locale/fallback",
    "internationalization/locale/translations",
    "editor_plugins/enabled"
]

func execute(params: Dictionary) -> void:
    var codec = codec_script.new()
    var files := uid_utils_script.find_all_files("res://")
    var include_files := bool(params.get("include_files", false))
    var extension_counts := {}
    for path in files:
        var extension := path.get_extension().to_lower()
        if extension.is_empty():
            extension = "<none>"
        extension_counts[extension] = int(extension_counts.get(extension, 0)) + 1

    var features: Array = []
    for feature in FEATURE_TAGS:
        if OS.has_feature(feature):
            features.append(feature)

    var project_settings := {}
    for setting_name in PROJECT_SETTING_KEYS:
        if ProjectSettings.has_setting(setting_name):
            project_settings[setting_name] = codec.encode(ProjectSettings.get_setting(setting_name), 3)

    var autoloads := {}
    for property_info in ProjectSettings.get_property_list():
        var setting_name := str(property_info.get("name", ""))
        if setting_name.begins_with("autoload/"):
            autoloads[setting_name.trim_prefix("autoload/")] = codec.encode(ProjectSettings.get_setting(setting_name), 2)

    var project_action_names := _explicit_input_actions()

    var input_actions := {}
    for action_name in project_action_names:
        var events: Array = []
        for event in InputMap.action_get_events(action_name):
            events.append(codec.encode(event, 2))
        input_actions[str(action_name)] = {
            "deadzone": InputMap.action_get_deadzone(action_name),
            "events": events
        }

    var plugins := _inspect_plugins(files)
    var export_presets := _inspect_export_presets(codec)
    var result := {
        "project_root": ProjectSettings.globalize_path("res://"),
        "engine": {
            "version": codec.encode(Engine.get_version_info(), 2),
            "features": features,
            "os": OS.get_name(),
            "os_version": OS.get_version(),
            "distribution": OS.get_distribution_name(),
            "processor": OS.get_processor_name(),
            "display_server": DisplayServer.get_name(),
            "rendering_adapter": RenderingServer.get_video_adapter_name(),
            "rendering_vendor": RenderingServer.get_video_adapter_vendor()
        },
        "settings": project_settings,
        "autoloads": autoloads,
        "input_actions": input_actions,
        "global_classes": codec.encode(ProjectSettings.get_global_class_list(), 2),
        "plugins": plugins,
        "export_presets": export_presets,
        "files": {
            "total": files.size(),
            "extension_counts": extension_counts,
            "has_csharp": int(extension_counts.get("cs", 0)) > 0 or int(extension_counts.get("csproj", 0)) > 0,
            "has_gdextension": int(extension_counts.get("gdextension", 0)) > 0,
            "paths": files if include_files else []
        }
    }
    print(JSON.stringify(result))

func _explicit_input_actions() -> Array[StringName]:
    var names: Array[StringName] = []
    var config := ConfigFile.new()
    if config.load("res://project.godot") != OK or not config.has_section("input"):
        return names
    for key in config.get_section_keys("input"):
        names.append(StringName(str(key)))
    names.sort()
    return names

func _inspect_plugins(files: Array[String]) -> Array:
    var enabled_raw = ProjectSettings.get_setting("editor_plugins/enabled", PackedStringArray())
    var enabled: Array = Array(enabled_raw)
    var plugins: Array = []
    for path in files:
        if path.get_file() != "plugin.cfg" or not path.begins_with("res://addons/"):
            continue
        var config := ConfigFile.new()
        var error := config.load(path)
        var plugin_path := path.trim_prefix("res://addons/").trim_suffix("/plugin.cfg")
        plugins.append({
            "path": path,
            "id": plugin_path,
            "enabled": plugin_path in enabled,
            "valid": error == OK,
            "name": str(config.get_value("plugin", "name", "")) if error == OK else "",
            "version": str(config.get_value("plugin", "version", "")) if error == OK else "",
            "script": str(config.get_value("plugin", "script", "")) if error == OK else ""
        })
    return plugins

func _inspect_export_presets(codec: RefCounted) -> Array:
    if not FileAccess.file_exists("res://export_presets.cfg"):
        return []
    var config := ConfigFile.new()
    if config.load("res://export_presets.cfg") != OK:
        return [{"valid": false, "path": "res://export_presets.cfg"}]

    var presets: Array = []
    for section in config.get_sections():
        if not section.begins_with("preset.") or section.contains(".options"):
            continue
        var values := {}
        for key in config.get_section_keys(section):
            values[str(key)] = codec.encode(config.get_value(section, key), 2)
        presets.append({"section": section, "valid": true, "values": values})
    return presets
