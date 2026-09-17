# pause_menu.gd — CanvasLayer overlay that toggles on ui_cancel, pauses the
# tree, and keeps working while paused because its process_mode is ALWAYS.
#
# Expected scene tree (node name : type) — build it with the Pause And Settings
# skeleton in references/game_ui.md:
#   PauseMenu : CanvasLayer           <- attach this script here (layer = 10)
#     PauseRoot : Control             unique_name_in_owner = true  (%PauseRoot)
#       Dim : ColorRect
#       Center : CenterContainer
#         Dialog : PanelContainer
#           Body : VBoxContainer
#             ResumeButton : Button   unique_name_in_owner = true  (%ResumeButton)
#             QuitButton : Button     unique_name_in_owner = true  (%QuitButton)
#   The three %-nodes MUST have unique_name_in_owner set.
#
# Autoload: needs `SceneTransition` registered (for Quit To Title).
#
# Input actions: ui_cancel (built in — Esc). No project_batch call needed.
#
# Attach with:
#   scene_batch '{"scene_path":"scenes/pause_menu.tscn","actions":[
#     {"type":"configure_node","node_path":"root","properties":{"layer":10,"process_mode":2}},
#     {"type":"configure_node","node_path":"root/PauseRoot","unique_name_in_owner":true},
#     {"type":"attach_script","node_path":"root","script_path":"scripts/pause_menu.gd"}]}'
extends CanvasLayer

signal paused_changed(is_paused: bool)

@export var title_scene: String = "res://scenes/main_menu.tscn"

@onready var _root: Control = %PauseRoot
@onready var _resume_button: Button = %ResumeButton
@onready var _quit_button: Button = %QuitButton

var _is_paused: bool = false


func _ready() -> void:
	# PROCESS_MODE_ALWAYS is what keeps this menu alive once the tree pauses.
	# Without it the buttons freeze the instant the pause takes effect.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	_resume_button.pressed.connect(set_game_paused.bind(false))
	_quit_button.pressed.connect(_on_quit_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	set_game_paused(not _is_paused)


func set_game_paused(value: bool) -> void:
	if _is_paused == value:
		return
	_is_paused = value
	get_tree().paused = value
	_root.visible = value
	if value:
		_resume_button.grab_focus()
	paused_changed.emit(value)


func is_game_paused() -> bool:
	return _is_paused


func _on_quit_pressed() -> void:
	set_game_paused(false)
	await SceneTransition.change_scene(title_scene)
