# dungeon_generator.gd
# A deterministic, seed-driven PROCEDURAL dungeon builder. Attach to a Node3D and call
# build(seed, difficulty) — it constructs an entire playable level in code: lighting +
# atmosphere, room-and-corridor geometry (BoxMesh + BoxShape3D, exactly like the hand-built
# dungeon_mine.tscn), spawn/respawn markers, an exit teleporter, and a populated set of
# enemies (via EnemySpawner).
#
# Why build geometry from primitives (not FBX kit pieces)?
# It mirrors how dungeon_mine.tscn is authored (StaticBody3D floors/walls with Box collision
# + Box mesh), needs zero art dependencies, and the "wall wherever a floor tile has no floor
# neighbour" rule below GUARANTEES the player and enemies are sealed in, with corridor doorways
# appearing automatically wherever a corridor meets a room.
#
# THE ALGORITHM (simple + reliable):
#   1. A coarse MACRO GRID of cells. One room is placed inside each of the first N cells, with
#      a random footprint and offset that always stays INSIDE its cell — so rooms can never
#      overlap (no rejection sampling, no infinite loops).
#   2. Rooms are CHAINED with L-shaped, 1-tile-wide corridors (room i to room i-1), which
#      guarantees the whole dungeon is connected.
#   3. Everything is carved into a tile occupancy map (Dictionary of Vector2i). We then emit
#      a floor box per occupied tile, and a wall box on every tile edge whose neighbour is
#      empty. That single rule both encloses rooms AND opens corridor doorways for free.
#
# DETERMINISM:
#   build(seed) creates `var rng := RandomNumberGenerator.new(); rng.seed = seed`. EVERY random
#   draw (room sizes, offsets, light/marker scatter, the enemy army) flows from that rng, so a
#   given seed always rebuilds the exact same dungeon. We never call the global randf().
#
# REGENERATION:
#   build() first clears everything it previously made (keeping only the scene's Player child),
#   so calling build() again with a new seed swaps in a brand-new dungeon in place.
#
# GROUPS / MARKER NAMES it produces (matched by SceneManager.find_child by NAME):
#   - "from_overworld"   Marker3D in the START room  (group "respawn_point") — default entry id
#   - "Respawn_Entrance" Marker3D in the START room  (group "respawn_point") — mine-style entry id
#   - "Respawn_Room_<n>" Marker3D per room           (group "respawn_point")
#   - "EnemySpawn_*"     Marker3D scattered in non-start rooms (group "enemy_spawn")
#   - "ExitTeleport"     an ExitPortal (exit_portal.gd) in the START room — a glowing, signed
#                        "Leave Dungeon" portal (walk into it OR look + interact) back to town

class_name DungeonGenerator
extends Node3D

# --- Scene / wiring exports -------------------------------------------------
## Seed used by the scene's own _ready() bootstrap so opening the scene Just Works.
@export var start_seed: int = 12345
## Difficulty handed to the EnemySpawner by the _ready() bootstrap.
@export var difficulty: int = 1
## Where the exit teleporter sends the player. Wire this to your overworld hub.
@export_file("*.tscn") var exit_scene_path: String = "res://stages/overworld/town_template.tscn"
## Spawn-marker name the exit requests in the destination scene.
@export var exit_spawn_point: StringName = &"from_dungeon"
## When true, and ONLY if the player arrives with an empty hotbar (e.g. opening this scene
## directly with F6), hand them a basic kit so the dungeon is immediately playable. A player
## who enters from the overworld already armed keeps their own gear (this won't fire).
@export var grant_starter_kit: bool = true
## Locks this scene's biome: when non-empty and it matches a theme name (case-insensitive),
## _pick_theme returns that theme on EVERY floor instead of the seed-random pick. Empty (default)
## keeps the original per-seed random theme. Lets an entrance scene pin its dungeon to one biome
## (e.g. "Cave", "Mine", "Sewer", "PowerPlant").
@export var forced_theme_name: String = ""
## Extra RARE harvestable/loot item ids this dungeon can yield (e.g. &"scrap_metal", &"power_core",
## &"raw_gemstone", &"glow_crystal", &"rusted_key"). When non-empty these are (a) folded into the
## reward/vault chest contents and (b) the menu _place_rare_nodes draws its scattered rare harvest
## nodes from. Empty (default) reproduces the original loot exactly.
@export var rare_loot_ids: Array[StringName] = []

# --- Geometry constants (METERS, consistent with dungeon_mine.tscn) ---------
const TILE_SIZE: float = 4.0       # one floor tile is 4m x 4m
const WALL_HEIGHT: float = 4.0     # matches the mine's 4m walls
const WALL_THICKNESS: float = 0.5  # thin-ish wall slabs
const FLOOR_THICKNESS: float = 1.0 # floor slab is 1m tall, centered at y=-0.5 (top at y=0)
const MARKER_Y: float = 1.0        # marker height off the floor (player capsule sized)

# --- Layout constants ------------------------------------------------------
const MIN_ROOMS: int = 5
const MAX_ROOMS: int = 8
const MIN_ROOM_TILES: int = 2      # 8m
const MAX_ROOM_TILES: int = 4      # 16m
const MACRO_CELL_TILES: int = 7    # room (<=4) + spacing/corridor margin, prevents overlap

# 4-neighbour directions on the tile grid (for the wall-emission rule).
const DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

# --- KayKit Dungeon Remastered art pieces ----------------------------------
# Measured on import: floor_tile_large is exactly 4x4m centred at origin; wall is 4 wide x 4 tall
# x 1 thick, base at y=0, default running along X (facing +/-Z); pillar is 1.5x4 base-centred. All
# on the same 4m grid as TILE_SIZE, so they drop in with NO scaling. We keep invisible box
# colliders for clean physics + navmesh and lay these meshes on top.
const KIT_FLOOR: PackedScene = preload("res://assets/models/dungeon_kit/floor_tile_large.gltf")
const KIT_WALL: PackedScene = preload("res://assets/models/dungeon_kit/wall.gltf")
const KIT_PILLAR: PackedScene = preload("res://assets/models/dungeon_kit/pillar.gltf")

# --- Progression -----------------------------------------------------------
## Every Nth floor is a BOSS floor: a boss waits in the end room and the way down stays
## sealed until it dies. 3 = floors 3, 6, 9, ...
const BOSS_EVERY: int = 3
## Extra EnemySpawner difficulty added per floor descended (floor N = difficulty + (N-1)*this).
const DIFFICULTY_PER_FLOOR: int = 2
## Floors are seeded as start_seed + (depth-1)*this, so each floor is its own deterministic level.
const FLOOR_SEED_STRIDE: int = 1013
## The boss spawned on boss floors (defaults to the mini-boss colossus). Kept as the FINAL
## FALLBACK for when every tier pool below (and the legacy boss_pool) is left empty.
@export_file("*.tscn") var boss_scene_path: String = "res://entities/enemies/magma_colossus.tscn"
## LEGACY un-tiered boss pool. Now only used as a fallback when the depth-tiered pools below are
## ALL emptied (kept so any scene that set this in the inspector still behaves). New code should
## tune the three tiered pools instead. Left empty by default — the tiered pools drive the choice.
@export var boss_pool: Array[String] = []

# --- Depth-tiered boss pools -----------------------------------------------
# WHY: a single flat pool meant floor 3 could roll the 600hp Magma Colossus while floor 9 rolled
# the 110hp Ravager — boss difficulty was a coin-flip, not a curve. _spawn_boss now picks the pool
# by depth tier = clampi((_depth-1)/BOSS_EVERY,0,2), so early boss floors only field light bruisers
# and the heavyweight colossus is reserved for the deep floors. Each pool is chosen from
# DETERMINISTICALLY off the generation rng (same seed => same boss). Empty a pool to fall through to
# the legacy boss_pool, then to boss_scene_path — so clearing all three reverts to the old behaviour.
## Boss floors 1-3 (depth 1..3): light, fast bruisers (~110-160hp). The first real boss fight.
@export var boss_pool_early: Array[String] = [
	"res://entities/enemies/obsidian_brute.tscn",  # 120hp
	"res://entities/enemies/ravager.tscn",         # 110hp
]
## Boss floors 4-6 (depth 4..6): the tougher bruisers step up.
@export var boss_pool_mid: Array[String] = [
	"res://entities/enemies/iron_bruiser.tscn",    # 160hp
	"res://entities/enemies/obsidian_brute.tscn",  # 120hp
]
## Boss floors 7+ (depth 7..): the heavyweight colossus becomes possible — a true wall of HP.
@export var boss_pool_late: Array[String] = [
	"res://entities/enemies/magma_colossus.tscn",  # 600hp
	"res://entities/enemies/iron_bruiser.tscn",    # 160hp
]
## Soft cap on the per-boss-floor HP bump in _spawn_boss so deep colossus fights stay beatable
## rather than scaling without bound. The bump is 1.0 + 0.25*(boss_number-1), clamped to this.
@export var boss_hp_scale_max: float = 2.5

