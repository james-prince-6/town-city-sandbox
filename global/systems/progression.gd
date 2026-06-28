# progression.gd
# Autoload singleton (registered in Project Settings -> Autoload as "Progression").
#
# The combat progression brain: killing enemies grants XP, XP fills a level, each level
# grants a skill point, and points are spent across three playstyle branches (Melee /
# Ranged / Survival) on Skill resources. Skills are passive stat boosts (more damage,
# health, stamina, crit, faster bows) plus a few unlockable perks.
#
# Like QuestSystem this is the single source of RUNTIME truth — the Skill .tres files are
# shareable templates that store no progress. Everything mutable (xp, level, unspent
# points, per-skill rank) lives here and is saved via capture_state()/restore_state(),
# gathered by SaveManager alongside the other autoloads.
#
# Design notes:
# - Skill definitions are auto-loaded by scanning SKILL_DB_PATH at startup into
#   `database` ({ id -> Skill }), mirroring QuestSystem._load_database(). Drop a new
#   Skill .tres in and it appears in the tree automatically.
# - Derived stats are NOT stored; they're summed on demand from allocated ranks via
#   get_stat(), so loading a save or buying a skill always yields a consistent total.
# - Flat health/stamina bonuses are pushed onto PlayerStats by _apply_to_player_stats(),
#   keeping PlayerStats' base at 100 and adding the survival-tree bonus on top.
#
# Access from anywhere: Progression.add_xp(10), Progression.melee_damage_mult(), etc.

extends Node

## Folder scanned for Skill (.tres) resources at startup. Every Skill found is registered
## into `database` under its `id`.
const SKILL_DB_PATH := "res://global/progression/skills/"

## Base PlayerStats values the survival tree adds onto. Kept here so recomputing max
## health/stamina is always "base + bonus" and never drifts as skills are bought/refunded.
const BASE_MAX_HEALTH: float = 100.0
const BASE_MAX_STAMINA: float = 100.0

## XP curve: points needed to go from `level` to `level + 1`. A clear linear ramp so each
## level costs a bit more than the last (level 1->2 = 50, 2->3 = 90, 3->4 = 130, ...).
const XP_BASE: int = 50
const XP_PER_LEVEL: int = 40

## Skill points awarded each time the player levels up.
const POINTS_PER_LEVEL: int = 1

## End-game scaling perks (Survival branch). Flat skill passives hard-cap (~+60%), so these two
## perks instead scale with PLAYER LEVEL beyond ENDGAME_SCALE_LEVEL, giving descent its late-game
## reward without an unbounded curve. Each is gated by get_rank() > 0, so an un-perked build pays
## nothing. Tunable here so the integrator can reshape the end-game without editing the getters.
const ENDGAME_SCALE_LEVEL: int = 10
## late_bloomer: extra weapon-damage MULTIPLIER added per player level above ENDGAME_SCALE_LEVEL.
const LATE_BLOOMER_DMG_PER_LEVEL: float = 0.03
## iron_resolve: extra FLAT max health added per player level above ENDGAME_SCALE_LEVEL.
const IRON_RESOLVE_HP_PER_LEVEL: float = 4.0

# --- Signals ---------------------------------------------------------------

## Emitted whenever XP changes (a kill, or a load). Carries the running totals plus how
## much XP the CURRENT level needs, so an XP bar can draw a ratio without extra calls.
signal xp_changed(xp: int, level: int, xp_to_next: int)

## Emitted once per level gained, after points are credited. `points_gained` is how many
## points this level-up handed out (usually POINTS_PER_LEVEL).
signal leveled_up(level: int, points_gained: int)

## Emitted whenever allocation changes (a skill bought, or a load). UI refreshes off this.
signal skills_changed

# --- Core state ------------------------------------------------------------

## id (StringName) -> Skill resource. Lookup table for every skill definition.
var database: Dictionary = {}

## Total XP earned at the CURRENT level (resets toward 0 each level-up; spillover carries).
var xp: int = 0

## Current player level (starts at 1).
var level: int = 1

## Unspent skill points available to allocate.
var points: int = 0

## skill_id (StringName) -> int rank currently owned. Absent = rank 0.
var _ranks: Dictionary = {}

func _ready() -> void:
	# Keep ticking even while a blocking UI pauses the tree, mirroring the other systems.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_database()
	# PlayerStats may not have finished _ready yet; push our derived maxima next idle frame.
	call_deferred("_apply_to_player_stats")

# --- Database --------------------------------------------------------------

