# player_house.gd
# The player's HOME interior — the showcase room for the house-upgrade feature.
#
# Built on the reusable RoomInterior base (see room_interior.gd): the base code-builds
# the warm wooden shell (floor / walls / ceiling / lights), the Player, the "from_town"
# entry marker and the "Leave" door back to town. This subclass only sets the room's
# look-and-feel members and overrides _furnish() to drop the furniture and stations.
#
# WHAT MAKES THIS ROOM SPECIAL — it is UPGRADEABLE. It reflects the HouseUpgrades
# autoload's owned-upgrade set:
#   * ALWAYS present: a bed, a small table + chairs, and an UPGRADE STATION the player
#     presses E on to buy improvements.
#   * CONDITIONALLY present: each upgrade's fixture appears only when HouseUpgrades says
#     it is owned (storage_chest -> chest, kitchen -> cooking station, workshop ->
#     workbench, garden -> renewable herb plants, comfy_bed -> a nicer double bed,
#     decor -> rugs/lamps/plants).
# We also listen to HouseUpgrades.upgrade_purchased so a fixture pops into the room the
# instant it is bought at the station — no need to leave and re-enter the house.
#
# ROBUSTNESS: the HouseUpgrades autoload is reached via get_node_or_null("/root/...")
# rather than the global identifier, so this scene still loads cleanly even if the
# autoload has not been registered yet (the room just shows the always-present pieces).
# Every external scene/model path is loaded defensively; a missing asset is skipped with
# a warning instead of crashing the build.

extends "res://stages/interiors/room_interior.gd"

# --- Scene / model paths used by the upgrade fixtures ------------------------
const UPGRADE_STATION_SCENE := "res://entities/props/upgrade_station.tscn"
const CHEST_SCENE := "res://entities/props/chest.tscn"
const COOKING_STATION_SCENE := "res://entities/machines/cooking_station.tscn"
const WORKBENCH_SCENE := "res://entities/machines/workbench.tscn"
const HERB_PLANT_SCENE := "res://entities/harvestables/herb_plant.tscn"

const FURNITURE_DIR := "res://assets/models/furniture/furniture-kit/"
const BED_SINGLE := FURNITURE_DIR + "bedSingle.fbx"
const BED_DOUBLE := FURNITURE_DIR + "bedDouble.fbx"
const TABLE := FURNITURE_DIR + "tableCloth.fbx"
const CHAIR := FURNITURE_DIR + "chairCushion.fbx"
const RUG := FURNITURE_DIR + "rugRectangle.fbx"
const RUG_ROUND := FURNITURE_DIR + "rugRound.fbx"
const FLOOR_LAMP := FURNITURE_DIR + "lampRoundFloor.fbx"
const TABLE_LAMP := FURNITURE_DIR + "lampRoundTable.fbx"
const POTTED_PLANT := FURNITURE_DIR + "pottedPlant.fbx"
const SMALL_PLANT := FURNITURE_DIR + "plantSmall1.fbx"
const BOOKCASE := FURNITURE_DIR + "bookcaseClosed.fbx"
const KITCHEN_STOVE := FURNITURE_DIR + "kitchenStove.fbx"
const KITCHEN_CABINET := FURNITURE_DIR + "kitchenCabinet.fbx"
const SIDE_TABLE := FURNITURE_DIR + "sideTable.fbx"

# id -> true once that upgrade's fixture has been placed this scene-life, so a live
# purchase signal never double-places something already in the room.
var _placed_upgrades: Dictionary = {}

func _init() -> void:
	room_size = Vector2(18.0, 16.0)
	wall_height = 4.0
	floor_color = Color(0.42, 0.30, 0.20, 1.0)        # warm honey-wood floor
	wall_color = Color(0.55, 0.43, 0.33, 1.0)         # cosy timber walls
	ambient_color = Color(0.62, 0.55, 0.46, 1.0)      # warm fill light
	light_energy = 2.8
	ceiling = true
	leave_target_spawn = &"from_house"
	sign_text = "Home"

# --- Furnishing -------------------------------------------------------------

