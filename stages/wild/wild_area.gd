# wild_area.gd
# The reusable BASE every themed open "wild area" (woods, ashlands, frozen wastes, …) is
# built on. A themed area is a tiny SUBCLASS that does nothing but set config members and
# call super() — the base then assembles a complete, walkable, self-contained scene:
#   sky + sun + ambient (themed), a big themed ground plane with collision, four invisible
#   boundary walls so the player can't walk off the edge, decorative NatureScatter foliage,
#   deterministically-placed resource nodes (harvestables) + wildlife + optional enemies,
#   the Player dropped on a "from_town" marker, and a glowing return gate back to town.
#
# WHY a base + config split: content agents only own a ~20-line subclass of pure data, so a
# new biome is cheap and every area shares the same correct SceneManager contract (its own
# Player + a Marker3D named "from_town" present by the end of _ready) and the same scatter
# logic. No hand-placed clutter to maintain; everything is code-built and deterministic per
# a seed so it dresses identically every run (nothing to save).
#
# HOW a subclass uses it:
#   extends "res://stages/wild/wild_area.gd"
#   func _ready() -> void:
#       area_title = "The Whispering Woods"
#       return_spawn = &"from_woods"
#       ground_color = Color(0.25, 0.4, 0.18)
#       sky_top = Color(0.3, 0.5, 0.8); sky_horizon = Color(0.7, 0.85, 0.95)
#       nature_filters_collide = PackedStringArray(["CommonTree", "Pine", "Rock_Medium"])
#       nature_filters_foliage = PackedStringArray(["Bush", "Fern", "Grass", "Flower"])
#       resource_nodes = [{"path": "res://entities/harvestables/rock.tscn", "count": 12, "clear": 6.0}]
#       animal_variants = PackedStringArray(["res://entities/animals/deer.tscn"]); animal_count = 8
#       super()           # <-- the base does all the building
#
# The base reads the members AFTER they're set, so the subclass MUST set them BEFORE super().
class_name WildArea
extends Node3D

# --- Theme / environment config (subclass overrides before super()) ---------

## Radius (metres) of the playable disc. Ground + walls are sized from this; scatter fills it.
@export var area_radius: float = 80.0
## Flat albedo of the ground plane (the dominant biome colour).
@export var ground_color: Color = Color(0.33, 0.43, 0.24)
## Sky gradient top colour (overhead).
@export var sky_top: Color = Color(0.35, 0.52, 0.85)
## Sky gradient horizon colour (where sky meets ground).
@export var sky_horizon: Color = Color(0.7, 0.8, 0.9)
## Directional sun light colour.
@export var sun_color: Color = Color(1.0, 1.0, 1.0)
## Sun brightness.
@export var sun_energy: float = 1.1
## Sky-sourced ambient fill brightness.
@export var ambient_energy: float = 1.0
## Turn on exponential distance fog (good for moody / hazy biomes).
@export var fog_enabled: bool = false
## Fog tint (used only when fog_enabled).
@export var fog_color: Color = Color(0.6, 0.65, 0.7)
## Fog thickness (used only when fog_enabled). Higher = denser.
@export var fog_density: float = 0.01

# --- Environment quality preset (per-area mood; safe defaults) ---------------
# Read in _build_environment so a biome can be dialed vibrant or muted WITHOUT touching
# code. Defaults give the open wild a vibrant filmic look; glow/SSAO stay off so the base
# look is unchanged unless a subclass opts in. Every member is plain so a missing override
# simply uses the default (no-op).

## Tonemap operator for the area. Defaults to FILMIC for punchy, natural outdoor colour.
## (See Environment.TONE_MAPPER_*.) Use TONE_MAPPER_LINEAR for a flat, washed look.
@export var tonemap_mode: int = Environment.TONE_MAPPER_FILMIC
## Tonemap exposure. >1 brightens / lifts the whole frame; <1 darkens. 1.0 = neutral.
@export var tonemap_exposure: float = 1.0
## Enable bloom/glow on bright pixels (sun glints, emissive gates). Off by default (cheap).
@export var glow_enabled: bool = false
## Glow strength when glow_enabled. Higher = bloomier.
@export var glow_intensity: float = 0.8
## Enable screen-space ambient occlusion (contact shadows in crevices). Off by default (perf).
@export var ssao_enabled: bool = false

# --- Predator danger dial ---------------------------------------------------

