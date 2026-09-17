class_name GodotSkillInspectImage
extends RefCounted

# Reads an image file as numbers and ASCII (see core/image_describe.gd) so a
# caller that cannot look at pixels can still check that art exists, is the
# right size, is palette-limited, sits where it should, and changed (or did not)
# against a reference frame.
#
# Files are read with Image.load_from_file rather than load()/ResourceLoader, so
# freshly generated art works before `--import` has ever run, and screenshots
# living outside the project (absolute paths) work too.
#
# Describe results are read through _field() (and probed with `has(&"key")`)
# rather than `.get("literal")` because the dispatcher derives this op's allowed
# parameter list from exactly those literals — reading output keys that way
# would turn every one of them into a silently accepted parameter.

var utils_script = preload("../core/utils.gd")
var describe_script = preload("../core/image_describe.gd")

const IMAGE_EXTENSIONS = ["png", "jpg", "jpeg", "webp", "bmp", "tga", "svg", "exr", "hdr"]
# JPEG always rings around edges, so its default background tolerance is wide
# enough to keep codec noise out of content_bbox; everything else is exact.
const LOSSY_EXTENSIONS = ["jpg", "jpeg"]
const LOSSY_BACKGROUND_TOLERANCE = 0.12
const IMPORT_ARTEFACT_EXTENSIONS = ["ctex", "stex", "import", "md5"]
const EXPECT_KEYS = ["not_blank", "min_opaque_ratio", "max_unique_colors", "has_alpha", "width", "height", "max_diff_ratio", "frames_consistent"]


func execute(params: Dictionary) -> void:
    var output_format := str(params.get("format", "json")).strip_edges().to_lower()
    if output_format != "json" and output_format != "text":
        utils_script.log_error("inspect_image format must be \"json\" or \"text\"; got: " + output_format)
        return

    var expect_value: Variant = params.get("expect", {})
    if not (expect_value is Dictionary):
        utils_script.log_error("inspect_image expect must be an object, e.g. {\"not_blank\": true, \"min_opaque_ratio\": 0.1}")
        return
    var expect: Dictionary = expect_value
    for key in expect.keys():
        if not (str(key) in EXPECT_KEYS):
            utils_script.log_error("Unknown inspect_image expect key: %s (supported: %s)" % [str(key), ", ".join(EXPECT_KEYS)])
            return

    var options := {
        "ascii": bool(params.get("ascii", false)),
        "ascii_color": bool(params.get("ascii_color", false)),
        "ascii_width": int(params.get("ascii_width", 64)),
        "max_unique": int(params.get("max_unique", 4096))
    }
    var tolerance_value: Variant = params.get("background_tolerance", null)
    if tolerance_value != null:
        if not (tolerance_value is float or tolerance_value is int) or float(tolerance_value) < 0.0 or float(tolerance_value) > 1.0:
            utils_script.log_error("inspect_image background_tolerance must be a number from 0 (exact match) to 1; got: " + str(tolerance_value))
            return
    if params.has("compare_to"):
        var compare_path := _resolve_path(params.get("compare_to", ""))
        if compare_path.is_empty():
            utils_script.log_error("inspect_image compare_to is empty; pass a res:// or absolute path to the reference image")
            return
        var compare_image := _load_image(compare_path, "compare_to")
        if compare_image == null:
            return
        options["compare_to"] = compare_image

    var multi := params.has("image_paths")
    var targets := _collect_targets(params)
    if targets.is_empty():
        return

    var entries: Array = []
    var all_passed := true
    for target in targets:
        var path := str(target)
        var image := _load_image(path, "image_path")
        if image == null:
            return
        if tolerance_value == null:
            options["background_tolerance"] = _default_tolerance(path)
        else:
            options["background_tolerance"] = float(tolerance_value)
        var described: Dictionary = describe_script.describe(image, options)
        if described.has(&"error"):
            utils_script.log_error("inspect_image could not read %s: %s" % [path, str(_field(described, "error", ""))])
            return
        var entry := {"image_path": path}
        entry.merge(described)
        if entry.has(&"diff_error"):
            utils_script.log_error("inspect_image compare_to mismatch for %s: %s" % [path, str(_field(entry, "diff_error", ""))])
            all_passed = false
        var results: Array = []
        if not _check_image_expectations(expect, entry, path, results):
            all_passed = false
        entry["expect_results"] = results
        entry["expect_passed"] = _all_passed(results)
        entries.append(entry)

    var payload := {}
    if multi:
        var consistent := _frames_consistent(entries)
        payload["image_paths"] = targets
        payload["count"] = entries.size()
        payload["frames_consistent"] = consistent
        if consistent:
            payload["frame_size"] = _frame_size(entries)
        else:
            payload["frame_size"] = null
        payload["images"] = entries
        var frame_results: Array = []
        if expect.has("frames_consistent"):
            var wanted := bool(expect["frames_consistent"])
            var passed := consistent == wanted
            frame_results.append({"check": "frames_consistent", "expected": wanted, "actual": consistent, "passed": passed})
            if not passed:
                all_passed = false
                utils_script.log_error("inspect_image expect.frames_consistent failed: the frames are %s (%s) - every frame of a sequence must share one canvas size, so re-export the odd ones at the same width and height" % [
                    "consistent" if consistent else "inconsistent", _size_summary(entries)])
        payload["expect_results"] = frame_results
        payload["expect_passed"] = all_passed
    else:
        payload = entries[0]

    if output_format == "text":
        print(_as_text(payload, multi))
    else:
        print(JSON.stringify(payload))


