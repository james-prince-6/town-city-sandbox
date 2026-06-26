# damage_info.gd
# A small, passed-around description of a single instance of damage: how much, what
# element, and who caused it. Created by attackers (weapon swings, projectiles,
# bombs, enemy attacks) and handed to a HurtBox, which forwards it to a Health
# component. Health applies the entity's per-type multiplier (weakness/resistance).
#
# It's a RefCounted (not a Resource/Node) — cheap to make and throw away each hit.

class_name DamageInfo
extends RefCounted

## Damage elements. Entities can be weak (>1x) or resistant (<1x) to each via a
## Health.damage_multipliers dict. PHYSICAL is the default for swords/arrows/fists.
enum DamageType { PHYSICAL, FIRE, ICE, POISON, EXPLOSIVE }

## Raw damage before the target's resistance/weakness multiplier.
var amount: float = 0.0
## Which element this hit is (see DamageType).
var type: DamageType = DamageType.PHYSICAL
## The node that caused it (the attacker), for knockback / aggro / kill credit.
var source: Node = null

# --- Game-feel metadata (set by the HitBox that lands this hit) --------------
## True if this hit was a critical (the floating number / FX show it bigger).
var is_crit: bool = false
## World position where the hit landed (used to spawn damage numbers / impact FX).
var hit_position: Vector3 = Vector3.ZERO
## Normalized horizontal direction from attacker toward target (used for knockback).
var hit_direction: Vector3 = Vector3.ZERO
## How hard to shove the target along hit_direction (0 = no knockback).
var knockback: float = 0.0

## Convenience constructor: DamageInfo.create(25.0, DamageInfo.DamageType.FIRE, self).
static func create(amount: float, type: DamageType = DamageType.PHYSICAL, source: Node = null) -> DamageInfo:
	var d := DamageInfo.new()
	d.amount = amount
	d.type = type
	d.source = source
	return d
