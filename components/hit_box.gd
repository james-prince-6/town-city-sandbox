# hit_box.gd
# The "this deals damage" volume. An Area3D that, while active, damages any HurtBox
# of its target_team that it overlaps. It's the one mechanism behind every kind of
# attack in the game:
#   - melee swing  : spawn a HitBox in front of the player for a fraction of a second
#   - arrow/bullet : a moving projectile carries a one_shot HitBox
#   - bomb / AoE   : spawn a big HitBox for one frame at the blast point
#   - enemy attack : the enemy spawns/enables a HitBox aimed at the player
#
# It records which HurtBoxes it has already hit so one swing/blast can't tick a
# target repeatedly. Set `source` to the attacker (for kill credit / knockback).

class_name HitBox
extends Area3D

## Damage dealt per target.
@export var amount: float = 10.0
## Element of the damage (see DamageInfo.DamageType).
@export var damage_type: DamageInfo.DamageType = DamageInfo.DamageType.PHYSICAL
## Only HurtBoxes on this team are hit (keeps friendly fire out).
@export var target_team: HurtBox.Team = HurtBox.Team.ENEMY
## Free this HitBox the moment it lands its first hit (use for arrows/bullets).
@export var one_shot: bool = false
## Auto-free after this many seconds (0 = live until something frees it). Handy for
## a melee swing's brief active window or a bomb blast's one-frame flash.
@export var lifetime: float = 0.0
## While false the box is inert (lets you pre-place a disabled box and switch it on).
@export var active: bool = true

## The attacker that owns this hit (set by whoever spawns the box).
var source: Node = null

## True if this hit is a critical — carried into the DamageInfo for bigger FX / numbers.
## Set at runtime by the attacker (e.g. a weapon that rolled a crit).
var is_crit: bool = false

## Knockback force imparted to whatever this hits (0 = none). Carried into the
## DamageInfo; the hurt body applies it via apply_knockback() if it has that method.
@export var knockback: float = 0.0

## When true, an elemental hit (FIRE/ICE/POISON) also inflicts the matching lingering status
## (burn/chill/poison) on the target's StatusReceiver. PHYSICAL/EXPLOSIVE never do. Leave on for
## normal attacks; turn off for hits that shouldn't stack a status (e.g. a pure burst).
@export var applies_status: bool = true

# HurtBoxes already hit by this box, so a single swing/blast hits each target once.
var _already_hit: Dictionary = {}

func _ready() -> void:
	monitoring = true
	area_entered.connect(_on_area_entered)
	if lifetime > 0.0:
		var t := get_tree().create_timer(lifetime)
		t.timeout.connect(queue_free)

## Re-arm the box to hit everything again (e.g. the next swing of a reused HitBox).
func reset() -> void:
	_already_hit.clear()

func _on_area_entered(area: Area3D) -> void:
	if not active:
		return
	if not (area is HurtBox):
		return
	var hurt := area as HurtBox
	if hurt.team != target_team:
		return
	if _already_hit.has(hurt):
		return
	_already_hit[hurt] = true
	# Build the hit and stamp it with game-feel metadata (crit, where it landed, which
	# way to shove the target). Game-feel systems read these off the DamageInfo.
	var info := DamageInfo.create(amount, damage_type, source if source != null else self)
	info.is_crit = is_crit
	info.knockback = knockback
	info.hit_position = hurt.global_position
	var dir: Vector3 = hurt.global_position - global_position
	dir.y = 0.0
	info.hit_direction = dir.normalized() if dir.length() > 0.01 else Vector3.ZERO
	hurt.take_hit(info)
	# Elemental hits also inflict a lingering status (burn/chill/poison) on the target's
	# StatusReceiver, if it has one. Mapping + tuning live in status_receiver.gd.
	if applies_status:
		var host := hurt.get_parent()
		if host != null:
			var receiver := host.get_node_or_null("StatusReceiver")
			if receiver != null and receiver.has_method("apply_from_damage"):
				receiver.apply_from_damage(damage_type, amount, source)
	if one_shot:
		active = false
		queue_free()