func _collect_targets(params: Dictionary) -> Array:
    if params.has("image_paths"):
        var raw: Variant = params.get("image_paths", [])
        if not (raw is Array):
            utils_script.log_error("inspect_image image_paths must be an array of file or directory paths")
            return []
        var list: Array = raw
        if list.is_empty():
            utils_script.log_error("inspect_image image_paths is empty; pass at least one image file or a directory of frames")
            return []
        var targets: Array = []
        for item in list:
            var path := _resolve_path(item)
            if path.is_empty():
                utils_script.log_error("inspect_image image_paths entries cannot be empty")
                return []
            if _is_directory(path):
                var found := _images_in_directory(path)
                if found.is_empty():
                    utils_script.log_error("No images in directory %s (looked for %s); check the path or list the files explicitly" % [path, ", ".join(IMAGE_EXTENSIONS)])
                    return []
                targets.append_array(found)
            else:
                targets.append(path)
        return targets

    var single := _resolve_path(params.get("image_path", ""))
    if single.is_empty():
        utils_script.log_error("inspect_image requires image_path (a res:// or absolute path to a .png/.jpg/.webp), or image_paths for a list or a directory of frames")
        return []
    if _is_directory(single):
        utils_script.log_error("image_path %s is a directory; pass it as image_paths: [\"%s\"] to describe every frame in it" % [single, single])
        return []
    return [single]


func _images_in_directory(path: String) -> Array:
    var directory := DirAccess.open(path)
    if directory == null:
        utils_script.log_error("Could not open directory: " + path)
        return []
    var files: Array = []
    for file_name in directory.get_files():
        if str(file_name).get_extension().to_lower() in IMAGE_EXTENSIONS:
            files.append(path.path_join(str(file_name)))
    # Frame sequences are named frame_2.png / frame_10.png, so order them the way
    # a person reads them rather than the way ASCII sorts them.
    files.sort_custom(func(left: String, right: String) -> bool:
        return left.get_file().naturalnocasecmp_to(right.get_file()) < 0
    )
    return files


func _default_tolerance(path: String) -> float:
    if path.get_extension().to_lower() in LOSSY_EXTENSIONS:
        return LOSSY_BACKGROUND_TOLERANCE
    return 0.0


func _load_image(path: String, context: String) -> Image:
    var extension := path.get_extension().to_lower()
    if not (extension in IMAGE_EXTENSIONS):
        var hint := ""
        if extension in IMPORT_ARTEFACT_EXTENSIONS:
            hint = " - that is an import artefact, not the picture; pass the source file it was imported from (for .godot/imported/name.png-<hash>.ctex pass res://.../name.png)"
        utils_script.log_error("inspect_image %s has unsupported extension \"%s\": %s (supported: %s)%s" % [context, extension, path, ", ".join(IMAGE_EXTENSIONS), hint])
        return null
    var absolute := ProjectSettings.globalize_path(path)
    if not FileAccess.file_exists(absolute):
        utils_script.log_error("Image file does not exist: %s (project-relative paths resolve against res://; pass an absolute path for files outside the project)" % path)
        return null
    var image := Image.load_from_file(absolute)
    if image == null or image.is_empty():
        utils_script.log_error("Failed to read image data from %s; the file may be truncated or not an image - re-export it" % path)
        return null
    return image


