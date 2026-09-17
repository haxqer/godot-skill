# health.gd — reusable health component. Add it as a child of anything that can
# be hurt; hurtbox.gd routes damage into it. Owns nothing but the number, the
# invulnerability window, and the signals other nodes bind to.
#
# Expected scene tree (node name : type):
#   Enemy : CharacterBody2D
#     Health : Node                   <- attach this script here
#   unique_name_in_owner: mark Health as unique (`%Health`) when a sibling
#   script needs it without knowing the exact path.
#
# Autoload: no. Declares `class_name Health`; run
#   godot --headless --path /absolute/path/to/project --import
# after copying it, before any script that annotates a variable as `Health`.
#
# Input actions: none.
#
# Attach with:
#   scene_batch '{"scene_path":"scenes/enemy.tscn","actions":[
#     {"type":"add_node","parent_node_path":"root","node_type":"Node","node_name":"Health"},
#     {"type":"attach_script","node_path":"root/Health","script_path":"scripts/health.gd","script_properties":{"max_health":3}}]}'
class_name Health
extends Node

signal damaged(amount: int, current: int)
signal healed(amount: int, current: int)
signal died

@export var max_health: int = 3
## Seconds of immunity after a hit lands. 0.0 disables the window.
@export var invulnerability_time: float = 0.5

var current_health: int = 0

var _invulnerable_for: float = 0.0


func _ready() -> void:
	current_health = max_health
	set_process(false)


func _process(delta: float) -> void:
	_invulnerable_for = maxf(_invulnerable_for - delta, 0.0)
	if _invulnerable_for <= 0.0:
		set_process(false)


func is_alive() -> bool:
	return current_health > 0


func is_invulnerable() -> bool:
	return _invulnerable_for > 0.0


## Returns true when the hit actually landed, so a hitbox can tell a blocked
## hit (invulnerable, already dead) from a real one.
func apply_damage(amount: int) -> bool:
	if amount <= 0 or not is_alive() or is_invulnerable():
		return false
	current_health = maxi(current_health - amount, 0)
	if invulnerability_time > 0.0:
		_invulnerable_for = invulnerability_time
		set_process(true)
	damaged.emit(amount, current_health)
	if current_health == 0:
		died.emit()
	return true


func heal(amount: int) -> void:
	if amount <= 0 or not is_alive():
		return
	current_health = mini(current_health + amount, max_health)
	healed.emit(amount, current_health)


func reset() -> void:
	current_health = max_health
	_invulnerable_for = 0.0
	set_process(false)


## 0.0 – 1.0, safe to feed straight into a ProgressBar or shader parameter.
func ratio() -> float:
	if max_health <= 0:
		return 0.0
	return float(current_health) / float(max_health)