## Multiplier applied to the chase speed of HOSTILE scattered animals (predators) in this
## area; peaceful wildlife is untouched. 1.0 keeps each species' native move_speed. Gather
## zones drop this just below 1.0 (see iron_hills.gd) so big cats stay faster than a walk but
## a sprinting player can still kite away — ambient danger, not a guaranteed kill. Applied
## once after the wildlife pool finishes scattering; predators read it live each frame.
@export var hostile_animal_speed_scale: float = 1.0

# --- Biome ambient particles ------------------------------------------------
# A single low-cost CPUParticles3D field (dust motes / pollen / drifting embers) spawned
# AFTER geometry, covering the playable disc. Collision-free, gentle continuous emit. Purely
# atmospheric and fully guarded — disable per area or tune density/colour/drift.

## Spawn the drifting ambient particle field. Off for crisp / sterile biomes.
@export var ambient_particles_enabled: bool = true
## Particle tint (alpha sets opacity). Soft warm dust by default.
@export var ambient_particle_color: Color = Color(0.85, 0.82, 0.72, 0.35)
## How many motes drift across the whole area at once. Kept low; it's ambience, not weather.
@export var ambient_particle_amount: int = 40
## Per-mote constant drift (m/s). A faint downward+sideways settle by default; set upward
## (positive Y) for rising embers/sparks in a volcanic biome.
@export var ambient_particle_drift: Vector3 = Vector3(0.15, -0.06, 0.0)
## Height (m) of the particle volume above the ground the motes fill.
@export var ambient_particle_ceiling: float = 9.0
## Visual size (m) of each mote quad.
@export var ambient_particle_size: float = 0.09

# --- Portal / gate glow + pulse ---------------------------------------------
# The return gate and dungeon entrances get a brighter emissive plus an optional looping
# "breathing" pulse so they read as live magical thresholds from across the area. If the
# Clock autoload is present, brightness scales up at night so gates beckon in the dark.

## Brighten gate emission and enable the breathing pulse. Off = the old static glow.
@export var enable_portal_glow: bool = true
## Base emission energy multiplier for the return gate (raised from the old flat 2.0).
@export var portal_glow_energy: float = 2.8
## Breaths per ~2 seconds for the pulse (higher = faster throb). Ignored if glow disabled.
@export var portal_pulse_speed: float = 0.7

# --- Return-to-town config --------------------------------------------------

## Marker name in town_template the player lands on when leaving via the return gate
## (e.g. &"from_woods"). town_template must contain a Marker3D with this exact name.
@export var return_spawn: StringName = &""
## Sign text on the return gate; also a human label for the area.
@export var area_title: String = "Wild Area"
## Optional one-line tagline shown under the area title on the entry title-card
## (e.g. "Eastern Reach"). Blank = title only. Cosmetic; no gameplay effect.
@export var area_tagline: String = ""

# --- Dungeon-entrance config ------------------------------------------------

## Dungeon entrances to place inside this area. Each entry is a Dictionary:
##   {"scene": String (a dungeon entrance .tscn), "label": String, "pos": Vector3}
## A cave-mouth teleport gate is built at "pos" (ground-snapped); aim + E enters
## the dungeon. The dungeon entrance scene should set its own
##   exit_scene_path = <THIS wild area's .tscn>
##   exit_spawn_point = &"from_dungeon"
## so the player is returned to the "from_dungeon" marker this area always builds.
@export var dungeon_entrances: Array = []

# --- Decoration / content config (Arrays the subclass fills) ----------------

## Nature-kit name substrings scattered WITH collision (player bumps them): trees, boulders.
@export var nature_filters_collide: PackedStringArray = []
## Nature-kit name substrings scattered WITHOUT collision (walk-through): bushes, grass, flowers.
@export var nature_filters_foliage: PackedStringArray = []

## Resource (harvestable) node kinds to scatter. Each entry is a Dictionary:
##   {"path": String (a harvestable variant .tscn), "count": int, "clear": float}
## "clear" keeps that inner radius around the entry point free of this kind.
@export var resource_nodes: Array = []

## Paths to entities/animals/*.tscn wildlife scenes; a random pick is placed per instance.
@export var animal_variants: PackedStringArray = []
## How many wildlife instances to scatter.
@export var animal_count: int = 0

## Optional combat tie-in: paths to existing res://entities/enemies/*.tscn.
@export var enemy_scenes: PackedStringArray = []
## How many enemy instances to scatter.
@export var enemy_count: int = 0

