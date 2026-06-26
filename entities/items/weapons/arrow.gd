# arrow.gd
# A simple flying projectile fired by a RangedWeaponItem (the bow). It's an Area3D that
# moves itself a fixed velocity every physics frame and carries a one_shot HitBox child
# (target_team ENEMY). When that HitBox overlaps an enemy HurtBox it deals the damage and
# frees itself, so the arrow vanishes on its first hit.
#
# We move the whole arrow (HitBox included) by translating this root each physics frame —
# no RigidBody, no gravity, dead-simple straight-line flight. A lifetime timer cleans up
# arrows that miss so they don't pile up in the scene.
#
# The bow calls setup(damage, damage_type, source, velocity) right after add_child(), so
# this node configures its HitBox child once it's in the tree.

extends Area3D

## Seconds before a missed arrow frees itself, so flights don't accumulate forever.
@export var lifetime: float = 5.0

# Physics layer that counts as "solid world". Floors/walls/props are StaticBody3D on the
# default layer 1; the player/enemies share it (CharacterBody3D) but are filtered out by type
# so the arrow only STOPS on geometry, never on a living body (those are the HitBox's job).
const WORLD_LAYER: int = 1

# Travel velocity in metres/second (world space). Set by setup(); zero until then.
var _velocity: Vector3 = Vector3.ZERO

# The shooter, cached so the world-impact raycast can exclude it (no muzzle self-hit).
var _source: Node = null

# The damage-dealing child, configured in setup(). Assumed to be a HitBox named "HitBox".
@onready var _hit_box: HitBox = $HitBox

func _ready() -> void:
	# Auto-clean a miss. one_shot frees us on a hit; this covers everything else.
	if lifetime > 0.0:
		var t := get_tree().create_timer(lifetime)
		t.timeout.connect(_on_lifetime_expired)

## Called by the bow immediately after the arrow is added to the scene tree. Wires the
## arrow's damage/element/source into its HitBox and sets the flight velocity.
## Safe to call after add_child(): _ready has run so $HitBox is resolved.
##
## The trailing args carry combat-feel/perk data (all optional, so older 4-arg callers keep
## working): `is_crit`/`knockback` are stamped into the DamageInfo, and `piercing` (the
## Piercing Shot perk) leaves the HitBox NON-one_shot so the arrow passes through every
## enemy it overlaps (HitBox dedupes per target) and only stops at its lifetime/a wall.
func setup(damage: float, damage_type: DamageInfo.DamageType, source: Node, velocity: Vector3, is_crit: bool = false, knockback: float = 0.0, piercing: bool = false) -> void:
	_velocity = velocity
	_source = source
	if _hit_box != null:
		_hit_box.amount = damage
		_hit_box.damage_type = damage_type
		_hit_box.target_team = HurtBox.Team.ENEMY
		# Normal arrows vanish on first hit; a piercing arrow keeps its HitBox live so it
		# punches through and can hit several enemies before its lifetime expires.
		_hit_box.one_shot = not piercing
		_hit_box.source = source
		_hit_box.is_crit = is_crit
		_hit_box.knockback = knockback

func _physics_process(delta: float) -> void:
	# Sweep this frame's travel segment for solid world geometry first, so a fast arrow can't
	# tunnel through (or sail past) a wall/floor — it sticks at the impact point and frees.
	var from: Vector3 = global_position
	var to: Vector3 = from + _velocity * delta
	if _check_world_hit(from, to):
		return

	# Straight-line flight: move the whole arrow (and its HitBox) along the velocity.
	global_position = to
	# If the one_shot HitBox already freed itself on impact, follow it out.
	if not is_instance_valid(_hit_box):
		queue_free()

# Raycast this frame's travel along the world layer; on hitting static geometry, snap to the
# impact point and free. Living bodies (CharacterBody3D) are skipped (the HitBox handles those,
# so piercing arrows pass through enemies as before); the shooter is excluded so the arrow
# can't kill itself on the muzzle the instant it spawns.
func _check_world_hit(from: Vector3, to: Vector3) -> bool:
	if from.is_equal_approx(to):
		return false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	if space == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = WORLD_LAYER
	query.collide_with_bodies = true
	query.collide_with_areas = false
	var excludes: Array[RID] = [get_rid()]
	if _source is CollisionObject3D:
		excludes.append((_source as CollisionObject3D).get_rid())
	query.exclude = excludes
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return false
	var collider: Object = hit.get("collider")
	if collider is CharacterBody3D:
		return false
	var point: Vector3 = hit.get("position")
	global_position = point
	queue_free()
	return true

func _on_lifetime_expired() -> void:
	if is_instance_valid(self):
		queue_free()
