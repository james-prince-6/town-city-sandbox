# sunpetal_meadow.gd
# A themed SUBCLASS of WildArea: "Sunpetal Meadow" — a bright, sunny orchard/grassland with
# a calm, low-stakes farming vibe. It owns nothing but config: it sets the base's members to
# describe THIS biome, then calls super() so wild_area.gd assembles the whole self-contained
# scene (sky/sun/ambient, ground + walls, scattered foliage, harvestables, wildlife, the
# Player on a "from_town" marker, and the glowing return gate back to town).
#
# WHY a meadow biome of pure data: the heavy lifting (and the SceneManager contract) lives in
# the base, so this file stays a small, readable description that's cheap to tweak. The theme
# is FOOD-rich — berry bushes, herbs, the meadow-special wild honey hives, mushroom patches,
# and a handful of oak trees — with mostly peaceful livestock and a single hostile boar so the
# place still has a little bite without losing the sunny, farming mood.
#
# The base reads these members AFTER they're set, so they MUST be assigned BEFORE super().
extends "res://stages/wild/wild_area.gd"

func _ready() -> void:
	# Human label (gate sign) + the town marker the player lands on when returning.
	area_title = "Sunpetal Meadow"
	return_spawn = &"from_meadow"

	# Bright, sunny grassland palette: vivid green ground under a clear, luminous sky.
	ground_color = Color(0.34, 0.62, 0.22)
	sky_top = Color(0.32, 0.58, 0.92)
	sky_horizon = Color(0.82, 0.92, 0.99)
	sun_color = Color(1.0, 0.97, 0.86)
	sun_energy = 1.4
	ambient_energy = 1.2

	# Collidable nature: a few orchard trees + boulders the player bumps into.
	nature_filters_collide = PackedStringArray(["CommonTree", "Rock_Medium"])
	# Walk-through dressing: lots of flowers, grass and low plants for the meadow look.
	nature_filters_foliage = PackedStringArray(["Flower", "Grass", "Clover", "Plant", "Bush"])

	# FOOD-rich harvestables. honey_hive is the meadow SPECIAL (drops wild_honey).
	resource_nodes = [
		{"path": "res://entities/harvestables/berry_bush.tscn", "count": 12, "clear": 6.0},
		{"path": "res://entities/harvestables/herb_plant.tscn", "count": 8, "clear": 5.0},
		{"path": "res://entities/harvestables/honey_hive.tscn", "count": 5, "clear": 7.0},
		{"path": "res://entities/harvestables/mushroom_patch.tscn", "count": 4, "clear": 5.0},
		{"path": "res://entities/harvestables/tree_oak.tscn", "count": 6, "clear": 8.0},
	]

	# Peaceful livestock + a single hostile boar mixed into the wildlife pool.
	animal_variants = PackedStringArray([
		"res://entities/animals/cow.tscn",
		"res://entities/animals/pig.tscn",
		"res://entities/animals/chicken.tscn",
		"res://entities/animals/rabbit.tscn",
		"res://entities/animals/boar.tscn",
	])
	animal_count = 12

	# Hand the fully-described config to the base, which does all the actual building.
	super()