# --- Constants --------------------------------------------------------------

const NATURE_DIR := "res://assets/models/nature/stylized-megakit"
const TOWN_SCENE := "res://stages/overworld/town_template.tscn"
const PLAYER_SCENE := "res://entities/player/player.tscn"
const GATE_SCRIPT := "res://global/teleport area/teleport_raycast.gd"
## Base seed for all deterministic scatter; each kind offsets it by an index so different
## kinds don't land in correlated positions.
const SCATTER_SEED := 90210
## How far the boundary walls sit beyond the ground edge, and how tall they are.
const WALL_THICKNESS := 2.0
const WALL_HEIGHT := 40.0

# --- Runtime atmosphere state ----------------------------------------------
# Kept so the time-of-day tint can re-blend each minute from the UNTINTED base
# colours (never from already-tinted values, which would drift over time).
var _sky_mat: ProceduralSkyMaterial
var _base_sky_top: Color
var _base_sky_horizon: Color

# Time-of-day MULTIPLIER keyframes [hour:float, tint:Color]. Multiplicative so each
# biome keeps its own hue identity while warmth/brightness shift across the day:
# deep-blue dim night, golden dawn, bright neutral noon, warm dusk. Wraps 24->0.
const _TINT_KEYS := [
	[0.0, Color(0.34, 0.40, 0.66)],   # deep blue night
	[5.0, Color(0.44, 0.46, 0.70)],   # pre-dawn lightening
	[6.0, Color(0.72, 0.62, 0.70)],   # first-light twilight (mauve, eases the cold->gold ramp)
	[7.0, Color(1.06, 0.82, 0.66)],   # golden dawn
	[12.0, Color(1.0, 1.0, 1.0)],     # bright noon (neutral = base colour)
	[17.0, Color(1.05, 0.90, 0.80)],  # late afternoon warmth
	[18.0, Color(1.12, 0.80, 0.64)],  # golden hour (richer than 17h, softens dusk fall-off)
	[19.0, Color(1.10, 0.68, 0.54)],  # warm dusk
	[20.0, Color(0.78, 0.55, 0.60)],  # afterglow twilight (rose fading toward night)
	[21.0, Color(0.46, 0.43, 0.62)],  # falling into night
	[24.0, Color(0.34, 0.40, 0.66)],  # wrap back to midnight
]

func _ready() -> void:
	# Order matters: environment + ground + walls first (the ground collider must exist
	# before any ground-aligned scatter raycasts), then dressing, then content, then the
	# player + gate. Everything is guarded so empty config still yields a walkable area.
	_build_environment()
	# Tint the freshly-built sky for the current hour, then keep it in sync as time
	# passes. Both are guarded no-ops if the sky material or Clock autoload is absent.
	_apply_time_of_day_tint()
	_connect_time_of_day()
	_build_ground()
	_build_walls()
	_dress_foliage()
	# Atmosphere: a faint drifting particle field over the disc (guarded no-op if disabled).
	_build_ambient_particles()
	_scatter_resources()
	_scatter_animals()
	_scatter_enemies()
	# The player-entry marker + the Player itself MUST both exist by the end of _ready so
	# SceneManager can move the incoming player onto "from_town".
	_build_entry_marker()
	_build_player()
	_build_return_gate()
	# Dungeon entrances + the "from_dungeon" return marker (both no-ops if no entrances,
	# except the marker which is always built so any dungeon can return into this area).
	_build_dungeon_return_marker()
	_build_dungeon_entrances()
	# Last: fade in the area's name over the scene crossfade (guarded, silent if blank).
	_announce_area()

# --- Environment ------------------------------------------------------------

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = sky_top
	sky_mat.sky_horizon_color = sky_horizon
	sky_mat.ground_horizon_color = sky_horizon
	sky_mat.ground_bottom_color = ground_color
	sky.sky_material = sky_mat
	# Remember the material + the UNTINTED config colours so the time-of-day tint can
	# re-blend from the originals every minute without compounding.
	_sky_mat = sky_mat
	_base_sky_top = sky_top
	_base_sky_horizon = sky_horizon
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = ambient_energy
	# Per-area quality preset. Tonemap + exposure always applied; glow/SSAO opt-in so the
	# base cost stays low. Each is a plain tunable, so an unset subclass uses the default.
	env.tonemap_mode = tonemap_mode
	env.tonemap_exposure = tonemap_exposure
	if glow_enabled:
		env.glow_enabled = true
		env.glow_intensity = glow_intensity
	if ssao_enabled:
		env.ssao_enabled = true
	if fog_enabled:
		env.fog_enabled = true
		env.fog_light_color = fog_color
		# Godot 4: exponential depth fog via fog_density.
		env.fog_density = fog_density
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -38.0, 0.0)
	sun.light_color = sun_color
	sun.light_energy = sun_energy
	sun.shadow_enabled = true
	add_child(sun)

