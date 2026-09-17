# hurtbox.gd — the receiving half of the damage pair. Sits on whatever can be
# hurt, carries a team so friendly fire is impossible, and forwards the damage
# into a Health component when one is wired up.
#
# Expected scene tree (node name : type):
#   Enemy : CharacterBody2D
#     Health : Node                   (health.gd)
#     Hurtbox : Area2D                <- attach this script here
#       CollisionShape2D : CollisionShape2D
#   `health_path` points at the Health node, relative to this Area2D.
#   unique_name_in_owner: not needed on any node.
#
# Autoload: no. Declares `class_name Hurtbox` and annotates `Health`; run
#   godot --headless --path /absolute/path/to/project --import
# after copying health.gd + hurtbox.gd, before validating.
#
# Input actions: none.
#
# Attach with:
#   scene_batch '{"scene_path":"scenes/enemy.tscn","actions":[
#     {"type":"attach_script","node_path":"root/Hurtbox","script_path":"scripts/hurtbox.gd",
#      "script_properties":{"team":"enemy","health_path":{"__type":"NodePath","value":"../Health"}}}]}'
class_name Hurtbox
extends Area2D

signal hurt(amount: int)
signal blocked

## Hitboxes only damage a hurtbox whose team differs from theirs.
@export var team: String = "enemy"
## Path to the Health component, relative to this node. Leave empty for a
## hurtbox that only reports hits (a training dummy, a breakable prop).
## It is a NodePath rather than an exported node so the dispatcher can set it
## without a live scene tree.
@export var health_path: NodePath = ^"../Health"

var health: Health = null


func _ready() -> void:
	# A hurtbox is detected, it does not detect: monitoring off saves the
	# physics server a pass, monitorable on is what lets hitboxes find it.
	monitoring = false
	monitorable = true
	add_to_group(&"hurtbox")
	if not health_path.is_empty():
		health = get_node_or_null(health_path) as Health


## Called by hitbox.gd. Returns true when the damage was accepted, so the
## hitbox knows whether to spend its one-shot charge.
func take_hit(amount: int) -> bool:
	if amount <= 0:
		blocked.emit()
		return false
	if health != null and not health.apply_damage(amount):
		blocked.emit()
		return false
	hurt.emit(amount)
	return true
