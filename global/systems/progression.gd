# progression.gd
# Autoload singleton (registered as "Progression").
#
# USE-BASED progression (D1 rework, 2026-06-28) — Skyrim-style. Replaces the old "global XP ->
# level -> spend skill points" model with FOUR skills that rise as you USE them:
#
#   Melee     — levels when you swing a melee weapon (register_use on a committed swing)
#   Ranged    — levels when you fire a bow / crossbow
#   Magic     — levels when you cast a wand (a ranged weapon with a mana cost)
#   Survival  — levels when you take a hit (endure damage)
#
# Each skill level grants a small AUTO passive (more damage / faster fire / more HP & resist),
# and leveling a skill earns a PERK POINT for that skill's tree, spent on its perks (cleave,
# piercing shot, lifesteal, second wind, etc.). So the player's build emerges from what they do.
#
# DESIGN PRINCIPLES that keep the rest of the game unchanged:
#  - The combat-facing GETTERS are IDENTICAL in name + signature to before
#    (melee_damage_mult / ranged_damage_mult / ranged_cooldown_mult / crit_chance /
#    bonus_max_health / bonus_max_stamina / melee_lifesteal / damage_reduction / has_perk).
#    Only their INTERNALS changed: they now read skill LEVELS (auto-scale) + allocated PERKS.
#    NEW getters for Magic: magic_damage_mult / magic_cooldown_mult / mana_cost_mult.
#  - The old stat-passive Skill .tres (heavy_hands, marksman, toughness, ...) are now IGNORED
#    (is_perk == false): their effect is the per-level auto-scale. The is_perk == true .tres
#    are the allocatable perks. We keep them all in `database` so nothing dangles; the old
#    `prerequisite` chain is dropped — perks gate on SKILL LEVEL (required_level reinterpreted
#    as "min level in this perk's skill") + perk points.
#  - add_xp() (enemy kills, quest rewards, dev) is repurposed as a modest "combat experience"
#    nudge spread across the combat skills, so every old caller still improves the player.
#
# Anti-grind (§5.2): each skill level costs progressively more use, and every attack that
# trains a skill spends stamina/mana, so you can't free-grind by mashing into the air.
#
# All numbers below are TUNABLE constants — expect to balance them against playtests.

extends Node

## Folder scanned for Skill (.tres) resources at startup (the PERK definitions).
const SKILL_DB_PATH := "res://global/progression/skills/"

## Base PlayerStats values the Survival skill adds onto (so max H/S is always base + bonus).
const BASE_MAX_HEALTH: float = 100.0
const BASE_MAX_STAMINA: float = 100.0

# --- The four use-based skills (== Skill.Branch ints; APPEND-ONLY) ----------
const SKILL_MELEE: int = 0
const SKILL_RANGED: int = 1
const SKILL_SURVIVAL: int = 2
const SKILL_MAGIC: int = 3
const SKILLS: Array[int] = [SKILL_MELEE, SKILL_RANGED, SKILL_SURVIVAL, SKILL_MAGIC]
const SKILL_NAMES: Dictionary = {0: "Melee", 1: "Ranged", 2: "Survival", 3: "Magic"}

## Highest level any single skill can reach.
const LEVEL_CAP: int = 20

# --- TUNABLE: use-XP curve (rising cost per level = anti-grind) -------------
const USE_XP_BASE: float = 8.0
const USE_XP_PER_LEVEL: float = 5.0
## Use-XP from one trained action (a committed swing / shot / cast / hit taken).
const USE_XP_PER_ACTION: float = 3.0
## Fraction of an add_xp() grant turned into use-XP and split across the combat skills.
const ADD_XP_USE_SCALE: float = 0.15

# --- TUNABLE: per-level AUTO passives (the base each skill grants by level) --
const MELEE_DMG_PER_LEVEL: float = 0.03      # +3% melee damage / level  (+57% at 20)
const RANGED_DMG_PER_LEVEL: float = 0.03
const MAGIC_DMG_PER_LEVEL: float = 0.035
const RANGED_CD_PER_LEVEL: float = 0.01      # 1% faster / level (clamped at -70%)
const MAGIC_CD_PER_LEVEL: float = 0.01
const CRIT_PER_LEVEL: float = 0.004          # +0.4% crit / level of your best attack skill
const SURVIVAL_HP_PER_LEVEL: float = 4.0     # +4 max HP / level (+76 at 20)
const SURVIVAL_STAM_PER_LEVEL: float = 2.0
const SURVIVAL_RESIST_PER_LEVEL: float = 0.008  # +0.8% damage resist / level

## Perk points a skill's tree earns each time that skill levels up.
const PERK_POINTS_PER_LEVEL: int = 1

## Mana cost multiplier applied while the Mana Surge magic perk is owned.
const MANA_SURGE_COST_MULT: float = 0.6