func _check_image_expectations(expect: Dictionary, described: Dictionary, path: String, results: Array) -> bool:
    var passed := true
    for key in EXPECT_KEYS:
        if key == "frames_consistent" or not expect.has(key):
            continue
        var wanted: Variant = expect[key]
        var actual: Variant = null
        var ok := true
        var message := ""
        match key:
            "not_blank":
                actual = not bool(_field(described, "blank", false))
                ok = bool(actual) == bool(wanted)
                if bool(wanted):
                    message = "every pixel is identical (or fully transparent) - nothing was drawn, so check the node is visible, inside the viewport, and that the capture happened after the frame rendered"
                else:
                    message = "expected a blank image, but content is present"
            "min_opaque_ratio":
                actual = float(_field(described, "opaque_ratio", 0.0))
                ok = float(actual) >= float(wanted)
                message = "opaque_ratio %s is below %s - almost nothing is drawn; check alpha and visibility, or lower min_opaque_ratio if the subject really is that small" % [actual, wanted]
            "max_unique_colors":
                actual = int(_field(described, "unique_colors", 0))
                ok = int(actual) <= int(wanted)
                message = "%s colours found, %s allowed - the art is not palette-limited; re-export without smoothing and scale with nearest-neighbour" % [actual, wanted]
            "has_alpha":
                actual = bool(_field(described, "has_alpha", false))
                ok = bool(actual) == bool(wanted)
                message = "has_alpha is %s - re-export the PNG with a transparent background, or cut a flat background out with scripts/assets/chroma_key_cutout.py" % actual
            "width":
                actual = int(_field(described, "width", 0))
                ok = int(actual) == int(wanted)
                message = "image is %s px wide, expected %s - re-export at that canvas size, or fix the expectation" % [actual, wanted]
            "height":
                actual = int(_field(described, "height", 0))
                ok = int(actual) == int(wanted)
                message = "image is %s px tall, expected %s - re-export at that canvas size, or fix the expectation" % [actual, wanted]
            "max_diff_ratio":
                if not described.has(&"diff_ratio"):
                    ok = false
                    message = "no comparison was made - pass compare_to with a reference image of the same size"
                else:
                    actual = float(_field(described, "diff_ratio", 1.0))
                    ok = float(actual) <= float(wanted)
                    message = "%s of the pixels differ from compare_to, %s allowed - the render changed; print the ascii of both images to see where" % [actual, wanted]
        results.append({"check": key, "expected": wanted, "actual": actual, "passed": ok})
        if not ok:
            passed = false
            utils_script.log_error("inspect_image expect.%s failed for %s: %s" % [key, path, message])
    return passed


func _field(source: Dictionary, key: String, fallback: Variant) -> Variant:
    return source[key] if source.has(key) else fallback


func _all_passed(results: Array) -> bool:
    for result in results:
        if not bool(_field(result, "passed", false)):
            return false
    return true


func _frames_consistent(entries: Array) -> bool:
    if entries.size() < 2:
        return true
    var first: Dictionary = entries[0]
    for entry in entries:
        if int(_field(entry, "width", -1)) != int(_field(first, "width", -2)):
            return false
        if int(_field(entry, "height", -1)) != int(_field(first, "height", -2)):
            return false
    return true


func _frame_size(entries: Array) -> Dictionary:
    if entries.is_empty():
        return {}
    var first: Dictionary = entries[0]
    return {"width": int(_field(first, "width", 0)), "height": int(_field(first, "height", 0))}


func _size_summary(entries: Array) -> String:
    var parts: PackedStringArray = []
    for entry in entries:
        parts.append("%s %dx%d" % [
            str(_field(entry, "image_path", "")).get_file(),
            int(_field(entry, "width", 0)),
            int(_field(entry, "height", 0))
        ])
    return ", ".join(parts)


func _resolve_path(raw: Variant) -> String:
    var path := str(raw).strip_edges().replace("\\", "/")
    if path.is_empty():
        return ""
    if path.begins_with("res://") or path.begins_with("user://") or path.begins_with("/"):
        return path
    return "res://" + path


func _is_directory(path: String) -> bool:
    return DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))


