# cinder_barrens.gd
# The CINDER BARRENS wild area: a harsh, smoke-choked volcanic ash waste where almost nothing
# grows and the few living things want you dead. Like every themed wild area this is a tiny
# data-only subclass of WildArea (res://stages/wild/wild_area.gd): we set the theme/content
# config members here, then call super() so the base assembles the whole self-contained scene
# (themed sky+sun+fog, ground+walls, sparse scatter, deterministically-placed harvestables +
# hostile wildlife + enemies, the Player on a "from_town" marker, and a return gate to town).
#
# WHY a subclass: content stays ~20 lines of pure config; the base owns all building logic and
# the SceneManager contract. The base reads these members AFTER they're set, so they MUST be
# assigned BEFORE super().
extends "res://stages/wild/wild_area.gd"

func _ready() -> void:
	# --- Identity / return-to-town ---
	area_title = "Cinder Barrens"
	return_spawn = &"from_barrens"

	# --- Theme: dark charcoal ash ground under a dusky, smoke-reddened sky, dim red sun ---
	ground_color = Color(0.12, 0.10, 0.10)            # dark charcoal ash
	sky_top = Color(0.30, 0.12, 0.08)                  # dusky red overhead
	sky_horizon = Color(0.55, 0.25, 0.12)              # smoldering orange at the horizon
	sun_color = Color(0.85, 0.45, 0.32)                # dim reddish sun
	sun_energy = 0.7
	ambient_energy = 0.6
	# Smoky haze hangs over the wastes.
	fog_enabled = true
	fog_color = Color(0.35, 0.22, 0.18)
	fog_density = 0.02

	# --- Sparse, dead nature: only charred trees + boulders, with a few scattered pebbles ---
	nature_filters_collide = PackedStringArray(["DeadTree", "Rock_Medium"])
	nature_filters_foliage = PackedStringArray(["Pebble"])

	# --- Harvestables: stone, sulfur vents (the barrens special), crystal, and iron rock ---
	resource_nodes = [
		{"path": "res://entities/harvestables/stone_node.tscn", "count": 8, "clear": 6.0},
		# Barrens special: sulfur vents are dense here (sulfur_crystal).
		{"path": "res://entities/harvestables/sulfur_vent.tscn", "count": 8, "clear": 6.0},
		{"path": "res://entities/harvestables/crystal_cluster.tscn", "count": 6, "clear": 7.0},
		{"path": "res://entities/harvestables/rock.tscn", "count": 6, "clear": 6.0},
	]

	# --- Hostile wildlife roaming the ash ---
	animal_variants = PackedStringArray([
		"res://entities/animals/ash_bear.tscn",
		"res://entities/animals/mountain_lion.tscn",
	])
	animal_count = 5

	# --- Combat tie-in: melee fire creatures stalk the barrens ---
	enemy_scenes = PackedStringArray([
		"res://entities/enemies/ember_hound.tscn",
		"res://entities/enemies/gnasher.tscn",
	])
	enemy_count = 4

	# --- Dungeon entrances: two grim mouths in the ash, on opposite flanks ---
	# Set BEFORE super(); the base builds a cave-mouth gate at each pos. Both dungeons return
	# the player to this area's always-built "from_dungeon" marker.
	dungeon_entrances = [
		{"scene": "res://stages/dungeons/abandoned_mine.tscn", "label": "Abandoned Mine", "pos": Vector3(-24, 0, 18)},
		{"scene": "res://stages/dungeons/abandoned_power_plant.tscn", "label": "Abandoned Power Plant", "pos": Vector3(26, 0, 16)},
	]

	# Hand off to the base, which builds the entire scene from the config above.
	super()
