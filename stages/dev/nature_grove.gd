# nature_grove.gd
# A walkable dev scene (F6) that shows off the Stylized Nature MegaKit + the NatureScatter
# system: a big grassy ground dressed with scattered trees (with collision), rocks, bushes,
# ferns, flowers and mushrooms. Built in code so there's no hand-placed clutter to maintain —
# copy the _scatter() calls to dress any scene. A player is dropped in so you can walk around.
extends Node3D

const NATURE_DIR := "res://assets/models/nature/stylized-megakit"

func _ready() -> void:
	_build_environment()
	_build_ground()
	# Trees + boulders get collision (you bump into them); foliage is walk-through.
	_scatter(["CommonTree", "Pine", "TwistedTree"], 40, 55.0, 1, true, 8.0)
	_scatter(["DeadTree"], 10, 55.0, 2, true, 8.0)
	_scatter(["Rock_Medium"], 24, 55.0, 3, true, 0.0)
	_scatter(["Pebble", "RockPath"], 50, 55.0, 4, false, 0.0)
	_scatter(["Bush", "Fern", "Plant"], 90, 55.0, 5, false, 0.0)
	_scatter(["Grass", "Clover"], 140, 55.0, 6, false, 0.0)
	_scatter(["Flower", "Mushroom"], 70, 55.0, 7, false, 6.0)
	# Drop the player in to explore.
	var player: Node3D = (load("res://entities/player/player.tscn") as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0.0, 1.5, 0.0)

func _scatter(filter: Array, count: int, radius: float, rng_seed: int, collision: bool, clear: float) -> void:
	var s: Node3D = load("res://entities/props/nature_scatter.gd").new()
	s.set("models_dir", NATURE_DIR)
	s.set("name_filter", PackedStringArray(filter))
	s.set("count", count)
	s.set("area_radius", radius)
	s.set("rng_seed", rng_seed)
	s.set("make_collision", collision)
	s.set("clear_radius", clear)
	add_child(s)

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_horizon_color = Color(0.7, 0.8, 0.9)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)

func _build_ground() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(140.0, 1.0, 140.0)
	col.shape = box
	col.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(140.0, 140.0)
	mesh.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.33, 0.43, 0.24)
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)
