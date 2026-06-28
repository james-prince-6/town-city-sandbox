# general_store_inside.gd
# The town's GENERAL STORE interior — a small, stocked shop the player walks into from
# town to buy supplies. It is a thin content subclass of RoomInterior: the base already
# code-builds the room shell (floor, walls, ceiling, lights, the Player, the "from_town"
# entry marker, and the "Leave" door that teleports back to town), so all this file does
# is (1) set the room's size / palette / warm shop lighting / return-spawn id in _init(),
# and (2) override _furnish() to dress the room — sales counter, wall shelving, stocked
# produce/freezer displays, storage crates and barrels — and finally drop the Shopkeeper
# behind the counter. The Shopkeeper scene self-configures and opens the general_store
# ShopUI on interact, so placing it is the only wiring the shop needs to be usable.
#
# SceneManager contract (player + "from_town" marker present by end of _ready) is satisfied
# for free by the base. Leaving returns the player to the town marker named "from_store".
#
# Extended by PATH (not by `RoomInterior`) so it resolves even on a cold headless cache.

extends "res://stages/interiors/room_interior.gd"

# Asset roots (kept as consts so a typo shows up once, not per call site).
const KIT := "res://assets/models/furniture/furniture-kit/"        # Kenney furniture .fbx
const MART := "res://assets/models/props/mini-market/"             # Kenney mini-market .fbx
const FOOD := "res://assets/models/food_drink/food-kit/"           # Kenney food .fbx
const RES := "res://assets/models/props/kaykit_resources/"         # KayKit resource props .gltf
const SHOPKEEPER := "res://entities/npc/shopkeeper.tscn"           # self-opens general_store ShopUI

func _init() -> void:
	# A wide, shallow shop floor: the counter sits across the back, shelving lines the
	# side walls, and the player has a clear aisle from the door.
	room_size = Vector2(16.0, 14.0)
	wall_height = 4.0
	# Warm timber floor + warm plaster walls read as a cosy trading post rather than a cell.
	floor_color = Color(0.44, 0.32, 0.21, 1.0)
	wall_color = Color(0.63, 0.55, 0.44, 1.0)
	# Warm, slightly amber fill so the goods glow like they are under shop lamps.
	ambient_color = Color(0.58, 0.50, 0.40, 1.0)
	light_energy = 3.2
	leave_target_spawn = &"from_store"
	sign_text = "Exit"

# --- Furnishing -------------------------------------------------------------
# Floor is y = 0. The entry/Leave door is on the -Z (north) wall; the player spawns near
# z = -5 facing +Z, so the counter and keeper face the player from the +Z (south) end.
func _furnish() -> void:
	_floor_decor()
	_wall_shelving()
	_storage()
	_counter_and_keeper()

# Rugs and a couple of potted plants to soften the entrance. Flat decor walks through
# (collision = false); the plants keep their fitted colliders.
func _floor_decor() -> void:
	place(KIT + "rugDoormat.fbx", Vector3(0.0, 0.02, -5.0), 0.0, 1.0, false)
	place(KIT + "rugRectangle.fbx", Vector3(0.0, 0.02, -0.5), 0.0, 1.4, false)
	place(KIT + "pottedPlant.fbx", Vector3(-7.0, 0.0, -5.6), 0.0)
	place(KIT + "pottedPlant.fbx", Vector3(7.0, 0.0, -5.6), 0.0)

