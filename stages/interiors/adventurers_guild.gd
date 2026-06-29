# adventurers_guild.gd
# The Adventurers Guild — Sally Steelfield's gruff meeting hall (v1 venue, M-C). A thin
# RoomInterior subclass: the base code-builds the room shell + Player + "from_town" marker +
# Leave door; this file sets a hard, torchlit palette and _furnish()es Sally plus the DUNGEON
# ENTRANCE hook — a teleport into the v1 procedural dungeon (Mine theme). GREYBOX: the entrance
# is open now so the venue is testable; the Beat-3 "To the Source" questline (M-F) gates it
# behind the finale flag (it can flip the teleport's `locked` to false when the hub completes).
#
# Extended by PATH (not by `RoomInterior`) so it resolves on a cold headless cache.
extends "res://stages/interiors/room_interior.gd"

const KIT := "res://assets/models/furniture/furniture-kit/"
# Guild-specific Mine variant whose exit portal returns to the Guild (spawn "from_town"),
# not the shared dungeon that exits to Town. See guild_mine.tscn.
const DUNGEON := "res://stages/dungeons/procedural/guild_mine.tscn"
# (TELEPORT_SCRIPT is inherited from RoomInterior — don't redeclare it.)

func _init() -> void:
	room_size = Vector2(20.0, 16.0)
	wall_height = 5.0
	# Dark flagstone + warm torchlight fill: a hard adventurers' hall, not a cosy cottage.
	floor_color = Color(0.24, 0.20, 0.17, 1.0)
	wall_color = Color(0.30, 0.26, 0.22, 1.0)
	ambient_color = Color(0.42, 0.35, 0.28, 1.0)
	light_energy = 2.8
	mood_warmth = 1.15
	leave_target_spawn = &"from_guild"
	sign_text = "Exit"
	area_title = "Adventurers Guild"

func _furnish() -> void:
	# A long meeting table (two desks) with benches; lockers + armour stands along the walls.
	place(KIT + "desk.fbx", Vector3(-3.5, 0.0, -1.0), 0.0)
	place(KIT + "desk.fbx", Vector3(-3.5, 0.0, 1.4), 0.0)
	place(KIT + "bench.fbx", Vector3(-3.5, 0.0, -2.6), 0.0)
	place(KIT + "bench.fbx", Vector3(-3.5, 0.0, 3.0), 0.0)
	place(KIT + "bookcaseClosedWide.fbx", Vector3(-8.0, 0.0, -6.6), 0.0)
	place(KIT + "coatRackStanding.fbx", Vector3(-9.0, 0.0, 6.4), 0.0)
	place(KIT + "coatRackStanding.fbx", Vector3(9.0, 0.0, 6.4), 0.0)
	# Sally stands by the stair down, facing the room.
	place_npc("res://global/npc/definitions/sally.tres", Vector3(3.4, 0.0, 4.6), 205.0)
	_build_dungeon_entrance()

# A torchlit archway in the back-east corner that teleports into the v1 procedural dungeon.
# Duck-typed teleport_raycast (layer 1): aim + E to descend. M-F can set its `locked` until the
# finale unlocks (the flag the hub sets), reusing the same locked-gate mechanism added in M-A.
func _build_dungeon_entrance() -> void:
	var hd := room_size.y * 0.5
	var gate := StaticBody3D.new()
	gate.name = "DungeonEntrance"
	gate.set_script(load(TELEPORT_SCRIPT))
	gate.set("target_scene_path", DUNGEON)
	gate.set("prompt_text", "Descend into the Mine")
	gate.set("target_spawn_point", &"")
	add_child(gate)
	gate.position = Vector3(6.5, 1.3, hd - 1.0)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 2.6, 1.0)
	col.shape = box
	gate.add_child(col)

	# Dark emissive archway slab so the stair-down reads from across the hall.
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 3.2, 0.4)
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.04, 0.06)
	mat.emission_enabled = true
	mat.emission = Color(0.55, 0.22, 0.12)
	mat.emission_energy_multiplier = 1.6
	mesh.material_override = mat
	add_child(mesh)
	mesh.position = Vector3(6.5, 1.6, hd - 0.7)

	var label := Label3D.new()
	label.text = "To the Mine"
	label.font_size = 56
	label.pixel_size = 0.006
	label.modulate = Color(1.0, 0.85, 0.7)
	label.outline_size = 10
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	add_child(label)
	label.position = Vector3(6.5, 3.2, hd - 0.7)
