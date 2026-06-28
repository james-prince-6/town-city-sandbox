# apothecary_inside.gd
# The interior of the town APOTHECARY / ALCHEMIST shop — a second storefront the player
# can step inside from town. It is a thin content subclass of RoomInterior: the base
# already code-builds the shell (floor, walls, ceiling, lights, the Player, the "from_town"
# entry marker, and the "Leave" door that teleports back to town), so all this file does is
# (1) set a few room-config members in _init() to give the place its own moody green/blue
# apothecary mood, and (2) override _furnish() to drop the shop dressing: wall shelves lined
# with potion bottles, a brewing counter, scattered herbs in pots, a soft rug, and an
# alchemist vendor you can actually shop with.
#
# SceneManager contract is satisfied by the base (_build_entry makes the Player + "from_town"
# marker during _ready, before _furnish runs), so this subclass never touches geometry,
# lighting, the player or the door wiring — only decoration.
#
# Town wiring: a town-side teleport points its Target Scene Path at apothecary_inside.tscn,
# and the town must own a Marker3D named "from_apothecary" (matching leave_target_spawn) so
# leaving drops the player back at the apothecary's town-side door.

extends "res://stages/interiors/room_interior.gd"

# Shop the alchemist vendor runs. Reuse the existing general store inventory so the vendor is
# immediately functional; the apothecary flavour comes from the name + the dressing.
const SHOPKEEPER_SCENE := "res://entities/npc/shopkeeper.tscn"
const APOTHECARY_SHOP := "res://global/shop/shops/general_store.tres"

# Decorative potion/bottle props (each a self-contained StaticBody prop). Placed with
# collision off so they read as light table dressing the player can walk past.
const BOTTLE_PROPS := [
	"res://entities/props/bar/soda_bottle.tscn",
	"res://entities/props/bar/wine_glass.tscn",
	"res://entities/props/bar/drink_glass.tscn",
	"res://entities/props/bar/drink_mug.tscn",
	"res://entities/props/bar/coffee_cup.tscn",
]

func _init() -> void:
	# A cosy, slightly cramped shop footprint.
	room_size = Vector2(15.0, 13.0)
	wall_height = 4.0
	# Dim, earthy interior — aged plaster walls over a dark wood floor.
	floor_color = Color(0.20, 0.17, 0.14, 1.0)
	wall_color = Color(0.30, 0.34, 0.30, 1.0)
	# Moody green/blue apothecary glow (bubbling potions, not warm hearthlight).
	ambient_color = Color(0.34, 0.48, 0.46, 1.0)
	light_energy = 2.0
	# Town-side return marker the Leave door drops the player on.
	leave_target_spawn = &"from_apothecary"
	sign_text = "Apothecary"

# --- Furnishing -------------------------------------------------------------

