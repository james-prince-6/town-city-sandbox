# frost_bolt_projectile.gd
# A shard of supercooled ice a ranged caster flings at the player. Mechanically it is a
# sibling of cinder_spit_projectile.gd: an Area3D that flies in a straight line carrying a
# single one_shot HitBox (target_team = PLAYER). The instant that HitBox lands on the
# player's HurtBox it deals ICE damage and the whole bolt frees itself; if it never hits
# anything it self-destructs after `max_lifetime` so stray shots don't pile up.
#
# The enemy doesn't poke our internals — it just calls launch(dir, amount, type, source,
# knockback) right after instancing us (duck-typed in enemy.gd._spawn_one_projectile). We
# build our own child HitBox from those numbers so all damage still flows the standard
# HitBox -> HurtBox -> Health/PlayerStats way (see docs/combat.md).
#
# We move ourselves manually each physics frame (no RigidBody): straight-line travel is
# all a bolt needs, and it keeps the HitBox overlap simple and predictable. The medium
# speed leaves a satisfying sliver of air-travel time so a sharp player can sidestep it.

extends Area3D

## Travel speed in m/s. A frost bolt is brisk but not instant, so it reads as a dodgeable
## projectile rather than a hitscan beam.
@export var speed: float = 14.0

## Seconds before an un-hit bolt gives up and frees itself.
@export var max_lifetime: float = 4.0

# Physics layer that counts as "solid world". Floors/walls/props are StaticBody3D on the
# default layer 1; the player/caster share it (CharacterBody3D) but are filtered out by type so
# the bolt shatters on geometry, never on a living body (the HitBox handles those hits).
const WORLD_LAYER: int = 1

# --- Runtime ---------------------------------------------------------------
# Normalised flight direction, set by launch().
var _direction: Vector3 = Vector3.FORWARD
# The caster, cached so the world-impact raycast can exclude it (no muzzle self-hit).
var _source: Node = null
# The child HitBox that actually deals the damage; built in launch().
var _hit_box: HitBox = null
# Counts up so we can self-destruct at max_lifetime.
var _age: float = 0.0
# Guards the one-and-done free (HitBox is one_shot, but we also free on its hit).
var _spent: bool = false


# Called by the spawning enemy right after instancing. Stores the heading and builds the
# one_shot HitBox payload that hits the player. `knockback` is optional (defaults to 0) so
# older 4-arg callers keep working unchanged.
func launch(direction: Vector3, amount: float, damage_type: DamageInfo.DamageType, source: Node, knockback: float = 0.0) -> void:
	_direction = direction.normalized()
	_source = source

	# Build the damage volume: one_shot so it frees on first contact, target PLAYER so it
	# can only hurt the player (never its own kind), source = the caster for credit.
	_hit_box = HitBox.new()
	_hit_box.amount = amount
	_hit_box.damage_type = damage_type
	_hit_box.target_team = HurtBox.Team.PLAYER
	_hit_box.one_shot = true
	_hit_box.lifetime = 0.0          # we own this projectile's lifetime, not the box
	_hit_box.source = source
	_hit_box.knockback = knockback

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.3
	shape.shape = sphere
	_hit_box.add_child(shape)
	add_child(_hit_box)

	# When the HitBox is freed (it frees itself on its first landed hit), tear down the
	# whole projectile so the visual shard vanishes with the impact.
	_hit_box.tree_exited.connect(_on_hitbox_gone)

	# Point our visual along the direction of travel (forward is -Z).
	if _direction.length() > 0.05:
		look_at(global_position + _direction, Vector3.UP)


func _physics_process(delta: float) -> void:
	# Straight-line flight; gravity-free so the bolt reads as a "magic" projectile and aim
	# stays predictable. Sweep this frame's segment for solid world first so the bolt shatters
	# on walls/floors instead of phasing through them.
	var from: Vector3 = global_position
	var to: Vector3 = from + _direction * speed * delta
	if _check_world_hit(from, to):
		return
	global_position = to

	# Time out if we never connect.
	_age += delta
	if _age >= max_lifetime:
		_destroy()


# Raycast this frame's travel along the world layer; on hitting static geometry, snap to the
# impact point and self-destruct. Living bodies (CharacterBody3D player/caster) are skipped so
# the HitBox keeps owning the player hit; the caster is excluded so we never pop on the muzzle.
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
	_destroy()
	return true


# The one_shot HitBox removed itself after landing its hit -> the projectile is spent.
func _on_hitbox_gone() -> void:
	_destroy()


# Single, guarded teardown path (timeout OR hit both end here exactly once).
func _destroy() -> void:
	if _spent:
		return
	_spent = true
	queue_free()