# --- Depth-tiered weapon loot pools ----------------------------------------
# WHY: loot weapon pools were FLAT — a floor-1 chest and a floor-10 chest drew from the same six
# weapons, so descending was never mechanically rewarding. _weapon_pool_for_depth picks by tier =
# clampi((_depth-1)/2,0,3) so early floors hand out basic gear and deep floors start dropping the
# high-tier blades. Selecting from a different-sized pool still consumes EXACTLY ONE rng draw per
# weapon (same as before), so enemy placement downstream is byte-identical for a given seed — only
# WHICH weapon changes. Empty a tier to revert that tier to the original six-weapon fallback list.
## Floors 1-2: starter melee + bow.
@export var weapon_pool_t0: Array[StringName] = [&"bow", &"steel_sword", &"iron_sword"]
## Floors 3-4: ranged + elemental wands enter the rotation.
@export var weapon_pool_t1: Array[StringName] = [&"steel_sword", &"crossbow", &"flame_wand", &"frost_wand"]
## Floors 5-6: the full wand set + a dark blade.
@export var weapon_pool_t2: Array[StringName] = [&"crossbow", &"flame_wand", &"frost_wand", &"arcane_wand", &"obsidian_blade"]
## Floors 7+: the top-tier blades and arcane gear — descending finally pays off.
@export var weapon_pool_t3: Array[StringName] = [&"arcane_wand", &"obsidian_blade", &"crystal_blade", &"greatsword", &"radiant_sword"]

# --- Depth-scaled atmosphere -----------------------------------------------
# WHY: every floor looked identically lit, so there was no felt sense of a crushing descent.
# _build_environment now thickens the fog and dims the ambient per floor (purely cosmetic — no
# combat/nav impact). All bounds are tunable and clamped so the deepest floors stay legible.
## Master gate for the per-floor fog/ambient ramp below. Off => the original per-theme look.
@export var enable_depth_scaling: bool = true
## Fractional fog-density increase per floor descended (floor N adds this * (N-1) of the base).
@export var fog_density_per_floor: float = 0.06
## Absolute ceiling on the scaled fog density so deep floors never become an unreadable pea-soup.
@export var fog_density_max: float = 0.12
## Fractional ambient-energy reduction per floor descended (deeper => darker).
@export var ambient_energy_per_floor: float = 0.04
## Floor under which the scaled ambient energy is never allowed to drop (keeps the floor legible).
@export var ambient_energy_min: float = 0.18

# --- Cosmetic detail scatter -----------------------------------------------
# WHY: extra ground-level flavour (rubble, ore veins, fungus) that reads as lived-in decay, kept
# entirely separate from the existing _scatter_clutter so it can be tuned/disabled independently.
# Implemented in dungeon_details.gd, loaded BY PATH (no class_name in the hot path), driven off a
# SEPARATE seed offset so toggling it never perturbs geometry/loot/enemy determinism. Collision-free.
## Master gate for the cosmetic detail scatter. Off => no detail pass at all (a true no-op).
@export var enable_details: bool = true
## Rough detail count per room tile (a 4-tile room ~= this * 4 details). Clamped per-room internally.
@export var details_density: float = 0.6

# Current floor (1-based). Bumped by descend(); resets to 1 whenever the scene reloads.
var _depth: int = 1
# The locked vault for this floor: { "rect": Rect2i, "doorways": Array of {tile,dir} } or {}.
var _vault: Dictionary = {}

# --- Shared materials (built once per build) -------------------------------
var _floor_mat: StandardMaterial3D
var _wall_mat: StandardMaterial3D

# The THEME chosen for the current floor (a row from _themes()). Set at the top of build() and
# read by _build_materials / _build_environment / _build_lights so a floor's whole palette is
# driven from one place. Stays {} until the first build().
var _theme: Dictionary = {}


# When run directly (F6) the scene needs to be playable with no external driver, so build a
# default dungeon and place our own Player child on the entry marker. When loaded through
# SceneManager.change_scene(...), this still builds in _ready (children run _ready before the
# parent, so the Player is already grouped and the markers exist), and SceneManager then moves
# the player onto whatever spawn id it was asked for — harmlessly on top of our own placement.
func _ready() -> void:
	_build_current_floor()
	_move_player_to_entry()
	# Deferred so the autoloads/hotbar have settled before we test-and-equip.
	_grant_starter_kit_if_unarmed.call_deferred()


# Build the floor matching the current _depth, deriving a per-floor seed + difficulty.
func _build_current_floor() -> void:
	var floor_seed: int = start_seed + (_depth - 1) * FLOOR_SEED_STRIDE
	var floor_diff: int = difficulty + (_depth - 1) * DIFFICULTY_PER_FLOOR
	build(floor_seed, floor_diff)


## Called by the DescendPortal to go one floor deeper. Deferred: build()'s _clear() frees the
## portal that called us, so we can't rebuild synchronously from inside its interact().
func descend() -> void:
	_descend_deferred.call_deferred()


func _descend_deferred() -> void:
	_depth += 1
	_build_current_floor()
	_move_player_to_entry()


## Build (or rebuild) the whole dungeon for `seed`. Deterministic: same seed => same level.
func build(seed: int, difficulty_level: int = 1) -> void:
	_clear()

	# Pick this floor's THEME first, so every palette consumer below (materials, environment,
	# lights) reads from it. Chosen via a DEDICATED rng seeded from `seed` so the choice is
	# stable for a seed yet never disturbs the main generation rng — geometry, markers, vault
	# and loot stay byte-identical to the un-themed build for the same seed.
	_theme = _pick_theme(seed)

	_build_materials()

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	var boss: bool = (_depth % BOSS_EVERY == 0)

	_build_environment()
	_build_sun()

	# 1) Lay out rooms, 2) carve them + connecting corridors into a tile map, 3) carve a
	#    locked vault (own room + single corridor) off to the side.
	var rooms: Array = _generate_rooms(rng)
	var floor_map: Dictionary = {}
	for room in rooms:
		var rect: Rect2i = room
		_carve_room(floor_map, rect)
	_connect_rooms(floor_map, rooms)
	_vault = _carve_vault(floor_map, rooms)

	# 4) Emit geometry from the tile map (floors + auto-enclosing walls + navmesh).
	_build_floor_and_walls(floor_map)
	_place_pillars(rooms)
	# Decorative themed clutter (rocks, barrels, dead trees, mushrooms...). Own rng seeded from
	# `seed` so it's stable per floor yet never perturbs the main rng (loot/enemies stay identical).
	_scatter_clutter(rooms, seed)
	# Cosmetic, collision-free detail scatter (rubble/veins/fungus). Loaded by PATH and given its
	# own seed offset inside the helper, so toggling enable_details never disturbs the main rng.
	_scatter_details(rooms, seed)

	# Atmosphere + navigation aids + progression furniture.
	_build_lights(rooms, rng)
	_place_markers(rooms, rng)
	_place_floor_label(rooms)
	var portal: DescendPortal = _place_descend_portal(rooms, boss)
	_place_town_exit(rooms)
	_place_loot(rooms, rng, seed, boss)
	_place_vault_contents(rng, seed)
	# Scatter rare harvestable nodes (own rng seeded from `seed`, so it never perturbs the main
	# rng — enemies/geometry stay byte-identical). No-op when rare_loot_ids is empty.
	_place_rare_nodes(rooms, rng, seed)

	# Populate the generated spawn markers with a seeded, budgeted army (scaled by depth).
	var spawner := EnemySpawner.new()
	spawner.name = "EnemySpawner"
	add_child(spawner)
	spawner.populate(self, difficulty_level, rng)

	# Boss floors: drop the boss in the reserved end room and gate the way down on its death.
	if boss:
		_spawn_boss(rooms, portal, rng)


