# minigame_manager.gd
# Autoload singleton (registered in Project Settings -> Autoload as
# "MinigameManager"). The single entry point for playing arcade minigames.
#
# An ArcadeCabinet prop calls MinigameManager.play(<its minigame scene>) when the
# player interacts. The manager then:
#   1. Pauses the world: get_tree().paused = true + Clock.pause() (the Clock runs
#      with PROCESS_MODE_ALWAYS, so the tree pause won't stop it on its own —
#      same dance as the pause menu).
#   2. Frees the mouse so the player can click the game's UI.
#   3. Instances the minigame as a child of this autoload (the game is a
#      CanvasLayer at a high layer, so it draws over everything).
#   4. Waits for the game's `finished(score, reward)` signal, then grants
#      GameState.add_money(reward), frees the game, unpauses, and recaptures the
#      mouse.
#
# Only one game can be open at a time (guarded by `_active`). This node itself
# runs with PROCESS_MODE_ALWAYS so it keeps working while the tree is paused.

extends Node

## The minigame currently on screen, or null. Public so callers (an arcade prop,
## the pause menu's escape etiquette) can check whether a game is running.
var _active: Minigame = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

## True while a minigame is open. Useful for other UI (e.g. the pause menu)
## deciding whether to grab Escape.
func is_playing() -> bool:
	return _active != null

# --- Public API ------------------------------------------------------------

## Play a minigame from a PackedScene whose root extends Minigame. No-op if a
## game is already running (you can't stack cabinets).
func play(minigame_scene: PackedScene) -> void:
	if _active != null:
		return
	if minigame_scene == null:
		push_warning("MinigameManager.play: null scene.")
		return

	# Once-per-in-game-day gate. The arcade is a small bonus, not the economy, so
	# a given cabinet may only be played once per day. State lives in
	# GameState.flags (which is SAVED). Guarded so a missing GameState never blocks.
	var game_state = get_node_or_null("/root/GameState")
	if game_state != null:
		var gate_key := _day_gate_key(minigame_scene)
		if game_state.get_flag(gate_key, -1) == game_state.day:
			var feed = get_node_or_null("/root/NotificationFeed")
			if feed != null and feed.has_method("notify"):
				feed.notify("Come back tomorrow.")
			return

	var instance := minigame_scene.instantiate()
	if instance is not Minigame:
		push_warning("MinigameManager.play: scene root is not a Minigame, ignoring.")
		instance.queue_free()
		return

	_active = instance as Minigame
	# Mark this cabinet as played today now that the game is actually starting.
	if game_state != null:
		game_state.set_flag(_day_gate_key(minigame_scene), game_state.day)
	# Connect first so a game that finishes on its very first frame is handled.
	_active.finished.connect(_on_finished, CONNECT_ONE_SHOT)
	add_child(_active)

	# Pause the world. Clock has PROCESS_MODE_ALWAYS so do it explicitly too.
	get_tree().paused = true
	if Clock:
		Clock.pause()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

# --- Daily gate helpers ----------------------------------------------------

## Per-cabinet flag key so each distinct minigame scene has its own daily cooldown
## (playing whack doesn't lock simon). Falls back to a shared key if the scene has
## no resource_path (e.g. a runtime-built PackedScene).
func _day_gate_key(minigame_scene: PackedScene) -> StringName:
	var path := minigame_scene.resource_path
	if path.is_empty():
		return &"minigame_last_day"
	return StringName("minigame_last_day_" + path)

# --- Signal handling -------------------------------------------------------

func _on_finished(score: int, reward: int) -> void:
	# `score` isn't spent here, but kept in the signature so games can report it
	# (high-score tracking can hook the same signal later).
	if reward > 0:
		GameState.add_money(reward)

	if is_instance_valid(_active):
		_active.queue_free()
	_active = null

	# Resume the world and re-capture the mouse for first-person play.
	get_tree().paused = false
	if Clock:
		Clock.resume()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