func _furnish() -> void:
	# A rug to anchor the living area and warm up the bare floor.
	place(RUG, Vector3(0.0, 0.01, 1.0), 0.0, 1.6, false)

	# ALWAYS: a bed to sleep in (west wall), a table + chairs (centre), and the
	# upgrade station the player uses to buy everything else.
	place(BED_SINGLE, Vector3(-7.2, 0.0, 4.0), 90.0)
	_place_dining_set(Vector3(0.0, 0.0, 1.0))
	_spawn_scene(UPGRADE_STATION_SCENE, Vector3(6.6, 0.0, -4.5), 180.0)

	# Already-owned upgrades: place each fixture up front. Reached defensively so a
	# missing/unregistered HouseUpgrades autoload simply leaves the base furniture.
	var hu: Node = get_node_or_null("/root/HouseUpgrades")
	if hu != null:
		for id in _upgrade_ids():
			if bool(hu.is_owned(id)):
				_place_upgrade(id)
		# Live updates: a fixture appears the moment its upgrade is purchased.
		if not hu.upgrade_purchased.is_connected(_on_upgrade_purchased):
			hu.upgrade_purchased.connect(_on_upgrade_purchased)

# Ordered list of the upgrade ids this house knows how to furnish.
func _upgrade_ids() -> Array:
	return [
		&"storage_chest",
		&"kitchen",
		&"workshop",
		&"garden",
		&"comfy_bed",
		&"decor",
	]

# Re-place just the newly-bought upgrade's fixture without a reload.
func _on_upgrade_purchased(id: StringName) -> void:
	_place_upgrade(id)

# Place the fixture(s) for a single upgrade id (idempotent per scene-life).
func _place_upgrade(id: StringName) -> void:
	if _placed_upgrades.has(id):
		return
	_placed_upgrades[id] = true
	match id:
		&"storage_chest":
			# A sturdy stash chest by the entry. Unique id so its contents persist.
			var chest: Node3D = _spawn_scene(CHEST_SCENE, Vector3(-6.6, 0.0, -4.5), 180.0)
			if chest != null:
				chest.set("chest_id", &"player_house_storage")
		&"kitchen":
			# Functional cooking station plus a stove + cabinet for the kitchen look.
			_spawn_scene(COOKING_STATION_SCENE, Vector3(6.4, 0.0, 5.0), 180.0)
			place(KITCHEN_STOVE, Vector3(4.7, 0.0, 6.4), 180.0)
			place(KITCHEN_CABINET, Vector3(7.6, 0.0, 6.4), 180.0)
		&"workshop":
			# Functional workbench with a bookcase as a tool/parts rack behind it.
			_spawn_scene(WORKBENCH_SCENE, Vector3(-6.0, 0.0, 6.0), 180.0)
			place(BOOKCASE, Vector3(-7.8, 0.0, 6.6), 90.0)
		&"garden":
			# A renewable herb patch: respawn_seconds > 0 so it regrows after harvest.
			_place_herb(Vector3(1.6, 0.0, 6.4))
			_place_herb(Vector3(3.2, 0.0, 6.6))
		&"comfy_bed":
			# A nicer double bed (the upgrade's reward) beside the starter bed.
			place(BED_DOUBLE, Vector3(-6.6, 0.0, 6.4), 90.0)
		&"decor":
			# Pure-vibes dressing: a round rug, lamps and greenery around the room.
			place(RUG_ROUND, Vector3(6.0, 0.01, 1.0), 0.0, 1.3, false)
			place(FLOOR_LAMP, Vector3(8.0, 0.0, -3.0), 0.0)
			place(POTTED_PLANT, Vector3(-8.0, 0.0, -3.0), 0.0)
			place(SMALL_PLANT, Vector3(8.0, 0.0, 3.0), 0.0)
			place(SIDE_TABLE, Vector3(-7.4, 0.0, 1.0), 0.0)
			place(TABLE_LAMP, Vector3(-7.4, 0.62, 1.0), 0.0, 1.0, false)

# --- Local helpers ----------------------------------------------------------

# A small table with a chair on each of two sides, centred on `centre`.
func _place_dining_set(centre: Vector3) -> void:
	place(TABLE, centre, 0.0)
	place(CHAIR, centre + Vector3(0.0, 0.0, 1.1), 0.0)
	place(CHAIR, centre + Vector3(0.0, 0.0, -1.1), 180.0)

# Instance a herb_plant and make it renewable (regrows a while after harvest).
func _place_herb(pos: Vector3) -> void:
	var herb: Node3D = _spawn_scene(HERB_PLANT_SCENE, pos, 0.0)
	if herb != null:
		herb.set("respawn_seconds", 180.0)

# Instance a packed scene by path, parent it in the room, place + face it.
# Returns the node, or null if the scene could not be loaded (logged, not fatal).
func _spawn_scene(scene_path: String, pos: Vector3, yaw_degrees: float = 0.0) -> Node3D:
	var packed := load(scene_path) as PackedScene
	if packed == null:
		push_warning("player_house: could not load scene '%s' — skipping." % scene_path)
		return null
	var node: Node3D = packed.instantiate()
	add_child(node)
	node.position = pos
	node.rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
	return node
