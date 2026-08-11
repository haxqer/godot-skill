class_name GodotSkillBuildTheme
extends RefCounted

# Authors a Theme .tres grouped by control type. Every Theme item setter is a
# positional (name, theme_type, value) call with no property equivalent, so a
# realistic theme is dozens of unlabeled resource_batch call_method entries. This
# op collapses that into readable, grouped JSON with a flat StyleBoxFlat shorthand
# and hex-string colors. It is sugar over Theme.set_* — no special orchestration.

var utils_script = preload("../core/utils.gd")
var codec_script = preload("../core/variant_codec.gd")

var codec = null

func execute(params: Dictionary) -> void:
    var target_path := _normalize_res_path(params.get("resource_path", ""))
    if target_path.is_empty():
        utils_script.log_error("build_theme requires resource_path")
        return

    var theme := _open_theme(params, target_path)
    if theme == null:
        return
    codec = codec_script.new()

    if params.has("default_font"):
        var font = codec.decode(params.get("default_font"), "build_theme.default_font")
        if not (font is Font):
            utils_script.log_error("build_theme.default_font must resolve to a Font")
            return
        theme.default_font = font
    if params.has("default_font_size"):
        theme.default_font_size = int(params.get("default_font_size"))
    if params.has("default_base_scale"):
        theme.default_base_scale = float(params.get("default_base_scale"))

    var types = params.get("types", {})
    if not (types is Dictionary):
        utils_script.log_error("build_theme.types must be a dictionary")
        return
    for type_name in types.keys():
        if not _apply_type_items(theme, str(type_name), types[type_name], "types." + str(type_name)):
            return

    var variations = params.get("variations", {})
    if not (variations is Dictionary):
        utils_script.log_error("build_theme.variations must be a dictionary")
        return
    for variation_name in variations.keys():
        var spec = variations[variation_name]
        if not (spec is Dictionary):
            utils_script.log_error("build_theme.variations entries must be dictionaries")
            return
        var base_type := str(spec.get("base", ""))
        if base_type.is_empty():
            utils_script.log_error("build_theme.variations.%s requires base" % str(variation_name))
            return
        theme.set_type_variation(str(variation_name), base_type)
        if not _apply_type_items(theme, str(variation_name), spec, "variations." + str(variation_name)):
            return

    if not _ensure_parent_directory(target_path):
        return
    var save_error := ResourceSaver.save(theme, target_path)
    if save_error != OK:
        utils_script.log_error("Failed to save Theme %s: %s" % [target_path, error_string(save_error)])
        return

    print(JSON.stringify({
        "ok": true,
        "resource_path": target_path,
        "type_list": theme.get_type_list()
    }))

func _open_theme(params: Dictionary, target_path: String) -> Theme:
    if FileAccess.file_exists(target_path):
        var existing = ResourceLoader.load(target_path, "", ResourceLoader.CACHE_MODE_IGNORE)
        if not (existing is Theme):
            utils_script.log_error("Existing resource is not a Theme: " + target_path)
            return null
        return existing
    if not bool(params.get("create_if_missing", true)):
        utils_script.log_error("Theme does not exist: " + target_path)
        return null
    return Theme.new()

