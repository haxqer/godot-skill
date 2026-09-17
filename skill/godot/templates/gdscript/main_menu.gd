# main_menu.gd — title screen controller. Binds the four menu buttons, greys out
# Continue when there is no save, and grabs focus so a gamepad can navigate the
# menu from the first frame.
#
# Expected scene tree (node name : type) — build it with the Title Screen
# skeleton in references/game_ui.md, then rename the buttons to match:
#   MainMenu : Control                <- attach this script here
#     ... containers ...
#       NewGameButton : Button        unique_name_in_owner = true  (%NewGameButton)
#       ContinueButton : Button       unique_name_in_owner = true  (%ContinueButton)
#       SettingsButton : Button       unique_name_in_owner = true  (%SettingsButton)
#       QuitButton : Button           unique_name_in_owner = true  (%QuitButton)
#   All four buttons MUST have unique_name_in_owner set, or `%Name` returns null.
#
# Autoload: needs `GameManager`, `SaveManager` and `SceneTransition` registered.
#
# Input actions: none beyond the built-in ui_* set.
#
# Attach with:
#   scene_batch '{"scene_path":"scenes/main_menu.tscn","actions":[
#     {"type":"configure_node","node_path":"root/Frame/Column/MenuSlot/Menu/NewGameButton","unique_name_in_owner":true},
#     {"type":"attach_script","node_path":"root","script_path":"scripts/main_menu.gd","script_properties":{"new_game_scene":"res://scenes/level_1.tscn"}}]}'
extends Control

@export var new_game_scene: String = "res://scenes/level_1.tscn"
@export var settings_scene: String = ""
@export var save_slot: int = 0

@onready var _new_game_button: Button = %NewGameButton
@onready var _continue_button: Button = %ContinueButton
@onready var _settings_button: Button = %SettingsButton
@onready var _quit_button: Button = %QuitButton


func _ready() -> void:
	_new_game_button.pressed.connect(_on_new_game_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)

	_continue_button.disabled = not SaveManager.has_save(save_slot)
	_settings_button.disabled = settings_scene.is_empty()
	# Without an explicit grab the menu has no focus and a gamepad cannot move.
	_new_game_button.grab_focus()


func _on_new_game_pressed() -> void:
	GameManager.reset()
	await SceneTransition.change_scene(new_game_scene)


func _on_continue_pressed() -> void:
	var data: Dictionary = SaveManager.load_game(save_slot)
	GameManager.from_save_data(data)
	var scene_path: String = str(data.get("scene_path", new_game_scene))
	await SceneTransition.change_scene(scene_path)


func _on_settings_pressed() -> void:
	if settings_scene.is_empty():
		return
	await SceneTransition.change_scene(settings_scene)


func _on_quit_pressed() -> void:
	get_tree().quit()