# --- Cleanup ---------------------------------------------------------------

# Free everything we previously generated so build() can be called repeatedly. The scene's
# Player child (if any) is preserved. free() (not queue_free) is used so the names are
# available again immediately within the same build call.
func _clear() -> void:
	for child in get_children():
		if child.name == "Player":
			continue
		child.free()


# --- Floor themes ----------------------------------------------------------

# The palette table. Each floor wears one of these rows (chosen deterministically by
# _pick_theme), which drives the floor/wall albedo, the environment ambient + fog, and the
# cool->warm colour range the per-room lights lerp across. Geometry is identical across themes —
# only colours change. The first row (Stone) reproduces the ORIGINAL hardcoded look exactly.
func _themes() -> Array:
	return [
		{
			"name": "Stone",
			"floor_albedo": Color(0.13, 0.12, 0.14),  # dark stone (matches the mine)
			"wall_albedo": Color(0.17, 0.16, 0.19),   # slightly lighter tone than the floor
			"ambient_color": Color(0.22, 0.22, 0.3),
			"fog_color": Color(0.05, 0.05, 0.08),
			"fog_density": 0.025,
			"light_cool": Color(0.7, 0.8, 1.0),       # the cool end the room lights lerp from
			"light_warm": Color(1.0, 0.65, 0.35),     # ...to this warm ember end
		},
		{
			"name": "Frost",
			"floor_albedo": Color(0.16, 0.18, 0.22),
			"wall_albedo": Color(0.22, 0.26, 0.32),
			"ambient_color": Color(0.26, 0.32, 0.42),
			"fog_color": Color(0.16, 0.22, 0.3),
			"fog_density": 0.03,
			"light_cool": Color(0.6, 0.85, 1.0),
			"light_warm": Color(0.85, 0.95, 1.0),
		},
		{
			"name": "Ember",
			"floor_albedo": Color(0.18, 0.11, 0.09),
			"wall_albedo": Color(0.24, 0.13, 0.1),
			"ambient_color": Color(0.34, 0.18, 0.12),
			"fog_color": Color(0.18, 0.06, 0.03),
			"fog_density": 0.035,
			"light_cool": Color(1.0, 0.55, 0.3),
			"light_warm": Color(1.0, 0.78, 0.35),
		},
		{
			"name": "Bog",
			"floor_albedo": Color(0.11, 0.14, 0.1),
			"wall_albedo": Color(0.14, 0.18, 0.13),
			"ambient_color": Color(0.18, 0.26, 0.18),
			"fog_color": Color(0.08, 0.13, 0.07),
			"fog_density": 0.045,
			"light_cool": Color(0.6, 0.9, 0.7),
			"light_warm": Color(0.85, 0.95, 0.45),
		},
		{
			"name": "Cave",
			"floor_albedo": Color(0.15, 0.12, 0.09),
			"wall_albedo": Color(0.2, 0.16, 0.12),
			"ambient_color": Color(0.24, 0.2, 0.16),
			"fog_color": Color(0.09, 0.07, 0.05),
			"fog_density": 0.035,
			"light_cool": Color(0.7, 0.75, 0.85),
			"light_warm": Color(0.95, 0.7, 0.45),
		},
		{
			"name": "Mine",
			"floor_albedo": Color(0.16, 0.13, 0.1),
			"wall_albedo": Color(0.21, 0.17, 0.12),
			"ambient_color": Color(0.26, 0.22, 0.15),
			"fog_color": Color(0.1, 0.08, 0.05),
			"fog_density": 0.03,
			"light_cool": Color(0.8, 0.78, 0.7),
			"light_warm": Color(1.0, 0.72, 0.32),
		},
		{
			"name": "Sewer",
			"floor_albedo": Color(0.12, 0.15, 0.12),
			"wall_albedo": Color(0.14, 0.18, 0.15),
			"ambient_color": Color(0.18, 0.26, 0.2),
			"fog_color": Color(0.07, 0.12, 0.08),
			"fog_density": 0.06,
			"light_cool": Color(0.55, 0.85, 0.65),
			"light_warm": Color(0.7, 0.9, 0.5),
		},
		{
			"name": "PowerPlant",
			"floor_albedo": Color(0.16, 0.18, 0.21),
			"wall_albedo": Color(0.19, 0.22, 0.27),
			"ambient_color": Color(0.2, 0.24, 0.32),
			"fog_color": Color(0.08, 0.1, 0.14),
			"fog_density": 0.028,
			"light_cool": Color(0.6, 0.78, 1.0),
			"light_warm": Color(1.0, 0.75, 0.2),
		},
	]


# Choose this floor's theme from a DEDICATED rng seeded by the floor seed. Using its own rng
# (rather than the main generation rng) means theming a floor never shifts any other random draw,
# so geometry/markers/vault/loot reproduce exactly while the theme stays stable for the seed.
func _pick_theme(seed: int) -> Dictionary:
	var themes: Array = _themes()
	# Biome lock: if an entrance scene set forced_theme_name and it matches a theme (case-
	# insensitive), use that theme on every floor instead of the random draw. Falls through to the
	# seed-random pick when empty or unmatched, so the default behaviour is untouched.
	if forced_theme_name != "":
		var want: String = forced_theme_name.to_lower()
		for t in themes:
			var row: Dictionary = t
			if String(row.get("name", "")).to_lower() == want:
				return row
	var theme_rng := RandomNumberGenerator.new()
	theme_rng.seed = seed
	var idx: int = theme_rng.randi_range(0, themes.size() - 1)
	var chosen: Dictionary = themes[idx]
	return chosen


# --- Materials / atmosphere ------------------------------------------------

func _build_materials() -> void:
	var floor_albedo: Color = _theme["floor_albedo"]
	var wall_albedo: Color = _theme["wall_albedo"]

	_floor_mat = StandardMaterial3D.new()
	_floor_mat.albedo_color = floor_albedo
	_floor_mat.roughness = 1.0

	_wall_mat = StandardMaterial3D.new()
	_wall_mat.albedo_color = wall_albedo
	_wall_mat.roughness = 0.95


# Murky sky + ambient + fog, mirroring dungeon_mine.tscn's WorldEnvironment. Ambient + fog now
# come from the chosen theme (the sky stays a neutral murk across themes).
func _build_environment() -> void:
	var ambient_color: Color = _theme["ambient_color"]
	var fog_color: Color = _theme["fog_color"]
	var fog_density: float = _theme["fog_density"]
	var ambient_energy: float = 0.5

	# Depth ramp: each floor descended thickens the fog and dims the ambient a little, so a deep
	# floor reads as a crushing, suffocating descent. Bounds-clamped so the deepest floors stay
	# legible. Purely cosmetic — fog/ambient touch neither collision nor the baked navmesh.
	if enable_depth_scaling:
		var floors_down: int = maxi(_depth - 1, 0)
		fog_density = minf(fog_density * (1.0 + fog_density_per_floor * float(floors_down)), fog_density_max)
		ambient_energy = maxf(0.5 * (1.0 - ambient_energy_per_floor * float(floors_down)), ambient_energy_min)

	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_horizon_color = Color(0.1, 0.09, 0.12)
	sky_mat.ground_horizon_color = Color(0.03, 0.03, 0.05)

	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = ambient_color
	env.ambient_light_energy = ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = fog_color
	env.fog_density = fog_density

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)


func _build_sun() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.position = Vector3(0.0, 20.0, 0.0)
	sun.light_energy = 0.35
	sun.shadow_enabled = true
	add_child(sun)


# --- Room layout -----------------------------------------------------------

