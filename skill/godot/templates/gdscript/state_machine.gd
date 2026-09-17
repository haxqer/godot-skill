# state_machine.gd — node-based finite state machine. Every child that extends
# State (state.gd) becomes a state, keyed by its node name. States ask for a
# switch with request_transition(&"Run"); nothing else drives the machine.
#
# Expected scene tree (node name : type):
#   Player : CharacterBody2D
#     StateMachine : Node             <- attach this script here
#       Idle : Node                   (extends State)
#       Run : Node                    (extends State)
#       Jump : Node                   (extends State)
#   unique_name_in_owner: not needed on any node.
#
# Autoload: no. Declares `class_name StateMachine`; run
#   godot --headless --path /absolute/path/to/project --import
# after copying this file and state.gd, before validating anything that uses them.
#
# Input actions: none (the individual states read input).
#
# Attach with:
#   scene_batch '{"scene_path":"scenes/player.tscn","actions":[
#     {"type":"attach_script","node_path":"root/StateMachine","script_path":"scripts/state_machine.gd"}]}'
class_name StateMachine
extends Node

signal state_changed(from_state: StringName, to_state: StringName)

## The state entered on ready. Leave empty to use the first State child.
@export var initial_state: State
## The node the states act on. Defaults to this machine's parent.
@export var agent: Node

var current_state: State = null

var _states: Dictionary = {}


func _ready() -> void:
	if agent == null:
		agent = get_parent()

	var first: State = null
	for child in get_children():
		var state := child as State
		if state == null:
			continue
		state.agent = agent
		_states[state.name] = state
		state.transition_requested.connect(_on_transition_requested)
		if first == null:
			first = state

	if initial_state != null:
		first = initial_state
	if first == null:
		push_error("StateMachine on '%s' has no State children — add at least one." % name)
		return
	transition_to(first.name)


func _process(delta: float) -> void:
	if current_state != null:
		current_state.update(delta)


func _physics_process(delta: float) -> void:
	if current_state != null:
		current_state.physics_update(delta)


## Switch to the child State whose node name is `next_state_name`.
func transition_to(next_state_name: StringName) -> void:
	if not _states.has(next_state_name):
		push_error("StateMachine has no child State named '%s'. Children: %s" % [next_state_name, _states.keys()])
		return
	var next_state: State = _states[next_state_name]
	if next_state == current_state:
		return

	var previous_name: StringName = &""
	if current_state != null:
		previous_name = current_state.name
		current_state.exit()

	current_state = next_state
	current_state.enter(previous_name)
	state_changed.emit(previous_name, next_state_name)


func _on_transition_requested(next_state_name: StringName) -> void:
	transition_to(next_state_name)
