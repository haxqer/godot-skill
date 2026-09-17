# game_manager.gd — autoload holding run-scoped state: score, lives, high score.
# It owns no nodes and knows nothing about the UI; the HUD binds to its signals.
#
# Expected scene tree: none. This is a script autoload, not a scene.
#
# Autoload: YES, as `GameManager`. Register it with:
#   project_batch '{"actions":[
#     {"type":"add_autoload","autoload_name":"GameManager","path":"res://scripts/game_manager.gd"}]}'
#   Do NOT also give this file a `class_name GameManager` — a class_name that
#   matches an autoload fails with `Class "GameManager" hides an autoload singleton`.
#
# Input actions: none.
#
# Attach with: nothing to attach — autoloads are registered, not attached.
# Call it from anywhere as `GameManager.add_score(10)`.
extends Node

signal score_changed(score: int)
signal lives_changed(lives: int)
signal game_started
signal game_over

@export var starting_lives: int = 3

var score: int = 0
var lives: int = 0
var high_score: int = 0


func _ready() -> void:
	reset()


## Start a fresh run. Call it before loading the first level, not after.
func reset() -> void:
	score = 0
	lives = starting_lives
	score_changed.emit(score)
	lives_changed.emit(lives)
	game_started.emit()


func add_score(amount: int) -> void:
	if amount == 0:
		return
	score = maxi(score + amount, 0)
	high_score = maxi(high_score, score)
	score_changed.emit(score)


func lose_life() -> void:
	if lives <= 0:
		return
	lives -= 1
	lives_changed.emit(lives)
	if lives == 0:
		game_over.emit()


func gain_life() -> void:
	lives += 1
	lives_changed.emit(lives)


## Everything worth writing to a save file, in one dictionary.
func to_save_data() -> Dictionary:
	return {"score": score, "lives": lives, "high_score": high_score}


## The inverse of to_save_data(). Missing keys fall back to the current values,
## so an older save file still loads.
func from_save_data(data: Dictionary) -> void:
	score = int(data.get("score", score))
	lives = int(data.get("lives", lives))
	high_score = int(data.get("high_score", high_score))
	score_changed.emit(score)
	lives_changed.emit(lives)