# Place one room per macro-cell for the first N cells of a near-square macro grid. Each room
# is sized + offset to stay WITHIN its cell, so rooms can never overlap.
func _generate_rooms(rng: RandomNumberGenerator) -> Array:
	var count: int = rng.randi_range(MIN_ROOMS, MAX_ROOMS)
	var cols: int = int(ceil(sqrt(float(count))))
	var rooms: Array = []

	for i in range(count):
		var mc: int = i % cols          # macro column
		var mr: int = i / cols          # macro row
		var base_x: int = mc * MACRO_CELL_TILES
		var base_z: int = mr * MACRO_CELL_TILES

		var w: int = rng.randi_range(MIN_ROOM_TILES, MAX_ROOM_TILES)
		var h: int = rng.randi_range(MIN_ROOM_TILES, MAX_ROOM_TILES)
		# Keep a >=1-tile margin inside the cell so neighbouring rooms never touch and the
		# connecting corridors have clear space to run.
		var max_ox: int = max(0, MACRO_CELL_TILES - w - 1)
		var max_oz: int = max(0, MACRO_CELL_TILES - h - 1)
		var ox: int = rng.randi_range(0, max_ox)
		var oz: int = rng.randi_range(0, max_oz)

		rooms.append(Rect2i(base_x + ox, base_z + oz, w, h))

	return rooms


# Mark every tile inside a room rectangle as floor.
func _carve_room(floor_map: Dictionary, rect: Rect2i) -> void:
	for tx in range(rect.position.x, rect.position.x + rect.size.x):
		for tz in range(rect.position.y, rect.position.y + rect.size.y):
			floor_map[Vector2i(tx, tz)] = true


# Chain the rooms with L-shaped, 1-tile corridors (room i <-> room i-1) so the whole dungeon
# is guaranteed connected.
func _connect_rooms(floor_map: Dictionary, rooms: Array) -> void:
	for i in range(1, rooms.size()):
		var a: Vector2i = _room_center_tile(rooms[i - 1])
		var b: Vector2i = _room_center_tile(rooms[i])
		_carve_corridor(floor_map, a, b)


func _room_center_tile(room) -> Vector2i:
	var rect: Rect2i = room
	return Vector2i(rect.position.x + rect.size.x / 2, rect.position.y + rect.size.y / 2)


# Carve an L: a horizontal run along a.y, then a vertical run along b.x.
func _carve_corridor(floor_map: Dictionary, a: Vector2i, b: Vector2i) -> void:
	var x0: int = min(a.x, b.x)
	var x1: int = max(a.x, b.x)
	for x in range(x0, x1 + 1):
		floor_map[Vector2i(x, a.y)] = true
	var z0: int = min(a.y, b.y)
	var z1: int = max(a.y, b.y)
	for z in range(z0, z1 + 1):
		floor_map[Vector2i(b.x, z)] = true


# --- Geometry emission -----------------------------------------------------

# Emit a floor box per occupied tile, plus a wall box on every tile edge whose neighbour is
# empty. The wall rule encloses rooms and opens corridor doorways automatically. Floors and
# walls go UNDER a NavigationRegion3D so we can bake a walkable navmesh from them (the
# eroded-by-agent-radius bake leaves thin wall-tops un-walkable and carves corridors, so
# enemies path room-to-room through doorways instead of clipping through walls).
func _build_floor_and_walls(floor_map: Dictionary) -> void:
	var nav := NavigationRegion3D.new()
	nav.name = "NavRegion"
	add_child(nav)

	var floors := Node3D.new()
	floors.name = "Floors"
	nav.add_child(floors)
	var walls := Node3D.new()
	walls.name = "Walls"
	nav.add_child(walls)

	for key in floor_map:
		var tile: Vector2i = key
		_add_floor_tile(floors, tile)
		for d in DIRS:
			var dir: Vector2i = d
			if not floor_map.has(tile + dir):
				_add_wall_edge(walls, tile, dir)

	_bake_navmesh(nav)


# Build + bake a NavigationMesh from the region's child box meshes. Baked SYNCHRONOUSLY so the
# walkable surface exists before any spawned enemy starts pathing this same frame.
func _bake_navmesh(nav: NavigationRegion3D) -> void:
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.2
	nm.agent_radius = 0.5      # erodes walkable area off walls + off the 0.5m-wide wall tops
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.4
	nm.agent_max_slope = 45.0
	# Parse the clean box COLLIDERS (not the detailed KayKit meshes) so the bake stays simple +
	# correct — floors define the walkable surface, wall blockers carve it.
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nav.navigation_mesh = nm
	nav.bake_navigation_mesh(false)


func _add_floor_tile(parent: Node3D, tile: Vector2i) -> void:
	var center: Vector3 = _tile_to_world(tile)
	# Invisible floor-slab collider (body origin at y=-0.5 so its top sits at y=0).
	var body := StaticBody3D.new()
	body.position = Vector3(center.x, -FLOOR_THICKNESS * 0.5, center.z)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(TILE_SIZE, FLOOR_THICKNESS, TILE_SIZE)
	col.shape = box
	body.add_child(col)
	# KayKit floor tile laid on the floor plane (lifted +0.5 to undo the body offset).
	var art: Node3D = KIT_FLOOR.instantiate()
	art.position = Vector3(0.0, FLOOR_THICKNESS * 0.5, 0.0)
	body.add_child(art)
	_tint_art(art, _floor_mat)
	parent.add_child(body)


# A wall on the edge between `tile` and its empty neighbour in `dir`: an invisible thin blocker
# (axis-aligned) plus a KayKit wall mesh rotated to run along the edge and face into the room.
func _add_wall_edge(parent: Node3D, tile: Vector2i, dir: Vector2i) -> void:
	var center: Vector3 = _tile_to_world(tile)
	var col_size: Vector3
	var rot_y: float = 0.0
	if dir.x != 0:
		# East/West edge: blocker thin in X, runs along Z; rotate the (X-long) wall 90deg.
		col_size = Vector3(WALL_THICKNESS, WALL_HEIGHT, TILE_SIZE)
		rot_y = PI * 0.5 if dir.x < 0 else -PI * 0.5
	else:
		# North/South edge: blocker thin in Z, wall runs along X (its default).
		col_size = Vector3(TILE_SIZE, WALL_HEIGHT, WALL_THICKNESS)
		rot_y = 0.0 if dir.y < 0 else PI

	var body := StaticBody3D.new()
	body.position = Vector3(
		center.x + float(dir.x) * TILE_SIZE * 0.5,
		0.0,
		center.z + float(dir.y) * TILE_SIZE * 0.5
	)
	# Blocker collider raised to sit y=0..WALL_HEIGHT.
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = col_size
	col.shape = box
	col.position = Vector3(0.0, WALL_HEIGHT * 0.5, 0.0)
	body.add_child(col)
	# KayKit wall mesh (base at y=0), rotated to the edge.
	var art: Node3D = KIT_WALL.instantiate()
	art.rotation.y = rot_y
	body.add_child(art)
	_tint_art(art, _wall_mat)
	parent.add_child(body)


# Tile (tx, tz) -> world position of that tile's CENTER on the floor plane.
func _tile_to_world(tile: Vector2i) -> Vector3:
	return Vector3(float(tile.x) * TILE_SIZE, 0.0, float(tile.y) * TILE_SIZE)


# A decorative KayKit pillar at each room's four outer corners (where walls meet) — purely
# visual (the wall colliders already block), so they read as structural columns.
func _place_pillars(rooms: Array) -> void:
	var holder := Node3D.new()
	holder.name = "Pillars"
	add_child(holder)
	for room in rooms:
		var rect: Rect2i = room
		var min_x: float = float(rect.position.x) * TILE_SIZE - TILE_SIZE * 0.5
		var max_x: float = float(rect.position.x + rect.size.x - 1) * TILE_SIZE + TILE_SIZE * 0.5
		var min_z: float = float(rect.position.y) * TILE_SIZE - TILE_SIZE * 0.5
		var max_z: float = float(rect.position.y + rect.size.y - 1) * TILE_SIZE + TILE_SIZE * 0.5
		for cx in [min_x, max_x]:
			for cz in [min_z, max_z]:
				var p: Node3D = KIT_PILLAR.instantiate()
				p.position = Vector3(cx, 0.0, cz)
				holder.add_child(p)
				_tint_art(p, _wall_mat)


