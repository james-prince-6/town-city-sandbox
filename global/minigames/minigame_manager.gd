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

	var instance := minigame_scene.instantiate()
	if instance is not Minigame:
		push_warning("MinigameManager.play: scene root is not a Minigame, ignoring.")
		instance.queue_free()
		return

	_active = instance as Minigame
	# Connect first so a game that finishes on its very first frame is handled.
	_active.finished.connect(_on_finished, CONNECT_ONE_SHOT)
	add_child(_active)

	# Pause the world. Clock has PROCESS_MODE_ALWAYS so do it explicitly too.
	get_tree().paused = true
	if Clock:
		Clock.pause()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

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
