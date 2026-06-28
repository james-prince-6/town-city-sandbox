# town_hall.gd
# The town's municipal building — a large, formal civic hall the player can step into from
# town. It is a thin CONTENT subclass of RoomInterior: the base already code-builds the
# room shell (floor, walls, ceiling, lights, the Player, the "from_town" entry marker, and
# the "Leave" door that teleports back to town_template). All this file does is:
#   1. set the room's config members (a larger, brighter, stone/marble room), and
#   2. override _furnish() to dress it out as a town hall — a reception counter the player
#      walks up to, public seating in rows, civic banners and greenery, a notice board, and
#      one existing townsfolk NPC (Mira) standing behind the counter for flavour.
#
# Why a subclass and not a hand-authored .tscn: the base guarantees the SceneManager
# contract (own Player + "from_town" Marker3D present by the end of _ready) for free, so
# this file never touches geometry, lighting, the player, or the door wiring — it only
# decorates. We extend by PATH (not by the RoomInterior class_name) so it still resolves
# when the headless cache is cold.
#
# Layout (room is 24 wide on X, 18 deep on Z; entrance/Leave door on the north -Z wall):
#   - Player spawns at "from_town" just inside the north wall, facing south into the room.
#   - Reception counter (a run of desks) sits at the far south end facing the entrance,
#     with Mira standing behind it and civic record cabinets + banners against the south wall.
#   - Public benches sit in two columns of rows down the middle, leaving a central aisle.
#   - A notice board (open bookcase + sign) sits against the west wall; potted plants and
#     standing coat racks (as civic flag stands) flank the room for a lawful, orderly feel.
extends "res://stages/interiors/room_interior.gd"

const KIT := "res://assets/models/furniture/furniture-kit/"

func _init() -> void:
	# A large, formal municipal room — bigger footprint, taller walls, brighter than a home.
	room_size = Vector2(24.0, 18.0)
	wall_height = 6.0
	# Pale marble floor and light stone walls read as a civic interior.
	floor_color = Color(0.74, 0.73, 0.70, 1.0)
	wall_color = Color(0.80, 0.78, 0.74, 1.0)
	ceiling = true
	# Bright, even fill light for an official public space.
	ambient_color = Color(0.74, 0.74, 0.78, 1.0)
	light_energy = 3.6
	# Town-side return marker the Leave door drops the player on.
	leave_target_spawn = &"from_townhall"
	sign_text = "Town Hall"

func _furnish() -> void:
	_furnish_reception()
	_furnish_seating()
	_furnish_notice_board()
	_furnish_decor()
	_furnish_banners()

# --- Reception counter (far south end, facing the entrance) -----------------

func _furnish_reception() -> void:
	# A run of three desks forms one long reception counter facing north (toward entrants).
	place(KIT + "desk.fbx", Vector3(-2.4, 0.0, 6.8), 180.0)
	place(KIT + "desk.fbx", Vector3(0.0, 0.0, 6.8), 180.0)
	place(KIT + "desk.fbx", Vector3(2.4, 0.0, 6.8), 180.0)

	# Mira works the counter — reuse her existing NPCDefinition; she stands behind the desk
	# facing north (yaw 180) toward anyone who walks up.
	place_npc("res://global/npc/definitions/mira.tres", Vector3(0.0, 0.0, 7.9), 180.0)
	# A clerk's chair tucked beside her as set dressing.
	place(KIT + "chairDesk.fbx", Vector3(1.4, 0.0, 7.7), 0.0)

	# Civic record cabinets against the south wall behind the counter.
	place(KIT + "bookcaseClosedWide.fbx", Vector3(-4.2, 0.0, 8.4), 180.0)
	place(KIT + "bookcaseClosedWide.fbx", Vector3(4.2, 0.0, 8.4), 180.0)

	# A document tray / books on the counter (flat decor, no collision needed).
	place(KIT + "books.fbx", Vector3(-0.6, 0.78, 6.8), 0.0, 1.0, false)

# --- Public seating (rows down the middle, central aisle clear) -------------

