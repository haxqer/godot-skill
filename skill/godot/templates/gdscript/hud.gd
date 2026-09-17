# hud.gd — in-game HUD controller. It reads nothing per frame: every label is
# updated from a GameManager signal, and the health bar from a Health component
# handed to it by the level.
#
# Expected scene tree (node name : type) — build it with the In-Game HUD
# skeleton in references/game_ui.md:
#   HUD : CanvasLayer                 <- attach this script here (layer = 1)
#     TopLeft : MarginContainer
#       Vitals : VBoxContainer
#         HealthBar : ProgressBar     unique_name_in_owner = true  (%HealthBar)
#         LivesLabel : Label          unique_name_in_owner = true  (%LivesLabel)
#     TopRight : MarginContainer
#       ScoreLabel : Label            unique_name_in_owner = true  (%ScoreLabel)
#   The three %-nodes MUST have unique_name_in_owner set, or `%Name` returns null.
#
# Autoload: needs `GameManager` registered. Uses `Health` (health.gd), so run
#   godot --headless --path /absolute/path/to/project --import
# after copying health.gd.
#
# Input actions: none.
#
# Attach with:
#   scene_batch '{"scene_path":"scenes/hud.tscn","actions":[
#     {"type":"configure_node","node_path":"root/TopRight/ScoreLabel","unique_name_in_owner":true},
#     {"type":"attach_script","node_path":"root","script_path":"scripts/hud.gd"}]}'
# Then, from the level script: %HUD.bind_health($Player/Health)
extends CanvasLayer

@onready var _score_label: Label = %ScoreLabel
@onready var _lives_label: Label = %LivesLabel
@onready var _health_bar: ProgressBar = %HealthBar

var _health: Health = null


func _ready() -> void:
	GameManager.score_changed.connect(_on_score_changed)
	GameManager.lives_changed.connect(_on_lives_changed)
	GameManager.game_over.connect(_on_game_over)
	# Signals only fire on change, so paint the current values once here.
	_on_score_changed(GameManager.score)
	_on_lives_changed(GameManager.lives)


## Point the health bar at a Health component. Safe to call again on respawn.
func bind_health(health: Health) -> void:
	if health == null:
		return
	if _health != null:
		_health.damaged.disconnect(_on_health_changed)
		_health.healed.disconnect(_on_health_changed)
	_health = health
	_health.damaged.connect(_on_health_changed)
	_health.healed.connect(_on_health_changed)
	_health_bar.max_value = float(_health.max_health)
	_health_bar.value = float(_health.current_health)


func _on_health_changed(_amount: int, current: int) -> void:
	_health_bar.value = float(current)


func _on_score_changed(score: int) -> void:
	_score_label.text = "SCORE %06d" % score


func _on_lives_changed(lives: int) -> void:
	_lives_label.text = "LIVES %d" % lives


func _on_game_over() -> void:
	_score_label.text = "GAME OVER  %06d" % GameManager.score
