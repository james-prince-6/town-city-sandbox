# abandoned_cabin.gd
# A small, spooky ABANDONED CABIN the player enters from the Whispering Woods. Built on the
# shared RoomInterior base, so the floor, four walls, ceiling, the Player, the "from_town"
# entry marker and the "Leave" door are all code-built for us — we only set a few config
# members (a cramped, dim, cold room with dusty timber colours) and override _furnish() to
# dress it as long-abandoned: a stripped bed, an overturned table and toppled chairs, a
# leaning bookcase, scattered crates, a mouldering rug, a coat rack and a trashcan.
#
# The set-piece twist is a CELLAR TRAPDOOR: a dark hatch in the floor carrying the standard
# teleport_raycast script, pointing DOWN into res://stages/dungeons/cabin_cellar.tscn. A
# Marker3D named exactly "from_cellar" sits beside the hatch so that when the cellar dungeon
# exits back UP, the player lands here next to the trapdoor (the cellar exits to this scene
# at the "from_cellar" spawn).
#
# We extend by PATH so the subclass resolves even on a cold headless cache.

extends "res://stages/interiors/room_interior.gd"

const KIT := "res://assets/models/furniture/furniture-kit/"
const CELLAR_SCENE := "res://stages/dungeons/cabin_cellar.tscn"

func _init() -> void:
	# Cramped one-room cabin footprint (~12 x 10 m): X in [-6, 6], Z in [-5, 5].
	room_size = Vector2(12.0, 10.0)
	wall_height = 3.2
	# Dusty, weathered timber underfoot; grey, water-stained plank walls.
	floor_color = Color(0.24, 0.19, 0.14, 1.0)
	wall_color = Color(0.30, 0.29, 0.27, 1.0)
	# Dim, cold, abandoned mood: desaturated blue-grey ambient and a weak guttering lamp.
	ambient_color = Color(0.30, 0.33, 0.40, 1.0)
	light_energy = 1.0
	# The cabin is reached FROM the Whispering Woods, so the Leave door returns there (not the
	# town hub). Whispering Woods owns a Marker3D named "from_cabin" beside the cabin gate.
	leave_target_scene = "res://stages/wild/whispering_woods.tscn"
	leave_target_spawn = &"from_cabin"
	sign_text = "Leave"

# Dress the cabin abandoned + drop the cellar trapdoor. Keep the north (-Z) strip clear:
# that wall holds the entry "from_town" marker and the "Leave" door.
func _furnish() -> void:
	# --- Stripped bed shoved into the south-west corner, headboard to the west wall. ---
	place(KIT + "bedSingle.fbx", Vector3(-4.7, 0.0, 3.4), -90.0)
	place(KIT + "cabinetBedDrawer.fbx", Vector3(-4.9, 0.0, 1.5), -90.0)

	# --- Overturned table + toppled chairs near the middle: the table tipped onto its
	# side (rolled 90 deg about Z), one chair knocked flat, one still upright but askew. ---
	var table: Node3D = place(KIT + "table.fbx", Vector3(-0.6, 0.5, 0.6), 18.0)
	if table != null and is_instance_valid(table):
		table.rotation_degrees = Vector3(0.0, 18.0, 92.0)
	var chair_down: Node3D = place(KIT + "chair.fbx", Vector3(0.9, 0.35, 1.4), 0.0)
	if chair_down != null and is_instance_valid(chair_down):
		chair_down.rotation_degrees = Vector3(86.0, 40.0, 0.0)
	place(KIT + "chair.fbx", Vector3(-2.0, 0.0, -0.4), 150.0)

	# --- Leaning bookcase against the east (+X) wall, a few books spilled at its foot. ---
	var shelf: Node3D = place(KIT + "bookcaseOpen.fbx", Vector3(5.2, 0.0, -2.6), 90.0)
	if shelf != null and is_instance_valid(shelf):
		shelf.rotation_degrees = Vector3(0.0, 90.0, -5.0)
	place(KIT + "books.fbx", Vector3(4.4, 0.0, -1.6), 25.0, 1.0, false)
	place(KIT + "bookcaseClosed.fbx", Vector3(5.2, 0.0, 0.4), 90.0)

	# --- Scattered crates (cardboard boxes stand in for crates in this kit). ---
	place(KIT + "cardboardBoxClosed.fbx", Vector3(4.4, 0.0, 3.6), 35.0)
	place(KIT + "cardboardBoxOpen.fbx", Vector3(3.2, 0.0, 4.2), -20.0)
	var box_stacked: Node3D = place(KIT + "cardboardBoxClosed.fbx", Vector3(4.6, 0.55, 3.6), 12.0)
	if box_stacked != null and is_instance_valid(box_stacked):
		box_stacked.rotation_degrees = Vector3(0.0, 12.0, 6.0)

	# --- Mouldering rug + abandoned odds and ends. ---
	place(KIT + "rugRectangle.fbx", Vector3(-1.2, 0.02, 2.2), 8.0, 1.0, false)
	place(KIT + "coatRackStanding.fbx", Vector3(-5.2, 0.0, -3.6), 120.0)
	place(KIT + "trashcan.fbx", Vector3(-4.6, 0.0, -4.2), 0.0)

	# --- The cellar trapdoor + its UP-return marker. ---
	_build_cellar_trapdoor(Vector3(2.4, 0.0, -2.0))

# Build a dark floor hatch that descends into the cellar dungeon, plus a "from_cellar"
# Marker3D right beside it so the cellar's UP exit lands the player back in the cabin.
func _build_cellar_trapdoor(pos: Vector3) -> void:
	# Teleport gate: a thin dark hatch lying in the floor, on collision layer 1 so the
	# player's interaction raycast can aim + E it.
	var gate := StaticBody3D.new()
	gate.name = "CellarTrapdoor"
	gate.set_script(load(TELEPORT_SCRIPT))
	gate.set("target_scene_path", CELLAR_SCENE)
	gate.set("prompt_text", "Descend into the cellar")
	# The cellar is a generated dungeon: it places its own Player on its own entry marker
	# ("from_overworld"), so no spawn id is needed here (blank avoids a spurious "spawn not
	# found" warning for a "from_town" marker the dungeon never builds).
	gate.set("target_spawn_point", &"")
	add_child(gate)
	gate.position = pos + Vector3(0.0, 0.08, 0.0)

	# Dark hatch mesh (a slightly raised wooden lid over a black opening).
	var lid := MeshInstance3D.new()
	var lid_mesh := BoxMesh.new()
	lid_mesh.size = Vector3(1.8, 0.16, 1.8)
	lid.mesh = lid_mesh
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = Color(0.10, 0.07, 0.05, 1.0)
	lid_mat.roughness = 1.0
	lid.material_override = lid_mat
	gate.add_child(lid)

	# A fitted collider so the player bumps the hatch and the raycast resolves to this body.
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 0.16, 1.8)
	col.shape = box
	gate.add_child(col)

	# Floating label so the descent point is obvious in the gloom.
	var label := Label3D.new()
	label.text = "Cellar"
	label.font_size = 56
	label.pixel_size = 0.006
	label.modulate = Color(0.85, 0.85, 0.95)
	label.outline_size = 12
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(label)
	label.position = pos + Vector3(0.0, 1.4, 0.0)

	# UP-return marker: the cellar dungeon exits to this cabin scene at "from_cellar".
	var marker := Marker3D.new()
	marker.name = "from_cellar"
	add_child(marker)
	marker.position = pos + Vector3(0.0, 1.0, 1.6)