## Endgame perks ramp once TOTAL skill levels (the global level) exceed this.
const ENDGAME_SCALE_LEVEL: int = 24
const LATE_BLOOMER_DMG_PER_LEVEL: float = 0.03
const IRON_RESOLVE_HP_PER_LEVEL: float = 4.0

# --- Signals ---------------------------------------------------------------

## Kept for compatibility (a generic "progression changed" ping; UIs rebuild off it).
signal xp_changed(xp: int, level: int, xp_to_next: int)
## Fires once per GLOBAL level gained (sum of skill levels). NotificationFeed + CombatFeel listen.
signal leveled_up(level: int, points_gained: int)
## Fires whenever allocation / skill state changes (a perk bought, a skill level, a load).
signal skills_changed
## NEW: a specific skill reached a new level (branch == SKILL_*; new_level is the new level).
signal skill_leveled(branch: int, new_level: int)

# --- Core state ------------------------------------------------------------

## id (StringName) -> Skill resource. Every Skill .tres; only is_perk ones are allocatable.
var database: Dictionary = {}

## branch (int) -> { "level": int, "xp": float }. The per-skill use-leveling state.
var _skill: Dictionary = {}

## branch (int) -> int unspent perk points for that skill's tree.
var _perk_points: Dictionary = {}

## perk_id (StringName) -> int rank owned. Absent = 0.
var _ranks: Dictionary = {}

## Cached global level (sum of skill levels, normalised so a fresh character is level 1).
var _global_level: int = 1

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_database()
	for b in SKILLS:
		_skill[b] = {"level": 1, "xp": 0.0}
		_perk_points[b] = 0
	_global_level = _compute_global_level()
	# PlayerStats may not have finished _ready yet; push derived maxima next idle frame.
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

func get_skill(id: StringName) -> Skill:
	return database.get(id)

## Allocatable PERKS in a branch (is_perk == true), ordered by their skill-level gate then id.
func get_perks_in_branch(branch: int) -> Array[Skill]:
	var result: Array[Skill] = []
	for id in database:
		var skill: Skill = database[id]
		if skill != null and skill.is_perk and int(skill.branch) == branch:
			result.append(skill)
	result.sort_custom(func(a: Skill, b: Skill) -> bool:
		if a.required_level != b.required_level:
			return a.required_level < b.required_level
		return String(a.id) < String(b.id))
	return result

## Compatibility alias for the old skill-tree UIs that call get_skills_in_branch().
func get_skills_in_branch(branch: int) -> Array[Skill]:
	return get_perks_in_branch(branch)

# --- Use-based levelling ----------------------------------------------------

## Use-XP needed to advance a skill FROM `level` to `level + 1` (rising = anti-grind).
func skill_xp_to_next(level: int) -> float:
	return USE_XP_BASE + float(maxi(level, 1)) * USE_XP_PER_LEVEL

## Train a skill. Called by combat when an action commits (a swing/shot/cast/hit-taken).
## Accumulates use-XP, loops level-ups crediting perk points, and keeps PlayerStats + UI in sync.
func register_use(branch: int, amount: float = USE_XP_PER_ACTION) -> void:
	if not _skill.has(branch) or amount <= 0.0:
		return
	var s: Dictionary = _skill[branch]
	if int(s["level"]) >= LEVEL_CAP:
		return
	s["xp"] = float(s["xp"]) + amount
	var leveled := false
	while int(s["level"]) < LEVEL_CAP and float(s["xp"]) >= skill_xp_to_next(int(s["level"])):
		s["xp"] = float(s["xp"]) - skill_xp_to_next(int(s["level"]))
		s["level"] = int(s["level"]) + 1
		_perk_points[branch] = int(_perk_points[branch]) + PERK_POINTS_PER_LEVEL
		leveled = true
		skill_leveled.emit(branch, int(s["level"]))
	if leveled:
		_apply_to_player_stats()
		_recompute_global_level()
		skills_changed.emit()
	# Always ping so a skill bar can animate mid-level.
	xp_changed.emit(0, _global_level, 1)

## The global character level = sum of skill levels, normalised so a fresh character (all
## skills at 1) reads as level 1. Drives the endgame perks + the HUD "Level N!" toast.
func _compute_global_level() -> int:
	var total: int = 0
	for b in SKILLS:
		total += int(_skill[b]["level"])
	return maxi(1, total - (SKILLS.size() - 1))

## Recompute the cached global level; fire leveled_up for each global level just gained.
func _recompute_global_level() -> void:
	var gl: int = _compute_global_level()
	if gl > _global_level:
		var gained: int = gl - _global_level
		_global_level = gl
		for i in range(gained):
			leveled_up.emit(_global_level - (gained - 1 - i), PERK_POINTS_PER_LEVEL)
	else:
		_global_level = gl

# --- Repurposed XP entry points (kept so old callers keep working) ---------