func _furnish() -> void:
	var hw: float = room_size.x * 0.5  # 7.5
	var hd: float = room_size.y * 0.5  # 6.5

	# Soft rug to anchor the centre of the shop floor (flat decor, walk-through).
	place("res://entities/props/furniture/rug.tscn", Vector3(0.0, 0.02, 1.0), 0.0, 1.6, false)

	# Tall stock shelves down the WEST wall, packed with bottles.
	_shelf_with_bottles(Vector3(-hw + 0.7, 0.0, -3.0), 90.0)
	_shelf_with_bottles(Vector3(-hw + 0.7, 0.0, 0.5), 90.0)
	_shelf_with_bottles(Vector3(-hw + 0.7, 0.0, 4.0), 90.0)

	# Stock shelves down the EAST wall too.
	_shelf_with_bottles(Vector3(hw - 0.7, 0.0, -3.0), -90.0)
	_shelf_with_bottles(Vector3(hw - 0.7, 0.0, 0.5), -90.0)

	# An apothecary cabinet (drawers of dried ingredients) in the back-east corner.
	place("res://entities/props/furniture/cabinet.tscn", Vector3(hw - 1.0, 0.0, 4.2), -90.0)

	# The brewing counter: a long table across the SOUTH (back) wall, the vendor behind it.
	place("res://entities/props/furniture/table.tscn", Vector3(0.0, 0.0, hd - 1.6), 0.0, 1.3)
	# Potions / mixing glassware lined up along the counter top.
	_bottle_row(Vector3(-2.2, 0.78, hd - 1.6), 0.9, 5)

	# A small round prep table off to one side with a couple of bottles brewing on it.
	place("res://entities/props/furniture/round_table.tscn", Vector3(-4.5, 0.0, hd - 3.0), 0.0)
	_place_bottle(0, Vector3(-4.7, 0.78, hd - 3.1), 0.0)
	_place_bottle(1, Vector3(-4.2, 0.78, hd - 2.8), 30.0)

	# Herbs growing in pots — give the shop its living, green apothecary feel.
	place("res://entities/props/furniture/potted_plant.tscn", Vector3(-hw + 1.0, 0.0, hd - 1.2), 0.0)
	place("res://entities/props/furniture/potted_plant.tscn", Vector3(hw - 1.0, 0.0, hd - 1.2), 0.0)
	place("res://entities/props/furniture/potted_plant.tscn", Vector3(3.6, 0.0, -hd + 3.0), 0.0)

	# Moody accent lamps (the cool ambient is the base; these add pools of light).
	place("res://entities/props/furniture/table_lamp.tscn", Vector3(2.2, 0.78, hd - 1.6), 0.0, 1.0, false)
	place("res://entities/props/crystal_lamp.tscn", Vector3(-4.5, 0.78, hd - 3.0), 0.0, 1.0, false)

	# A reading bookcase of recipes in the front-east corner.
	place("res://entities/props/furniture/bookcase.tscn", Vector3(hw - 0.7, 0.0, -hd + 1.4), -90.0)

	# The alchemist vendor, standing behind the brewing counter facing the entry.
	_place_vendor(Vector3(0.0, 0.0, hd - 2.6), 0.0)

# --- Local helpers ----------------------------------------------------------

# Place a bookcase "shelf" against a wall and stand a few potion bottles in front of it.
func _shelf_with_bottles(pos: Vector3, yaw: float) -> void:
	place("res://entities/props/furniture/bookcase.tscn", pos, yaw)
	# Nudge the bottles a little out from the wall along the shelf's facing.
	var inward: Vector3 = Vector3(sin(deg_to_rad(yaw)), 0.0, cos(deg_to_rad(yaw))) * 0.5
	_place_bottle(0, pos + inward + Vector3(0.0, 0.85, -0.4), yaw)
	_place_bottle(2, pos + inward + Vector3(0.0, 0.85, 0.4), yaw)

# Line up `count` bottles starting at `start`, stepping +X by `step`, cycling prop variants.
func _bottle_row(start: Vector3, step: float, count: int) -> void:
	for i in count:
		_place_bottle(i, start + Vector3(step * float(i), 0.0, 0.0), 0.0)

# Place one decorative bottle, cycling through the prop variants. Collision off (light decor).
func _place_bottle(variant: int, pos: Vector3, yaw: float) -> void:
	var path: String = BOTTLE_PROPS[variant % BOTTLE_PROPS.size()]
	place(path, pos, yaw, 1.0, false)

# Instance the shopkeeper scene, point it at the apothecary's storefront, name it, and drop
# it in the room facing `yaw`. Falls back to a plain ambience NPC if the scene is missing.
func _place_vendor(pos: Vector3, yaw: float) -> void:
	var packed := load(SHOPKEEPER_SCENE) as PackedScene
	if packed == null:
		place_npc("res://global/npc/definitions/sela.tres", pos, yaw)
		return
	var keeper: Node3D = packed.instantiate()
	var shop: Resource = load(APOTHECARY_SHOP)
	if shop != null:
		keeper.set("shop", shop)
	keeper.set("npc_name", "Wren")
	keeper.set("npc_id", &"wren_apothecary")
	add_child(keeper)
	keeper.global_position = pos
	keeper.rotation_degrees = Vector3(0.0, yaw, 0.0)
