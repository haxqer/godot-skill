extends Control

@export var screen_id := "unset"

func _on_cancel_pressed() -> void:
    screen_id = "cancelled"