# --- Time-of-day sky tinting ------------------------------------------------

# Re-blend the procedural sky from the area's base colours toward the current
# hour's tint. Multiplicative: golden at dawn, neutral-bright at noon, warm at
# dusk, deep-blue-dim at night — while every biome keeps its own configured hue.
# Fully guarded: no sky material (env couldn't build) or no Clock = silent no-op.
func _apply_time_of_day_tint() -> void:
	if _sky_mat == null:
		return
	var clock: Node = get_node_or_null("/root/Clock")
	var hour_f: float = 12.0
	if clock != null and clock.has_method("get_time_fraction"):
		var frac: float = clock.get_time_fraction()
		hour_f = frac * 24.0
	var tint: Color = _sample_tint(hour_f)
	_sky_mat.sky_top_color = _base_sky_top * tint
	_sky_mat.sky_horizon_color = _base_sky_horizon * tint
	_sky_mat.ground_horizon_color = _base_sky_horizon * tint

# Connect once to the Clock so the sky drifts as in-game time advances. Guarded so
# the area still tints statically (at load) if Clock is missing or has no signal.
func _connect_time_of_day() -> void:
	var clock: Node = get_node_or_null("/root/Clock")
	if clock == null or not clock.has_signal("time_changed"):
		return
	if not clock.time_changed.is_connected(_on_clock_time_changed):
		clock.time_changed.connect(_on_clock_time_changed)

func _on_clock_time_changed(_hour: int, _minute: int) -> void:
	_apply_time_of_day_tint()

# Linear-interpolate a tint Color from _TINT_KEYS for a 0..24 hour. Smoothstep on
# the segment fraction so transitions ease in/out rather than ramp linearly.
func _sample_tint(hour_f: float) -> Color:
	var h: float = clampf(hour_f, 0.0, 24.0)
	for i in range(_TINT_KEYS.size() - 1):
		var lo: Array = _TINT_KEYS[i]
		var hi: Array = _TINT_KEYS[i + 1]
		var lo_h: float = lo[0]
		var hi_h: float = hi[0]
		if h >= lo_h and h <= hi_h:
			var span: float = maxf(0.0001, hi_h - lo_h)
			var t: float = smoothstep(0.0, 1.0, (h - lo_h) / span)
			var lo_c: Color = lo[1]
			var hi_c: Color = hi[1]
			return lo_c.lerp(hi_c, t)
	# Past the last key (shouldn't happen with a 24.0 endpoint) — use the last tint.
	var last: Array = _TINT_KEYS[_TINT_KEYS.size() - 1]
	var last_c: Color = last[1]
	return last_c

# --- Area title-card announce -----------------------------------------------

# Fade the area's name (+ optional tagline) in over the scene crossfade via the
# AreaTitleCard autoload. Reached defensively: if the autoload isn't registered we
# connect to nothing and the emit is harmless. Silent when area_title is blank.
func _announce_area() -> void:
	if area_title.strip_edges() == "":
		return
	var card: Node = get_node_or_null("/root/AreaTitleCard")
	if card != null and card.has_method("show_card"):
		card.show_card(area_title, area_tagline)

# --- Ground + boundary walls ------------------------------------------------

func _build_ground() -> void:
	var span: float = area_radius * 2.0
	var body := StaticBody3D.new()
	body.name = "Ground"
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# A THICK slab (top face still at y=0) so the player can never tunnel through it on
	# spawn. A thin (1m) collider could be passed in a single fall step before the freshly
	# added body registers in a cold physics space — heavier first-loaded areas (lots of
	# scatter colliders) hit that race and dropped the player into the void. 12m is safe.
	box.size = Vector3(span, 12.0, span)
	col.shape = box
	# Top face of the slab sits at y=0 so scatter rays (from +60 down) land on y=0.
	col.position = Vector3(0.0, -6.0, 0.0)
	body.add_child(col)
	var mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(span, span)
	mesh.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = ground_color
	mesh.material_override = mat
	body.add_child(mesh)
	add_child(body)

