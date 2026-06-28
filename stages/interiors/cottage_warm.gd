# cottage_warm.gd
# A townsperson's cosy home — the "NPC cottage (warm)" interior. This is a CONTENT subclass
# of RoomInterior: it owns NO geometry, lighting, player or door wiring. The base
# (room_interior.gd) code-builds the shell, the Player, the "from_town" marker and the
# "Leave" door during _ready(); all this file does is (a) set a few config members to give
# the room its small-and-warm character, and (b) override _furnish() to drop a believable,
# lived-in set of furniture, plants and a single resident NPC.
#
# WHY a subclass and not a hand-authored .tscn: SceneManager frees the whole old world and
# rebuilds the destination under a SubViewport, so the scene must own its own Player and a
# "from_town" Marker3D by the end of _ready(). Inheriting RoomInterior gets all of that for
# free and keeps the authored surface tiny — just placements.
#
# Town wiring: a town-side teleport should point its Target Scene Path at cottage_warm.tscn,
# and town_template must carry a Marker3D named "from_cottage1" (matches leave_target_spawn)
# so stepping back out of the Leave door lands the player at this cottage's door in town.
#
# Extend by PATH (not by `RoomInterior`) so it resolves even on a cold headless cache.
extends "res://stages/interiors/room_interior.gd"

# Furniture-kit (Kenney) model paths. All confirmed present under furniture-kit/.
const KIT := "res://assets/models/furniture/furniture-kit/"

func _init() -> void:
	# A small, cosy single room. X = 12 wide, Z = 11 deep.
	room_size = Vector2(12.0, 11.0)
	wall_height = 3.6
	# Warm timber floor and warm plaster walls for a homely glow.
	floor_color = Color(0.40, 0.27, 0.17, 1.0)
	wall_color = Color(0.60, 0.49, 0.40, 1.0)
	# Warm amber ambience + a soft, slightly dim lamp — not a clinical white box.
	ambient_color = Color(0.56, 0.46, 0.38, 1.0)
	light_energy = 2.1
	ceiling = true
	# Town-side return marker the Leave door drops the player on.
	leave_target_spawn = &"from_cottage1"
	sign_text = "Leave"

# Place the home's contents. Coordinates are local to the room centre (0,0); the entry/door
# is on the -Z (north) wall, so the area around (0, .., -4) is kept clear for walking in.
# Half-extents here are hw = 6 (X) and hd = 5.5 (Z).
func _furnish() -> void:
	# --- Sleeping corner (south-west) ----------------------------------------
	# Bed tucked head-to-the-west-wall, footboard pointing into the room.
	place(KIT + "bedSingle.fbx", Vector3(-4.4, 0.0, 3.4), 90.0)
	# Nightstand + a soft floor lamp beside the bed.
	place(KIT + "cabinetBedDrawer.fbx", Vector3(-5.2, 0.0, 1.4), 90.0)
	place(KIT + "lampRoundFloor.fbx", Vector3(-5.3, 0.0, 0.2))
	# A book left on the nightstand — a small lived-in touch.
	place(KIT + "books.fbx", Vector3(-5.2, 0.62, 1.4), 30.0, 1.0, false)

	# --- Hearth / cooking nook (east wall) -----------------------------------
	# No dedicated fireplace in the kit, so a stove + range hood reads as the warm hearth.
	place(KIT + "kitchenStove.fbx", Vector3(5.2, 0.0, -2.4), -90.0)
	place(KIT + "hoodLarge.fbx", Vector3(5.5, 0.0, -2.4), -90.0)
	# A little counter cabinet next to it for the cooking corner.
	place(KIT + "kitchenCabinet.fbx", Vector3(5.2, 0.0, -0.4), -90.0)

	# --- Dining / living centre ----------------------------------------------
	# Rug anchors the middle of the room.
	place(KIT + "rugRectangle.fbx", Vector3(1.0, 0.01, 0.8), 0.0, 1.0, false)
	# Round table with two chairs — a place to share a meal.
	place(KIT + "tableRound.fbx", Vector3(1.2, 0.0, 0.8))
	place(KIT + "chair.fbx", Vector3(1.2, 0.0, 2.1), 180.0)
	place(KIT + "chair.fbx", Vector3(1.2, 0.0, -0.5), 0.0)

	# --- Storage & study (west / north wall) ---------------------------------
	# Open bookcase against the west wall.
	place(KIT + "bookcaseOpen.fbx", Vector3(-5.4, 0.0, -2.2), 90.0)
	# A coat rack by the entrance so the door corner feels used.
	place(KIT + "coatRackStanding.fbx", Vector3(-4.8, 0.0, -4.6), 0.0)
	# Doormat just inside the Leave door.
	place(KIT + "rugDoormat.fbx", Vector3(0.0, 0.01, -4.4), 0.0, 1.0, false)

	# --- Greenery (warmth & life) --------------------------------------------
	place(KIT + "pottedPlant.fbx", Vector3(5.2, 0.0, 4.6))
	place(KIT + "plantSmall1.fbx", Vector3(-5.4, 0.0, 4.6))
	place(KIT + "plantSmall2.fbx", Vector3(1.2, 0.74, 0.8), 0.0, 1.0, false)  # on the table

	# --- The resident --------------------------------------------------------
	# Reuse Pip's existing NPCDefinition as the homeowner, stood near the table facing the door.
	place_npc("res://global/npc/definitions/wanderer_pip.tres", Vector3(2.8, 0.0, 1.4), -120.0)
