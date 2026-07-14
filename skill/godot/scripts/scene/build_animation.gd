class_name GodotSkillBuildAnimation
extends RefCounted

# Builds an Animation resource from declarative track/key data, then saves it
# standalone and/or registers it on an AnimationPlayer inside a scene through
# an AnimationLibrary (the only way AnimationMixer exposes animations in 4.x).
#
# Value-track paths follow Godot's "NodePath:property" convention relative to
# the AnimationPlayer's root_node (its parent by default), e.g.
# "Sprite2D:position" or ".:modulate".

var scene_editor_script = preload("../core/scene_editor.gd")
var utils_script = preload("../core/utils.gd")
var codec_script = preload("../core/variant_codec.gd")

const LOOP_MODES = {
    "none": Animation.LOOP_NONE,
    "linear": Animation.LOOP_LINEAR,
    "pingpong": Animation.LOOP_PINGPONG
}
const UPDATE_MODES = {
    "continuous": Animation.UPDATE_CONTINUOUS,
    "discrete": Animation.UPDATE_DISCRETE,
    "capture": Animation.UPDATE_CAPTURE
}
const INTERPOLATIONS = {
    "nearest": Animation.INTERPOLATION_NEAREST,
    "linear": Animation.INTERPOLATION_LINEAR,
    "cubic": Animation.INTERPOLATION_CUBIC
}

func execute(params: Dictionary) -> void:
    var animation_name := str(params.get("animation_name", "")).strip_edges()
    if animation_name.is_empty():
        utils_script.log_error("build_animation requires animation_name")
        return

    var animation := _build_animation(params)
    if animation == null:
        return

    var saved_path := ""
    if params.has("resource_save_path"):
        saved_path = _normalize_res_path(params.get("resource_save_path", ""))
        if saved_path.is_empty():
            utils_script.log_error("resource_save_path cannot be empty")
            return
        if not _ensure_parent_directory(saved_path):
            return
        var save_error := ResourceSaver.save(animation, saved_path)
        if save_error != OK:
            utils_script.log_error("Failed to save Animation %s: %s" % [saved_path, error_string(save_error)])
            return

    var attached := false
    if params.has("scene_path"):
        if not _attach_to_player(params, animation_name, animation):
            return
        attached = true

    if saved_path.is_empty() and not attached:
        utils_script.log_error("build_animation requires resource_save_path or scene_path; nothing was written")
        return

    print(JSON.stringify({
        "ok": true,
        "animation_name": animation_name,
        "length": animation.length,
        "track_count": animation.get_track_count(),
        "resource_save_path": saved_path,
        "attached_to_scene": attached
    }))

func _build_animation(params: Dictionary) -> Animation:
    var codec = codec_script.new()
    var animation := Animation.new()
    animation.length = max(float(params.get("length", 1.0)), 0.001)
    if params.has("step"):
        animation.step = max(float(params.get("step", 0.1)), 0.0)

    var loop_mode := str(params.get("loop_mode", "none")).to_lower()
    if not LOOP_MODES.has(loop_mode):
        utils_script.log_error("Unsupported loop_mode: " + loop_mode)
        return null
    animation.loop_mode = LOOP_MODES[loop_mode]

    var tracks = params.get("tracks", [])
    if not (tracks is Array) or tracks.is_empty():
        utils_script.log_error("build_animation requires a non-empty tracks array")
        return null

    for track_index in range(tracks.size()):
        var raw_track = tracks[track_index]
        if not (raw_track is Dictionary):
            utils_script.log_error("tracks entries must be dictionaries")
            return null
        if not _add_track(animation, raw_track as Dictionary, track_index, codec):
            return null
    return animation

