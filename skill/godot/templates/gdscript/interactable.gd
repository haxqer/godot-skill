# interactable.gd — Area2D that shows a prompt while a player stands in it and
# runs interact() on the interact action. Subclass it and override interact()
# for doors, chests, NPCs and levers.
#
# Expected scene tree (node name : type):
#   Chest : Area2D                    <- attach this script (or a subclass) here
#     CollisionShape2D : CollisionShape2D
#     Sprite2D : Sprite2D
#     Prompt : Label                  (position it above the sprite)
#   The player body must be in the group "player" (configure_node `groups`).
#   unique_name_in_owner: not needed on any node.
#
# Autoload: no. Declares `class_name Interactable`; run
#   godot --headless --path /absolute/path/to/project --import
# after copying it, before any script that says `extends Interactable`.
#
# Input actions: interact. Create it with:
#   project_batch '{"actions":[
#     {"type":"add_input_action","action_name":"interact","replace":true},
#     {"type":"add_input_event","action_name":"interact","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":69}}}]}'
#
# Attach with:
#   scene_batch '{"scene_path":"scenes/chest.tscn","actions":[
#     {"type":"attach_script","node_path":"root","script_path":"scripts/interactable.gd","script_properties":{"prompt_text":"Open","one_shot":true}}]}'
class_name Interactable
extends Area2D

signal interacted(by: Node2D)
signal focus_changed(focused: bool)

@export var prompt_text: String = "Interact"
## true = usable once (a chest), false = usable forever (a lever).
@export var one_shot: bool = false

@onready var _prompt: Label = $Prompt

var _used: bool = false
var _nearby: Array[Node2D] = []


func _ready() -> void:
	_prompt.text = prompt_text
	_prompt.visible = false
	add_to_group(&"interactable")
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func can_interact() -> bool:
	return not (one_shot and _used)


## Override this in a subclass. Call `super.interact(by)` first so the prompt
## and the `interacted` signal still behave.
func interact(by: Node2D) -> void:
	if not can_interact():
		return
	_used = true
	interacted.emit(by)
	_set_focused(not _nearby.is_empty() and can_interact())


func _on_body_entered(body: Node2D) -> void:
	if not body.is_in_group(&"player"):
		return
	if not _nearby.has(body):
		_nearby.append(body)
	_set_focused(can_interact())


func _on_body_exited(body: Node2D) -> void:
	_nearby.erase(body)
	_set_focused(not _nearby.is_empty() and can_interact())


func _unhandled_input(event: InputEvent) -> void:
	if _nearby.is_empty() or not can_interact():
		return
	if not event.is_action_pressed("interact"):
		return
	get_viewport().set_input_as_handled()
	interact(_nearby[0])


func _set_focused(value: bool) -> void:
	if _prompt.visible == value:
		return
	_prompt.visible = value
	focus_changed.emit(value)