# Shelving and freestanding displays line the two side walls. The mini-market shelves
# come pre-modelled with boxes/bags on them; the produce/bread displays and freezer are
# already stocked, so the room reads as a full store without per-item placement.
func _wall_shelving() -> void:
	# West wall (x = -8): backs to the wall, opening toward +X (into the room).
	place(MART + "shelf-boxes.fbx", Vector3(-7.2, 0.0, -3.5), 90.0)
	place(MART + "shelf-bags.fbx", Vector3(-7.2, 0.0, -1.2), 90.0)
	place(MART + "shelf-boxes.fbx", Vector3(-7.2, 0.0, 1.1), 90.0)
	place(KIT + "bookcaseOpen.fbx", Vector3(-7.4, 0.0, 3.4), 90.0)

	# East wall (x = +8): backs to the wall, opening toward -X.
	place(KIT + "bookcaseOpen.fbx", Vector3(7.4, 0.0, -3.5), -90.0)
	place(MART + "shelf-bags.fbx", Vector3(7.2, 0.0, -1.2), -90.0)
	place(MART + "shelf-boxes.fbx", Vector3(7.2, 0.0, 1.1), -90.0)

	# Freestanding stocked displays flanking the main aisle, facing the entering player.
	place(MART + "display-fruit.fbx", Vector3(-3.6, 0.0, -1.5), 180.0)
	place(MART + "display-bread.fbx", Vector3(3.6, 0.0, -1.5), 180.0)

	# A standing freezer cabinet tucked into the back-east corner.
	place(MART + "freezers-standing.fbx", Vector3(6.4, 0.0, 5.8), 180.0)

# Crates, barrels and resource stacks in the back corners sell the "stockroom spilling
# into the shop" feel. KayKit resource props are .gltf but load as PackedScenes like any
# imported model, so place() handles them the same way.
func _storage() -> void:
	# Back-west corner: timber and stone stock.
	place(RES + "Wood_Log_Stack.gltf", Vector3(-6.8, 0.0, 5.9), 20.0)
	place(RES + "Stone_Bricks_Stack_Medium.gltf", Vector3(-5.1, 0.0, 6.2), -10.0)
	place(RES + "Pallet_Wood.gltf", Vector3(-3.4, 0.0, 6.2), 0.0)

	# Cardboard cartons stacked beside the west shelving, near the counter approach.
	place(KIT + "cardboardBoxClosed.fbx", Vector3(-5.2, 0.0, 3.0), 12.0)
	place(KIT + "cardboardBoxOpen.fbx", Vector3(-5.9, 0.0, 3.7), -18.0)
	place(KIT + "cardboardBoxClosed.fbx", Vector3(-5.2, 0.55, 3.0), 40.0)

	# Back-east corner: fuel barrels for atmosphere.
	place(RES + "Fuel_A_Barrels.gltf", Vector3(3.0, 0.0, 6.2), 0.0)
	place(FOOD + "barrel.fbx", Vector3(1.6, 0.0, 6.3), 0.0)

# The sales counter spans the centre-back of the room. The Shopkeeper stands behind it;
# interacting with him opens the general_store ShopUI (configured on shopkeeper.tscn).
func _counter_and_keeper() -> void:
	# Counter run built from kitchen-bar units, capped with end pieces. Counter top ~0.9m.
	const CZ := 3.6
	place(KIT + "kitchenBarEnd.fbx", Vector3(-2.6, 0.0, CZ), 0.0)
	for i in range(5):
		var x := -2.0 + float(i) * 1.0
		place(KIT + "kitchenBar.fbx", Vector3(x, 0.0, CZ), 0.0)
	place(KIT + "kitchenBarEnd.fbx", Vector3(3.1, 0.0, CZ), 180.0)

	# Till + a few loose goods on the counter top (small, walk-through decor).
	place(MART + "cash-register.fbx", Vector3(-1.4, 0.92, CZ - 0.1), 180.0, 1.0, false)
	place(FOOD + "soda-bottle.fbx", Vector3(1.4, 0.92, CZ - 0.1), 0.0, 1.0, false)
	place(FOOD + "can.fbx", Vector3(1.9, 0.92, CZ - 0.1), 0.0, 1.0, false)
	place(MART + "shopping-basket.fbx", Vector3(-3.8, 0.0, 2.4), -25.0)

	# The Shopkeeper, parked behind the counter facing the entrance. Instanced by PATH so
	# it resolves on a cold headless cache; it self-configures from its own scene data.
	var packed := load(SHOPKEEPER) as PackedScene
	if packed == null:
		push_warning("general_store_inside: could not load shopkeeper.tscn.")
		return
	var keeper: Node3D = packed.instantiate()
	add_child(keeper)
	keeper.global_position = Vector3(0.0, 0.0, 4.9)
	keeper.rotation_degrees = Vector3(0.0, 180.0, 0.0)
