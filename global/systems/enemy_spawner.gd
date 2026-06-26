# enemy_spawner.gd
# A small, reusable populator that fills a level's "enemy_spawn" Marker3D points with
# real monsters from a weighted SPAWN TABLE, scaled to a difficulty number.
#
# Why this exists:
# Hand-placing enemies (like dungeon_mine.tscn does) is great for a crafted level, but a
# PROCEDURAL dungeon only knows WHERE enemies could go (the markers the generator drops),
# not WHICH ones. This node turns "here are 14 spawn markers + difficulty 3" into "spawn
# a believable, budgeted mix of hounds / swarmers / spitters / brutes at those markers".
#
# How it plugs into the combat backbone:
# Each entry in the SPAWN TABLE is a full enemy SCENE (ember_hound.tscn, ...). Those scenes
# already carry their own EnemyStats .tres, Health, HurtBox and brain (see enemy.gd), so we
# just instantiate, parent under the world, and drop them on a marker — nothing else to wire.
#
# DETERMINISM:
# Every random choice (which enemy, which marker, the small scatter offset) is drawn from a
# RandomNumberGenerator passed IN by the caller. Same rng state + same markers => same army,
# so a seeded DungeonGenerator build is fully reproducible. We never touch the global randf().
#
# Usage:
#   var spawner := EnemySpawner.new()
#   world.add_child(spawner)
#   spawner.populate(world, difficulty, rng)   # fills every "enemy_spawn" marker under `world`

class_name EnemySpawner
extends Node

# --- The roster ------------------------------------------------------------
# The four verified enemy scenes this spawner can draw from. Preloaded with an explicit
# PackedScene type (the project treats "inferred from Variant" as an ERROR, so we never
# lean on := for a preload).
const SCENE_ASH: PackedScene = preload("res://entities/enemies/ash_swarmer.tscn")
const SCENE_HOUND: PackedScene = preload("res://entities/enemies/ember_hound.tscn")
const SCENE_SPITTER: PackedScene = preload("res://entities/enemies/cinder_spitter.tscn")
const SCENE_BRUTE: PackedScene = preload("res://entities/enemies/obsidian_brute.tscn")
const SCENE_GNASHER: PackedScene = preload("res://entities/enemies/gnasher.tscn")
const SCENE_STALKER: PackedScene = preload("res://entities/enemies/stalker.tscn")
const SCENE_RAVAGER: PackedScene = preload("res://entities/enemies/ravager.tscn")
const SCENE_CASTER: PackedScene = preload("res://entities/enemies/cinder_caster.tscn")
const SCENE_FROST: PackedScene = preload("res://entities/enemies/frost_caster.tscn")
const SCENE_VENOM: PackedScene = preload("res://entities/enemies/venom_spitter.tscn")
const SCENE_RIME: PackedScene = preload("res://entities/enemies/rime_stalker.tscn")
const SCENE_BOG: PackedScene = preload("res://entities/enemies/bog_lurker.tscn")

# --- Tuning ----------------------------------------------------------------
## Base threat budget spent regardless of difficulty (a near-empty dungeon still bites).
@export var base_budget: int = 6
## Extra threat budget granted per difficulty step.
@export var budget_per_difficulty: int = 4
## Hard cap so a silly difficulty value can't spawn thousands of bodies.
@export var max_enemies: int = 60
## Height (m) above a marker that an enemy is dropped, so it doesn't spawn inside the floor.
@export var spawn_lift: float = 0.6

# --- Elites ----------------------------------------------------------------
# A small slice of spawns are promoted to ELITES: tougher, richer, and visually glowing gold so
# the player can pick them out of a mob. The chance scales with difficulty (deeper => more
# elites) but is capped so a floor never becomes all-elite. Only populate() rolls elites;
# spawn_wave() never does, so its output stays byte-identical to before.
## Elite chance at difficulty 0 (the floor of the scaling curve).
@export var elite_base_chance: float = 0.04
## Extra elite chance added per difficulty step.
@export var elite_chance_per_difficulty: float = 0.02
## Hard ceiling on the elite chance no matter how high difficulty climbs.
@export var elite_max_chance: float = 0.35
## Max-HP multiplier applied to an elite's duplicated stats.
@export var elite_health_mult: float = 2.2
## Attack-damage multiplier applied to an elite's duplicated stats.
@export var elite_damage_mult: float = 1.6
## XP-reward multiplier applied to an elite's duplicated stats.
@export var elite_xp_mult: float = 3.0
## Emissive glow energy stamped on an elite's Animator (0 would leave it unlit).
@export var elite_emission_energy: float = 1.6
## Emissive glow colour for elites (a gold-ish tone).
@export var elite_emission_color: Color = Color(1.0, 0.84, 0.3)
## Fallback up-scale for an elite with no Animator to glow (so it's still visually distinct).
@export var elite_fallback_scale: float = 1.25