## Generic "combat experience" grant from enemy kills / quest rewards / dev tools. Spread as a
## modest use-XP nudge across the combat skills (Melee/Ranged/Magic) — direct use is still the
## main driver; this just keeps fights + quests feeling like they grow you.
func add_xp(amount: int) -> void:
	if amount <= 0:
		return
	var per: float = float(amount) * ADD_XP_USE_SCALE / 3.0
	register_use(SKILL_MELEE, per)
	register_use(SKILL_RANGED, per)
	register_use(SKILL_MAGIC, per)

## Death penalty: shave use-XP off each combat skill's in-progress level (never de-levels).
## Returns the total use-XP removed so the death screen can report something.
func lose_xp(amount: int) -> int:
	if amount <= 0:
		return 0
	var per: float = float(amount) * ADD_XP_USE_SCALE / 3.0
	var lost: float = 0.0
	for b in [SKILL_MELEE, SKILL_RANGED, SKILL_MAGIC]:
		var s: Dictionary = _skill[b]
		var take: float = minf(per, float(s["xp"]))
		s["xp"] = float(s["xp"]) - take
		lost += take
	xp_changed.emit(0, _global_level, 1)
	return int(round(lost))

# --- Perk allocation -------------------------------------------------------

## True if `perk_id` is an allocatable perk whose gates are met: it's a perk, not maxed, its
## skill is high enough level (required_level reinterpreted as the perk's skill level), and the
## perk's branch has enough perk points.
func can_allocate(perk_id: StringName) -> bool:
	var skill: Skill = database.get(perk_id)
	if skill == null or not skill.is_perk:
		return false
	if get_rank(perk_id) >= skill.max_rank:
		return false
	var branch: int = int(skill.branch)
	if int(_perk_points.get(branch, 0)) < skill.cost:
		return false
	if get_skill_level(branch) < skill.required_level:
		return false
	return true

## Spend perk points to raise a perk one rank. Recomputes derived stats + emits skills_changed.
func allocate(perk_id: StringName) -> bool:
	if not can_allocate(perk_id):
		return false
	var skill: Skill = database[perk_id]
	var branch: int = int(skill.branch)
	_perk_points[branch] = int(_perk_points[branch]) - skill.cost
	_ranks[perk_id] = get_rank(perk_id) + 1
	_apply_to_player_stats()
	skills_changed.emit()
	return true

# --- Queries ---------------------------------------------------------------

func get_rank(perk_id: StringName) -> int:
	return int(_ranks.get(perk_id, 0))

func has_perk(perk_id: StringName) -> bool:
	return get_rank(perk_id) >= 1

func get_skill_level(branch: int) -> int:
	return int(_skill[branch]["level"]) if _skill.has(branch) else 1

func get_skill_xp(branch: int) -> float:
	return float(_skill[branch]["xp"]) if _skill.has(branch) else 0.0

func get_skill_xp_to_next(branch: int) -> float:
	return skill_xp_to_next(get_skill_level(branch))

func get_perk_points(branch: int) -> int:
	return int(_perk_points.get(branch, 0))

func skill_display_name(branch: int) -> String:
	return String(SKILL_NAMES.get(branch, "Skill"))

# Compatibility shims for the old skill-tree UIs (now inert / being rewritten):
func get_level() -> int:
	return _global_level
func get_points() -> int:
	var t: int = 0
	for b in SKILLS:
		t += int(_perk_points[b])
	return t
func get_xp() -> int:
	return 0
func xp_to_next(_lvl: int) -> int:
	return 1

# Levels above 1 in a skill (what the auto-scale multiplies; level 1 = baseline, no bonus).
func _auto(branch: int) -> int:
	return maxi(get_skill_level(branch) - 1, 0)

# --- Derived stats (sum of perk stat_per_rank — the auto-scale is added in the getters) ---

## Sum stat_per_rank[stat_key] * rank over every ALLOCATED perk. (Stat-passive skills are
## retired; their effect is the per-level auto-scale, added directly in each getter.)
func get_stat(stat_key: StringName) -> float:
	var total: float = 0.0
	for perk_id in _ranks:
		var rank: int = int(_ranks[perk_id])
		if rank <= 0:
			continue
		var skill: Skill = database.get(perk_id)
		if skill == null:
			continue
		if skill.stat_per_rank.has(stat_key):
			total += float(skill.stat_per_rank[stat_key]) * float(rank)
	return total

func melee_damage_mult() -> float:
	return 1.0 + MELEE_DMG_PER_LEVEL * float(_auto(SKILL_MELEE)) + get_stat(&"melee_damage_mult") + _late_bloomer_bonus()

func ranged_damage_mult() -> float:
	return 1.0 + RANGED_DMG_PER_LEVEL * float(_auto(SKILL_RANGED)) + get_stat(&"ranged_damage_mult") + _late_bloomer_bonus()