func _load_database() -> void:
	var dir := DirAccess.open(SKILL_DB_PATH)
	if dir == null:
		push_warning("Progression: skills folder not found at %s" % SKILL_DB_PATH)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		# In exported builds Godot renames .tres -> .tres.remap; strip that so the load()
		# path stays valid in both the editor and exports (mirrors QuestSystem).
		if file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
			var clean := file_name.trim_suffix(".remap")
			var res := load(SKILL_DB_PATH + clean)
			if res is Skill:
				if res.id == &"":
					push_warning("Progression: %s has an empty id, skipping." % clean)
				else:
					database[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()

## Look up the full Skill definition for an id (or null if unknown).
func get_skill(id: StringName) -> Skill:
	return database.get(id)

## Every Skill in a given branch, as resources (for the tree UI to list a column).
func get_skills_in_branch(branch: int) -> Array[Skill]:
	var result: Array[Skill] = []
	for id in database:
		var skill: Skill = database[id]
		if skill != null and skill.branch == branch:
			result.append(skill)
	# Stable, readable order: required_level then id so columns don't shuffle each run.
	result.sort_custom(func(a: Skill, b: Skill) -> bool:
		if a.required_level != b.required_level:
			return a.required_level < b.required_level
		return String(a.id) < String(b.id))
	return result

# --- XP curve & levelling --------------------------------------------------

## XP needed to advance FROM `lvl` to `lvl + 1`.
func xp_to_next(lvl: int) -> int:
	return XP_BASE + (maxi(lvl, 1) - 1) * XP_PER_LEVEL

## Grant XP (typically from an enemy kill). Accumulates, loops level-ups crediting points,
## and emits xp_changed (and leveled_up per level). Recomputes derived PlayerStats once.
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	xp += amount
	var gained_levels: int = 0
	# Loop in case a single big reward spans several levels.
	while xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
		points += POINTS_PER_LEVEL
		gained_levels += 1
		leveled_up.emit(level, POINTS_PER_LEVEL)
	if gained_levels > 0:
		# More max health/stamina may now be affordable; keep PlayerStats in sync and tell
		# the UI the point pool changed.
		_apply_to_player_stats()
		skills_changed.emit()
	xp_changed.emit(xp, level, xp_to_next(level))

## Shave XP off the CURRENT level's progress (a death penalty). Never de-levels and never drops
## below 0 — only the in-progress bar is reduced. Returns how much was actually removed so the
## caller (the death screen) can report it, and emits xp_changed so the HUD bar updates.
func lose_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	var lost: int = mini(amount, xp)
	xp -= lost
	xp_changed.emit(xp, level, xp_to_next(level))
	return lost

# --- Allocation ------------------------------------------------------------

## True if the skill exists and every gate (rank, points, level, prerequisite) is met.
func can_allocate(skill_id: StringName) -> bool:
	var skill: Skill = database.get(skill_id)
	if skill == null:
		return false
	if get_rank(skill_id) >= skill.max_rank:
		return false
	if points < skill.cost:
		return false
	if level < skill.required_level:
		return false
	if skill.prerequisite != &"":
		if get_rank(skill.prerequisite) < skill.prerequisite_rank:
			return false
	return true

## Spend points to raise a skill one rank. Returns true on success. Recomputes derived
## stats and emits skills_changed so combat and UI pick up the change.
func allocate(skill_id: StringName) -> bool:
	if not can_allocate(skill_id):
		return false
	var skill: Skill = database[skill_id]
	points -= skill.cost
	_ranks[skill_id] = get_rank(skill_id) + 1
	_apply_to_player_stats()
	skills_changed.emit()
	return true

# --- Queries ---------------------------------------------------------------

func get_rank(skill_id: StringName) -> int:
	return int(_ranks.get(skill_id, 0))

func get_points() -> int:
	return points

func get_level() -> int:
	return level

func get_xp() -> int:
	return xp

## True if a perk (or any skill) is owned at rank >= 1. Combat reads this for perks.
func has_perk(skill_id: StringName) -> bool:
	return get_rank(skill_id) >= 1

# --- Derived stats ---------------------------------------------------------

## Sum stat_per_rank[stat_key] * rank over every allocated skill. Returns 0.0 if nothing
## contributes. This is the single source of every derived combat number.
func get_stat(stat_key: StringName) -> float:
	var total: float = 0.0
	for skill_id in _ranks:
		var rank: int = int(_ranks[skill_id])
		if rank <= 0:
			continue
		var skill: Skill = database.get(skill_id)
		if skill == null:
			continue
		if skill.stat_per_rank.has(stat_key):
			var per_rank: float = float(skill.stat_per_rank[stat_key])
			total += per_rank * float(rank)
	return total

## Multiplier applied to melee weapon damage (1.0 = unmodified). Adds the level-scaled late_bloomer
## bonus on top of the flat skill passives so late-game levels keep mattering.
func melee_damage_mult() -> float:
	return 1.0 + get_stat(&"melee_damage_mult") + _late_bloomer_bonus()

## Multiplier applied to ranged weapon damage (1.0 = unmodified). Same late_bloomer bonus as melee.
func ranged_damage_mult() -> float:
	return 1.0 + get_stat(&"ranged_damage_mult") + _late_bloomer_bonus()

## Multiplier applied to ranged weapon cooldown (1.0 = unmodified, 0.3 = 70% faster).
## Clamped so cooldown can never drop below 30% of the weapon's base.
func ranged_cooldown_mult() -> float:
	return clampf(1.0 - get_stat(&"ranged_cooldown_reduction"), 0.3, 1.0)

## Chance (0..1) a hit crits. Combat may roll this to apply a damage bonus.
func crit_chance() -> float:
	return clampf(get_stat(&"crit_chance"), 0.0, 1.0)

## Flat extra max health from the survival tree, plus the level-scaled iron_resolve bonus so a
## deep-into-the-game character keeps gaining durability after Toughness has maxed.
func bonus_max_health() -> float:
	return get_stat(&"max_health") + _iron_resolve_bonus()

## late_bloomer perk: +LATE_BLOOMER_DMG_PER_LEVEL to the melee/ranged damage multiplier for every
## player level earned beyond ENDGAME_SCALE_LEVEL. Returns 0.0 until the perk is owned (get_rank > 0)
## so it never touches an un-perked build; scales with rank too, should the .tres raise max_rank.
func _late_bloomer_bonus() -> float:
	var rank: int = get_rank(&"late_bloomer")
	if rank <= 0:
		return 0.0
	var levels_over: int = maxi(level - ENDGAME_SCALE_LEVEL, 0)
	return LATE_BLOOMER_DMG_PER_LEVEL * float(levels_over) * float(rank)

## iron_resolve perk: +IRON_RESOLVE_HP_PER_LEVEL FLAT max health per player level beyond
## ENDGAME_SCALE_LEVEL. Folded into bonus_max_health() so _apply_to_player_stats() tops the bar up
## as the cap climbs each level-up. Returns 0.0 until owned.
func _iron_resolve_bonus() -> float:
	var rank: int = get_rank(&"iron_resolve")
	if rank <= 0:
		return 0.0
	var levels_over: int = maxi(level - ENDGAME_SCALE_LEVEL, 0)
	return IRON_RESOLVE_HP_PER_LEVEL * float(levels_over) * float(rank)

## Flat extra max stamina from the survival tree.
func bonus_max_stamina() -> float:
	return get_stat(&"max_stamina")

## Fraction (0..1) of melee damage dealt that is returned to the player as health.
## Drives the Lifesteal perk; melee weapons heal final_damage * this on a swing.
func melee_lifesteal() -> float:
	return clampf(get_stat(&"melee_lifesteal"), 0.0, 1.0)

## Fraction (0..0.9) of incoming damage ignored. Drives the Thick Skin skill; the player's
## _on_hurt scales incoming damage by (1.0 - this). Capped at 90% so hits always sting.
func damage_reduction() -> float:
	return clampf(get_stat(&"damage_reduction"), 0.0, 0.9)

# --- Pushing derived maxima onto PlayerStats -------------------------------

## Recompute PlayerStats.max_health / max_stamina as base + survival bonus. Current values
## are preserved (clamped down only if they'd exceed the new max); a raised max tops the
## current bar up by the same delta so a fresh "+20 max health" feels like a heal.
func _apply_to_player_stats() -> void:
	if PlayerStats == null:
		return
	var new_max_health: float = BASE_MAX_HEALTH + bonus_max_health()
	var new_max_stamina: float = BASE_MAX_STAMINA + bonus_max_stamina()

	var health_delta: float = new_max_health - PlayerStats.max_health
	PlayerStats.max_health = new_max_health
	# Raising the cap grants the extra as current HP; lowering it just clamps.
	if health_delta > 0.0 and not PlayerStats.is_dead():
		PlayerStats.health += health_delta
	PlayerStats.health = clampf(PlayerStats.health, 0.0, new_max_health)
	PlayerStats.health_changed.emit(PlayerStats.health, new_max_health)

	var stamina_delta: float = new_max_stamina - PlayerStats.max_stamina
	PlayerStats.max_stamina = new_max_stamina
	if stamina_delta > 0.0:
		PlayerStats.stamina += stamina_delta
	PlayerStats.stamina = clampf(PlayerStats.stamina, 0.0, new_max_stamina)
	PlayerStats.stamina_changed.emit(PlayerStats.stamina, new_max_stamina)

# --- Save / load -----------------------------------------------------------

func capture_state() -> Dictionary:
	return {
		"xp": xp,
		"level": level,
		"points": points,
		"ranks": _ranks.duplicate(),
	}

func restore_state(data: Dictionary) -> void:
	xp = int(data.get("xp", 0))
	level = maxi(int(data.get("level", 1)), 1)
	points = int(data.get("points", 0))
	_ranks = {}
	var saved_ranks: Dictionary = data.get("ranks", {})
	for id in saved_ranks:
		_ranks[id] = int(saved_ranks[id])
	# Recompute everything off the restored ranks and announce the fresh totals.
	_apply_to_player_stats()
	xp_changed.emit(xp, level, xp_to_next(level))
	skills_changed.emit()
