# dialog_box.gd — typewriter dialog. Feed it an Array[String]; ui_accept either
# completes the current line instantly or advances to the next one, and the box
# hides itself and emits `finished` after the last line.
#
# Expected scene tree (node name : type) — build it with the Dialog Box
# skeleton in references/game_ui.md:
#   DialogBox : CanvasLayer           <- attach this script here (layer = 5)
#     DialogRoot : Control            unique_name_in_owner = true  (%DialogRoot)
#       Anchor : MarginContainer
#         Box : PanelContainer
#           Body : VBoxContainer
#             SpeakerLabel : Label        unique_name_in_owner = true
#             BodyLabel : RichTextLabel   unique_name_in_owner = true
#                                         (bbcode_enabled, fit_content, autowrap_mode 3)
#   The three %-nodes MUST have unique_name_in_owner set.
#
# Autoload: no (register it as one if every scene should reach the same box).
#
# Input actions: ui_accept (built in — Space/Enter). No project_batch call needed.
#
# Attach with:
#   scene_batch '{"scene_path":"scenes/dialog_box.tscn","actions":[
#     {"type":"configure_node","node_path":"root/DialogRoot","unique_name_in_owner":true},
#     {"type":"attach_script","node_path":"root","script_path":"scripts/dialog_box.gd","script_properties":{"characters_per_second":40.0}}]}'
extends CanvasLayer

signal line_shown(index: int)
signal finished

@export var characters_per_second: float = 40.0

@onready var _root: Control = %DialogRoot
@onready var _speaker_label: Label = %SpeakerLabel
@onready var _body_label: RichTextLabel = %BodyLabel

var _lines: Array[String] = []
var _index: int = 0
var _typing: bool = false
var _revealed: float = 0.0


func _ready() -> void:
	_root.visible = false
	set_process(false)


func show_lines(lines: Array[String], speaker: String = "") -> void:
	if lines.is_empty():
		return
	_lines = lines
	_index = 0
	_speaker_label.text = speaker
	_speaker_label.visible = not speaker.is_empty()
	_root.visible = true
	_show_current_line()


func is_open() -> bool:
	return _root.visible


func _show_current_line() -> void:
	# visible_characters drives the reveal; rewriting `text` per character
	# re-parses the BBCode every frame and drops any [color] tags mid-word.
	_body_label.text = _lines[_index]
	_body_label.visible_characters = 0
	_revealed = 0.0
	_typing = true
	set_process(true)
	line_shown.emit(_index)


func _process(delta: float) -> void:
	if not _typing:
		return
	_revealed += characters_per_second * delta
	_body_label.visible_characters = int(_revealed)
	if _body_label.visible_characters >= _body_label.get_total_character_count():
		_finish_line()


func _finish_line() -> void:
	_typing = false
	_body_label.visible_characters = -1
	set_process(false)


func _unhandled_input(event: InputEvent) -> void:
	if not _root.visible or not event.is_action_pressed("ui_accept"):
		return
	get_viewport().set_input_as_handled()
	if _typing:
		_finish_line()
		return
	_index += 1
	if _index < _lines.size():
		_show_current_line()
		return
	_root.visible = false
	_lines = []
	finished.emit()
