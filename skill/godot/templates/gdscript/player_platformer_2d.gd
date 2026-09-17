# player_platformer_2d.gd — side-view CharacterBody2D controller with gravity
# read from project settings, coyote time, jump buffering and a short hop.
#
# Expected scene tree (node name : type) — create it before attaching:
#   Player : CharacterBody2D          <- attach this script here
#     CollisionShape2D : CollisionShape2D   (shape = CapsuleShape2D)
#     Sprite2D : Sprite2D
#   unique_name_in_owner: not needed on any node.
#
# Autoload: no.
#
# Input actions required: move_left, move_right, jump. Create them with:
#   project_batch '{"actions":[
#     {"type":"add_input_action","action_name":"move_left","replace":true},
#     {"type":"add_input_event","action_name":"move_left","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":65}}},
#     {"type":"add_input_action","action_name":"move_right","replace":true},
#     {"type":"add_input_event","action_name":"move_right","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":68}}},
#     {"type":"add_input_action","action_name":"jump","replace":true},
#     {"type":"add_input_event","action_name":"jump","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":32}}}]}'
#
# Attach with:
#   scene_batch '{"scene_path":"scenes/player.tscn","actions":[{"type":"attach_script","node_path":"root","script_path":"scripts/player_platformer_2d.gd"}]}'
extends CharacterBody2D

signal jumped
signal landed

@export var speed: float = 220.0
@export var acceleration: float = 1800.0
@export var friction: float = 2200.0
@export var jump_velocity: float = -380.0
@export var coyote_time: float = 0.12
@export var jump_buffer_time: float = 0.12
@export var short_hop_factor: float = 0.45

@onready var _sprite: Sprite2D = $Sprite2D

var _gravity: float = float(ProjectSettings.get_setting("physics/2d/default_gravity", 980.0))
var _coyote_timer: float = 0.0
var _buffer_timer: float = 0.0
var _was_on_floor: bool = false


func _physics_process(delta: float) -> void:
	var on_floor: bool = is_on_floor()
	if on_floor:
		_coyote_timer = coyote_time
	else:
		velocity.y += _gravity * delta
		_coyote_timer -= delta

	if Input.is_action_just_pressed("jump"):
		_buffer_timer = jump_buffer_time
	else:
		_buffer_timer -= delta

	if _buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = jump_velocity
		_buffer_timer = 0.0
		_coyote_timer = 0.0
		jumped.emit()

	# Releasing jump early cuts the rise, which is what makes the jump feel
	# controllable instead of fixed-height.
	if Input.is_action_just_released("jump") and velocity.y < 0.0:
		velocity.y *= short_hop_factor

	var direction: float = Input.get_axis("move_left", "move_right")
	if absf(direction) > 0.01:
		velocity.x = move_toward(velocity.x, direction * speed, acceleration * delta)
		_sprite.flip_h = direction < 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)

	move_and_slide()

	var landed_now: bool = is_on_floor()
	if landed_now and not _was_on_floor:
		landed.emit()
	_was_on_floor = landed_now