# Recursively push a material onto every MeshInstance3D under an instanced art node, so the
# theme's floor/wall albedo actually paints the KayKit geometry (which otherwise keeps its own
# baked stone texture in every theme).
func _tint_art(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_tint_art(child, mat)


# --- Decorative clutter ----------------------------------------------------

# Scatter purely-decorative themed clutter (rocks, barrels, wood, ore, plus theme flavour like
# mushrooms in the Bog or dead trees in the Ember) on random room-interior tiles. No collision,
# so it never blocks the baked navmesh. Uses its OWN rng (seeded from the floor seed) so it's
# deterministic per floor without disturbing the main rng's loot/enemy placement.
func _scatter_clutter(rooms: Array, seed: int) -> void:
	var pool: Array = _clutter_pool(String(_theme.get("name", "Stone")))
	if pool.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed * 31 + 17
	var holder := Node3D.new()
	holder.name = "Clutter"
	add_child(holder)
	for room in rooms:
		var rect: Rect2i = room
		var n: int = clampi((rect.size.x * rect.size.y) / 4, 2, 8)
		for k in range(n):
			var tx: int = rect.position.x + rng.randi_range(0, rect.size.x - 1)
			var tz: int = rect.position.y + rng.randi_range(0, rect.size.y - 1)
			var center: Vector3 = _tile_to_world(Vector2i(tx, tz))
			var ps: PackedScene = pool[rng.randi() % pool.size()]
			var inst: Node3D = ps.instantiate() as Node3D
			if inst == null:
				continue
			holder.add_child(inst)
			inst.position = Vector3(center.x + rng.randf_range(-1.2, 1.2), 0.0, center.z + rng.randf_range(-1.2, 1.2))
			inst.rotation.y = rng.randf() * TAU
			inst.scale = Vector3.ONE * rng.randf_range(0.8, 1.25)

# The clutter model set for a theme: shared rocks/barrels/wood/ore + theme-specific flavour.
func _clutter_pool(theme_name: String) -> Array:
	var nat := "res://assets/models/nature/stylized-megakit/"
	var res := "res://assets/models/props/kaykit_resources/"
	var pool: Array = []
	pool += _load_clutter(res, ["Fuel_A_Barrel.gltf", "Fuel_A_Barrels.gltf", "Fuel_B_Barrel.gltf", "Wood_Log_A.gltf", "Wood_Log_Stack.gltf", "Stone_Chunks_Large.gltf", "Stone_Chunks_Small.gltf", "Stone_Bricks_Stack_Medium.gltf", "Pallet_Wood.gltf"])
	pool += _load_clutter(nat, ["Rock_Medium_1.gltf", "Rock_Medium_2.gltf", "Rock_Medium_3.gltf", "Pebble_Round_1.gltf", "Pebble_Square_1.gltf"])
	match theme_name:
		"Bog":
			pool += _load_clutter(nat, ["Mushroom_Common.gltf", "Mushroom_Laetiporus.gltf", "Fern_1.gltf", "Plant_1.gltf", "Plant_7.gltf", "TwistedTree_1.gltf"])
		"Ember":
			pool += _load_clutter(nat, ["DeadTree_1.gltf", "TwistedTree_1.gltf", "TwistedTree_2.gltf"])
		"Frost":
			pool += _load_clutter(nat, ["DeadTree_2.gltf", "DeadTree_3.gltf"])
			pool += _load_clutter(res, ["Iron_Nugget_Large.gltf", "Copper_Nugget_Large.gltf"])
		"Sewer":
			pool += _load_clutter(nat, ["Mushroom_Common.gltf", "Mushroom_Laetiporus.gltf"])
			pool += _load_clutter(res, ["Fuel_A_Barrel.gltf", "Fuel_A_Barrels.gltf", "Fuel_B_Barrel.gltf"])
		"Mine":
			pool += _load_clutter(res, ["Iron_Nugget_Large.gltf", "Iron_Nugget_Medium.gltf", "Stone_Bricks_Stack_Medium.gltf", "Pallet_Wood.gltf"])
		"PowerPlant":
			pool += _load_clutter(res, ["Fuel_A_Barrel.gltf", "Fuel_B_Barrel.gltf", "Iron_Nugget_Large.gltf"])
		"Cave":
			pool += _load_clutter(nat, ["Rock_Medium_1.gltf", "Rock_Medium_2.gltf", "Rock_Medium_3.gltf"])
			pool += _load_clutter(res, ["Iron_Nugget_Large.gltf", "Copper_Nugget_Large.gltf"])
		_:
			pool += _load_clutter(res, ["Iron_Nugget_Large.gltf", "Iron_Nugget_Medium.gltf", "Copper_Nugget_Large.gltf"])
			pool += _load_clutter(nat, ["DeadTree_4.gltf"])
	return pool

func _load_clutter(dir: String, names: Array) -> Array:
	var out: Array = []
	for n in names:
		var r: Resource = load(dir + String(n))
		if r is PackedScene:
			out.append(r)
	return out


# Cosmetic detail scatter. Delegates to dungeon_details.gd, loaded BY PATH (no class_name in this
# hot path) so the generator never hard-depends on a brand-new type. The helper runs off its own
# seed offset and adds collision-free meshes only, so it can never disturb geometry/loot/enemy
# determinism or the baked navmesh. A true no-op when enable_details is off or the script is missing.
func _scatter_details(rooms: Array, seed: int) -> void:
	if not enable_details:
		return
	var details: GDScript = load("res://stages/dungeons/procedural/dungeon_details.gd") as GDScript
	if details == null:
		return
	# Static entry point; passes everything it needs (no instance state) so it stays a pure helper.
	details.scatter(self, rooms, seed, details_density, String(_theme.get("name", "Stone")), TILE_SIZE)


# --- Lights ----------------------------------------------------------------

# A warm/cool OmniLight3D over each room centre, with a little seeded colour variety so the
# place doesn't read as flatly lit.
func _build_lights(rooms: Array, rng: RandomNumberGenerator) -> void:
	var holder := Node3D.new()
	holder.name = "Lights"
	add_child(holder)

	# The cool->warm endpoints this floor's lights interpolate between come from its theme.
	var light_cool: Color = _theme["light_cool"]
	var light_warm: Color = _theme["light_warm"]

	for room in rooms:
		var rect: Rect2i = room
		var center: Vector3 = _tile_to_world(_room_center_tile(rect))
		var light := OmniLight3D.new()
		light.position = Vector3(center.x, 5.0, center.z)
		# Lerp between the theme's cool and warm ends per-room for variety.
		var warm: float = rng.randf()
		light.light_color = light_cool.lerp(light_warm, warm)
		light.light_energy = rng.randf_range(1.8, 2.6)
		light.omni_range = float(max(rect.size.x, rect.size.y)) * TILE_SIZE + 8.0
		holder.add_child(light)


# --- Markers ---------------------------------------------------------------

# Drop the navigation markers: entry/respawn in the start room, a respawn per room, and a
# handful of "enemy_spawn" points scattered across every non-start room.
func _place_markers(rooms: Array, rng: RandomNumberGenerator) -> void:
	if rooms.is_empty():
		return

	var holder := Node3D.new()
	holder.name = "Markers"
	add_child(holder)

	# START room: both the generic overworld entry id and the mine-style entry id, plus a
	# respawn point. All in group "respawn_point" so the death/respawn system can use them.
	var start_center: Vector3 = _tile_to_world(_room_center_tile(rooms[0]))
	_add_marker(holder, "from_overworld", start_center, ["respawn_point"])
	_add_marker(holder, "Respawn_Entrance", start_center, ["respawn_point"])

	# A per-room respawn marker (handy as checkpoints) + scattered enemy spawns.
	for i in range(rooms.size()):
		var rect: Rect2i = rooms[i]
		var center: Vector3 = _tile_to_world(_room_center_tile(rect))
		_add_marker(holder, "Respawn_Room_%d" % i, center, ["respawn_point"])

		# No normal enemy spawns in the start room (safe landing) or the end room (reserved
		# as the climax/reward room — boss or descend portal lives there).
		if i == 0 or i == rooms.size() - 1:
			continue
		var spawns: int = rng.randi_range(2, 4)
		for s in range(spawns):
			var p: Vector3 = _random_point_in_room(rect, rng)
			_add_marker(holder, "EnemySpawn_%d_%d" % [i, s], p, ["enemy_spawn"])


func _add_marker(parent: Node3D, marker_name: String, pos: Vector3, groups: Array) -> void:
	var m := Marker3D.new()
	m.name = marker_name
	m.position = Vector3(pos.x, MARKER_Y, pos.z)
	for g in groups:
		m.add_to_group(g)
	parent.add_child(m)


# A random point inside a room, kept ~1m off the walls so nothing spawns clipped into them.
func _random_point_in_room(rect: Rect2i, rng: RandomNumberGenerator) -> Vector3:
	var min_x: float = float(rect.position.x) * TILE_SIZE - TILE_SIZE * 0.5 + 1.0
	var max_x: float = float(rect.position.x + rect.size.x - 1) * TILE_SIZE + TILE_SIZE * 0.5 - 1.0
	var min_z: float = float(rect.position.y) * TILE_SIZE - TILE_SIZE * 0.5 + 1.0
	var max_z: float = float(rect.position.y + rect.size.y - 1) * TILE_SIZE + TILE_SIZE * 0.5 - 1.0
	# Guard against tiny rooms where min could exceed max after the inset.
	if max_x < min_x:
		max_x = min_x
	if max_z < min_z:
		max_z = min_z
	return Vector3(rng.randf_range(min_x, max_x), 0.0, rng.randf_range(min_z, max_z))


# --- Exit (to town) + descend portal (deeper) ------------------------------

# Place a big, OBVIOUS ExitPortal in a corner of the START room, wired to the overworld, so the
# player can always find their way out near where they came in. The portal glows, casts light,
# and floats a "Leave Dungeon" sign; it triggers either by WALKING INTO it or by LOOKING at it +
# pressing "interact" (see exit_portal.gd). This replaces the old, easy-to-miss raycast teleporter.
func _place_town_exit(rooms: Array) -> void:
	if rooms.is_empty():
		return
	# A corner tile of the start room so the exit doesn't sit on top of the spawn point. Origin
	# on the floor (y = 0) — the ExitPortal stacks its own slab/light/sign up from there.
	var start_rect: Rect2i = rooms[0]
	var corner: Vector3 = _tile_to_world(Vector2i(start_rect.position.x, start_rect.position.y))
	var exit_pos := Vector3(corner.x, 0.0, corner.z)

	var portal := ExitPortal.new()
	portal.name = "ExitTeleport"
	portal.target_scene_path = exit_scene_path
	portal.target_spawn_point = exit_spawn_point
	add_child(portal)
	portal.global_position = exit_pos


# A glowing "stairs down" pad in the END room that rebuilds the dungeon one floor deeper.
# On a boss floor it starts disabled; _spawn_boss re-enables it when the boss dies. Returns the
# portal so the caller can wire that gate.
func _place_descend_portal(rooms: Array, boss: bool) -> DescendPortal:
	if rooms.is_empty():
		return null
	var end_center: Vector3 = _tile_to_world(_room_center_tile(rooms[rooms.size() - 1]))

	var portal := DescendPortal.new()
	portal.name = "DescendPortal"
	portal.generator = self
	portal.next_floor = _depth + 1
	portal.enabled = not boss

	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.3
	mesh.bottom_radius = 1.3
	mesh.height = 0.3
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.55, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.7, 1.0)
	mat.emission_energy_multiplier = 2.2
	mi.material_override = mat
	mi.position = Vector3(0.0, 0.15, 0.0)
	portal.add_child(mi)

	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.8, 1.6, 1.8)
	col.shape = box
	col.position = Vector3(0.0, 0.8, 0.0)
	portal.add_child(col)

	add_child(portal)
	portal.global_position = Vector3(end_center.x, 0.0, end_center.z)
	return portal


