# health.gd
# Reusable "Health" component.
#
# This is NOT an autoload — it is a small Node you drop in as a CHILD of an
# entity scene (a critter, a destructible harvestable, anything that can be hurt).
# The parent owns its own visuals/behaviour; this child just tracks hit points and
# shouts (via signals) when it gets damaged or dies.
#
# How other code uses it:
# - Combat: the player's forward raycast finds a body, looks for a Health child,
#   and calls take_damage(weapon.damage). This component emits `damaged`, and when
#   the pool hits 0 it emits `died` exactly once.
# - The parent connects to `damaged`/`died` to flash, play a sound, drop loot, etc.
#
# Because it is generic, the same script works on a slime and on a breakable rock —
# you only change the @export max_health in the Inspector.

extends Node

## Emitted every time damage is actually applied. `amount` is how much was taken
## (already clamped — never more than was left), `current` is the new health total.
## Listeners use this to flash the mesh, show a hit number, play a sound, etc.
signal damaged(amount: float, current: float)

## Emitted exactly ONCE, the moment health reaches 0. The parent connects to this
## to drop loot and queue_free() / respawn itself.
signal died

## Starting (and maximum) hit points. Editable per-entity in the Inspector, so a
## weak critter and a tough rock can share this exact script.
@export var max_health: float = 30.0

## Per-element damage multipliers, keyed by DamageInfo.DamageType (an int) -> float.
## >1.0 is a WEAKNESS (takes extra), <1.0 is RESISTANCE, 0.0 is immunity. Missing
## types default to 1.0. Example for an ice slime weak to fire, resistant to ice:
##   { DamageInfo.DamageType.FIRE: 2.0, DamageInfo.DamageType.ICE: 0.25 }
@export var damage_multipliers: Dictionary = {}

## Current hit points. Seeded to max_health in _ready and clamped to [0, max].
var current: float = 0.0

# Guards against emitting `died` more than once if take_damage is called again
# after the entity is already dead (e.g. two hits in the same frame).
var _is_dead: bool = false

func _ready() -> void:
	# Begin at full health. We do this here (not as the var's default) so it always
	# tracks whatever max_health was set to in the Inspector.
	current = max_health

# --- Damage / healing ------------------------------------------------------

## Apply a typed DamageInfo, scaling by this entity's weakness/resistance for that
## element, then routing through take_damage(). This is the path the combat system
## uses (HurtBox.hit -> health.apply_damage). Returns the actual damage dealt.
func apply_damage(info: DamageInfo) -> float:
	if info == null:
		return 0.0
	var mult: float = float(damage_multipliers.get(info.type, 1.0))
	var final_amount: float = info.amount * mult
	if final_amount <= 0.0:
		return 0.0
	take_damage(final_amount)
	# Game-feel (purely cosmetic): spawn a floating damage number + impact burst at
	# the hit point, now that the FINAL post-resistance damage is known. Guarded so
	# a hit with no active world / no CombatFeel autoload simply does nothing.
	var feel = get_node_or_null("/root/CombatFeel")
	if feel != null:
		feel.show_damage(info, final_amount, self)
	return final_amount

## Apply `amount` damage. Ignores zero/negative amounts and does nothing once the
## entity is already dead. Clamps health to a floor of 0 and emits `damaged`; if
## that brings health to 0 it emits `died` once.
func take_damage(amount: float) -> void:
	if amount <= 0.0:
		push_warning("Health.take_damage: non-positive amount %s ignored." % amount)
		return
	if _is_dead:
		# Already dead — nothing left to hurt.
		return

	# Don't subtract more than is actually left, so `damaged` reports the true loss.
	var applied: float = min(amount, current)
	current = max(current - amount, 0.0)
	damaged.emit(applied, current)

	if current <= 0.0:
		_is_dead = true
		died.emit()

## Restore `amount` hit points, never exceeding max_health. Ignores zero/negative
## amounts and refuses to revive something already dead.
func heal(amount: float) -> void:
	if amount <= 0.0:
		push_warning("Health.heal: non-positive amount %s ignored." % amount)
		return
	if _is_dead:
		# Healing the dead isn't this component's job; ignore it.
		return
	current = min(current + amount, max_health)

# --- Queries ---------------------------------------------------------------

## True once health has hit 0 (and `died` has fired).
func is_dead() -> bool:
	return _is_dead