func _furnish_seating() -> void:
	# Two columns of benches in three rows, facing the reception counter, with an open
	# central aisle so the player walks straight from the door to the counter.
	var rows := [-2.0, 0.5, 3.0]
	for z_pos in rows:
		var zf: float = z_pos
		place(KIT + "bench.fbx", Vector3(-3.6, 0.0, zf), 0.0)
		place(KIT + "bench.fbx", Vector3(3.6, 0.0, zf), 0.0)

	# A long runner rug down the central aisle (flat decor, walk-through).
	place(KIT + "rugRectangle.fbx", Vector3(0.0, 0.02, 1.0), 90.0, 1.6, false)

# --- Notice board (west wall) ----------------------------------------------

func _furnish_notice_board() -> void:
	# An open bookcase against the west wall stands in for a public notice board / pigeonholes.
	place(KIT + "bookcaseOpen.fbx", Vector3(-11.2, 0.0, -2.0), 90.0)
	place(KIT + "bookcaseOpen.fbx", Vector3(-11.2, 0.0, 1.0), 90.0)

	# A floating "NOTICES" sign above it so its purpose reads at a glance.
	# (Named notice_sign, not `sign`, to avoid shadowing GDScript's global sign() function.)
	var notice_sign := Label3D.new()
	notice_sign.text = "NOTICES"
	notice_sign.font_size = 48
	notice_sign.pixel_size = 0.006
	notice_sign.modulate = Color(0.15, 0.18, 0.25)
	notice_sign.outline_size = 8
	notice_sign.outline_modulate = Color(1.0, 1.0, 1.0, 0.9)
	notice_sign.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	notice_sign.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	add_child(notice_sign)
	notice_sign.position = Vector3(-11.55, 3.0, -0.5)

# --- Greenery and flag stands ----------------------------------------------

func _furnish_decor() -> void:
	# Tall potted plants flank the reception counter for a formal lobby look.
	place(KIT + "pottedPlant.fbx", Vector3(-5.4, 0.0, 6.6), 0.0)
	place(KIT + "pottedPlant.fbx", Vector3(5.4, 0.0, 6.6), 0.0)

	# Greenery in the far corners.
	place(KIT + "plantSmall1.fbx", Vector3(-10.6, 0.0, 7.6), 0.0)
	place(KIT + "plantSmall1.fbx", Vector3(10.6, 0.0, 7.6), 0.0)

	# Standing coat racks beside the entrance double as civic flag stands.
	place(KIT + "coatRackStanding.fbx", Vector3(-10.4, 0.0, -7.4), 0.0)
	place(KIT + "coatRackStanding.fbx", Vector3(10.4, 0.0, -7.4), 0.0)

# --- Civic banners + hall title --------------------------------------------

func _furnish_banners() -> void:
	# Hanging cloth banners on the south wall behind the counter. No banner model ships with
	# the furniture kit, so these are thin colour-blocked panels — small decorative meshes
	# hung flat against the wall (civic blue with a gold accent strip).
	_hang_banner(Vector3(-3.0, 4.0, 8.6), Color(0.16, 0.26, 0.5))
	_hang_banner(Vector3(3.0, 4.0, 8.6), Color(0.16, 0.26, 0.5))

	# The hall's title across the south wall, high above the counter.
	var title := Label3D.new()
	title.text = "TOWN HALL"
	title.font_size = 72
	title.pixel_size = 0.007
	title.modulate = Color(0.85, 0.72, 0.32)
	title.outline_size = 12
	title.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	title.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	title.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	add_child(title)
	title.position = Vector3(0.0, 5.0, 8.6)

# Hang one decorative banner panel (with a gold top valance) flat on the wall at `pos`.
func _hang_banner(pos: Vector3, cloth: Color) -> void:
	var banner := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 2.6, 0.05)
	banner.mesh = bm
	banner.material_override = _flat_material(cloth, 1.0)
	add_child(banner)
	banner.position = pos

	var valance := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(1.0, 0.35, 0.07)
	valance.mesh = vm
	valance.material_override = _flat_material(Color(0.82, 0.68, 0.28), 1.0)
	add_child(valance)
	valance.position = pos + Vector3(0.0, 1.45, 0.0)
