# hitbox.gd — the dealing half of the damage pair. Put it on an attack, a
# projectile or a spike; it finds a Hurtbox by area overlap and hands it damage.
# Teams stop a hitbox from hurting its own side.
#
# Expected scene tree (node name : type):
#   Bullet : Area2D
#     Hitbox : Area2D                 <- attach this script here
#       CollisionShape2D : CollisionShape2D
#   (A hitbox can also be the root itself; attach to "root" then.)
#   unique_name_in_owner: not needed on any node.
#
# Autoload: no. Declares `class_name Hitbox` and annotates `Hurtbox`; run
#   godot --headless --path /absolute/path/to/project --import
# after copying hitbox.gd + hurtbox.gd + health.gd, before validating.
#
# Input actions: none.
#
# Attach with:
#   scene_batch '{"scene_path":"scenes/bullet.tscn","actions":[
#     {"type":"attach_script","node_path":"root/Hitbox","script_path":"scripts/hitbox.gd","script_properties":{"damage":1,"team":"player","one_shot":true}}]}'
class_name Hitbox
extends Area2D

signal hit(hurtbox: Hurtbox)

@export var damage: int = 1
## Hurtboxes on this team are ignored, so an attack never hurts its owner.
@export var team: String = "player"
## When true the hitbox stops after one landed hit until rearm() is called.
@export var one_shot: bool = false

var _spent: bool = false


func _ready() -> void:
	monitoring = true
	add_to_group(&"hitbox")
	area_entered.connect(_on_area_entered)


func rearm() -> void:
	_spent = false


func _on_area_entered(area: Area2D) -> void:
	if one_shot and _spent:
		return
	var hurtbox := area as Hurtbox
	if hurtbox == null or hurtbox.team == team:
		return
	if hurtbox.take_hit(damage):
		_spent = true
		hit.emit(hurtbox)
