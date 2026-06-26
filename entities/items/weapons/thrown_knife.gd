# thrown_knife.gd
# A fast, straight-flying thrown knife. Unlike the bomb (a RigidBody that arcs and bounces),
# this is an Area3D that flies dead-straight under its own power and deals damage on contact,
# exactly like arrow.gd — just launched by a consumable instead of fired by a weapon.
#
# It carries a one_shot HitBox child (target_team ENEMY) and frees itself on its first hit
# or when its lifetime runs out. The throwing-knife Item launches it through the SAME
# launch(velocity, source) entry point the bomb uses (ConsumableItem._throw_from_camera),
# then stamps the per-throw `damage` onto this instance (set("damage", ...)) right after.
#
# Because the Item sets `damage` AFTER launch() returns (mirroring BombItem), we copy the
# current `damage` onto the HitBox every physics frame — by the time the knife reaches a
# target the value is already the throw's real damage.

extends Area3D

## Damage dealt on hit (before the target's multiplier). Overwritten by the Item per throw.
@export var damage: float = 10.0

## Element of the hit. A plain steel knife is PHYSICAL.
@export var damage_type: DamageInfo.DamageType = DamageInfo.DamageType.PHYSICAL

## Seconds before a missed knife frees itself, so flights don't accumulate forever.
@export var lifetime: float = 4.0

# Physics layer that counts as "solid world". Floors/walls/props are StaticBody3D on the
# default layer 1; the player/enemies share it (CharacterBody3D) but are filtered out by type
# so the knife sticks in geometry, never on a living body (the HitBox handles those hits).
const WORLD_LAYER: int = 1

# Travel velocity in metres/second (world space). Set by launch(); zero until then.
var _velocity: Vector3 = Vector3.ZERO

# The thrower, cached so the world-impact raycast can exclude it (no muzzle self-hit).
var _source: Node = null

# The damage-dealing child. Assumed to be a HitBox named "HitBox".
@onready var _hit_box: HitBox = $HitBox

func _ready() -> void:
	# Auto-clean a miss. one_shot frees us on a hit; this covers everything else.
	if lifetime > 0.0:
		var t := get_tree().create_timer(lifetime)
		t.timeout.connect(_on_lifetime_expired)

## Called once by the thrower (ConsumableItem._throw_from_camera) to send the knife flying.
## Same signature as thrown_bomb.launch(): `velocity` is m/s in world space, `source` is the
## attacker for kill credit. We configure the HitBox here for the player's team; the exact
## `amount` is (re)synced each frame from `damage`, which the Item sets just after this call.
func launch(velocity: Vector3, source: Node) -> void:
	_velocity = velocity
	_source = source
	if _hit_box != null:
		_hit_box.amount = damage
		_hit_box.damage_type = damage_type
		_hit_box.target_team = HurtBox.Team.ENEMY
		_hit_box.one_shot = true
		_hit_box.source = source

func _physics_process(delta: float) -> void:
	# Keep the HitBox's damage in step with `damage` (the Item sets it the frame after launch).
	if is_instance_valid(_hit_box):
		_hit_box.amount = damage
	# Sweep this frame's travel segment for solid world geometry first, so a fast knife can't
	# tunnel through (or fly past) a wall/floor — it sticks at the impact point and frees.
	var from: Vector3 = global_position
	var to: Vector3 = from + _velocity * delta
	if _check_world_hit(from, to):
		return
	# Straight-line flight: move the whole knife (and its HitBox) along the velocity.
	global_position = to
	# If the one_shot HitBox already freed itself on impact, follow it out.
	if not is_instance_valid(_hit_box):
		queue_free()

# Raycast this frame's travel along the world layer; on hitting static geometry, snap to the
# impact point and free. Living bodies (CharacterBody3D) are skipped (the HitBox owns those
# hits); the thrower is excluded so the knife can't pop on the muzzle the instant it spawns.
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
