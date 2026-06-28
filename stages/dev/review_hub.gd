# review_hub.gd
# DEV-ONLY review launcher (open with F6). Drops you in a lit room with a FULL test
# kit (tools, weapons, money, and a stack of every quest/rare item) and a labelled
# warp gate to every new area, interior and dungeon — so you can hop straight to each
# place and eyeball the things headless tests can't verify (gate heights, model scale,
# skins, furniture dressing, dungeon look, quest turn-ins, shop + house upgrades).
#
# Workflow: aim at a gate, press E to warp. To pick another destination, stop the run
# (F8) and press F6 again. Most destinations' own "Leave" door returns you to town.
# See docs/PLAYTEST_CHECKLIST.md for what to look at in each place.
extends Node3D

const PLAYER_SCENE := "res://entities/player/player.tscn"
const GATE_SCRIPT := "res://global/teleport area/teleport_raycast.gd"
const ACTION_SCRIPT := "res://stages/dev/review_action.gd"

func _ready() -> void:
	_build_environment()
	_build_floor()
	_build_player()
	_build_gates()
	_build_bench()
	_grant_kit.call_deferred()

# --- Test kit ---------------------------------------------------------------

func _grant_kit() -> void:
	await get_tree().process_frame
	GameState.add_money(9999)
	# Tools to work every harvestable (incl. the rare PICKAXE-pwr2 gem nodes).
	for id in [&"pickaxe", &"hatchet", &"magma_pick", &"crystal_pickaxe", &"lava_ladle"]:
		Inventory.add(id, 1)
	# A bit of combat kit for the dungeons.
	Inventory.add(&"steel_sword", 1)
	Inventory.add(&"bow", 1)
	Inventory.add(&"health_potion", 5)
	# A stack of every quest/rare/craft item so turn-ins, the shop, crafting and house
	# upgrades are all immediately testable without grinding.
	var stock := {
		&"scrap_metal": 12, &"power_core": 4, &"raw_gemstone": 8, &"glow_crystal": 8,
		&"rusted_key": 3, &"wood_plank": 10, &"wood_log": 12, &"copper_ingot": 8,
		&"gold_ingot": 4, &"iron_ore": 12, &"stone": 12, &"cave_mushroom": 8,
		&"wild_honey": 8, &"herb_bundle": 8, &"coconut": 6, &"plant_fiber": 8, &"hardwood": 6,
		# Crafted-tier mats + gear, so the new recipes/shop/held-models are testable immediately.
		&"refined_metal": 6, &"cut_gemstone": 6, &"power_cell": 3, &"gemstone_pendant": 2,
		&"glow_lamp": 1, &"reinforced_pickaxe": 1, &"radiant_sword": 1, &"glow_staff": 1,
		# Food, so the healing economy (eat to heal) is testable.
		&"cooked_meat": 5, &"banana": 5, &"raw_meat": 4, &"animal_hide": 4,
	}
	for id in stock:
		Inventory.add(id, stock[id])
	# Lay the tools out on the hotbar.
	Hotbar.set_slot(0, &"pickaxe")
	Hotbar.set_slot(1, &"hatchet")
	Hotbar.set_slot(2, &"steel_sword")
	Hotbar.set_slot(3, &"bow")
	Hotbar.set_slot(4, &"magma_pick")
	Hotbar.set_slot(5, &"crystal_pickaxe")
	Hotbar.set_slot(6, &"lava_ladle")
	Hotbar.set_slot(7, &"health_potion")
	Hotbar.select(0)

# --- Gates ------------------------------------------------------------------

func _build_gates() -> void:
	# Each row is a category. (label, scene_path, spawn) — spawn "from_town" enters
	# wild/interiors at their door; dungeons + town use "" (they place their own player).
	var wild := [
		["Woods", "res://stages/wild/whispering_woods.tscn", &"from_town"],
		["Hills", "res://stages/wild/iron_hills.tscn", &"from_town"],
		["Meadow", "res://stages/wild/sunpetal_meadow.tscn", &"from_town"],
		["Barrens", "res://stages/wild/cinder_barrens.tscn", &"from_town"],
	]
	var interiors := [
		["Player House", "res://stages/interiors/player_house.tscn", &"from_town"],
		["Town Hall", "res://stages/interiors/town_hall.tscn", &"from_town"],
		["General Store", "res://stages/interiors/general_store_inside.tscn", &"from_town"],
		["Apothecary", "res://stages/interiors/apothecary_inside.tscn", &"from_town"],
		["Cottage Warm", "res://stages/interiors/cottage_warm.tscn", &"from_town"],
		["Cottage Cozy", "res://stages/interiors/cottage_cozy.tscn", &"from_town"],
		["Abandoned Cabin", "res://stages/interiors/abandoned_cabin.tscn", &"from_town"],
	]
	var dungeons := [
		["Crystal Cave", "res://stages/dungeons/crystal_cave.tscn", &""],
		["Abandoned Mine", "res://stages/dungeons/abandoned_mine.tscn", &""],
		["Town Sewer", "res://stages/dungeons/town_sewer.tscn", &""],
		["Power Plant", "res://stages/dungeons/abandoned_power_plant.tscn", &""],
		["Cabin Cellar", "res://stages/dungeons/cabin_cellar.tscn", &""],
		["Proc. Dungeon", "res://stages/dungeons/procedural/generated_dungeon.tscn", &""],
	]
	var misc := [
		["TOWN", "res://stages/overworld/town_template.tscn", &""],
		["Combat Arena", "res://stages/dev/combat_arena.tscn", &""],
	]
	_build_row("WILD AREAS", wild, -6.0, Color(0.4, 0.8, 0.4))
	_build_row("INTERIORS", interiors, -1.0, Color(0.85, 0.7, 0.4))
	_build_row("ENEMY DUNGEONS", dungeons, 4.0, Color(0.85, 0.4, 0.5))
	_build_row("MISC", misc, 9.0, Color(0.5, 0.6, 0.9))

