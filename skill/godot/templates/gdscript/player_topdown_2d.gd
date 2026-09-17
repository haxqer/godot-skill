# player_topdown_2d.gd — eight-direction top-down CharacterBody2D controller
# with acceleration/friction smoothing and a remembered facing direction.
#
# Expected scene tree (node name : type):
#   Player : CharacterBody2D          <- attach this script here
#     CollisionShape2D : CollisionShape2D   (shape = CircleShape2D)
#     Sprite2D : Sprite2D
#   unique_name_in_owner: not needed on any node.
#
# Autoload: no.
#
# Input actions required: move_left, move_right, move_up, move_down. Create them with:
#   project_batch '{"actions":[
#     {"type":"add_input_action","action_name":"move_left","replace":true},
#     {"type":"add_input_event","action_name":"move_left","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":65}}},
#     {"type":"add_input_action","action_name":"move_right","replace":true},
#     {"type":"add_input_event","action_name":"move_right","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":68}}},
#     {"type":"add_input_action","action_name":"move_up","replace":true},
#     {"type":"add_input_event","action_name":"move_up","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":87}}},
#     {"type":"add_input_action","action_name":"move_down","replace":true},
#     {"type":"add_input_event","action_name":"move_down","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":83}}}]}'
#
# Attach with:
#   scene_batch '{"scene_path":"scenes/player.tscn","actions":[{"type":"attach_script","node_path":"root","script_path":"scripts/player_topdown_2d.gd"}]}'
extends CharacterBody2D

signal moved(direction: Vector2)
signal stopped

@export var speed: float = 180.0
@export var acceleration: float = 1400.0
@export var friction: float = 1600.0

@onready var _sprite: Sprite2D = $Sprite2D

var _facing: Vector2 = Vector2.DOWN
var _was_moving: bool = false


func _physics_process(delta: float) -> void:
	# get_vector already normalises the diagonal, so diagonal movement is not
	# faster than cardinal movement. Never add the four axes by hand.
	var direction: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var moving: bool = direction.length_squared() > 0.0

	if moving:
		velocity = velocity.move_toward(direction * speed, acceleration * delta)
		_facing = direction
		if absf(direction.x) > 0.01:
			_sprite.flip_h = direction.x < 0.0
		moved.emit(direction)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
		if _was_moving:
			stopped.emit()

	_was_moving = moving
	move_and_slide()


## The last non-zero input direction. Use it to aim attacks or pick an
## idle animation that keeps facing where the player last walked.
func facing() -> Vector2:
	return _facing