# Four tall invisible walls ringing the playable disc so the player can't walk off the
# ground plane. They're square (sized to the ground span) and sit just past the edge.
func _build_walls() -> void:
	var half: float = area_radius
	var edge: float = half + WALL_THICKNESS * 0.5
	var span: float = area_radius * 2.0 + WALL_THICKNESS * 2.0
	# (centre offset, full size) for each of the four walls.
	var defs := [
		{"pos": Vector3(0.0, WALL_HEIGHT * 0.5, -edge), "size": Vector3(span, WALL_HEIGHT, WALL_THICKNESS)},
		{"pos": Vector3(0.0, WALL_HEIGHT * 0.5, edge), "size": Vector3(span, WALL_HEIGHT, WALL_THICKNESS)},
		{"pos": Vector3(-edge, WALL_HEIGHT * 0.5, 0.0), "size": Vector3(WALL_THICKNESS, WALL_HEIGHT, span)},
		{"pos": Vector3(edge, WALL_HEIGHT * 0.5, 0.0), "size": Vector3(WALL_THICKNESS, WALL_HEIGHT, span)},
	]
	for d in defs:
		var wall := StaticBody3D.new()
		wall.name = "BoundaryWall"
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = d["size"]
		col.shape = box
		wall.add_child(col)
		add_child(wall)
		wall.position = d["pos"]

# --- Foliage dressing (NatureScatter) ---------------------------------------

func _dress_foliage() -> void:
	# Collidable nature (trees, boulders) — player bumps these; keep a small clear ring at
	# centre so nothing spawns on the player entry.
	if not nature_filters_collide.is_empty():
		_add_scatter(nature_filters_collide, 36, 11, true, 8.0)
	# Walk-through foliage (bushes, grass, flowers).
	if not nature_filters_foliage.is_empty():
		_add_scatter(nature_filters_foliage, 120, 12, false, 4.0)

func _add_scatter(filter: PackedStringArray, count: int, seed_index: int, collision: bool, clear: float) -> void:
	var s: Node3D = load("res://entities/props/nature_scatter.gd").new()
	s.set("models_dir", NATURE_DIR)
	s.set("name_filter", filter)
	s.set("count", count)
	# Scatter slightly inside the wall ring so props don't clip the boundary.
	s.set("area_radius", maxf(1.0, area_radius - 4.0))
	s.set("rng_seed", SCATTER_SEED + seed_index)
	s.set("make_collision", collision)
	s.set("clear_radius", clear)
	add_child(s)

# --- Biome ambient particles ------------------------------------------------

# Spawn ONE CPUParticles3D field of slow-drifting motes over the playable disc. CPU (not
# GPU) particles so it's identical headless and needs no shader compile; a box emitter sized
# to area_radius scatters them everywhere; a tiny unshaded billboard quad renders each mote.
# Collision-free and continuous. Fully guarded: disabled, zero-amount or zero-radius => no
# field is created. Needs no Clock (static, time-independent), so it is always safe.
func _build_ambient_particles() -> void:
	if not ambient_particles_enabled or ambient_particle_amount <= 0 or area_radius <= 0.0:
		return
	var p := CPUParticles3D.new()
	p.name = "AmbientParticles"
	p.amount = ambient_particle_amount
	p.lifetime = 8.0
	p.preprocess = p.lifetime          # start mid-life so the air is already full on spawn
	p.local_coords = false             # motes drift in world space, not with any parent move
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	# Fill the whole disc (use the radius as a half-extent box) up to the ceiling height.
	var half_h: float = maxf(0.5, ambient_particle_ceiling * 0.5)
	p.emission_box_extents = Vector3(area_radius, half_h, area_radius)
	# Gentle constant drift, no gravity, a hair of spread so motes don't move in lockstep.
	p.gravity = Vector3.ZERO
	p.direction = ambient_particle_drift.normalized() if ambient_particle_drift.length() > 0.001 else Vector3.UP
	p.spread = 25.0
	var speed: float = ambient_particle_drift.length()
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed * 1.5
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.3
	# A small billboard quad, unshaded + transparent so motes glow faintly and never lit-pop.
	var quad := QuadMesh.new()
	quad.size = Vector2(ambient_particle_size, ambient_particle_size)
	p.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = ambient_particle_color
	mat.vertex_color_use_as_albedo = false
	quad.material = mat
	add_child(p)
	# Centre the emitter box at mid-ceiling height so motes occupy ground..ceiling.
	p.position = Vector3(0.0, half_h, 0.0)
	p.emitting = true