# A floating "FLOOR N" sign over the start room so the player can read their depth.
func _place_floor_label(rooms: Array) -> void:
	if rooms.is_empty():
		return
	var label := Label3D.new()
	label.name = "FloorLabel"
	label.text = "FLOOR %d" % _depth
	label.font_size = 96
	label.modulate = Color(1.0, 0.85, 0.5)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	var c: Vector3 = _tile_to_world(_room_center_tile(rooms[0]))
	add_child(label)
	label.global_position = Vector3(c.x, 3.0, c.z)


# --- Loot ------------------------------------------------------------------

# Scatter treasure through the dungeon: a chest in most non-start rooms (consumables /
# materials, sometimes a weapon), a few grabbable floor pickups, and a GUARANTEED reward
# chest in the end room holding a random weapon plus healing/bombs. All deterministic via
# `rng`; chest ids include the seed so opened-state from one seed never bleeds into another.
func _place_loot(rooms: Array, rng: RandomNumberGenerator, level_seed: int, boss: bool) -> void:
	if rooms.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "Loot"
	add_child(holder)

	# Weapons the dungeon can reward, DEPTH-TIERED (see _weapon_pool_for_depth): early floors hand
	# out basic gear, deep floors drop the high-tier blades. One is guaranteed in the end-room
	# chest. Selecting from this pool consumes the same number of rng draws as the old flat list, so
	# enemy placement (drawn from the same rng AFTER loot) stays byte-identical for a given seed.
	var weapon_pool: Array[StringName] = _weapon_pool_for_depth()

	# The vault needs a key SOMEWHERE on the floor: pick a guaranteed "key room" (a middle
	# journey room) so the player can always reach the locked vault.
	var key_room: int = -1
	if not _vault.is_empty() and rooms.size() > 2:
		key_room = clampi(rooms.size() / 2, 1, rooms.size() - 2)

	# Journey rooms (skip the start room and the reserved end room).
	for i in range(1, rooms.size() - 1):
		var rect: Rect2i = rooms[i]
		# A guaranteed key chest in the key room; most other rooms get a normal chest.
		if i == key_room:
			var key_table := LootTable.new()
			var ke: Array[LootEntry] = []
			ke.append(_loot_entry(&"dungeon_key", 1, 1))
			ke.append(_loot_entry(&"health_potion", 1, 1))
			key_table.entries = ke
			_make_chest(holder, _random_point_in_room(rect, rng), StringName("proc_%d_key_%d" % [level_seed, i]), key_table)
		elif rng.randf() < 0.75:
			var chest_pos: Vector3 = _random_point_in_room(rect, rng)
			var table: LootTable = _room_loot_table(rng, weapon_pool)
			_make_chest(holder, chest_pos, StringName("proc_%d_chest_%d" % [level_seed, i]), table)
		# Plus one or two grabbable pickups on the floor.
		var drops: int = rng.randi_range(1, 2)
		for d in range(drops):
			var p: Vector3 = _random_point_in_room(rect, rng)
			var pick_id: StringName = _minor_pickup_id(rng)
			WorldItem.spawn(pick_id, rng.randi_range(1, 3), holder, p + Vector3.UP * 0.5)

	# Guaranteed reward chest in the END room, off in a corner so it doesn't sit on the
	# descend portal. Boss floors give a bigger haul (two weapons + extra supplies).
	var end_rect: Rect2i = rooms[rooms.size() - 1]
	var end_corner: Vector3 = _tile_to_world(Vector2i(end_rect.position.x, end_rect.position.y))
	var weapon_id: StringName = weapon_pool[rng.randi_range(0, weapon_pool.size() - 1)]
	var reward := LootTable.new()
	var rentries: Array[LootEntry] = []
	rentries.append(_loot_entry(weapon_id, 1, 1))
	rentries.append(_loot_entry(&"health_potion", 2, 3))
	rentries.append(_loot_entry(&"fire_bomb", 1, 2))
	if boss:
		var weapon_id2: StringName = weapon_pool[rng.randi_range(0, weapon_pool.size() - 1)]
		rentries.append(_loot_entry(weapon_id2, 1, 1))
		rentries.append(_loot_entry(&"health_potion", 2, 3))
		rentries.append(_loot_entry(&"smoke_grenade", 1, 2))
	# Fold this floor's rare ids into the guaranteed reward (no-op when none configured).
	_append_rare_loot(rentries)
	reward.entries = rentries
	_make_chest(holder, end_corner, StringName("proc_%d_reward" % level_seed), reward)


# Instance a chest at `pos`, wire it to grant `table` to the inventory, and give it a unique
# id so its opened-state persists correctly.
func _make_chest(parent: Node3D, pos: Vector3, chest_id: StringName, table: LootTable) -> void:
	var scene: PackedScene = load("res://entities/props/chest.tscn")
	if scene == null:
		return
	var chest: Node = scene.instantiate()
	chest.set("chest_id", chest_id)
	chest.set("loot", table)
	chest.set("grant_to_inventory", true)
	chest.set("spill_world_items", false)  # inventory grant only (avoids the double-loot path)
	parent.add_child(chest)
	(chest as Node3D).global_position = pos