# --- Test bench (debug-action pillars, aim + E) -----------------------------

func _build_bench() -> void:
	# (label, action) — fire with E to exercise slow-to-reach systems.
	var actions := [
		["+Rep All", &"rep_up"], ["-Rep All", &"rep_down"], ["+Day", &"day"],
		["+6h", &"time6"], ["+XP", &"xp"], ["Give Gear", &"gear"],
		["Hurt 60", &"hurt"], ["Heal", &"heal"], ["+Money", &"money"],
	]
	var tint := Color(0.95, 0.85, 0.4)
	var z: float = 12.0
	var spacing: float = 2.6
	var start_x: float = -float(actions.size() - 1) * 0.5 * spacing
	var head := Label3D.new()
	head.text = "TEST BENCH  (aim + E)"
	head.font_size = 80
	head.pixel_size = 0.012
	head.modulate = tint
	head.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	head.position = Vector3(0.0, 3.6, z)
	add_child(head)
	for i in range(actions.size()):
		var a: Array = actions[i]
		_action_pillar(String(a[0]), a[1], Vector3(start_x + i * spacing, 0.0, z), tint)

func _action_pillar(label: String, action: StringName, pos: Vector3, tint: Color) -> void:
	var pillar := StaticBody3D.new()
	pillar.set_script(load(ACTION_SCRIPT))
	pillar.set("action", action)
	pillar.set("label", label)
	add_child(pillar)
	pillar.global_position = pos
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 2.0, 1.2)
	col.shape = box
	col.position = Vector3(0.0, 1.0, 0.0)
	pillar.add_child(col)
	var mesh := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.55
	cyl.height = 1.6
	mesh.mesh = cyl
	mesh.position = Vector3(0.0, 0.8, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 0.6
	mesh.material_override = mat
	pillar.add_child(mesh)
	var sign_label := Label3D.new()
	sign_label.text = label
	sign_label.font_size = 44
	sign_label.pixel_size = 0.009
	sign_label.outline_size = 10
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.position = Vector3(0.0, 2.1, 0.0)
	pillar.add_child(sign_label)

func _build_row(header: String, entries: Array, z: float, tint: Color) -> void:
	var n: int = entries.size()
	var spacing: float = 3.0
	var start_x: float = -float(n - 1) * 0.5 * spacing
	# Category header floating above the row.
	var head := Label3D.new()
	head.text = header
	head.font_size = 80
	head.pixel_size = 0.012
	head.modulate = tint
	head.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	head.position = Vector3(0.0, 3.6, z)
	add_child(head)
	for i in range(n):
		var e: Array = entries[i]
		_gate(String(e[0]), String(e[1]), e[2], Vector3(start_x + i * spacing, 0.0, z), tint)

func _gate(label: String, scene_path: String, spawn: StringName, pos: Vector3, tint: Color) -> void:
	var gate := StaticBody3D.new()
	gate.set_script(load(GATE_SCRIPT))
	gate.set("target_scene_path", scene_path)
	gate.set("prompt_text", "Go: " + label)
	gate.set("target_spawn_point", spawn)
	add_child(gate)
	gate.global_position = pos
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 2.4, 1.4)
	col.shape = box
	col.position = Vector3(0.0, 1.2, 0.0)
	gate.add_child(col)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 2.2, 1.0)
	mesh.position = Vector3(0.0, 1.1, 0.0)
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.emission_enabled = true
	mat.emission = tint
	mat.emission_energy_multiplier = 0.8
	mesh.material_override = mat
	gate.add_child(mesh)
	var sign_label := Label3D.new()
	sign_label.text = label
	sign_label.font_size = 48
	sign_label.pixel_size = 0.01
	sign_label.outline_size = 10
	sign_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_label.position = Vector3(0.0, 2.6, 0.0)
	gate.add_child(sign_label)

# --- Shell ------------------------------------------------------------------

func _build_player() -> void:
	var player: Node3D = (load(PLAYER_SCENE) as PackedScene).instantiate()
	add_child(player)
	# Spawn behind the Test Bench (z=12), facing -Z toward the bench then the warp gates.
	player.global_position = Vector3(0.0, 1.5, 15.5)

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.36, 0.5)
	sky_mat.sky_horizon_color = Color(0.5, 0.55, 0.62)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.2
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -40.0, 0.0)
	sun.light_energy = 1.2
	add_child(sun)
	var title := Label3D.new()
	title.text = "REVIEW HUB — aim + E to warp. F8 to stop, F6 to return here."
	title.font_size = 56
	title.pixel_size = 0.011
	title.modulate = Color(1, 1, 1)
	title.outline_size = 12
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.position = Vector3(0.0, 4.6, 1.0)
	add_child(title)

func _build_floor() -> void:
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40.0, 1.0, 44.0)
	col.shape = box
	col.position = Vector3(0.0, -0.5, 0.0)
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40.0, 44.0)
	mesh.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.24, 0.26)
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)