# --- Deterministic placement core ------------------------------------------

# Instance `scene` `count` times, each dropped onto the ground via a downward raycast,
# deterministic per (SCATTER_SEED + seed_index). `clear` keeps an inner ring free so we
# don't bury the player entry / gate. Used by resources, animals and enemies alike — the
# seed_index differs per call so kinds don't correlate. Returns silently on bad input so
# empty/missing config never breaks the area.
func _scatter_scene(scene: PackedScene, count: int, seed_index: int, clear: float) -> void:
	if scene == null or count <= 0:
		return
	# Ground colliders are added during _ready; wait one physics frame so the ray hits them.
	await get_tree().physics_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = SCATTER_SEED + seed_index
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var fill_radius: float = maxf(1.0, area_radius - 4.0)
	for i in range(count):
		var ang: float = rng.randf() * TAU
		var dist: float = sqrt(rng.randf()) * fill_radius
		if clear > 0.0 and dist < clear:
			dist = clear + rng.randf() * maxf(0.01, fill_radius - clear)
		var pos: Vector3 = Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		var params := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 60.0, pos + Vector3.DOWN * 60.0)
		params.collision_mask = 1
		var hit: Dictionary = space.intersect_ray(params)
		if hit.is_empty():
			continue
		var hit_pos: Vector3 = hit["position"]
		var inst: Node3D = scene.instantiate() as Node3D
		if inst == null:
			continue
		add_child(inst)
		inst.global_position = hit_pos
		inst.rotation.y = rng.randf() * TAU

# Like _scatter_scene but each instance is a random pick from a pool (for animal/enemy
# variety). One shared seed so the whole set is deterministic.
func _scatter_pool(pool: Array[PackedScene], count: int, seed_index: int, clear: float) -> void:
	if pool.is_empty() or count <= 0:
		return
	await get_tree().physics_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = SCATTER_SEED + seed_index
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var fill_radius: float = maxf(1.0, area_radius - 4.0)
	for i in range(count):
		var scene: PackedScene = pool[rng.randi() % pool.size()]
		if scene == null:
			continue
		var ang: float = rng.randf() * TAU
		var dist: float = sqrt(rng.randf()) * fill_radius
		if clear > 0.0 and dist < clear:
			dist = clear + rng.randf() * maxf(0.01, fill_radius - clear)
		var pos: Vector3 = Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)
		var params := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 60.0, pos + Vector3.DOWN * 60.0)
		params.collision_mask = 1
		var hit: Dictionary = space.intersect_ray(params)
		if hit.is_empty():
			continue
		var hit_pos: Vector3 = hit["position"]
		var inst: Node3D = scene.instantiate() as Node3D
		if inst == null:
			continue
		add_child(inst)
		inst.global_position = hit_pos
		inst.rotation.y = rng.randf() * TAU

# --- Content scatter wrappers ----------------------------------------------

func _scatter_resources() -> void:
	# Each resource KIND gets its own seed_index so two kinds never overlap-correlate.
	var idx: int = 20
	for entry in resource_nodes:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = entry
		var path: String = String(d.get("path", ""))
		if path == "":
			continue
		var res: Resource = load(path)
		if not (res is PackedScene):
			push_warning("WildArea: resource path is not a PackedScene: %s" % path)
			continue
		var count: int = int(d.get("count", 0))
		var clear: float = float(d.get("clear", 0.0))
		_scatter_scene(res as PackedScene, count, idx, clear)
		idx += 1

func _scatter_animals() -> void:
	var pool: Array[PackedScene] = _load_pool(animal_variants)
	if pool.is_empty() or animal_count <= 0:
		return
	# Keep wildlife off the very centre so they don't spawn on the player. Await so the
	# scattered animals exist before we apply the per-area predator speed shave below.
	await _scatter_pool(pool, animal_count, 60, 6.0)
	_apply_predator_speed_shave()

# Multiply every scattered HOSTILE animal's chase speed by hostile_animal_speed_scale so a
# gather zone can soften its predators (see iron_hills). No-op at 1.0. Membership-tested via
# the "animal" group + the duck-typed `hostile` flag, so it never depends on the Animal
# class symbol being resolved (cold-cache safe) and skips gates/ground/player cleanly.
func _apply_predator_speed_shave() -> void:
	if is_equal_approx(hostile_animal_speed_scale, 1.0):
		return
	for child in get_children():
		if not child.is_in_group("animal"):
			continue
		if bool(child.get("hostile")):
			child.set("hostile_speed_scale", hostile_animal_speed_scale)