# A fresh copy of the weighted spawn table. Each row is { scene, cost, weight }:
#   cost   = how much threat budget the enemy consumes (tougher = pricier)
#   weight = relative likelihood of being picked among the AFFORDABLE rows
# Returned as a method (rather than a const literal) so the dictionaries stay plain,
# mutation-safe, and free of any const-expression quirks.
func _spawn_table() -> Array:
	return [
		{"scene": SCENE_ASH, "cost": 1, "weight": 4.0},     # fast, cheap chaff
		{"scene": SCENE_HOUND, "cost": 2, "weight": 3.0},   # bread-and-butter melee
		{"scene": SCENE_SPITTER, "cost": 2, "weight": 2.0}, # ranged pressure
		{"scene": SCENE_BRUTE, "cost": 4, "weight": 1.0},   # rare heavy
		{"scene": SCENE_GNASHER, "cost": 1, "weight": 4.0}, # fast, fragile swarm-biter
		{"scene": SCENE_STALKER, "cost": 3, "weight": 1.5}, # heavy ambusher w/ slam
		{"scene": SCENE_RAVAGER, "cost": 5, "weight": 0.75},# big elite bruiser
		{"scene": SCENE_VENOM, "cost": 2, "weight": 2.0},   # ranged poison spitter
		{"scene": SCENE_FROST, "cost": 3, "weight": 1.3},   # ranged ice caster (volley)
		{"scene": SCENE_CASTER, "cost": 4, "weight": 0.8},  # heavy fire caster (ring barrage)
		{"scene": SCENE_RIME, "cost": 2, "weight": 2.0},    # fast ice melee, chills on hit
		{"scene": SCENE_BOG, "cost": 3, "weight": 1.2},     # poison melee w/ slam
	]


## Fill every Marker3D in group "enemy_spawn" under `world` with budgeted, weighted enemies.
##
## world      : the dungeon root the markers live under and the enemies are parented to.
## difficulty : scales the threat budget (higher => more / tougher monsters).
## rng        : the seeded generator that drives EVERY random choice (determinism).
func populate(world: Node3D, difficulty: int, rng: RandomNumberGenerator) -> void:
	if world == null:
		push_warning("EnemySpawner.populate: no world given.")
		return
	if rng == null:
		# Caller forgot an rng — fall back to a fixed seed so we stay reproducible
		# rather than silently going non-deterministic.
		rng = RandomNumberGenerator.new()
		rng.seed = 0

	# Collect the spawn markers that belong to THIS world (scoped, so a second dungeon or
	# leftover markers elsewhere in the tree can't bleed in).
	var markers: Array = _collect_markers(world, "enemy_spawn")
	if markers.is_empty():
		push_warning("EnemySpawner.populate: no 'enemy_spawn' markers found under %s." % world.name)
		return

	# Shuffle the marker order deterministically so the round-robin fill isn't biased by
	# the order the generator happened to create them in.
	_shuffle(markers, rng)

	var table: Array = _spawn_table()
	var budget: int = base_budget + max(difficulty, 0) * budget_per_difficulty
	var spawned: int = 0
	var marker_index: int = 0
	# The per-enemy elite chance for this difficulty, computed once up front.
	var elite_chance: float = _elite_chance(difficulty)

	# Spend the budget: each loop picks an AFFORDABLE enemy (one whose cost fits the
	# remaining budget), drops it on the next marker (wrapping round-robin), and subtracts
	# its cost. Stops when nothing is affordable, the cap is hit, or budget runs dry.
	while budget > 0 and spawned < max_enemies:
		var entry: Dictionary = _pick_affordable(table, budget, rng)
		if entry.is_empty():
			break
		var marker: Node3D = markers[marker_index % markers.size()] as Node3D
		marker_index += 1
		var pos: Vector3 = marker.global_position + Vector3.UP * spawn_lift
		# A little jitter so multiple enemies sharing a wrapped marker don't stack perfectly.
		pos.x += rng.randf_range(-1.0, 1.0)
		pos.z += rng.randf_range(-1.0, 1.0)
		# Roll for elite AFTER the position draws, so a non-elite spawn is configured exactly as
		# before (the roll itself is the only added draw, keeping the army deterministic by seed).
		var is_elite: bool = rng.randf() < elite_chance
		_spawn_one(entry["scene"], world, pos, is_elite)
		budget -= int(entry["cost"])
		spawned += 1


