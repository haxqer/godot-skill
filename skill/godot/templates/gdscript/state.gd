# state.gd — base class for one state of a node-based state machine. Subclass it
# for every state; the machine (state_machine.gd) finds them as its children.
#
# Expected scene tree (node name : type):
#   Player : CharacterBody2D
#     StateMachine : Node             (state_machine.gd)
#       Idle : Node                   (a script that `extends State`)
#       Run : Node                    (a script that `extends State`)
#   The state's node NAME is the identifier used by request_transition().
#   unique_name_in_owner: not needed on any node.
#
# Autoload: no. This file declares `class_name State`, so run
#   godot --headless --path /absolute/path/to/project --import
# once after copying it, or every script that says `extends State` fails with
# `Identifier "State" not declared in the current scope`.
#
# Input actions: none.
#
# Attach with (a concrete subclass, not this file):
#   scene_batch '{"scene_path":"scenes/player.tscn","actions":[{"type":"attach_script","node_path":"root/StateMachine/Idle","script_path":"scripts/states/idle_state.gd"}]}'
class_name State
extends Node

## Emitted by request_transition(). state_machine.gd connects to it.
signal transition_requested(next_state_name: StringName)

## The node the state acts on — the machine assigns it before the first enter().
var agent: Node = null


## Override. Called once when the machine switches into this state.
func enter(_previous_state_name: StringName) -> void:
	pass


## Override. Called once when the machine switches out of this state.
func exit() -> void:
	pass


## Override. Called from the machine's _process while this state is current.
func update(_delta: float) -> void:
	pass


## Override. Called from the machine's _physics_process while this state is current.
func physics_update(_delta: float) -> void:
	pass


## Ask the machine to switch. Pass the *node name* of the target state.
func request_transition(next_state_name: StringName) -> void:
	transition_requested.emit(next_state_name)
