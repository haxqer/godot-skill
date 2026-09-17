# scene_transition.gd — autoload CanvasLayer that fades to black, swaps the
# scene, and fades back. It builds its own ColorRect at runtime, so there is no
# scene to author and nothing to wire.
#
# Expected scene tree: none. This is a script autoload, not a scene.
#
# Autoload: YES, as `SceneTransition`. Register it with:
#   project_batch '{"actions":[
#     {"type":"add_autoload","autoload_name":"SceneTransition","path":"res://scripts/scene_transition.gd"}]}'
#
# Input actions: none.
#
# Attach with: nothing to attach. change_scene() is a coroutine, so call it as
#   await SceneTransition.change_scene("res://scenes/level_1.tscn")
# from a function that is allowed to await (a signal handler is).
extends CanvasLayer

signal scene_changed(scene_path: String)

@export var fade_time: float = 0.35
@export var fade_color: Color = Color(0.0, 0.0, 0.0, 1.0)

var _fade: ColorRect = null
var _busy: bool = false


func _ready() -> void:
	# Above every gameplay layer, and running while the tree is paused so a
	# transition started from a pause menu still animates.
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS

	_fade = ColorRect.new()
	_fade.name = "Fade"
	_fade.color = fade_color
	# Without MOUSE_FILTER_IGNORE the overlay eats every click in the game.
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.modulate.a = 0.0
	_fade.visible = false
	add_child(_fade)


func change_scene(scene_path: String) -> void:
	if _busy:
		return
	_busy = true
	await fade_to_black()
	var error: Error = get_tree().change_scene_to_file(scene_path)
	if error != OK:
		push_error("SceneTransition: cannot load '%s' (%s). Check the res:// path and that the scene is saved." % [scene_path, error_string(error)])
	else:
		scene_changed.emit(scene_path)
	await fade_from_black()
	_busy = false


func fade_to_black() -> void:
	_fade.visible = true
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0, fade_time)
	await tween.finished


func fade_from_black() -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 0.0, fade_time)
	await tween.finished
	_fade.visible = false