## Convenience: drop `count` weighted enemies in a ring of `radius` around `around`,
## ignoring markers entirely. Handy for arena waves / boss adds. Returns the spawned nodes.
func spawn_wave(world: Node3D, count: int, rng: RandomNumberGenerator, around: Vector3 = Vector3.ZERO, radius: float = 6.0) -> Array:
	var out: Array = []
	if world == null or count <= 0:
		return out
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = 0
	var table: Array = _spawn_table()
	for i in range(count):
		var entry: Dictionary = _pick_weighted(table, rng)
		var ang: float = rng.randf_range(0.0, TAU)
		var dist: float = rng.randf_range(radius * 0.4, radius)
		var pos: Vector3 = around + Vector3(cos(ang) * dist, spawn_lift, sin(ang) * dist)
		var e: Node = _spawn_one(entry["scene"], world, pos)
		if e != null:
			out.append(e)
	return out


# --- Internals -------------------------------------------------------------

# Instance one enemy scene, parent it under the world, and place it. Returns the new node.
# When `elite` is true the enemy is promoted BEFORE entering the tree (so its boosted stats /
# glow are in place when enemy.gd / EnemyAnimator run their _ready). `elite` defaults false, so
# every existing caller (and spawn_wave) behaves exactly as before.
func _spawn_one(scene: PackedScene, world: Node3D, pos: Vector3, elite: bool = false) -> Node:
	if scene == null:
		return null
	var enemy: Node = scene.instantiate()
	# Promote BEFORE add_child: enemy.gd._apply_stats() (Health <- stats) and the EnemyAnimator
	# (which bakes emission into the model material) both run in _ready, fired by add_child.
	if elite:
		_make_elite(enemy)
	world.add_child(enemy)
	# Enemy scenes already carry their EnemyStats / Health / brain, so positioning is all
	# that's left. Set global position AFTER entering the tree.
	if enemy is Node3D:
		(enemy as Node3D).global_position = pos
	return enemy


# The per-enemy chance (0..1) of becoming an elite at the given difficulty: a base chance plus a
# per-step ramp, clamped to elite_max_chance so even a very deep floor keeps some normal chaff.
func _elite_chance(difficulty: int) -> float:
	var steps: int = max(difficulty, 0)
	var chance: float = elite_base_chance + elite_chance_per_difficulty * float(steps)
	return clampf(chance, 0.0, elite_max_chance)


# Promote a freshly-instantiated (not-yet-in-tree) enemy into an ELITE: a tougher, richer,
# glowing variant. We DUPLICATE its EnemyStats so the shared .tres every enemy of this type
# points at is never mutated, boost the duplicate's numbers, reassign it, and crank the body's
# emissive glow gold (falling back to scaling the node up if there's no Animator to light).
func _make_elite(enemy: Node) -> void:
	# Boost stats on a private copy so the shared resource stays pristine.
	var base_stats: EnemyStats = enemy.get("stats")
	if base_stats != null:
		var boosted: EnemyStats = base_stats.duplicate() as EnemyStats
		boosted.max_health = base_stats.max_health * elite_health_mult
		boosted.damage = base_stats.damage * elite_damage_mult
		boosted.xp = int(round(float(base_stats.xp) * elite_xp_mult))
		boosted.loot_amount = base_stats.loot_amount + 1
		enemy.set("stats", boosted)

	# Make the elite read at a glance. The EnemyAnimator bakes emission_color/emission_energy
	# into the model material in its _ready, so setting them now (pre-tree) takes effect. With no
	# Animator, scale the whole body up instead so it's still obviously bigger/meaner.
	var animator: Node = enemy.get_node_or_null("Animator")
	if animator != null:
		animator.set("emission_color", elite_emission_color)
		animator.set("emission_energy", elite_emission_energy)
	elif enemy is Node3D:
		(enemy as Node3D).scale = Vector3.ONE * elite_fallback_scale


# Pick a row whose cost fits `budget`, weighted by `weight`. Empty dict if none affordable.
func _pick_affordable(table: Array, budget: int, rng: RandomNumberGenerator) -> Dictionary:
	var affordable: Array = []
	for row in table:
		var r: Dictionary = row
		if int(r["cost"]) <= budget:
			affordable.append(r)
	if affordable.is_empty():
		return {}
	return _pick_weighted(affordable, rng)


# Standard weighted pick over a list of { weight: float, ... } rows using the seeded rng.
func _pick_weighted(rows: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total: float = 0.0
	for row in rows:
		var r: Dictionary = row
		total += float(r["weight"])
	if total <= 0.0:
		return rows[0]
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for row in rows:
		var r: Dictionary = row
		acc += float(r["weight"])
		if roll <= acc:
			return r
	return rows[rows.size() - 1]


# Find all Marker3D descendants of `world` that are in `group`. Scoped to the world subtree
# (rather than a global get_nodes_in_group) so multiple worlds can't cross-contaminate.
func _collect_markers(world: Node3D, group: String) -> Array:
	var out: Array = []
	var found: Array = world.find_children("", "Marker3D", true, false)
	for n in found:
		if (n as Node).is_in_group(group):
			out.append(n)
	return out


# In-place Fisher-Yates shuffle driven by the seeded rng (so order is reproducible).
func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