func _as_text(payload: Dictionary, multi: bool) -> String:
    var lines: PackedStringArray = []
    if multi:
        lines.append("images: %d" % int(_field(payload, "count", 0)))
        lines.append("frames_consistent: %s" % str(bool(_field(payload, "frames_consistent", false))).to_lower())
        var size_value: Variant = _field(payload, "frame_size", null)
        if size_value is Dictionary:
            lines.append("frame_size: %dx%d" % [int(_field(size_value, "width", 0)), int(_field(size_value, "height", 0))])
        var images: Array = _field(payload, "images", [])
        for entry in images:
            lines.append("")
            lines.append_array(_entry_text(entry))
        var frame_results: Array = _field(payload, "expect_results", [])
        for result in frame_results:
            lines.append(_expect_line(result))
    else:
        lines.append_array(_entry_text(payload))
    return "\n".join(lines)


func _entry_text(entry: Dictionary) -> PackedStringArray:
    var lines: PackedStringArray = []
    lines.append("image_path: " + str(_field(entry, "image_path", "")))
    lines.append("size: %dx%d" % [int(_field(entry, "width", 0)), int(_field(entry, "height", 0))])
    lines.append("blank: " + str(bool(_field(entry, "blank", false))).to_lower())
    lines.append("has_alpha: " + str(bool(_field(entry, "has_alpha", false))).to_lower())
    lines.append("opaque_ratio: %s" % float(_field(entry, "opaque_ratio", 0.0)))
    var box_value: Variant = _field(entry, "content_bbox", null)
    if box_value is Dictionary:
        var normalized: Variant = _field(entry, "content_bbox_normalized", {})
        lines.append("content_bbox: x=%d y=%d w=%d h=%d (normalized x=%.3f y=%.3f w=%.3f h=%.3f)" % [
            int(_field(box_value, "x", 0)), int(_field(box_value, "y", 0)),
            int(_field(box_value, "w", 0)), int(_field(box_value, "h", 0)),
            float(_field(normalized, "x", 0.0)), float(_field(normalized, "y", 0.0)),
            float(_field(normalized, "w", 0.0)), float(_field(normalized, "h", 0.0))])
    else:
        lines.append("content_bbox: none (nothing differs from the background)")
    lines.append("mean_color: " + str(_field(entry, "mean_color", "")))
    var background_note := " (transparent)" if bool(_field(entry, "background_transparent", false)) else ""
    lines.append("background_color: %s%s" % [str(_field(entry, "background_color", "")), background_note])
    var swatches: PackedStringArray = []
    var dominant: Array = _field(entry, "dominant_colors", [])
    for item in dominant:
        swatches.append("%s %.1f%%" % [str(_field(item, "hex", "")), float(_field(item, "ratio", 0.0)) * 100.0])
    lines.append("dominant_colors: " + " ".join(swatches))
    lines.append("unique_colors: %d" % int(_field(entry, "unique_colors", 0)))
    var quadrants: Variant = _field(entry, "quadrants", {})
    lines.append("quadrants: top_left=%.1f%% top_right=%.1f%% bottom_left=%.1f%% bottom_right=%.1f%%" % [
        float(_field(quadrants, "top_left", 0.0)) * 100.0, float(_field(quadrants, "top_right", 0.0)) * 100.0,
        float(_field(quadrants, "bottom_left", 0.0)) * 100.0, float(_field(quadrants, "bottom_right", 0.0)) * 100.0])
    if entry.has(&"diff_ratio"):
        lines.append("diff_ratio: %s" % float(_field(entry, "diff_ratio", 0.0)))
    if entry.has(&"diff_error"):
        lines.append("diff_error: " + str(_field(entry, "diff_error", "")))
    var results: Array = _field(entry, "expect_results", [])
    for result in results:
        lines.append(_expect_line(result))
    if entry.has(&"ascii"):
        lines.append("ascii:")
        var rows: Array = _field(entry, "ascii", [])
        for row in rows:
            lines.append(str(row))
    if entry.has(&"ascii_color"):
        lines.append("ascii_color:")
        var color_rows: Array = _field(entry, "ascii_color", [])
        for row in color_rows:
            lines.append(str(row))
    return lines


func _expect_line(result: Dictionary) -> String:
    return "expect.%s: %s (expected %s, actual %s)" % [
        str(_field(result, "check", "")),
        "PASS" if bool(_field(result, "passed", false)) else "FAIL",
        str(_field(result, "expected", "")),
        str(_field(result, "actual", ""))
    ]