# A per-room loot table: always some healing, often throwing knives, and a ~35% chance of a
# weapon (otherwise a stack of crafting material).
func _room_loot_table(rng: RandomNumberGenerator, weapon_pool: Array[StringName]) -> LootTable:
	var t := LootTable.new()
	var entries: Array[LootEntry] = []
	entries.append(_loot_entry(&"health_potion", 1, 2))
	if rng.randf() < 0.5:
		entries.append(_loot_entry(&"throwing_knife", 3, 6))
	if rng.randf() < 0.35:
		var w: StringName = weapon_pool[rng.randi_range(0, weapon_pool.size() - 1)]
		entries.append(_loot_entry(w, 1, 1))
	else:
		entries.append(_loot_entry(&"sulfur_crystal", 1, 3))
	t.entries = entries
	return t


# Build one LootEntry (kept tiny so the tables above read clearly).
func _loot_entry(id: StringName, lo: int, hi: int) -> LootEntry:
	var e := LootEntry.new()
	e.item_id = id
	e.min_count = lo
	e.max_count = hi
	return e


# A random minor floor pickup (potion / crafting material / a few knives).
func _minor_pickup_id(rng: RandomNumberGenerator) -> StringName:
	var pool: Array[StringName] = [&"health_potion", &"sulfur_crystal", &"lava_ash", &"throwing_knife"]
	return pool[rng.randi_range(0, pool.size() - 1)]


# The weapon-reward pool for the CURRENT floor, tiered by depth so descending is rewarding. Tier =
# clampi((_depth-1)/2,0,3) -> two floors per tier, capped at the top tier. Any tier left empty in
# the inspector reverts to the original flat six-weapon list (a safe rollback that also reproduces
# the pre-tiering loot exactly). The returned array's SIZE is the only thing depth changes here;
# callers still make the same number of rng draws, so downstream enemy placement is unaffected.
func _weapon_pool_for_depth() -> Array[StringName]:
	var tier: int = clampi((_depth - 1) / 2, 0, 3)
	var pool: Array[StringName]
	match tier:
		0:
			pool = weapon_pool_t0
		1:
			pool = weapon_pool_t1
		2:
			pool = weapon_pool_t2
		_:
			pool = weapon_pool_t3
	if pool.is_empty():
		# Safe rollback: the original flat pool, identical to the pre-tiering behaviour.
		var fallback: Array[StringName] = [&"crossbow", &"flame_wand", &"frost_wand", &"arcane_wand", &"bow", &"steel_sword"]
		return fallback
	return pool


# --- Rare nodes ------------------------------------------------------------

# Map a rare item id to the harvestable node scene that yields it. Only ids that have a mineable
# node appear here (power_core / rusted_key arrive via chests, not nodes), so an entrance can list
# all five rare ids and we simply scatter the ones that have a node.
const RARE_NODE_FOR_ID: Dictionary = {
	&"scrap_metal": "res://entities/harvestables/scrap_pile.tscn",
	&"raw_gemstone": "res://entities/harvestables/gem_node.tscn",
	&"glow_crystal": "res://entities/harvestables/glow_crystal_node.tscn",
}

# Scatter 2-4 rare harvestable nodes into non-start rooms, drawn from whichever rare_loot_ids map
# to a node scene. Loaded by PATH (cold-cache safe). Uses its OWN rng seeded from `seed` so it's
# deterministic per floor yet never disturbs the main generation rng — the `rng` param is accepted
# for interface symmetry but intentionally NOT drawn from. No-op when nothing matches (the empty
# default reproduces the original dungeon exactly).
func _place_rare_nodes(rooms: Array, _rng: RandomNumberGenerator, seed: int) -> void:
	if rooms.size() < 2 or rare_loot_ids.is_empty():
		return
	# Build the pool of node scene PATHS this floor can scatter.
	var paths: Array[String] = []
	for id in rare_loot_ids:
		if RARE_NODE_FOR_ID.has(id):
			var p: String = RARE_NODE_FOR_ID[id]
			if not paths.has(p):
				paths.append(p)
	if paths.is_empty():
		return

	var node_rng := RandomNumberGenerator.new()
	node_rng.seed = seed * 53 + 91
	var holder := Node3D.new()
	holder.name = "RareNodes"
	add_child(holder)

	var count: int = node_rng.randi_range(2, 4)
	for n in range(count):
		# Any non-start room (index 1..last). The end room is allowed — a rare node by the climax
		# reads fine and small dungeons may have few rooms.
		var ri: int = node_rng.randi_range(1, rooms.size() - 1)
		var rect: Rect2i = rooms[ri]
		var pos: Vector3 = _random_point_in_room(rect, node_rng)
		var scene_path: String = paths[node_rng.randi() % paths.size()]
		var scene: PackedScene = load(scene_path) as PackedScene
		if scene == null:
			continue
		var node: Node = scene.instantiate()
		holder.add_child(node)
		(node as Node3D).global_position = Vector3(pos.x, 0.0, pos.z)


# Append one 1-count LootEntry per rare_loot_id onto an existing entries array (in place). Used to
# fold the floor's rare ids into the guaranteed reward + vault chests. No rng draw, so turning rare
# loot on never perturbs enemy placement. No-op when rare_loot_ids is empty.
func _append_rare_loot(entries: Array[LootEntry]) -> void:
	for id in rare_loot_ids:
		entries.append(_loot_entry(id, 1, 1))


# --- Locked vault ----------------------------------------------------------

# Carve a small 2x2 vault room in guaranteed-empty space south of the macro grid, joined to the
# start room by a single corridor, and find the doorway tile(s) where that corridor meets the
# vault. A locked Door is placed at each doorway later (see _place_vault_contents). Returns the
# vault description, or {} if there were no rooms.
func _carve_vault(floor_map: Dictionary, rooms: Array) -> Dictionary:
	if rooms.is_empty():
		return {}
	# Place the vault just WEST of the start room (negative X is always empty — the macro grid
	# only ever uses X >= 0), so it's a short corridor away rather than across the whole map.
	var start_rect: Rect2i = rooms[0]
	var rect := Rect2i(-5, start_rect.position.y, 2, 2)
	_carve_room(floor_map, rect)

	# One corridor from the start room to the vault.
	var a: Vector2i = _room_center_tile(rooms[0])
	var b: Vector2i = _room_center_tile(rect)
	_carve_corridor(floor_map, a, b)

	# Doorway(s): a vault perimeter tile whose neighbour OUTSIDE the vault is corridor floor.
	var doorways: Array = []
	for tx in range(rect.position.x, rect.position.x + rect.size.x):
		for tz in range(rect.position.y, rect.position.y + rect.size.y):
			var tile := Vector2i(tx, tz)
			for d in DIRS:
				var dir: Vector2i = d
				var nb: Vector2i = tile + dir
				if not rect.has_point(nb) and floor_map.has(nb):
					doorways.append({"tile": tile, "dir": dir})
	return {"rect": rect, "doorways": doorways}


# Light + locked door(s) + a premium reward chest for the vault carved in _carve_vault.
func _place_vault_contents(rng: RandomNumberGenerator, level_seed: int) -> void:
	if _vault.is_empty():
		return
	var rect: Rect2i = _vault["rect"]
	var holder := Node3D.new()
	holder.name = "Vault"
	add_child(holder)

	var center: Vector3 = _tile_to_world(_room_center_tile(rect))

	# A warm light so the treasure room reads as special.
	var light := OmniLight3D.new()
	light.position = Vector3(center.x, 4.0, center.z)
	light.light_color = Color(1.0, 0.85, 0.4)
	light.light_energy = 2.4
	light.omni_range = 16.0
	holder.add_child(light)

	# A locked door at each doorway (normally one).
	var doorways: Array = _vault["doorways"]
	var di: int = 0
	for entry in doorways:
		var tile: Vector2i = entry["tile"]
		var dir: Vector2i = entry["dir"]
		_make_vault_door(holder, tile, dir, &"dungeon_key", StringName("proc_%d_vaultdoor_%d" % [level_seed, di]))
		di += 1

	# The premium reward: two strong weapons + a stack of supplies.
	var table := LootTable.new()
	var e: Array[LootEntry] = []
	e.append(_loot_entry(&"arcane_wand", 1, 1))
	e.append(_loot_entry(&"crossbow", 1, 1))
	e.append(_loot_entry(&"health_potion", 3, 5))
	e.append(_loot_entry(&"fire_bomb", 2, 3))
	# The premium vault also carries this floor's rare ids (no-op when none configured).
	_append_rare_loot(e)
	table.entries = e
	_make_chest(holder, center, StringName("proc_%d_vault" % level_seed), table)