func magic_damage_mult() -> float:
	return 1.0 + MAGIC_DMG_PER_LEVEL * float(_auto(SKILL_MAGIC)) + get_stat(&"magic_damage_mult") + _late_bloomer_bonus()

func ranged_cooldown_mult() -> float:
	return clampf(1.0 - (RANGED_CD_PER_LEVEL * float(_auto(SKILL_RANGED)) + get_stat(&"ranged_cooldown_reduction")), 0.3, 1.0)

func magic_cooldown_mult() -> float:
	return clampf(1.0 - (MAGIC_CD_PER_LEVEL * float(_auto(SKILL_MAGIC)) + get_stat(&"magic_cooldown_reduction")), 0.3, 1.0)

## Crit scales with your BEST attack skill (so a melee main and a caster both earn crit),
## plus any perk crit on top. Clamped to a valid probability.
func crit_chance() -> float:
	var best: int = maxi(maxi(_auto(SKILL_MELEE), _auto(SKILL_RANGED)), _auto(SKILL_MAGIC))
	return clampf(CRIT_PER_LEVEL * float(best) + get_stat(&"crit_chance"), 0.0, 1.0)

func bonus_max_health() -> float:
	return SURVIVAL_HP_PER_LEVEL * float(_auto(SKILL_SURVIVAL)) + get_stat(&"max_health") + _iron_resolve_bonus()

func bonus_max_stamina() -> float:
	return SURVIVAL_STAM_PER_LEVEL * float(_auto(SKILL_SURVIVAL)) + get_stat(&"max_stamina")

func damage_reduction() -> float:
	return clampf(SURVIVAL_RESIST_PER_LEVEL * float(_auto(SKILL_SURVIVAL)) + get_stat(&"damage_reduction"), 0.0, 0.9)

func melee_lifesteal() -> float:
	return clampf(get_stat(&"melee_lifesteal"), 0.0, 1.0)

## Mana cost multiplier for wand casts (the Mana Surge magic perk makes spells cheaper).
func mana_cost_mult() -> float:
	return MANA_SURGE_COST_MULT if has_perk(&"mana_surge") else 1.0

## late_bloomer perk: +damage multiplier per GLOBAL level beyond ENDGAME_SCALE_LEVEL.
func _late_bloomer_bonus() -> float:
	var rank: int = get_rank(&"late_bloomer")
	if rank <= 0:
		return 0.0
	return LATE_BLOOMER_DMG_PER_LEVEL * float(maxi(_global_level - ENDGAME_SCALE_LEVEL, 0)) * float(rank)

## iron_resolve perk: +flat max health per GLOBAL level beyond ENDGAME_SCALE_LEVEL.
func _iron_resolve_bonus() -> float:
	var rank: int = get_rank(&"iron_resolve")
	if rank <= 0:
		return 0.0
	return IRON_RESOLVE_HP_PER_LEVEL * float(maxi(_global_level - ENDGAME_SCALE_LEVEL, 0)) * float(rank)

# --- Pushing derived maxima onto PlayerStats -------------------------------

func _apply_to_player_stats() -> void:
	if PlayerStats == null:
		return
	var new_max_health: float = BASE_MAX_HEALTH + bonus_max_health()
	var new_max_stamina: float = BASE_MAX_STAMINA + bonus_max_stamina()

	var health_delta: float = new_max_health - PlayerStats.max_health
	PlayerStats.max_health = new_max_health
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
	var skills: Dictionary = {}
	for b in SKILLS:
		skills[b] = {"level": int(_skill[b]["level"]), "xp": float(_skill[b]["xp"])}
	return {
		"skills": skills,
		"perk_points": _perk_points.duplicate(),
		"ranks": _ranks.duplicate(),
	}

func restore_state(data: Dictionary) -> void:
	for b in SKILLS:
		_skill[b] = {"level": 1, "xp": 0.0}
		_perk_points[b] = 0
	var saved_skills: Dictionary = data.get("skills", {})
	for b in saved_skills:
		var bi: int = int(b)
		if _skill.has(bi) and saved_skills[b] is Dictionary:
			_skill[bi]["level"] = clampi(int(saved_skills[b].get("level", 1)), 1, LEVEL_CAP)
			_skill[bi]["xp"] = float(saved_skills[b].get("xp", 0.0))
	var saved_pp: Dictionary = data.get("perk_points", {})
	for b in saved_pp:
		_perk_points[int(b)] = int(saved_pp[b])
	_ranks = {}
	var saved_ranks: Dictionary = data.get("ranks", {})
	for id in saved_ranks:
		_ranks[id] = int(saved_ranks[id])
	_global_level = _compute_global_level()
	_apply_to_player_stats()
	xp_changed.emit(0, _global_level, 1)
	skills_changed.emit()
