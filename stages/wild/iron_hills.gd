# iron_hills.gd
# A rocky highland QUARRY biome — one of the themed "wild area" destinations. This subclass
# owns nothing but data: it sets the WildArea config members for the Iron Hills, then calls
# super() so the shared base (res://stages/wild/wild_area.gd) assembles the whole walkable,
# self-contained scene (sky/sun, ground+walls, scatter, resources, wildlife, the Player on a
# "from_town" marker, and the glowing return gate back to town).
#
# WHY this area exists: it's the player's mining ground for METAL ORE. Its signature node is
# the gold_vein (the "hills special"), backed by plentiful stone + iron rock and a sparse
# stand of hardy pines/dead trees. A mostly-peaceful herd (cows, deer, rabbits) grazes the
# slopes while a sparse pair of predators (mountain lion + tiger) prowls — no scripted
# enemies, the few cats ARE the threat, and they're shaved just slow enough to outrun.
#
# Theme: pale highland sky, grey-brown stone ground, fewer trees than the woods.
extends "res://stages/wild/wild_area.gd"

# --- Wildlife danger tuning -------------------------------------------------
# The Iron Hills should READ AS A GATHER ZONE with ambient danger, not a predator gauntlet.
# The shared base scatters animal_variants by sampling the pool UNIFORMLY, so we weight the
# roster by listing each species multiple times: many grazer copies + few predator copies =
# a mostly-peaceful highland that still has the odd big cat prowling. All knobs are exported
# so the balance can be tuned without code.

## Peaceful grazer species that dominate the hills (cows, deer, rabbits…).
@export var grazer_scenes: PackedStringArray = PackedStringArray([
	"res://entities/animals/cow.tscn",
	"res://entities/animals/deer.tscn",
	"res://entities/animals/rabbit.tscn",
])
## The ONLY predator species that prowl the slopes — kept to two so danger is occasional.
@export var predator_scenes: PackedStringArray = PackedStringArray([
	"res://entities/animals/mountain_lion.tscn",
	"res://entities/animals/tiger.tscn",
])
## Pool copies PER grazer species vs PER predator species. Because the base samples the pool
## uniformly, these act as spawn weights: the defaults (4 vs 1) make predators roughly 1-in-7
## picks, so the roster lands ~85% peaceful — a gather zone, not a gauntlet.
@export var grazer_weight: int = 4
@export var predator_weight: int = 1
## Total wildlife instances scattered across the hills.
@export var wildlife_count: int = 10
## Chase-speed shave for the hills' predators (see WildArea.hostile_animal_speed_scale): big
## cats stay faster than a walk (5.5 -> ~5.2 vs player 5.0) but slow enough a SPRINTING player
## can break away — so a caught player can still escape instead of being run down for sure.
@export var predator_speed_scale: float = 0.95

func _ready() -> void:
	area_title = "Iron Hills"
	# Telegraph the danger right on arrival: this is a quarry to mine, with cats about.
	area_tagline = "Mining country — mind the big cats"
	# town_template must contain a Marker3D named "from_hills" for the return gate landing.
	return_spawn = &"from_hills"

	# Grey-brown stone underfoot, a pale washed-out highland sky.
	ground_color = Color(0.42, 0.38, 0.34)
	sky_top = Color(0.55, 0.62, 0.72)
	sky_horizon = Color(0.82, 0.84, 0.86)
	sun_color = Color(1.0, 0.98, 0.93)
	sun_energy = 1.15
	ambient_energy = 1.0

	# Collidable nature: scattered boulders and hardy highland trees (sparse — a quarry, not a forest).
	nature_filters_collide = PackedStringArray(["Rock_Medium", "DeadTree", "Pine"])
	# Walk-through dressing: tufts of grass, loose pebbles, the odd bush.
	nature_filters_foliage = PackedStringArray(["Grass", "Pebble", "Bush"])

	# Resource nodes. The gold_vein is the Iron Hills SPECIAL; stone + iron rock are the staples.
	resource_nodes = [
		{"path": "res://entities/harvestables/stone_node.tscn", "count": 14, "clear": 6.0},
		{"path": "res://entities/harvestables/rock.tscn", "count": 12, "clear": 6.0},
		{"path": "res://entities/harvestables/gold_vein.tscn", "count": 5, "clear": 8.0},
		{"path": "res://entities/harvestables/tree_pine.tscn", "count": 6, "clear": 6.0},
	]

	# Wildlife: a mostly-peaceful grazer roster weighted heavily over a sparse pair of
	# predators, so the hills graze calm with the occasional prowling cat. Build the weighted
	# pool from the tunables above (grazer species listed grazer_weight times each, predators
	# predator_weight times each), then hand it to the base scatter.
	var roster := PackedStringArray()
	for _g in range(maxi(0, grazer_weight)):
		roster.append_array(grazer_scenes)
	for _p in range(maxi(0, predator_weight)):
		roster.append_array(predator_scenes)
	animal_variants = roster
	animal_count = wildlife_count
	# Soften the predators so a caught player can kite/sprint away (base applies this after
	# scattering, only to hostile animals).
	hostile_animal_speed_scale = predator_speed_scale

	# No scripted enemies here — the predators above provide the threat.
	enemy_scenes = PackedStringArray([])
	enemy_count = 0

	# --- Dungeon entrance: a Crystal Cave bored into the hillside ---
	# Set BEFORE super(); the base builds the cave-mouth gate. The cave returns the player to
	# this area's always-built "from_dungeon" marker.
	dungeon_entrances = [
		{"scene": "res://stages/dungeons/crystal_cave.tscn", "label": "Crystal Cave", "pos": Vector3(24, 0, -20)},
	]

	super()
