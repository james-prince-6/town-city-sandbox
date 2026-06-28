# save_manager.gd
# Autoload singleton (registered as "SaveManager").
#
# The whole game already keeps its persistent state in autoloads, and each of
# those exposes capture_state()/restore_state(). SaveManager is just the
# coordinator: on save it asks every system for a snapshot Dictionary and writes
# them all to one file; on load it reads them back and hands each system its
# snapshot. Add a new system to SAVE_TARGETS and it's covered — no other changes.
#
# We use FileAccess.store_var/get_var (Godot's binary format) rather than JSON on
# purpose: it round-trips Godot types EXACTLY — StringName item ids stay
# StringNames, ints stay ints, Transform3D stays a Transform3D. JSON would coerce
# all of those to strings/floats and quietly corrupt inventory keys and counts.
#
# Quick controls (registered input actions): F5 quicksave, F9 quickload.

extends Node

## Bumped if the save format ever changes incompatibly, so load can refuse old files.
const SAVE_VERSION := 1
const SAVE_DIR := "user://saves/"

## Known-good scene to fall back to when a save's recorded location can't be loaded
## (e.g. an old save points at a scene that was since moved/deleted). Never leaves the
## player staring at a blank screen. Matches MainMenu's FIRST_SCENE.
const FALLBACK_SCENE := "res://stages/overworld/town_template.tscn"
## Spawn marker the player lands on when a dungeon save returns them to the overworld (mirrors
## death-in-dungeon, which uses the same town "from_dungeon" marker).
const DUNGEON_RETURN_SPAWN: StringName = &"from_dungeon"

signal saved(slot: int)
signal loaded(slot: int)
signal save_failed(reason: String)
signal load_failed(reason: String)

# Each entry: the key written to the file -> the autoload node that owns that
# slice of state. Order doesn't matter for save; on load we restore in this order.
@onready var _save_targets: Dictionary = {
	"game_state": GameState,
	"inventory": Inventory,
	"clock": Clock,
	"player_stats": PlayerStats,
	"hotbar": Hotbar,
	"reputation": Reputation,
	"quests": QuestSystem,
	"crafting": CraftingSystem,
	"progression": Progression,
	"npc_moods": NPCMoods,
	"house_upgrades": HouseUpgrades,
}

# Holds the player transform between a load's scene-change request and the new
# scene actually finishing loading.
var _pending_player_transform = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quicksave"):
		save_game(0)
	elif event.is_action_pressed("quickload"):
		load_game(0)

# --- Public API ------------------------------------------------------------

func slot_path(slot: int) -> String:
	return "%sslot_%d.save" % [SAVE_DIR, slot]

func has_save(slot: int = 0) -> bool:
	return FileAccess.file_exists(slot_path(slot))

## Stronger than has_save: the file must exist AND parse AND carry a compatible
## version — i.e. load_game() would actually succeed. Use this to gate "Continue" so a
## corrupt/old/incompatible save doesn't dangle a button that loads into a blank screen.
func has_loadable_save(slot: int = 0) -> bool:
	if not has_save(slot):
		return false
	var file := FileAccess.open(slot_path(slot), FileAccess.READ)
	if file == null:
		return false
	var data = file.get_var()
	file.close()
	# Mirror the validation in load_game(): must be a dict at the expected version.
	return typeof(data) == TYPE_DICTIONARY and data.get("version", -1) == SAVE_VERSION

## Snapshot every system + the player's location and write it to `slot`.
func save_game(slot: int = 0) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

	var systems := {}
	for key in _save_targets:
		systems[key] = _save_targets[key].capture_state()

	var data := {
		"version": SAVE_VERSION,
		"systems": systems,
		"location": _capture_location(),
	}

	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		var reason := "could not open %s for writing (err %d)" % [slot_path(slot), FileAccess.get_open_error()]
		push_warning("SaveManager: " + reason)
		save_failed.emit(reason)
		return false
	file.store_var(data)
	file.close()
	saved.emit(slot)
	return true

## Read `slot` and restore every system. By default it also returns the player to
## the saved scene/position; pass restore_location=false to only restore data
## (used by tests, or when you want to stay in the current scene).
func load_game(slot: int = 0, restore_location: bool = true) -> bool:
	if not has_save(slot):
		load_failed.emit("no save in slot %d" % slot)
		return false

	var file := FileAccess.open(slot_path(slot), FileAccess.READ)
	if file == null:
		var reason := "could not open %s for reading (err %d)" % [slot_path(slot), FileAccess.get_open_error()]
		push_warning("SaveManager: " + reason)
		load_failed.emit(reason)
		return false
	var data = file.get_var()
	file.close()

	if typeof(data) != TYPE_DICTIONARY or data.get("version", -1) != SAVE_VERSION:
		var reason := "save file is missing or has an incompatible version"
		push_warning("SaveManager: " + reason)
		load_failed.emit(reason)
		return false

	var systems: Dictionary = data.get("systems", {})
	for key in _save_targets:
		if systems.has(key):
			_save_targets[key].restore_state(systems[key])

	if restore_location:
		_restore_location(data.get("location", {}))

	loaded.emit(slot)
	return true

