# whispering_woods.gd
# Themed SUBCLASS of WildArea for the WHISPERING WOODS — a lush, green, dappled forest
# biome reached from town and returned-from via the &"from_woods" marker. This file is pure
# CONFIG: it sets the base's members BEFORE calling super(), and the base (wild_area.gd) does
# ALL the building (sky/sun/ambient, ground + walls, foliage scatter, resource/animal scatter,
# the Player on a "from_town" marker, and the glowing return gate).
#
# WHY only data here: see wild_area.gd's header — every biome shares the same correct
# SceneManager contract and scatter logic, so a new area is just this ~20-line override.
#
# THE WOODS SPECIAL is the hardwood tree (hardwood_tree.tscn -> drops "hardwood"): a rarer,
# tougher chop than the common oak/pine, exclusive flavour of this forest.
extends "res://stages/wild/wild_area.gd"

func _ready() -> void:
	# --- Identity / return contract ---
	area_title = "Whispering Woods"
	return_spawn = &"from_woods"

	# --- Theme: lush mossy-green ground, soft blue sky, warm dappled sun ---
	ground_color = Color(0.22, 0.38, 0.16)        # mossy forest green
	sky_top = Color(0.30, 0.52, 0.82)             # soft blue overhead
	sky_horizon = Color(0.72, 0.85, 0.92)         # pale hazy horizon
	sun_color = Color(1.0, 0.95, 0.82)            # warm sunlight
	sun_energy = 1.0
	ambient_energy = 0.9                          # gentle, dappled fill

	# --- Nature dressing (decoration only; not harvestable) ---
	# Collidable: forest trees + scattered boulders the player bumps into.
	nature_filters_collide = PackedStringArray(["CommonTree", "Pine", "TwistedTree", "Rock_Medium"])
	# Walk-through undergrowth: bushes, ferns, plants, grass, flowers, mushrooms.
	nature_filters_foliage = PackedStringArray(["Bush", "Fern", "Plant", "Grass", "Flower", "Mushroom"])

	# --- Harvestable resource nodes (deterministic scatter) ---
	resource_nodes = [
		{"path": "res://entities/harvestables/tree_oak.tscn", "count": 14, "clear": 8.0},
		{"path": "res://entities/harvestables/tree_pine.tscn", "count": 10, "clear": 8.0},
		{"path": "res://entities/harvestables/hardwood_tree.tscn", "count": 4, "clear": 10.0},  # WOODS SPECIAL
		{"path": "res://entities/harvestables/herb_plant.tscn", "count": 10, "clear": 5.0},
		{"path": "res://entities/harvestables/mushroom_patch.tscn", "count": 8, "clear": 5.0},
		{"path": "res://entities/harvestables/berry_bush.tscn", "count": 6, "clear": 5.0},
	]

	# --- Wildlife: peaceful deer/rabbit/fox + a hostile boar in the mix ---
	animal_variants = PackedStringArray([
		"res://entities/animals/deer.tscn",
		"res://entities/animals/rabbit.tscn",
		"res://entities/animals/fox.tscn",
		"res://entities/animals/boar.tscn",
	])
	animal_count = 10

	# No standalone combat enemies in the woods — the boar is the only threat.

	# --- Dungeon entrance: the Abandoned Cabin tucked near the tree line ---
	# Set BEFORE super() so the base builds a cave-mouth gate at this position. The cabin
	# interior sets exit_scene_path back to this woods scene with exit_spawn_point=&"from_cabin".
	dungeon_entrances = [
		{"scene": "res://stages/interiors/abandoned_cabin.tscn", "label": "Abandoned Cabin", "pos": Vector3(-22, 0, -18)},
	]

	# Hand off to the base, which assembles the whole scene from the config above.
	super()

	# AFTER super() (which has built everything, including the gates): add a dedicated
	# "from_cabin" marker at the cabin gate so leaving the cabin drops the player right
	# beside its doorway rather than at the generic "from_dungeon" entry.
	var cabin_marker := Marker3D.new()
	cabin_marker.name = "from_cabin"
	add_child(cabin_marker)
	cabin_marker.global_position = Vector3(-22, 1.5, -15)
