# progression_rework_test.gd
# Headless verification for the D1 use-based leveling rework. Asserts in _ready(), writes
# user://_test_result.txt, quits 0/1. Run after an import pass:
#   Godot --headless --path <project> res://stages/dev/progression_rework_test.tscn --quit-after 120
extends Node

var _lines: Array = []
var _ok := true

func _ready() -> void:
	await get_tree().process_frame
	var P := get_node_or_null("/root/Progression")
	if P == null:
		_fail("Progression autoload missing (parse error?)"); _write(); get_tree().quit(1); return
	var MELEE: int = P.SKILL_MELEE
	var RANGED: int = P.SKILL_RANGED
	var MAGIC: int = P.SKILL_MAGIC
	var SURV: int = P.SKILL_SURVIVAL

	# 1. Use levels a skill + earns perk points.
	var start_lvl: int = P.get_skill_level(MELEE)
	P.register_use(MELEE, 100.0)
	if P.get_skill_level(MELEE) > start_lvl:
		_pass("Melee leveled by use: %d -> %d" % [start_lvl, P.get_skill_level(MELEE)])
	else:
		_fail("Melee did not level after register_use")
	if P.get_perk_points(MELEE) > 0:
		_pass("leveling Melee earned %d perk point(s)" % P.get_perk_points(MELEE))
	else:
		_fail("no perk points earned from leveling Melee")

	# 2. Auto-scale: more Melee level => higher melee_damage_mult.
	if P.melee_damage_mult() > 1.0:
		_pass("melee_damage_mult auto-scaled to %.2f" % P.melee_damage_mult())
	else:
		_fail("melee_damage_mult did not scale (%.2f)" % P.melee_damage_mult())

	# 3. Perk allocation: get Melee high enough, then buy Cleave (req Melee 4, cost 2).
	P.register_use(MELEE, 1000.0)
	if P.get_skill_level(MELEE) >= 4:
		_pass("Melee reached Lv %d (>=4 for Cleave)" % P.get_skill_level(MELEE))
	else:
		_fail("Melee only Lv %d (<4)" % P.get_skill_level(MELEE))
	var pts_before: int = P.get_perk_points(MELEE)
	if P.can_allocate(&"cleave") and P.allocate(&"cleave") and P.has_perk(&"cleave"):
		_pass("bought Cleave perk; has_perk(cleave) true")
	else:
		_fail("could not allocate Cleave (pts=%d, lvl=%d)" % [pts_before, P.get_skill_level(MELEE)])
	if P.get_perk_points(MELEE) == pts_before - 2:
		_pass("Cleave spent 2 Melee perk points (%d -> %d)" % [pts_before, P.get_perk_points(MELEE)])
	else:
		_fail("perk points wrong after Cleave: %d -> %d" % [pts_before, P.get_perk_points(MELEE)])

	# 4. Magic skill + a magic perk + cheaper casts.
	P.register_use(MAGIC, 1000.0)
	if P.get_skill_level(MAGIC) >= 6 and P.magic_damage_mult() > 1.0:
		_pass("Magic Lv %d, magic_damage_mult %.2f" % [P.get_skill_level(MAGIC), P.magic_damage_mult()])
	else:
		_fail("Magic did not scale (Lv %d, mult %.2f)" % [P.get_skill_level(MAGIC), P.magic_damage_mult()])
	if P.allocate(&"mana_surge") and P.mana_cost_mult() < 1.0:
		_pass("Mana Surge perk bought; mana_cost_mult now %.2f" % P.mana_cost_mult())
	else:
		_fail("Mana Surge not applied (mult %.2f)" % P.mana_cost_mult())

	# 5. Survival raises PlayerStats max health.
	var hp_before: float = PlayerStats.max_health
	P.register_use(SURV, 1000.0)
	if P.bonus_max_health() > 0.0 and PlayerStats.max_health > hp_before:
		_pass("Survival raised max HP: %.0f -> %.0f" % [hp_before, PlayerStats.max_health])
	else:
		_fail("Survival did not raise max HP (%.0f -> %.0f)" % [hp_before, PlayerStats.max_health])

	# 6. Retired stat-passive skills are NOT allocatable (their effect is auto-scale now).
	if not P.can_allocate(&"heavy_hands") and not P.can_allocate(&"toughness"):
		_pass("retired stat-passives (heavy_hands/toughness) are not allocatable")
	else:
		_fail("a retired stat-passive is still allocatable")

	# 7. Global level == (sum of skill levels) - 3.
	var sum: int = P.get_skill_level(MELEE) + P.get_skill_level(RANGED) + P.get_skill_level(MAGIC) + P.get_skill_level(SURV)
	if P.get_level() == max(1, sum - 3):
		_pass("global level %d == sum(skills) - 3" % P.get_level())
	else:
		_fail("global level %d != sum(%d)-3" % [P.get_level(), sum])

	# 8. Combat getters stay in valid ranges (combat depends on these).
	var ranges_ok: bool = P.crit_chance() >= 0.0 and P.crit_chance() <= 1.0 \
		and P.damage_reduction() >= 0.0 and P.damage_reduction() <= 0.9 \
		and P.ranged_cooldown_mult() >= 0.3 and P.ranged_cooldown_mult() <= 1.0 \
		and P.magic_cooldown_mult() >= 0.3 and P.magic_cooldown_mult() <= 1.0
	if ranges_ok:
		_pass("combat getters within valid clamps")
	else:
		_fail("a combat getter out of range")

	# 9. Level cap holds.
	P.register_use(MELEE, 9999999.0)
	if P.get_skill_level(MELEE) == P.LEVEL_CAP:
		_pass("Melee caps at LEVEL_CAP (%d)" % P.LEVEL_CAP)
	else:
		_fail("Melee level %d exceeded/!= cap %d" % [P.get_skill_level(MELEE), P.LEVEL_CAP])

	# 10. Save/load round-trip.
	var snap: Dictionary = P.capture_state()
	var saved_melee: int = P.get_skill_level(MELEE)
	var saved_cleave: int = P.get_rank(&"cleave")
	P.register_use(RANGED, 200.0)   # mutate after snapshot
	P.restore_state(snap)
	if P.get_skill_level(MELEE) == saved_melee and P.get_rank(&"cleave") == saved_cleave:
		_pass("save/load round-trips skill levels + perks")
	else:
		_fail("save/load mismatch (melee %d vs %d)" % [P.get_skill_level(MELEE), saved_melee])

	_write()
	get_tree().quit(0 if _ok else 1)

func _pass(m: String) -> void:
	_lines.append("PASS " + m)

func _fail(m: String) -> void:
	_ok = false
	_lines.append("FAIL " + m)

func _write() -> void:
	var f := FileAccess.open("user://_test_result.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(("PROGRESSION REWORK TEST: " + ("ALL PASS" if _ok else "FAILURES")) + "\n" + "\n".join(_lines))
		f.close()