func _apply_type_items(theme: Theme, theme_type: String, spec: Variant, context: String) -> bool:
    if not (spec is Dictionary):
        utils_script.log_error(context + " must be a dictionary")
        return false
    var entry := spec as Dictionary

    var colors = entry.get("colors", {})
    if colors is Dictionary:
        for name in colors.keys():
            var color: Variant = _to_color(colors[name], "%s.colors.%s" % [context, str(name)])
            if not (color is Color):
                return false
            theme.set_color(str(name), theme_type, color)

    var constants = entry.get("constants", {})
    if constants is Dictionary:
        for name in constants.keys():
            theme.set_constant(str(name), theme_type, int(constants[name]))

    var font_sizes = entry.get("font_sizes", {})
    if font_sizes is Dictionary:
        for name in font_sizes.keys():
            theme.set_font_size(str(name), theme_type, int(font_sizes[name]))

    var fonts = entry.get("fonts", {})
    if fonts is Dictionary:
        for name in fonts.keys():
            var font = codec.decode(fonts[name], "%s.fonts.%s" % [context, str(name)])
            if not (font is Font):
                utils_script.log_error("%s.fonts.%s must resolve to a Font" % [context, str(name)])
                return false
            theme.set_font(str(name), theme_type, font)

    var icons = entry.get("icons", {})
    if icons is Dictionary:
        for name in icons.keys():
            var icon = codec.decode(icons[name], "%s.icons.%s" % [context, str(name)])
            if not (icon is Texture2D):
                utils_script.log_error("%s.icons.%s must resolve to a Texture2D" % [context, str(name)])
                return false
            theme.set_icon(str(name), theme_type, icon)

    var styleboxes = entry.get("styleboxes", {})
    if styleboxes is Dictionary:
        for name in styleboxes.keys():
            var box: Variant = _to_stylebox(styleboxes[name], "%s.styleboxes.%s" % [context, str(name)])
            if not (box is StyleBox):
                return false
            theme.set_stylebox(str(name), theme_type, box)
    return true

func _to_color(raw: Variant, context: String) -> Variant:
    if raw is String:
        var text := str(raw)
        if not Color.html_is_valid(text.trim_prefix("#")):
            utils_script.log_error(context + " is not a valid hex color: " + text)
            return null
        return Color.html(text)
    var decoded = codec.decode(raw, context)
    if decoded is Color:
        return decoded
    utils_script.log_error(context + " must be a hex string or typed Color")
    return null

func _to_stylebox(spec: Variant, context: String) -> Variant:
    # Explicit resource reference or typed construction goes through the codec.
    if spec is Dictionary and (spec.has("__resource") or spec.has("__resource_type")):
        var decoded = codec.decode(spec, context)
        if decoded is StyleBox:
            return decoded
        utils_script.log_error(context + " must resolve to a StyleBox")
        return null
    if spec is String and str(spec) == "empty":
        return StyleBoxEmpty.new()
    if not (spec is Dictionary):
        utils_script.log_error(context + " must be a StyleBoxFlat shorthand, {\"__resource_type\":...}, or \"empty\"")
        return null

    # Flat shorthand -> StyleBoxFlat with hex colors and *_all convenience keys.
    var box := StyleBoxFlat.new()
    for key in (spec as Dictionary).keys():
        var value = (spec as Dictionary)[key]
        match str(key):
            "corner_radius":
                box.set_corner_radius_all(int(value))
            "border_width":
                box.set_border_width_all(int(value))
            "content_margin":
                box.set_content_margin_all(float(value))
            "expand_margin":
                box.set_expand_margin_all(float(value))
            _:
                if not _has_property(box, str(key)):
                    utils_script.log_error("%s: StyleBoxFlat has no property %s" % [context, str(key)])
                    return null
                if str(key).ends_with("_color"):
                    var color: Variant = _to_color(value, "%s.%s" % [context, str(key)])
                    if not (color is Color):
                        return null
                    box.set(str(key), color)
                else:
                    box.set(str(key), codec.decode(value, "%s.%s" % [context, str(key)]))
    return box

func _has_property(target: Object, property_name: String) -> bool:
    for property_info in target.get_property_list():
        if str(property_info.get("name", "")) == property_name:
            return true
    return false

func _ensure_parent_directory(path: String) -> bool:
    var absolute_parent := ProjectSettings.globalize_path(path.get_base_dir())
    var error := DirAccess.make_dir_recursive_absolute(absolute_parent)
    if error != OK and error != ERR_ALREADY_EXISTS:
        utils_script.log_error("Failed to create resource directory: " + absolute_parent)
        return false
    return true

func _normalize_res_path(path_value: Variant) -> String:
    var path := str(path_value).strip_edges().replace("\\", "/")
    if path.is_empty():
        return ""
    if path.begins_with("res://"):
        return path
    return "res://" + path.trim_prefix("/")
