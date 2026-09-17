# save_manager.gd — autoload writing versioned JSON save slots under user://.
# Every read is defensive: a missing file, a truncated file, or a file full of
# garbage returns an empty Dictionary instead of crashing the game.
#
# Expected scene tree: none. This is a script autoload, not a scene.
#
# Autoload: YES, as `SaveManager`. Register it with:
#   project_batch '{"actions":[
#     {"type":"add_autoload","autoload_name":"SaveManager","path":"res://scripts/save_manager.gd"}]}'
#
# Input actions: none.
#
# Attach with: nothing to attach. Use it as
#   SaveManager.save_game(GameManager.to_save_data(), 0)
#   var data: Dictionary = SaveManager.load_game(0)
extends Node

signal game_saved(slot: int)
signal game_loaded(slot: int)
signal save_failed(reason: String)

const SAVE_VERSION: int = 1
const SAVE_DIR: String = "user://saves"


func save_path(slot: int = 0) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]


func has_save(slot: int = 0) -> bool:
	return FileAccess.file_exists(save_path(slot))


func save_game(data: Dictionary, slot: int = 0) -> bool:
	var dir_error: Error = DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		_fail("cannot create %s (%s)" % [SAVE_DIR, error_string(dir_error)])
		return false

	var file: FileAccess = FileAccess.open(save_path(slot), FileAccess.WRITE)
	if file == null:
		_fail("cannot write %s (%s)" % [save_path(slot), error_string(FileAccess.get_open_error())])
		return false

	var payload: Dictionary = {
		"version": SAVE_VERSION,
		"saved_at": Time.get_datetime_string_from_system(true),
		"data": data,
	}
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	game_saved.emit(slot)
	return true


func load_game(slot: int = 0) -> Dictionary:
	if not has_save(slot):
		return {}

	var file: FileAccess = FileAccess.open(save_path(slot), FileAccess.READ)
	if file == null:
		_fail("cannot read %s (%s)" % [save_path(slot), error_string(FileAccess.get_open_error())])
		return {}
	var text: String = file.get_as_text()
	file.close()

	# JSON.parse_string returns Variant. `var x := JSON.parse_string(t)` is a
	# parse error in a stock project — always annotate it as Variant first.
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		_fail("%s is not a JSON object — delete the slot or restore a backup" % save_path(slot))
		return {}

	var payload: Dictionary = parsed
	var version: int = int(payload.get("version", 0))
	if version != SAVE_VERSION:
		push_warning("SaveManager: slot %d is version %d, this build writes %d. Migrate before trusting the values." % [slot, version, SAVE_VERSION])

	var raw: Variant = payload.get("data", {})
	var data: Dictionary = {}
	if raw is Dictionary:
		data = raw
	game_loaded.emit(slot)
	return data


func delete_save(slot: int = 0) -> void:
	if has_save(slot):
		var error: Error = DirAccess.remove_absolute(save_path(slot))
		if error != OK:
			_fail("cannot delete %s (%s)" % [save_path(slot), error_string(error)])


func _fail(reason: String) -> void:
	push_error("SaveManager: " + reason)
	save_failed.emit(reason)