# --- Location (which scene + where the player stands) ----------------------

func _capture_location() -> Dictionary:
	var loc := {}
	var scene := SceneManager.current_world()
	if scene:
		loc["scene"] = scene.scene_file_path
	var player := get_tree().get_first_node_in_group("player")
	if player is Node3D:
		loc["player_transform"] = (player as Node3D).global_transform
	return loc

func _restore_location(loc: Dictionary) -> void:
	var scene_path: String = loc.get("scene", "")
	# An empty path, or one pointing at a scene that no longer exists (e.g. a town
	# scene that was moved into stages/archive/), would make SceneManager free the old
	# world and then fail to load anything — a blank screen. Fall back to a known-good
	# scene instead. We DON'T restore the saved transform in that case: the saved spot
	# belongs to a different scene and would land the player nowhere sensible.
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		if scene_path != "":
			push_warning("SaveManager: saved scene '%s' is missing; loading fallback '%s'." % [scene_path, FALLBACK_SCENE])
		_pending_player_transform = null
		SceneManager.change_scene(FALLBACK_SCENE)
		return
	# A save made INSIDE a procedural dungeon returns the player to the overworld on load,
	# mirroring death-in-dungeon. The dungeon would regenerate a different floor 1 and the saved
	# coords could embed the player in a freshly-built wall, so we DON'T restore the transform —
	# the town's "from_dungeon" marker places them. (Detected by path, like death_screen.)
	if scene_path.to_lower().contains("dungeon"):
		_pending_player_transform = null
		SceneManager.change_scene(FALLBACK_SCENE, DUNGEON_RETURN_SPAWN)
		return
	_pending_player_transform = loc.get("player_transform", null)
	# Let SceneManager swap the scene, then drop the player back on their spot
	# once the new scene is ready.
	SceneManager.scene_loaded.connect(_on_scene_loaded_place_player, CONNECT_ONE_SHOT)
	# If that load fails, the place handler will never fire — clear the pending transform and
	# drop the dangling one-shot so a LATER scene change doesn't teleport the player to this
	# stale spot.
	SceneManager.scene_load_failed.connect(_on_restore_scene_failed, CONNECT_ONE_SHOT)
	SceneManager.change_scene(scene_path)

func _on_restore_scene_failed(_scene_path: String) -> void:
	_pending_player_transform = null
	if SceneManager.scene_loaded.is_connected(_on_scene_loaded_place_player):
		SceneManager.scene_loaded.disconnect(_on_scene_loaded_place_player)

func _on_scene_loaded_place_player(_scene_path: String) -> void:
	# The load succeeded, so the paired failure one-shot is no longer needed; drop it.
	if SceneManager.scene_load_failed.is_connected(_on_restore_scene_failed):
		SceneManager.scene_load_failed.disconnect(_on_restore_scene_failed)
	if _pending_player_transform != null:
		var player := get_tree().get_first_node_in_group("player")
		if player is Node3D:
			var player_3d := player as Node3D
			player_3d.global_transform = _pending_player_transform
			# Procedural dungeons build their floor StaticBody colliders during _ready,
			# which may not be physics-active the instant the scene reports loaded. Snapping
			# to the exact saved Y can then drop the player through the not-yet-solid floor.
			# Wait one physics frame so colliders are live, then raycast DOWN onto the ground
			# and rest the player on it. Harmless in the overworld (just re-confirms the floor).
			await get_tree().physics_frame
			if is_instance_valid(player_3d):
				_snap_player_to_floor(player_3d)
	_pending_player_transform = null

# Raycast straight down from above the player's saved position and, if it hits world
# geometry, place the player's feet just on top of it. Walls/floors/props all sit on
# physics layer 1; we mask only that layer and exclude the player so we hit the ground.
func _snap_player_to_floor(player_3d: Node3D) -> void:
	var origin := player_3d.global_transform.origin
	var from := origin + Vector3(0.0, 2.0, 0.0)
	var to := origin + Vector3(0.0, -50.0, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	# Don't let the player's own body swallow the ray. The player is a CollisionObject3D
	# (CharacterBody3D); exclude its RID so we hit the floor beneath, not the player.
	if player_3d is CollisionObject3D:
		query.exclude = [(player_3d as CollisionObject3D).get_rid()]
	var space_state := player_3d.get_world_3d().direct_space_state
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return # No ground found — keep the saved transform as-is.
	var hit_pos: Vector3 = result["position"]
	# Small lift so the player rests on the floor rather than clipping into it.
	var placed := player_3d.global_transform
	placed.origin.y = hit_pos.y + 0.1
	player_3d.global_transform = placed
