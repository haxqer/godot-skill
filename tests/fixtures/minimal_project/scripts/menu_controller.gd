extends Control

@export var menu_title := "Untitled"
@export var click_count := 0

func _on_start_pressed(extra = null) -> void:
    click_count += 1
    if extra != null:
        menu_title = str(extra)