func _add_track(animation: Animation, track: Dictionary, label_index: int, codec: RefCounted) -> bool:
    var track_path := str(track.get("path", "")).strip_edges()
    if track_path.is_empty():
        utils_script.log_error("tracks[%d] requires path" % label_index)
        return false

    var keys = track.get("keys", [])
    if not (keys is Array) or keys.is_empty():
        utils_script.log_error("tracks[%d] requires a non-empty keys array" % label_index)
        return false

    var track_type := str(track.get("type", "value")).to_lower()
    var track_idx := -1
    match track_type:
        "value":
            track_idx = animation.add_track(Animation.TYPE_VALUE)
        "method":
            track_idx = animation.add_track(Animation.TYPE_METHOD)
        "bezier":
            track_idx = animation.add_track(Animation.TYPE_BEZIER)
        _:
            utils_script.log_error("tracks[%d] has unsupported type: %s" % [label_index, track_type])
            return false

    animation.track_set_path(track_idx, NodePath(track_path))

    if track.has("interpolation"):
        var interpolation := str(track.get("interpolation", "linear")).to_lower()
        if not INTERPOLATIONS.has(interpolation):
            utils_script.log_error("tracks[%d] has unsupported interpolation: %s" % [label_index, interpolation])
            return false
        animation.track_set_interpolation_type(track_idx, INTERPOLATIONS[interpolation])

    if track_type == "value" and track.has("update_mode"):
        var update_mode := str(track.get("update_mode", "continuous")).to_lower()
        if not UPDATE_MODES.has(update_mode):
            utils_script.log_error("tracks[%d] has unsupported update_mode: %s" % [label_index, update_mode])
            return false
        animation.value_track_set_update_mode(track_idx, UPDATE_MODES[update_mode])

    for key_index in range(keys.size()):
        var raw_key = keys[key_index]
        if not (raw_key is Dictionary):
            utils_script.log_error("tracks[%d].keys entries must be dictionaries" % label_index)
            return false
        var key = raw_key as Dictionary
        var time := float(key.get("time", 0.0))
        var context := "tracks[%d].keys[%d]" % [label_index, key_index]

        match track_type:
            "value":
                if not key.has("value"):
                    utils_script.log_error(context + " requires value")
                    return false
                var value = codec.decode(key.get("value"), context + ".value")
                if value == null and key.get("value") != null:
                    return false
                animation.track_insert_key(track_idx, time, value, float(key.get("transition", 1.0)))
            "method":
                var method_name := str(key.get("method", ""))
                if method_name.is_empty():
                    utils_script.log_error(context + " requires method")
                    return false
                var args = codec.decode(key.get("args", []), context + ".args")
                if not (args is Array):
                    return false
                animation.track_insert_key(track_idx, time, {"method": StringName(method_name), "args": args})
            "bezier":
                if not key.has("value"):
                    utils_script.log_error(context + " requires value")
                    return false
                var in_handle = _coerce_handle(key.get("in_handle", []))
                var out_handle = _coerce_handle(key.get("out_handle", []))
                animation.bezier_track_insert_key(track_idx, time, float(key.get("value", 0.0)), in_handle, out_handle)
    return true

func _attach_to_player(params: Dictionary, animation_name: String, animation: Animation) -> bool:
    var editor = scene_editor_script.new()
    if not editor.open_existing_scene(params.get("scene_path", "")):
        return false

    var player_path := str(params.get("player_node_path", "root/AnimationPlayer"))
    var player_node = editor.scene_root.get_node_or_null(NodePath(_strip_root_prefix(player_path, editor)))
    if player_node == null and _strip_root_prefix(player_path, editor).is_empty():
        player_node = editor.scene_root

    if player_node == null:
        if not bool(params.get("create_player_if_missing", true)):
            utils_script.log_error("AnimationPlayer not found: " + player_path)
            editor.cleanup()
            return false
        var relative_path := _strip_root_prefix(player_path, editor)
        var leaf_name := relative_path.get_file()
        var parent_path := relative_path.get_base_dir()
        var added := editor.add_node({
            "parent_node_path": "root" if parent_path.is_empty() else "root/" + parent_path,
            "node_type": "AnimationPlayer",
            "node_name": leaf_name
        })
        if not added:
            editor.cleanup()
            return false
        player_node = editor.scene_root.get_node_or_null(NodePath(relative_path))

    if not (player_node is AnimationPlayer):
        utils_script.log_error("Node is not an AnimationPlayer: " + player_path)
        editor.cleanup()
        return false

    var player := player_node as AnimationPlayer
    var library_name := StringName(str(params.get("library", "")))
    var library: AnimationLibrary = null
    if player.has_animation_library(library_name):
        library = player.get_animation_library(library_name)
    else:
        library = AnimationLibrary.new()
        var add_error := player.add_animation_library(library_name, library)
        if add_error != OK:
            utils_script.log_error("Failed to add animation library: " + error_string(add_error))
            editor.cleanup()
            return false

    if library.has_animation(animation_name):
        library.remove_animation(animation_name)
    var animation_error := library.add_animation(StringName(animation_name), animation)
    if animation_error != OK:
        utils_script.log_error("Failed to add animation to library: " + error_string(animation_error))
        editor.cleanup()
        return false

    var saved := editor.save_scene(params.get("save_path", ""))
    editor.cleanup()
    return saved

func _strip_root_prefix(path: String, editor) -> String:
    var trimmed := path.strip_edges()
    if trimmed == "root" or trimmed == "." or trimmed.is_empty():
        return ""
    if trimmed.begins_with("root/"):
        return trimmed.trim_prefix("root/")
    var root_name := str(editor.scene_root.name)
    if trimmed.begins_with(root_name + "/"):
        return trimmed.trim_prefix(root_name + "/")
    return trimmed

func _coerce_handle(raw_value: Variant) -> Vector2:
    if raw_value is Dictionary:
        return Vector2(float(raw_value.get("x", 0.0)), float(raw_value.get("y", 0.0)))
    if raw_value is Array and raw_value.size() == 2:
        return Vector2(float(raw_value[0]), float(raw_value[1]))
    return Vector2.ZERO

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
