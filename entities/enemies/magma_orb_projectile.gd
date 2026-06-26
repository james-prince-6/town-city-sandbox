# magma_orb_projectile.gd
# A big, slow, glowing ball of molten rock — a telegraphed bullet-hell shot. Like its
# siblings (cinder_spit / frost_bolt) it's an Area3D that flies in a straight line carrying
# a single one_shot HitBox (target_team = PLAYER); on contact it deals its (EXPLOSIVE by
# default) damage and frees itself, and it self-destructs after `max_lifetime` if it never
# connects.
#
# What sets the orb apart is FEEL: a slow speed and a fat hitbox make it a readable,
# weaving-around threat rather than a snap shot — exactly what you want as the "bullet" in
# a barrage (RING / SPIRAL / VOLLEY) where many of them fill the arena and the player has
# to thread the gaps. The slow travel is the whole point; don't speed it up.
#
# The enemy doesn't poke our internals — it just calls launch(dir, amount, type, source,
# knockback) right after instancing us (duck-typed in enemy.gd._spawn_one_projectile). We
# build our own child HitBox so damage still flows the standard HitBox -> HurtBox ->
# Health/PlayerStats way (see docs/combat.md).

extends Area3D

## Travel speed in m/s. Deliberately slow so the orb is a fat, weaving-around threat the
## player can read and dodge — the satisfying air-travel delay IS the design here.
@export var speed: float = 8.0

## Seconds before an un-hit orb gives up and frees itself. A touch longer than the smaller
## shots because the orb crawls and so needs more time to cross the arena.
@export var max_lifetime: float = 5.0

## Radius (m) of the orb's damage volume. Larger than the small shots — a fat shot that's
## hard to ignore — tune alongside the mesh size in the .tscn so visual and hitbox agree.
@export var hit_radius: float = 0.55

# Physics layer that counts as "solid world". Floors/walls/props are StaticBody3D on the
# default layer 1; the player/caster share it (CharacterBody3D) but are filtered out by type so
# the orb bursts on geometry, never on a living body (the HitBox handles those hits).
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
	sphere.radius = hit_radius       # fat hitbox to match the big mesh
	shape.shape = sphere
	_hit_box.add_child(shape)
	add_child(_hit_box)

	# When the HitBox is freed (it frees itself on its first landed hit), tear down the
	# whole projectile so the visual orb vanishes with the impact.
	_hit_box.tree_exited.connect(_on_hitbox_gone)

	# Point our visual along the direction of travel (forward is -Z).
	if _direction.length() > 0.05:
		var up: Vector3 = Vector3.UP if absf(_direction.dot(Vector3.UP)) < 0.999 else Vector3.FORWARD
		look_at(global_position + _direction, up)


func _physics_process(delta: float) -> void:
	# Straight-line flight; gravity-free so the orb reads as a "magic" projectile and aim
	# stays predictable. Sweep this frame's segment for solid world first so the orb bursts on
	# walls/floors instead of crawling through them.
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
	if is_instance_valid(_source) and _source is CollisionObject3D:
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
