# boss.gd
# A mini-boss: a tougher Enemy with a multi-PHASE fight on top of the shared brain.
# It reuses everything in enemy.gd (chase, melee/ranged, the telegraphed special,
# flinch/stagger, knockback, the floating health bar) and layers a phase system:
#
#   PHASE 1 (full -> 50% HP): a slow, heavy melee bruiser that occasionally winds up a
#     big telegraphed SLAM (AoE knockback). Plenty of poise — only solid hits flinch it.
#   PHASE 2 (<= 50% HP): it ENRAGES — moves faster, attacks more often, its special
#     comes back sooner and fires more, AND it gains a second special: from here on it
#     ALTERNATES the ground-pound SLAM with a projectile VOLLEY, so the player can't camp
#     one safe spot. The transition flashes and immediately re-arms the special.
#
# Phase tuning mutates a PRIVATE copy of the stat sheet (duplicated in _ready) so the
# shared .tres on disk — and any other instance using it — is never touched.

class_name MiniBoss
extends Enemy

## Phase-2 multipliers / bonuses, exposed so the boss can be retuned in the Inspector
## without code changes. They scale the (private copy of the) stat sheet on enrage.
@export_group("Phases")
## Fraction of max HP at/under which the boss enters phase 2 (0.5 = at half health).
@export_range(0.0, 1.0) var phase2_health_fraction: float = 0.5
## Move speed is multiplied by this on enrage (>1 = faster).
@export var phase2_speed_mult: float = 1.45
## Normal attack_cooldown is multiplied by this on enrage (<1 = attacks more often).
@export var phase2_cooldown_mult: float = 0.6
## special_cooldown is multiplied by this on enrage (<1 = specials come back sooner).
@export var phase2_special_cooldown_mult: float = 0.5
## special_chance gains this much on enrage (clamped below 1.0).
@export var phase2_special_chance_bonus: float = 0.25

# Current phase (1 or 2). Starts at 1; bumped once when HP crosses the threshold.
var _phase: int = 1
# Flips each phase-2 special so the boss alternates SLAM <-> VOLLEY.
var _alt_special: bool = false


func _ready() -> void:
	# Work on a private copy of the stat sheet so phase mutations never bleed into the
	# shared .tres (which other instances / the next run would otherwise inherit).
	if stats != null:
		stats = stats.duplicate(true) as EnemyStats
	# Let the base Enemy wire up Health/HurtBox/health bar and start the brain.
	super()
	# Watch our own HP so we can flip to phase 2 at the threshold.
	if health != null:
		health.damaged.connect(_on_health_damaged)


# Each time we take damage, check whether this crossed the phase-2 threshold.
func _on_health_damaged(_amount: float, current: float) -> void:
	if _phase < 2 and stats != null and current <= stats.max_health * phase2_health_fraction:
		_enter_phase_2()


# Enrage: speed up, attack/special more often, and unlock the alternating second special.
func _enter_phase_2() -> void:
	_phase = 2
	if stats != null:
		stats.move_speed *= phase2_speed_mult
		stats.attack_cooldown *= phase2_cooldown_mult
		stats.special_cooldown *= phase2_special_cooldown_mult
		stats.special_chance = clampf(stats.special_chance + phase2_special_chance_bonus, 0.0, 0.95)
	# A quick flash sells the transition, and re-arming the special lets the new phase
	# open aggressively instead of waiting out the old cooldown.
	_flash_hurt()
	_last_special_ms = -100000


# Override the special-flavour pick: phase 1 uses the stat default (its SLAM); phase 2
# alternates SLAM <-> VOLLEY so the threat pattern changes when enraged.
func _choose_special_style() -> EnemyStats.SpecialStyle:
	if _phase >= 2:
		_alt_special = not _alt_special
		return EnemyStats.SpecialStyle.VOLLEY if _alt_special else EnemyStats.SpecialStyle.SLAM
	return stats.special_style


## Current phase (1 or 2) — handy for tests / debugging.
func current_phase() -> int:
	return _phase
