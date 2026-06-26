# status_receiver.gd
# A small component that holds the damage-over-time / slow STATUS EFFECTS currently on an
# entity, and ticks them. Drop it (or create it in code) as a child of any combatant that has
# either a sibling "Health" node (enemies) or is in the "player" group (the player).
#
# Effects are keyed by kind ("burn" / "chill" / "poison"); re-applying one refreshes its timer
# and keeps the stronger per-second value. Each kind maps to a damage element so resistances
# still matter (a fire-resistant enemy shrugs off most of a burn).
#
# - Burn / Poison: pure damage-over-time, ticked once per second so floating numbers read
#   clearly instead of spamming every frame.
# - Chill: a movement slow (speed_multiplier() < 1) plus a light DoT. The host (enemy.gd /
#   player.gd) multiplies its move speed by speed_multiplier() each frame.
#
# Elemental HitBoxes apply these automatically (see hit_box.gd -> apply_from_damage), so any
# fire/ice/poison weapon, wand, or enemy attack inflicts the matching status with no per-attack
# wiring.

class_name StatusReceiver
extends Node

## Kinds of status this component understands. Mapped from a damage element on apply.
enum Kind { BURN, CHILL, POISON }

## Emitted whenever the set of active effects changes (added / refreshed / expired) so a host
## can drive a visual tint or HUD icon if it wants. Carries the count of active effects.
signal effects_changed(active_count: int)

# Per-kind tuning applied when a hit of the matching element lands. dps is per second; the
# "min" floors keep weak hits still meaningful, the factor scales with the hit's damage.
const BURN_DURATION: float = 4.0
const POISON_DURATION: float = 6.0
const CHILL_DURATION: float = 3.0
const CHILL_SLOW: float = 0.5          # move at 50% speed while chilled
const DOT_TICK_SECONDS: float = 1.0    # apply DoT once per this many seconds

# Active effects: kind(int) -> { "expires": float(sec), "dps": float, "element": int, "slow": float }.
var _effects: Dictionary = {}

# Resolved once: the sibling Health (enemies) we damage, or null for the player (PlayerStats).
var _health: Node = null
var _is_player_host: bool = false
# Real-time accumulator so DoT ticks at a steady cadence regardless of frame rate / time-scale.
var _since_tick: float = 0.0


func _ready() -> void:
	var host := get_parent()
	if host != null:
		_health = host.get_node_or_null("Health")
		_is_player_host = host.is_in_group("player")


func _process(delta: float) -> void:
	if _effects.is_empty():
		return
	var now: float = float(Time.get_ticks_msec()) / 1000.0

	# Expire finished effects.
	var changed: bool = false
	for kind in _effects.keys():
		var e: Dictionary = _effects[kind]
		if now >= float(e["expires"]):
			_effects.erase(kind)
			changed = true
	if changed:
		effects_changed.emit(_effects.size())

	# Tick DoT on a fixed cadence.
	_since_tick += delta
	if _since_tick >= DOT_TICK_SECONDS:
		_since_tick -= DOT_TICK_SECONDS
		_tick_damage()


# --- Applying -------------------------------------------------------------

## Map an incoming damage element to a status and apply it. Called by HitBox on every elemental
## hit. base_amount lets stronger hits inflict stronger DoT. `attacker` keeps kill credit.
func apply_from_damage(element: int, base_amount: float, attacker: Node = null) -> void:
	match element:
		DamageInfo.DamageType.FIRE:
			apply(Kind.BURN, BURN_DURATION, maxf(2.0, base_amount * 0.25), DamageInfo.DamageType.FIRE, 0.0, attacker)
		DamageInfo.DamageType.POISON:
			apply(Kind.POISON, POISON_DURATION, maxf(1.5, base_amount * 0.2), DamageInfo.DamageType.POISON, 0.0, attacker)
		DamageInfo.DamageType.ICE:
			apply(Kind.CHILL, CHILL_DURATION, maxf(1.0, base_amount * 0.1), DamageInfo.DamageType.ICE, CHILL_SLOW, attacker)
		_:
			pass  # PHYSICAL / EXPLOSIVE inflict no lingering status.


## Add or refresh an effect. Refresh keeps the LATER expiry and the STRONGER dps/slow.
func apply(kind: int, duration: float, dps: float, element: int, slow: float, attacker: Node = null) -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	var new_expires: float = now + duration
	if _effects.has(kind):
		var cur: Dictionary = _effects[kind]
		new_expires = maxf(new_expires, float(cur["expires"]))
		dps = maxf(dps, float(cur["dps"]))
		slow = maxf(slow, float(cur["slow"]))
	_effects[kind] = {"expires": new_expires, "dps": dps, "element": element, "slow": slow, "attacker": attacker}
	effects_changed.emit(_effects.size())


# --- Queries --------------------------------------------------------------

## Combined movement multiplier from any slow effects (1.0 = normal). The host multiplies its
## move speed by this each frame. Uses the strongest slow currently active.
func speed_multiplier() -> float:
	var mult: float = 1.0
	for kind in _effects:
		var e: Dictionary = _effects[kind]
		mult = minf(mult, 1.0 - float(e["slow"]))
	return maxf(mult, 0.2)  # never fully freeze


func has_any() -> bool:
	return not _effects.is_empty()


# --- Damage ---------------------------------------------------------------

# Deal one cadence-tick of each DoT to the host (scaled per-second value). Routed through
# Health.apply_damage for enemies (so resistances + floating numbers apply) or PlayerStats for
# the player.
func _tick_damage() -> void:
	for kind in _effects:
		var e: Dictionary = _effects[kind]
		var dps: float = float(e["dps"])
		if dps <= 0.0:
			continue
		var element: int = int(e["element"])
		if _health != null and _health.has_method("apply_damage"):
			var info := DamageInfo.create(dps, element, e["attacker"])
			var host := get_parent()
			if host is Node3D:
				info.hit_position = (host as Node3D).global_position + Vector3.UP * 1.2
			_health.apply_damage(info)
		elif _is_player_host:
			PlayerStats.take_damage(dps)