# Build a key-locked Door (door.gd) filling the 1-tile opening between `inside_tile` (a vault
# tile) and the corridor tile in `dir`. door.gd disables the blocking collider on open.
func _make_vault_door(parent: Node3D, inside_tile: Vector2i, dir: Vector2i, key_id: StringName, door_name: StringName) -> void:
	var door := Door.new()
	door.name = String(door_name)
	door.required_key = key_id
	door.consume_key = true

	var leaf_size: Vector3
	if dir.x != 0:
		# Opening faces east/west: the leaf spans Z, thin in X.
		leaf_size = Vector3(WALL_THICKNESS, WALL_HEIGHT, TILE_SIZE)
	else:
		leaf_size = Vector3(TILE_SIZE, WALL_HEIGHT, WALL_THICKNESS)

	# Blocking collider on the door body root (door.gd toggles "CollisionShape3D").
	var col := CollisionShape3D.new()
	col.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = leaf_size
	col.shape = box
	door.add_child(col)

	# Visual leaf under "Pivot" (the node door.gd swings open).
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = leaf_size
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.3, 0.16)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.32, 0.1)
	mat.emission_energy_multiplier = 0.25
	mi.material_override = mat
	pivot.add_child(mi)
	door.add_child(pivot)

	parent.add_child(door)

	# Sit the door on the boundary between the vault tile and the corridor tile.
	var c: Vector3 = _tile_to_world(inside_tile)
	door.global_position = Vector3(
		c.x + float(dir.x) * TILE_SIZE * 0.5,
		WALL_HEIGHT * 0.5,
		c.z + float(dir.y) * TILE_SIZE * 0.5
	)


# --- Boss ------------------------------------------------------------------

# The boss pool for a given depth tier (0=early, 1=mid, 2=late). Falls back to the legacy un-tiered
# boss_pool when the requested tier pool is empty, so clearing the tiered pools reverts cleanly.
func _boss_pool_for_tier(tier: int) -> Array:
	var pool: Array
	match tier:
		0:
			pool = boss_pool_early
		1:
			pool = boss_pool_mid
		_:
			pool = boss_pool_late
	if pool.is_empty():
		pool = boss_pool  # legacy un-tiered fallback (empty by default; then boss_scene_path is used)
	return pool


# Drop the boss in the reserved end room and, on a boss floor, gate the descend portal on its
# death so the player can't skip the fight. The boss is drawn from the DEPTH-TIERED boss pool
# (deterministically, off the passed rng) and gets a soft-capped health bump on deeper boss floors.
func _spawn_boss(rooms: Array, portal: DescendPortal, rng: RandomNumberGenerator) -> void:
	if rooms.is_empty():
		return

	# Pick which boss to fight: a deterministic draw from the DEPTH-TIERED pool for this floor, so an
	# early boss floor can't roll a late-game heavyweight. Falls back to the legacy boss_pool, then
	# to the single boss_scene_path, when a pool is empty (so old setups keep their one boss).
	var tier: int = clampi((_depth - 1) / BOSS_EVERY, 0, 2)
	var pool: Array = _boss_pool_for_tier(tier)
	var chosen_path: String = boss_scene_path
	if not pool.is_empty():
		var bi: int = rng.randi_range(0, pool.size() - 1)
		chosen_path = pool[bi]

	var boss_scene: PackedScene = load(chosen_path)
	if boss_scene == null:
		push_warning("DungeonGenerator: boss scene '%s' could not be loaded." % chosen_path)
		# Don't trap the player on a boss floor we couldn't populate — open the descent.
		if portal != null:
			portal.unlock()
		return
	var boss: Node = boss_scene.instantiate()
	add_child(boss)
	var c: Vector3 = _tile_to_world(_room_center_tile(rooms[rooms.size() - 1]))
	(boss as Node3D).global_position = Vector3(c.x, 1.0, c.z)

	# Grab the boss's Health (inherited from enemy.tscn). enemy.gd._apply_stats() has already run
	# during add_child's _ready, seeding Health from the boss's stats, so we can scale the LIVE
	# values here. Deeper boss floors get a tougher boss: +25% max HP per boss floor beyond the
	# first (boss_number 1 -> x1.0, 2 -> x1.25, 3 -> x1.5, ...).
	var health: Node = boss.get_node_or_null("Health")
	var boss_number: int = _depth / BOSS_EVERY
	if health != null and boss_number > 1:
		# Soft-capped so deep boss HP scales as a curve that flattens, not without bound — a
		# 600hp colossus at x2.5 is already a wall; beyond that fights just become tedious.
		var hp_scale: float = minf(1.0 + 0.25 * float(boss_number - 1), boss_hp_scale_max)
		var base_max: float = health.max_health
		health.max_health = base_max * hp_scale
		health.current = health.max_health

	# Gate the descend portal on the boss's death. If the boss has no Health to die from (a
	# misconfigured boss scene), unlock immediately rather than soft-locking the floor forever.
	if portal != null:
		if health != null and health.has_signal("died"):
			health.connect("died", Callable(portal, "unlock"))
		else:
			portal.unlock()


# --- Starter kit (direct-play convenience) ---------------------------------

# If the player owns NO weapon at all (typically when this scene is opened directly with an
# empty save), hand them a basic kit so they have something to fight with. A player who
# arrived from the overworld already carries gear, so this won't touch them. Keyed on actual
# inventory ownership (not hotbar slots) so a stale/empty hotbar can't leave them unarmed.
func _grant_starter_kit_if_unarmed() -> void:
	if not grant_starter_kit:
		return
	# Direct-play convenience only: entry from the overworld goes through SceneManager (the dungeon
	# is parented under the world SubViewport, so it is NOT the tree's current_scene). F6 direct play
	# loads this scene under the tree root, where current_scene == self. Skip otherwise so a real
	# session never gets the convenience kit (and never has its hotbar disturbed).
	if get_tree().current_scene != self:
		return
	if not _player_has_no_weapon():
		return
	# One-time only: re-entering/descending dungeons must not re-farm a fresh free kit. A
	# GameState flag latches the first grant so subsequent unarmed checks are skipped entirely.
	if GameState.get_flag(&"starter_kit_granted"):
		return
	GameState.set_flag(&"starter_kit_granted", true)
	# Add to the bag only — never touch the hotbar, so the player's own tools/layout always survive.
	# A genuinely empty F6 save still gains weapons it can manually drag onto the hotbar.
	Inventory.add(&"steel_sword", 1)
	Inventory.add(&"bow", 1)
	Inventory.add(&"flame_wand", 1)
	Inventory.add(&"throwing_knife", 12)
	Inventory.add(&"health_potion", 3)


# True when the player carries none of the core weapons — used to decide whether the
# direct-play starter kit should fire.
func _player_has_no_weapon() -> bool:
	var weapons: Array[StringName] = [
		&"driftwood_club", &"steel_sword", &"obsidian_blade", &"bow", &"crossbow",
		&"flame_wand", &"frost_wand", &"arcane_wand"
	]
	for w in weapons:
		if Inventory.count_of(w) > 0:
			return false
	return true


# --- Player placement ------------------------------------------------------

# Move the scene's Player onto the start-room entry marker. Used on first build (F6 direct play)
# and after every descend() rebuild. Harmless when entered via SceneManager (which also places
# the player on its requested spawn point).
func _move_player_to_entry() -> void:
	var player := get_node_or_null("Player")
	if player == null or not player is Node3D:
		return
	var entry := find_child("from_overworld", true, false)
	if entry is Node3D:
		(player as Node3D).global_transform = (entry as Node3D).global_transform