func _scatter_enemies() -> void:
	var pool: Array[PackedScene] = _load_pool(enemy_scenes)
	if pool.is_empty() or enemy_count <= 0:
		return
	# Enemies kept well away from the entry so the player isn't ambushed on arrival.
	_scatter_pool(pool, enemy_count, 80, 14.0)

func _load_pool(paths: PackedStringArray) -> Array[PackedScene]:
	var out: Array[PackedScene] = []
	for p in paths:
		var path: String = String(p)
		if path == "":
			continue
		if not ResourceLoader.exists(path):
			push_warning("WildArea: scene path not found, skipping: %s" % path)
			continue
		var res: Resource = load(path)
		if res is PackedScene:
			out.append(res as PackedScene)
		else:
			push_warning("WildArea: path is not a PackedScene, skipping: %s" % path)
	return out

# --- Player entry + return gate --------------------------------------------

# The marker SceneManager moves the incoming player onto. Named EXACTLY "from_town".
func _build_entry_marker() -> void:
	var marker := Marker3D.new()
	marker.name = "from_town"
	add_child(marker)
	marker.global_position = Vector3(0.0, 1.5, 0.0)

func _build_player() -> void:
	var player: Node3D = (load(PLAYER_SCENE) as PackedScene).instantiate()
	add_child(player)
	player.global_position = Vector3(0.0, 1.5, 0.0)

# A glowing portal-ish gate a few metres from the entry: aim + E to return to town. Built
# from teleport_raycast.gd (duck-typed, layer 1) + a box collider + an emissive mesh + a
# Label3D sign showing the area title.
func _build_return_gate() -> void:
	var gate := StaticBody3D.new()
	gate.name = "ReturnGate"
	gate.set_script(load(GATE_SCRIPT))
	gate.set("target_scene_path", TOWN_SCENE)
	gate.set("prompt_text", "Return to Town")
	gate.set("target_spawn_point", return_spawn)

	# Interaction collider (the player's raycast hits this; layer 1 by default).
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 3.0, 2.0)
	col.shape = box
	col.position = Vector3(0.0, 1.5, 0.0)
	gate.add_child(col)

	# Glowing portal slab.
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 2.6, 0.4)
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.7, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.7, 1.0)
	# Classic static glow as the baseline; _apply_portal_glow (after the gate is in-tree)
	# brightens it and starts the breathing pulse when enable_portal_glow is on.
	mat.emission_energy_multiplier = 2.0
	mesh.material_override = mat
	mesh.position = Vector3(0.0, 1.3, 0.0)
	gate.add_child(mesh)

	# Floating sign above the portal.
	var label := Label3D.new()
	label.text = area_title
	label.font_size = 64
	label.pixel_size = 0.01
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.position = Vector3(0.0, 3.0, 0.0)
	gate.add_child(label)

	add_child(gate)
	# Now in-tree: brighten + start the breathing pulse (no-op/static if glow disabled).
	_apply_portal_glow(mat, gate, portal_glow_energy)
	# A few metres in front of the entry so the player sees it on arrival but doesn't stand in it.
	gate.global_position = Vector3(0.0, 0.0, 5.0)

# --- Portal / gate glow helpers ---------------------------------------------

# Brighten an emissive gate material and (when enabled) start a looping "breathing" pulse
# around that brightness so gates read as live thresholds. `host` owns the tween, so it is
# freed with the gate. When enable_portal_glow is off this is a pure no-op and the caller's
# classic static emission stands. Brightness is scaled once by the time of day if the Clock
# autoload is present (gates beckon brighter at night); without Clock it's a flat factor.
func _apply_portal_glow(mat: StandardMaterial3D, host: Node, glow_energy: float) -> void:
	if not enable_portal_glow or mat == null or host == null:
		return
	var energy: float = glow_energy * _portal_tod_factor()
	mat.emission_energy_multiplier = energy
	if portal_pulse_speed <= 0.0:
		return
	var dur: float = 1.0 / maxf(0.05, portal_pulse_speed)
	var t: Tween = host.create_tween().set_loops()
	t.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(mat, "emission_energy_multiplier", energy * 1.30, dur)
	t.tween_property(mat, "emission_energy_multiplier", energy * 0.75, dur)

