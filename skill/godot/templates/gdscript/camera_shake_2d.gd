# camera_shake_2d.gd — trauma-based Camera2D shake. Callers add trauma; the
# camera squares it (so small hits barely register), samples smooth noise for
# the offset and roll, and decays back to zero and stops processing.
#
# Expected scene tree (node name : type):
#   Camera2D : Camera2D               <- attach this script here
#   Usually a child of the player, or a standalone camera following one.
#   unique_name_in_owner: mark the camera unique (`%Camera2D`) when other
#   scripts need to reach it without knowing the path.
#
# Autoload: no.
#
# Input actions: none.
#
# Attach with:
#   scene_batch '{"scene_path":"scenes/level.tscn","actions":[
#     {"type":"attach_script","node_path":"root/Camera2D","script_path":"scripts/camera_shake_2d.gd","script_properties":{"decay":4.0}}]}'
# Then, from a hit reaction: %Camera2D.add_trauma(0.5)
extends Camera2D

## Trauma lost per second. Higher = snappier recovery.
@export var decay: float = 4.0
@export var max_offset: Vector2 = Vector2(24.0, 16.0)
@export var max_roll_degrees: float = 2.0
## How fast the noise is sampled — higher is buzzier, lower is a slow sway.
@export var noise_speed: float = 40.0

var _trauma: float = 0.0
var _time: float = 0.0
var _noise: FastNoiseLite = null


func _ready() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = randi()
	_noise.frequency = 0.5
	set_process(false)


## Add 0.0 – 1.0 of trauma. Small hits ≈ 0.2, a boss slam ≈ 0.8.
func add_trauma(amount: float) -> void:
	if amount <= 0.0:
		return
	_trauma = clampf(_trauma + amount, 0.0, 1.0)
	set_process(true)


func _process(delta: float) -> void:
	_time += delta * noise_speed
	_trauma = maxf(_trauma - decay * delta, 0.0)

	# Squaring the trauma is the whole trick: shake ramps up fast at high
	# trauma and fades out gently instead of stopping dead.
	var shake: float = _trauma * _trauma
	offset = Vector2(
		max_offset.x * shake * _noise.get_noise_2d(_time, 0.0),
		max_offset.y * shake * _noise.get_noise_2d(0.0, _time))
	rotation = deg_to_rad(max_roll_degrees) * shake * _noise.get_noise_2d(_time, _time)

	if _trauma <= 0.0:
		offset = Vector2.ZERO
		rotation = 0.0
		set_process(false)
