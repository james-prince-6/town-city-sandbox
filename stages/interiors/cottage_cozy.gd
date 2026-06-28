# cottage_cozy.gd
# A second NPC home built on the shared RoomInterior base. Where cottage_warm is a snug,
# golden-lit place, this one is a small, cooler, dimmer RUSTIC cottage — bluish twilight
# ambient, lower lamp energy, a weathered timber floor, and a different furniture layout
# (bed tucked in a back corner, a galley kitchen nook hugging one wall, a round dining
# table off-centre, an open bookcase, and a scatter of cosy decorations). The owner is
# Ember (reusing the existing shopkeeper_ember NPCDefinition), so visiting players meet a
# familiar face away from her usual post.
#
# The base RoomInterior already code-builds the floor, four walls, ceiling, lights, the
# Player, the "from_town" entry marker and the "Leave" door — we only set a handful of
# config members and override _furnish() to drop furniture + the NPC. We extend by PATH so
# the subclass resolves even on a cold headless cache.

extends "res://stages/interiors/room_interior.gd"

const KIT := "res://assets/models/furniture/furniture-kit/"

func _init() -> void:
	# Small, cosy footprint — clearly tighter than the warm cottage.
	room_size = Vector2(12.0, 11.0)
	wall_height = 3.4
	# Weathered, slightly cool timber underfoot; muted greyish plaster walls.
	floor_color = Color(0.30, 0.24, 0.19, 1.0)
	wall_color = Color(0.40, 0.40, 0.44, 1.0)
	# Cooler, dimmer mood: bluish evening ambient and a softer lamp.
	ambient_color = Color(0.36, 0.40, 0.50, 1.0)
	light_energy = 1.6
	# Town-side return marker the Leave door drops the player on.
	leave_target_spawn = &"from_cottage2"
	sign_text = "Cottage"

# Place furniture + the resident NPC. Room spans X in [-6, 6], Z in [-5.5, 5.5];
# the entry/Leave door is on the north (-Z) wall, so we keep that strip clear.
func _furnish() -> void:
	# --- Bed: tucked into the south-west corner, headboard to the west wall. ---
	place(KIT + "bedSingle.fbx", Vector3(-4.6, 0.0, 3.4), -90.0)
	place(KIT + "pillow.fbx", Vector3(-4.6, 0.5, 4.4), -90.0, 1.0, false)
	place(KIT + "cabinetBedDrawer.fbx", Vector3(-4.8, 0.0, 1.4), -90.0)
	place(KIT + "lampRoundTable.fbx", Vector3(-4.8, 0.62, 1.4), 0.0, 1.0, false)

	# --- Galley kitchen nook along the east (+X) wall, facing into the room. ---
	place(KIT + "kitchenFridgeSmall.fbx", Vector3(5.1, 0.0, -3.0), -90.0)
	place(KIT + "kitchenStove.fbx", Vector3(5.2, 0.0, -1.4), -90.0)
	place(KIT + "kitchenSink.fbx", Vector3(5.2, 0.0, 0.2), -90.0)
	place(KIT + "kitchenCabinet.fbx", Vector3(5.2, 0.0, 1.8), -90.0)
	place(KIT + "kitchenCoffeeMachine.fbx", Vector3(5.1, 0.92, 1.8), -90.0, 1.0, false)

	# --- Round dining table, off-centre toward the south, with two chairs. ---
	place(KIT + "rugRound.fbx", Vector3(-0.4, 0.02, 1.4), 0.0, 1.0, false)
	place(KIT + "tableRound.fbx", Vector3(-0.4, 0.0, 1.4))
	place(KIT + "chair.fbx", Vector3(0.9, 0.0, 1.4), -90.0)
	place(KIT + "chair.fbx", Vector3(-1.7, 0.0, 1.4), 90.0)

	# --- Open bookcase + reading corner on the west wall. ---
	place(KIT + "bookcaseOpen.fbx", Vector3(-5.4, 0.0, -2.6), 90.0)
	place(KIT + "books.fbx", Vector3(-5.2, 1.05, -2.6), 90.0, 1.0, false)
	place(KIT + "loungeChair.fbx", Vector3(-3.4, 0.0, -3.4), 110.0)
	place(KIT + "lampRoundFloor.fbx", Vector3(-5.0, 0.0, -4.4))

	# --- Decorations to soften the room. ---
	place(KIT + "pottedPlant.fbx", Vector3(4.6, 0.0, 4.6))
	place(KIT + "plantSmall2.fbx", Vector3(-0.4, 0.78, 1.4), 0.0, 1.0, false)
	place(KIT + "rugDoormat.fbx", Vector3(0.0, 0.02, -4.4), 0.0, 1.0, false)

	# --- Resident NPC: Ember, standing by the kitchen nook facing the room. ---
	place_npc("res://global/npc/definitions/shopkeeper_ember.tres", Vector3(2.6, 0.0, -0.4), -110.0)