# Brightness multiplier from the time of day: brightest deep night, dimmest at noon (cosine
# over the 24h day). Flat 1.0 when the Clock autoload is missing or lacks get_time_fraction.
func _portal_tod_factor() -> float:
	var clock: Node = get_node_or_null("/root/Clock")
	if clock == null or not clock.has_method("get_time_fraction"):
		return 1.0
	var frac: float = clock.get_time_fraction()
	var hour_f: float = frac * 24.0
	# day_t: 1.0 at midnight, 0.0 at noon.
	var day_t: float = (cos((hour_f / 24.0) * TAU) + 1.0) * 0.5
	return lerpf(0.85, 1.5, day_t)

# --- Dungeon entrances + return marker --------------------------------------

# The marker a dungeon moves the player onto when it returns the player to THIS area
# (a dungeon entrance scene sets exit_scene_path=<this area .tscn>, exit_spawn_point=&"from_dungeon").
# Always built (even with no entrances) so any dungeon can route back here. Placed a couple
# of metres beside the "from_town" entry so the player lands cleanly on arrival.
func _build_dungeon_return_marker() -> void:
	var marker := Marker3D.new()
	marker.name = "from_dungeon"
	add_child(marker)
	marker.global_position = Vector3(3.0, 1.5, 0.0)

# For each configured entry, build a cave-mouth teleport gate into a dungeon entrance scene.
# Guarded: empty dungeon_entrances leaves the area unchanged. The gate is duck-typed
# teleport_raycast.gd (layer 1) + a box collider + a dark emissive archway mesh + a Label3D
# sign. Ground-snapped via a downward ray on mask 1 (like resource scatter), falling back to
# the raw entry pos if the ray misses.
func _build_dungeon_entrances() -> void:
	if dungeon_entrances.is_empty():
		return
	# Ground colliders are added during _ready; wait one physics frame so the snap ray hits.
	await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for entry in dungeon_entrances:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var d: Dictionary = entry
		var scene_path: String = String(d.get("scene", ""))
		if scene_path == "":
			continue
		var label_text: String = String(d.get("label", "Dungeon"))
		var pos: Vector3 = d.get("pos", Vector3.ZERO)

		# Ground-snap the placement (same pattern as scatter): ray straight down on mask 1.
		var params := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 60.0, pos + Vector3.DOWN * 60.0)
		params.collision_mask = 1
		var hit: Dictionary = space.intersect_ray(params)
		var place: Vector3 = pos
		if not hit.is_empty():
			place = hit["position"]

		var gate := StaticBody3D.new()
		gate.name = "DungeonEntrance"
		gate.set_script(load(GATE_SCRIPT))
		gate.set("target_scene_path", scene_path)
		gate.set("prompt_text", "Enter " + label_text)
		# The dungeon entrance scene places its own player on its own entry marker, so the
		# spawn point is irrelevant here; leave it blank.
		gate.set("target_spawn_point", &"")

		# Interaction collider (player raycast hits this; layer 1 by default).
		var col := CollisionShape3D.new()
		var cbox := BoxShape3D.new()
		cbox.size = Vector3(3.0, 4.0, 3.0)
		col.shape = cbox
		col.position = Vector3(0.0, 2.0, 0.0)
		gate.add_child(col)

		# Dark emissive cave-mouth archway slab.
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2.6, 3.4, 0.6)
		mesh.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.05, 0.04, 0.07)
		mat.emission_enabled = true
		mat.emission = Color(0.5, 0.15, 0.35)
		# Classic static glow baseline; brightened + pulsed below once the gate is in-tree.
		mat.emission_energy_multiplier = 1.6
		mesh.material_override = mat
		mesh.position = Vector3(0.0, 1.7, 0.0)
		gate.add_child(mesh)

		# Floating sign above the cave mouth.
		var label := Label3D.new()
		label.text = label_text
		label.font_size = 64
		label.pixel_size = 0.01
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = false
		label.position = Vector3(0.0, 3.8, 0.0)
		gate.add_child(label)

		add_child(gate)
		gate.global_position = place
		# In-tree: brighten + pulse the cave mouth. Dungeon mouths read moodier than the
		# return gate, so scale their glow down a touch. No-op/static when glow disabled.
		_apply_portal_glow(mat, gate, portal_glow_energy * 0.6)
