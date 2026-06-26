# ambient_audio.gd
# Autoload singleton (registered as "AmbientAudio"). Background MUSIC + AMBIENCE that
# cross-fade by scene MOOD (menu / town / dungeon / combat). It listens to
# SceneManager.scene_loaded and picks a mood from the scene path, so the score shifts
# automatically as the player moves between the overworld, dungeons, and the arena.
#
# Audio files are OPTIONAL and discovered by CONVENTION — drop a looping .ogg at:
#     res://assets/audio/music/<mood>.ogg     (background track)
#     res://assets/audio/ambient/<mood>.ogg   (ambience bed: wind, cave drips, town hum...)
# where <mood> is one of: menu, town, dungeon, combat. If a file for the current mood is
# missing, that layer just fades to silence — no error. So this works as pure hooks today
# and "lights up" the moment you add tracks; no code change needed to enable music.
#
# Routing: music plays on the "Music" bus and ambience on "Ambient" (see
# default_bus_layout.tres), both sent to Master — so the pause menu's master volume governs
# everything and a future settings panel can add per-layer sliders. If those buses are ever
# absent we fall back to Master so audio still plays.
#
# NOTE: intentionally NO class_name — the autoload is registered under the name
# "AmbientAudio", and a matching class_name would collide with that global.

extends Node

## Where mood tracks are looked up, by convention <dir>/<mood>.ogg.
const MUSIC_DIR: String = "res://assets/audio/music/"
const AMBIENT_DIR: String = "res://assets/audio/ambient/"
## Cross-fade duration between moods, in seconds.
const FADE_TIME: float = 1.5
## Target levels for each layer when fully faded in (music sits under ambience-and-SFX).
const MUSIC_VOLUME_DB: float = -8.0
const AMBIENT_VOLUME_DB: float = -14.0
## Effectively-silent floor we fade out to before stopping a player.
const SILENT_DB: float = -60.0

var _music_players: Array[AudioStreamPlayer] = []   # two, ping-ponged for cross-fade
var _music_active: int = 0                           # index of the currently-audible music player
var _music_tween: Tween

var _ambient_players: Array[AudioStreamPlayer] = []  # two, ping-ponged for cross-fade
var _ambient_active: int = 0
var _ambient_tween: Tween

var _current_mood: StringName = &""

func _ready() -> void:
	# ALWAYS so cross-fade tweens keep running while the tree is paused (menus, dialogue).
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_players()
	SceneManager.scene_loaded.connect(_on_scene_loaded)
	# Boot shows the title screen first, before any gameplay scene loads.
	set_mood(&"menu")

func _build_players() -> void:
	var music_bus: StringName = _bus_or_master(&"Music")
	var ambient_bus: StringName = _bus_or_master(&"Ambient")
	for i in 2:
		_music_players.append(_make_player(music_bus))
		_ambient_players.append(_make_player(ambient_bus))

func _make_player(bus: StringName) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = SILENT_DB
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p

# Use the named bus if the project defines it, else Master so audio still plays.
func _bus_or_master(bus_name: StringName) -> StringName:
	if AudioServer.get_bus_index(bus_name) != -1:
		return bus_name
	return &"Master"

# --- Public API ------------------------------------------------------------

## Switch to a mood, cross-fading music + ambience to that mood's tracks (or to silence when a
## track file isn't present). No-op if already on that mood, so repeated scene loads of the same
## kind don't restart the score.
func set_mood(mood: StringName) -> void:
	if mood == _current_mood:
		return
	_current_mood = mood
	_music_active = _crossfade(_music_players, _music_active, _music_tween, _load_audio(MUSIC_DIR, mood), MUSIC_VOLUME_DB)
	_music_tween = _last_tween
	_ambient_active = _crossfade(_ambient_players, _ambient_active, _ambient_tween, _load_audio(AMBIENT_DIR, mood), AMBIENT_VOLUME_DB)
	_ambient_tween = _last_tween

## The current mood (&"" before the first set_mood / after stop_all).
func current_mood() -> StringName:
	return _current_mood

## Fade everything to silence (e.g. for a cutscene). A following set_mood resumes normally.
func stop_all() -> void:
	_current_mood = &""
	_music_active = _crossfade(_music_players, _music_active, _music_tween, null, MUSIC_VOLUME_DB)
	_music_tween = _last_tween
	_ambient_active = _crossfade(_ambient_players, _ambient_active, _ambient_tween, null, AMBIENT_VOLUME_DB)
	_ambient_tween = _last_tween

# --- Mood routing ----------------------------------------------------------

func _on_scene_loaded(scene_path: String) -> void:
	set_mood(_mood_for_scene(scene_path))

# Map a scene path to a mood. Dungeons and the combat arena get their own beds; everything else
# (town/overworld/dev scenes) is "town". Mirrors death_screen's path-based dungeon test.
func _mood_for_scene(path: String) -> StringName:
	var p: String = path.to_lower()
	if p.contains("dungeon"):
		return &"dungeon"
	if p.contains("arena") or p.contains("combat"):
		return &"combat"
	return &"town"

# --- Loading ---------------------------------------------------------------

# Load <dir>/<mood>.ogg if it exists, else null. Marks the stream to loop so a bed plays forever.
func _load_audio(dir: String, mood: StringName) -> AudioStream:
	var path: String = dir + String(mood) + ".ogg"
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path) as AudioStream
	# Ogg/MP3/WAV streams each expose a `loop` property; set it so background beds repeat.
	if stream != null and "loop" in stream:
		stream.set("loop", true)
	return stream

# --- Cross-fade ------------------------------------------------------------

# Holds the tween built by the most recent _crossfade call, so callers can store it (GDScript
# can't return two values cleanly without a Variant-typed container, which this project forbids).
var _last_tween: Tween = null

# Cross-fade a ping-pong player pair to `stream` (or to silence when null). Fades the currently
# audible player out and, if there's a new stream, the other player in; returns the new active
# index. The built tween is exposed via _last_tween for the caller to retain/kill next time.
func _crossfade(players: Array[AudioStreamPlayer], active: int, prev_tween: Tween, stream: AudioStream, target_db: float) -> int:
	# Kill any still-running fade for this layer before starting a new one.
	if prev_tween and prev_tween.is_valid():
		prev_tween.kill()
	var outgoing: AudioStreamPlayer = players[active]
	var incoming: AudioStreamPlayer = players[1 - active]
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(outgoing, "volume_db", SILENT_DB, FADE_TIME)
	var new_active: int = active
	if stream != null:
		incoming.stream = stream
		incoming.volume_db = SILENT_DB
		incoming.play()
		tween.tween_property(incoming, "volume_db", target_db, FADE_TIME)
		new_active = 1 - active
	# Stop the faded-out player once the fade completes, so it isn't left running silently.
	tween.set_parallel(false)
	tween.tween_callback(outgoing.stop)
	_last_tween = tween
	return new_active
