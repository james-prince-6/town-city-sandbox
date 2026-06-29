# astros_fishing.gd
# Astros Fishing Friends — Droghnaut's fishing shop (v1 venue, M-C). A thin RoomInterior
# subclass: the base code-builds the room shell + Player + "from_town" marker + Leave door;
# this file sets a cool, watery palette and _furnish()es Droghnaut behind a small counter plus
# a GREYBOX "fishing spot" (a still water plane + a `FishingSpot` marker). The actual catch
# loop is built in M-E (decision D6 = light fishing) by attaching its interaction to that
# marker, and wired into Droghnaut's dialogue in M-F.
#
# Extended by PATH (not by `RoomInterior`) so it resolves on a cold headless cache.
extends "res://stages/interiors/room_interior.gd"

const KIT := "res://assets/models/furniture/furniture-kit/"

func _init() -> void:
	room_size = Vector2(18.0, 16.0)
	wall_height = 4.5
	# Damp blue-grey boards + cool aquarium fill so the room reads watery and calm.
	floor_color = Color(0.20, 0.28, 0.34, 1.0)
	wall_color = Color(0.32, 0.42, 0.48, 1.0)
	ambient_color = Color(0.44, 0.54, 0.62, 1.0)
	light_energy = 3.0
	leave_target_spawn = &"from_fishing"
	sign_text = "Exit"
	area_title = "Astros Fishing Friends"

func _furnish() -> void:
	# A small sales counter across the back, Droghnaut behind it facing the entrance.
	place(KIT + "kitchenBarEnd.fbx", Vector3(-1.6, 0.0, 5.0), 0.0)
	place(KIT + "kitchenBar.fbx", Vector3(-0.6, 0.0, 5.0), 0.0)
	place(KIT + "kitchenBar.fbx", Vector3(0.4, 0.0, 5.0), 0.0)
	place(KIT + "kitchenBarEnd.fbx", Vector3(1.4, 0.0, 5.0), 180.0)
	place_npc("res://global/npc/definitions/droghnaut.tres", Vector3(-0.1, 0.0, 6.2), 180.0)
	# Tackle crates + a little greenery to dress the corners.
	place(KIT + "cardboardBoxClosed.fbx", Vector3(-7.0, 0.0, 5.6), 14.0)
	place(KIT + "cardboardBoxClosed.fbx", Vector3(-6.3, 0.55, 5.6), -22.0)
	place(KIT + "pottedPlant.fbx", Vector3(7.0, 0.0, 5.6), 0.0)
	# Greybox fishing spot: a still pool the player can stand beside. M-E attaches the catch
	# interaction to the `FishingSpot` marker next to it.
	_build_fishing_pool()

# A flat translucent water plane + a named marker for the (future) fishing interaction.
func _build_fishing_pool() -> void:
	var water := MeshInstance3D.new()
	water.name = "FishingPool"
	var pm := PlaneMesh.new()
	pm.size = Vector2(7.0, 5.0)
	water.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.14, 0.34, 0.5, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.3
	mat.roughness = 0.08
	water.material_override = mat
	add_child(water)
	water.position = Vector3(0.0, 0.06, -3.5)
	# The hook M-E's catch loop attaches to (found by name from Droghnaut's dialogue / the venue).
	var spot := Marker3D.new()
	spot.name = "FishingSpot"
	add_child(spot)
	spot.position = Vector3(0.0, 0.0, -1.0)
