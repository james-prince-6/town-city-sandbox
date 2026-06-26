# crossbow_bolt.gd
# A heavy crossbow bolt fired by a RangedWeaponItem (the crossbow). It behaves like
# arrow.gd — an Area3D that flies in a straight line under its own power and carries a
# HitBox child (target_team ENEMY) — but it's a HEAVIER hit: it travels fast and PIERCES
# BY DEFAULT, punching clean through enemies instead of stopping at the first one.
#
# It implements the exact same setup() signature the bow calls on arrow.gd, so the
# existing RangedWeaponItem.use() spawns and fires it unchanged. The crossbow .tres just
# supplies a high damage, a fast projectile_speed, and points projectile_scene here.

extends Area3D

## Seconds before a missed bolt frees itself, so flights don't accumulate forever.
@export var lifetime: float = 5.0

## A crossbow bolt punches through targets by default (its HitBox stays live so it can
## hit several enemies in a line). Independent of the Piercing Shot perk, which can only
## ADD piercing to weapons that don't already have it.
@export var pierce_by_default: bool = true

# Physics layer that counts as "solid world". Floors/walls/props are StaticBody3D on the
# default layer 1; the player/enemies share it (CharacterBody3D) but are filtered out by type
# so the bolt sticks in geometry, never on a living body (those stay the HitBox's job, which
# keeps the pierce-through-enemies behaviour intact).
const WORLD_LAYER: int = 1

# Travel velocity in metres/second (world space). Set by setup(); zero until then.
var _velocity: Vector3 = Vector3.ZERO

# The shooter, cached so the world-impact raycast can exclude it (no muzzle self-hit).
var _source: Node = null

# The damage-dealing child, configured in setup(). Assumed to be a HitBox named "HitBox".
@onready var _hit_box: HitBox = $HitBox

func _ready() -> void:
	# Auto-clean a miss. A non-piercing bolt's one_shot frees us on a hit; this covers the rest.
	if lifetime > 0.0:
		var t := get_tree().create_timer(lifetime)
		t.timeout.connect(_on_lifetime_expired)

## Called by the crossbow immediately after the bolt is added to the scene tree. Same exact
## signature as arrow.setup(), so RangedWeaponItem.use() drives it unchanged. Wires the
## bolt's damage/element/source into its HitBox and sets the flight velocity. The bolt
## pierces if EITHER the perk passed piercing=true OR this bolt pierces by default.
func setup(damage: float, damage_type: DamageInfo.DamageType, source: Node, velocity: Vector3, is_crit: bool = false, knockback: float = 0.0, piercing: bool = false) -> void:
	_velocity = velocity
	_source = source
	if _hit_box != null:
		_hit_box.amount = damage
		_hit_box.damage_type = damage_type
		_hit_box.target_team = HurtBox.Team.ENEMY
		# Heavy bolt: pierce by default. one_shot only when NOTHING grants piercing.
		_hit_box.one_shot = not (piercing or pierce_by_default)
		_hit_box.source = source
		_hit_box.is_crit = is_crit
		_hit_box.knockback = knockback

func _physics_process(delta: float) -> void:
	# Sweep this frame's travel segment for solid world geometry first, so a fast bolt can't
	# tunnel through (or fly past) a wall/floor — it sticks at the impact point and frees.
	var from: Vector3 = global_position
	var to: Vector3 = from + _velocity * delta
	if _check_world_hit(from, to):
		return
	# Straight-line flight: move the whole bolt (and its HitBox) along the velocity.
	global_position = to
	# If the one_shot HitBox already freed itself on impact, follow it out.
	if not is_instance_valid(_hit_box):
		queue_free()

# Raycast this frame's travel along the world layer; on hitting static geometry, snap to the
# impact point and free. Living bodies (CharacterBody3D) are skipped so the bolt keeps piercing
# through enemies (the HitBox owns those hits); the shooter is excluded so it can't pop on the
# muzzle the instant it spawns.
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
