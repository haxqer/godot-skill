# enemy_patrol_2d.gd — ground enemy that walks a patrol. With `patrol_points`
# filled it ping-pongs (or loops) between them; with the array empty it walks
# until a RayCast2D reports a wall or the floor ahead running out.
#
# Expected scene tree (node name : type):
#   Enemy : CharacterBody2D           <- attach this script here
#     CollisionShape2D : CollisionShape2D
#     Sprite2D : Sprite2D
#     EdgeCheck : RayCast2D           (position ≈ (10, 0), target_position (0, 20))
#     WallCheck : RayCast2D           (position (0, 0), target_position (14, 0))
#     Health : Node                   (health.gd — optional)
#     Hurtbox : Area2D                (hurtbox.gd — optional)
#   Both RayCast2D nodes must have enabled = true.
#   unique_name_in_owner: not needed on any node.
#
# Autoload: no.
#
# Input actions: none.
#
# Attach with:
#   scene_batch '{"scene_path":"scenes/enemy.tscn","actions":[
#     {"type":"attach_script","node_path":"root","script_path":"scripts/enemy_patrol_2d.gd","script_properties":{"speed":60.0,"ping_pong":true}}]}'
extends CharacterBody2D

signal turned(direction: int)

@export var speed: float = 60.0
## World-space X/Y stops. Leave empty to patrol by raycast instead.
@export var patrol_points: Array[Vector2] = []
## true = walk back and forth, false = loop back to the first point.
@export var ping_pong: bool = true
@export var arrive_distance: float = 4.0

@onready var _sprite: Sprite2D = $Sprite2D
@onready var _edge_ray: RayCast2D = $EdgeCheck
@onready var _wall_ray: RayCast2D = $WallCheck

var _gravity: float = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
var _index: int = 0
var _step: int = 1
var _direction: int = 1


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += _gravity * delta

	if patrol_points.is_empty():
		_patrol_by_rays()
	else:
		_patrol_by_points()

	velocity.x = float(_direction) * speed
	_sprite.flip_h = _direction < 0
	move_and_slide()


func _patrol_by_points() -> void:
	var target: Vector2 = patrol_points[_index]
	if absf(global_position.x - target.x) <= arrive_distance:
		_advance_index()
		target = patrol_points[_index]
	_set_direction(1 if target.x > global_position.x else -1)


func _advance_index() -> void:
	var count: int = patrol_points.size()
	if count <= 1:
		return
	if ping_pong:
		if _index + _step < 0 or _index + _step >= count:
			_step = -_step
		_index += _step
	else:
		_index = (_index + 1) % count
	_index = clampi(_index, 0, count - 1)


func _patrol_by_rays() -> void:
	# The edge ray points down just ahead of the feet: it stops colliding one
	# step before the platform ends, which is the moment to turn around.
	if _wall_ray.is_colliding():
		_set_direction(-_direction)
	elif is_on_floor() and not _edge_ray.is_colliding():
		_set_direction(-_direction)


func _set_direction(next_direction: int) -> void:
	if next_direction == 0 or next_direction == _direction:
		return
	_direction = next_direction
	_edge_ray.position.x = absf(_edge_ray.position.x) * float(_direction)
	_wall_ray.target_position.x = absf(_wall_ray.target_position.x) * float(_direction)
	turned.emit(_direction)
