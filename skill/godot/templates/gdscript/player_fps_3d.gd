# player_fps_3d.gd — first-person CharacterBody3D controller: mouse look with a
# clamped pitch, sprint, jump, and gravity read from project settings. Captures
# the mouse on ready; Esc releases it, a click re-captures it.
#
# Expected scene tree (node name : type):
#   Player : CharacterBody3D          <- attach this script here
#     CollisionShape3D : CollisionShape3D   (shape = CapsuleShape3D, height 1.8)
#     CameraPivot : Node3D                  (position.y = 1.6 — eye height)
#       Camera3D : Camera3D
#   unique_name_in_owner: not needed on any node.
#
# Autoload: no.
#
# Input actions required: move_left, move_right, move_forward, move_back, jump,
# sprint (ui_cancel is built in). Create them with:
#   project_batch '{"actions":[
#     {"type":"add_input_action","action_name":"move_forward","replace":true},
#     {"type":"add_input_event","action_name":"move_forward","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":87}}},
#     {"type":"add_input_action","action_name":"move_back","replace":true},
#     {"type":"add_input_event","action_name":"move_back","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":83}}},
#     {"type":"add_input_action","action_name":"sprint","replace":true},
#     {"type":"add_input_event","action_name":"sprint","event":{"__resource_type":"InputEventKey","properties":{"physical_keycode":4194325}}}]}'
#   (move_left = 65, move_right = 68, jump = 32 — same shape as the 2D player.)
#
# Attach with:
#   scene_batch '{"scene_path":"scenes/player.tscn","actions":[{"type":"attach_script","node_path":"root","script_path":"scripts/player_fps_3d.gd"}]}'
extends CharacterBody3D

@export var speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.0025
@export var pitch_limit_degrees: float = 89.0
@export var capture_mouse_on_ready: bool = true

@onready var _pivot: Node3D = $CameraPivot
@onready var _camera: Camera3D = $CameraPivot/Camera3D

var _gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))


func _ready() -> void:
	_camera.current = true
	if capture_mouse_on_ready:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion != null and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# Yaw turns the body, pitch turns only the pivot: rotating the body on
		# X would tip the collision capsule over.
		rotate_y(-motion.relative.x * mouse_sensitivity)
		var limit: float = deg_to_rad(pitch_limit_degrees)
		_pivot.rotation.x = clampf(_pivot.rotation.x - motion.relative.y * mouse_sensitivity, -limit, limit)
		return

	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= _gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity

	var input_dir: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var target_speed: float = sprint_speed if Input.is_action_pressed("sprint") else speed

	if direction.length_squared() > 0.0:
		velocity.x = direction.x * target_speed
		velocity.z = direction.z * target_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, target_speed)
		velocity.z = move_toward(velocity.z, 0.0, target_speed)

	move_and_slide()
