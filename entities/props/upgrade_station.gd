# upgrade_station.gd
# The in-world half of the HOUSE UPGRADE feature: a small drafting desk / planning
# board you walk up to inside your home and use to improve the place. All the real
# logic lives in the HouseUpgrades autoload (what's owned, costs, buying) and the
# UpgradeUI autoload (the menu); this node is just the physical thing the player
# looks at and presses E on.
#
# Duck-typed interaction (no special-casing in player.gd): the player's interaction
# RayCast3D hits this StaticBody3D, calls get_interaction_prompt() to show
# "[E] Improve Home", and interact(player) on press, which opens the UpgradeUI.
#
# Code-built so the .tscn stays thin (just the script): _ready builds the desk mesh
# and a box collider on physics layer 1 (so the player's interaction ray can hit it).

extends StaticBody3D

## Friendly name shown in the interaction prompt.
@export var display_name: String = "Improve Home"

func _ready() -> void:
	# Sit on the default physics layer 1 so the player's layer-1 interaction ray can
	# detect us (mirrors how every other interactable is reachable).
	collision_layer = 1
	collision_mask = 1
	add_to_group("interactable")
	_build_visual()

# --- Interaction (duck-typed by the player's RayCast3D) ---------------------

func get_interaction_prompt() -> String:
	return display_name

func interact(_player: Node) -> void:
	UpgradeUI.open()

# --- Visual / collider ------------------------------------------------------

# Builds a simple desk-with-board look out of two boxes and a matching box collider.
# Kept in code so the scene file is a thin script holder (see the file header).
func _build_visual() -> void:
	# The desk top + legs as one squat box.
	var desk := MeshInstance3D.new()
	var desk_mesh := BoxMesh.new()
	desk_mesh.size = Vector3(1.2, 0.9, 0.7)
	desk.mesh = desk_mesh
	desk.position = Vector3(0.0, 0.45, 0.0)
	var desk_mat := StandardMaterial3D.new()
	desk_mat.albedo_color = Color(0.42, 0.30, 0.20)  # warm wood
	desk.material_override = desk_mat
	add_child(desk)

	# An upright planning board behind the desk so it reads as an "improve home" station.
	var board := MeshInstance3D.new()
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(1.0, 0.7, 0.06)
	board.mesh = board_mesh
	board.position = Vector3(0.0, 1.15, -0.3)
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.85, 0.82, 0.70)  # cream paper
	board.material_override = board_mat
	add_child(board)

	# Collider roughly enclosing the desk so the player bumps into it and the ray hits.
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 1.5, 0.9)
	col.shape = shape
	col.position = Vector3(0.0, 0.75, -0.1)
	add_child(col)
