# audio_manager.gd — autoload owning a pool of AudioStreamPlayers for SFX and a
# two-player crossfade for music. Overlapping sounds never cut each other off,
# and a music change never pops.
#
# Expected scene tree: none — it builds its players in _ready().
#
# Autoload: YES, as `AudioManager`. Register it with:
#   project_batch '{"actions":[
#     {"type":"add_autoload","autoload_name":"AudioManager","path":"res://scripts/audio_manager.gd"}]}'
#   Create the buses first (otherwise every player falls back to Master):
#   setup_audio_buses '{"buses":[{"name":"Master","volume_db":0.0},
#     {"name":"Music","send":"Master","volume_db":-6.0},
#     {"name":"SFX","send":"Master","volume_db":-3.0}],
#     "save_path":"audio/default_bus_layout.tres","set_project_setting":true}'
#
# Input actions: none.
#
# Attach with: nothing to attach. Use it as
#   AudioManager.play_sfx(preload("res://audio/hit.wav"))
#   AudioManager.play_music(preload("res://audio/level.ogg"))
extends Node

@export var sfx_voices: int = 8
@export var music_fade_time: float = 1.0
## Volume treated as silence during a crossfade.
@export var silence_db: float = -60.0

var _sfx_players: Array[AudioStreamPlayer] = []
var _music_a: AudioStreamPlayer = null
var _music_b: AudioStreamPlayer = null
var _music_active: AudioStreamPlayer = null
var _next_voice: int = 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in sfx_voices:
		var player := AudioStreamPlayer.new()
		player.name = "Sfx%d" % index
		player.bus = _bus_or_master(&"SFX")
		add_child(player)
		_sfx_players.append(player)
	_music_a = _make_music_player("MusicA")
	_music_b = _make_music_player("MusicB")
	_music_active = _music_a


## Plays on the next free-ish voice, round-robin. Never allocates at runtime.
func play_sfx(stream: AudioStream, volume_db: float = 0.0, pitch_scale: float = 1.0) -> void:
	if stream == null or _sfx_players.is_empty():
		return
	var player: AudioStreamPlayer = _sfx_players[_next_voice]
	_next_voice = (_next_voice + 1) % _sfx_players.size()
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.play()


## Crossfades to `stream`. Calling it with the track already playing is a no-op.
func play_music(stream: AudioStream, fade_time: float = -1.0) -> void:
	if stream == null or _music_active == null:
		return
	if _music_active.stream == stream and _music_active.playing:
		return

	var duration: float = music_fade_time if fade_time < 0.0 else fade_time
	var outgoing: AudioStreamPlayer = _music_active
	var incoming: AudioStreamPlayer = _music_b if _music_active == _music_a else _music_a
	incoming.stream = stream
	incoming.volume_db = silence_db
	incoming.play()
	_music_active = incoming

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(incoming, "volume_db", 0.0, duration)
	tween.tween_property(outgoing, "volume_db", silence_db, duration)
	tween.chain().tween_callback(outgoing.stop)


func stop_music(fade_time: float = 0.5) -> void:
	if _music_active == null:
		return
	var player: AudioStreamPlayer = _music_active
	var tween := create_tween()
	tween.tween_property(player, "volume_db", silence_db, fade_time)
	tween.tween_callback(player.stop)


func _make_music_player(player_name: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = _bus_or_master(&"Music")
	player.volume_db = silence_db
	add_child(player)
	return player


# Assigning a bus that does not exist silently mutes the player, so fall back
# to Master and say so instead of shipping a game with no sound.
func _bus_or_master(bus_name: StringName) -> StringName:
	if AudioServer.get_bus_index(bus_name) != -1:
		return bus_name
	push_warning("AudioManager: no '%s' audio bus — using Master. Run setup_audio_buses." % bus_name)
	return &"Master"
