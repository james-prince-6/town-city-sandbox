# spell_projectile.gd
# A generalised MAGIC projectile fired by a wand (a RangedWeaponItem). Like arrow.gd
# it's an Area3D that moves itself a fixed velocity every physics frame and carries a
# one_shot HitBox child (target_team ENEMY); when that HitBox overlaps an enemy HurtBox
# it deals damage and frees, so the bolt vanishes on its first hit (unless it pierces).
#
# What makes it "general" is a set of EXPORTED behaviour knobs so ONE scene + script can
# cover every spell. Designers don't override these from the wand .tres (a .tres can't
# reach into a sub-scene's exports); instead each spell points at a tiny INHERITED scene
# variant of spell_projectile.tscn that sets these values (see fireball.tscn / ice_shard
# .tscn / arcane_missile.tscn):
#   - explode_radius   > 0 -> on hit/expiry spawn a brief AoE HitBox of that radius.
#   - homing_strength  > 0 -> each frame steer slightly toward the nearest "enemy".
#   - pierce_by_default     -> this spell punches through enemies even without the perk.
#
# The wand drives it through the SAME setup() signature the bow uses for arrow.gd, so
# RangedWeaponItem.use() spawns and fires spells unchanged. We also recolour the glowing
# emissive mesh from the damage_type in setup() so each element reads at a glance
# (FIRE orange, ICE cyan, EXPLOSIVE yellow, POISON green, PHYSICAL/arcane purple).

extends Area3D

## Radius (m) of the brief AoE blast spawned on impact / expiry. 0 = no blast (a single
## point-hit spell). When > 0 the projectile detonates a short-lived HitBox of this
## radius (same element) at its position, then frees itself.
@export var explode_radius: float = 0.0

## How hard the spell curves toward the nearest enemy. 0 = dead straight. Higher = a
## tighter (but still gentle) homing curve; the per-frame turn is clamped so it reads as
## a SLIGHT steer, never an instant lock-on.
@export var homing_strength: float = 0.0

## Range (m) within which homing looks for a target to steer toward.
@export var homing_range: float = 18.0

## If true this spell pierces by default (its HitBox stays live so it passes through
## several enemies), regardless of whether the Piercing Shot perk is active. Used by the
## ice-shard variant for a "lance through the line" feel.
@export var pierce_by_default: bool = false

## Fallback launch speed (m/s) used only if setup() is somehow handed a zero velocity.
## Normal fire always supplies the velocity (projectile_speed) from the wand.
@export var travel_speed_fallback: float = 22.0

## Seconds before a missed spell frees itself (and detonates, if explode_radius > 0), so
## flights don't accumulate forever.
@export var max_lifetime: float = 5.0

# Physics layers that count as "solid world" for impact detection. Dungeon floors/walls and
# building/prop colliders all live on the default layer 1 (StaticBody3D). The player and
# enemies share that layer (CharacterBody3D), so the ray also reports them — we filter those
# out by node type so spells only DETONATE on static geometry and never on a living body
# (creature hits stay the HitBox's job, which keeps piercing intact).
const WORLD_LAYER: int = 1

# Travel velocity in metres/second (world space). Set by setup(); zero until then.
var _velocity: Vector3 = Vector3.ZERO

# Combat payload, cached so the AoE blast (if any) can reuse it at detonation time.
var _damage: float = 0.0
var _damage_type: int = DamageInfo.DamageType.PHYSICAL
var _source: Node = null
var _is_crit: bool = false
var _knockback: float = 0.0

# Guard so a simultaneous hit + lifetime can't detonate the blast twice.
var _detonated: bool = false

# The damage-dealing child, configured in setup(). Assumed to be a HitBox named "HitBox".
@onready var _hit_box: HitBox = $HitBox
# The glowing body, recoloured per element in setup().
@onready var _mesh: MeshInstance3D = $Mesh

func _ready() -> void:
	# Auto-clean a miss. The one_shot HitBox frees us on a hit; this covers everything else
	# (and triggers the AoE on expiry when explode_radius > 0).
	if max_lifetime > 0.0:
		var t := get_tree().create_timer(max_lifetime)
		t.timeout.connect(_on_lifetime_expired)

## Called by the wand immediately after the spell is added to the scene tree (same exact
## signature the bow calls on arrow.gd, so RangedWeaponItem.use() drives spells unchanged).
## Wires the spell's damage/element/source into its HitBox, sets the flight velocity, and
## recolours the emissive mesh to match the element so it reads as magic.
func setup(damage: float, damage_type: DamageInfo.DamageType, source: Node, velocity: Vector3, is_crit: bool = false, knockback: float = 0.0, piercing: bool = false) -> void:
	_velocity = velocity
	if _velocity.length() < 0.001:
		# Defensive: never sit dead in the air if handed a zero velocity.
		_velocity = -global_transform.basis.z * travel_speed_fallback
	_damage = damage
	_damage_type = damage_type
	_source = source
	_is_crit = is_crit
	_knockback = knockback

	if _hit_box != null:
		_hit_box.amount = damage
		_hit_box.damage_type = damage_type
		_hit_box.target_team = HurtBox.Team.ENEMY
		# A normal spell vanishes on first hit; a piercing one (perk OR this variant's
		# pierce_by_default) keeps its HitBox live so it punches through several enemies.
		_hit_box.one_shot = not (piercing or pierce_by_default)
		_hit_box.source = source
		_hit_box.is_crit = is_crit
		_hit_box.knockback = knockback

	_apply_element_color(damage_type)

func _physics_process(delta: float) -> void:
	# Gentle homing: bend the velocity toward the nearest enemy, clamped so it's a curve.
	if homing_strength > 0.0:
		_apply_homing(delta)

	# Sweep this frame's travel segment for solid world geometry (floor/walls/props). If we'd
	# pass through one, snap to the impact point, detonate (AoE if explode_radius > 0) and free.
	# Done as a segment cast (from -> to) so a fast spell can't tunnel through a thin wall.
	var from: Vector3 = global_position
	var to: Vector3 = from + _velocity * delta
	if _check_world_hit(from, to):
		return

	# Straight-line (or curved) flight: move the whole spell (and its HitBox) along velocity.
	global_position = to

	# If the one_shot HitBox already freed itself on impact, detonate (if set) and follow it out.
	if not is_instance_valid(_hit_box):
		_detonate_and_free()

# Raycast this frame's travel segment against the solid-world layer. Returns true (after
# detonating + freeing at the impact point) when the spell strikes static geometry; false when
# the path is clear. Living bodies (player/enemies, CharacterBody3D) are skipped so the spell
# only stops on walls/floors/props — enemy damage and piercing stay the HitBox's job. The
# source caster is excluded so a freshly-fired spell can't detonate on the muzzle.
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
	# A creature's physics body shares this layer; let the HitBox handle those so piercing and
	# normal enemy hits behave exactly as before. Only static geometry stops the spell here.
	var collider: Object = hit.get("collider")
	if collider is CharacterBody3D:
		return false
	var point: Vector3 = hit.get("position")
	global_position = point
	_detonate_and_free()
	return true

# Steer _velocity toward the nearest node in group "enemy" within homing_range. The turn
# rate is clamped by homing_strength * delta so the path curves gently instead of snapping.
func _apply_homing(delta: float) -> void:
	var nodes: Array = get_tree().get_nodes_in_group("enemy")
	if nodes.is_empty():
		return
	var best: Node3D = null
	var best_dist: float = homing_range
	for n in nodes:
		if not (n is Node3D):
			continue
		var node3d := n as Node3D
		var d: float = global_position.distance_to(node3d.global_position)
		if d < best_dist:
			best_dist = d
			best = node3d
	if best == null:
		return

	var speed: float = _velocity.length()
	if speed < 0.001:
		return
	var current_dir: Vector3 = _velocity / speed
	var desired: Vector3 = (best.global_position - global_position)
	if desired.length() < 0.001:
		return
	desired = desired.normalized()
	# slerp weight = a small fraction per frame -> a slight curve, never an instant lock.
	var weight: float = clampf(homing_strength * delta, 0.0, 1.0)
	var new_dir: Vector3 = current_dir.slerp(desired, weight)
	_velocity = new_dir * speed
	# Keep the mesh pointing where it now flies. Use a side up-vector when the new direction is
	# near-vertical so look_at doesn't error on a parallel up/forward.
	if not new_dir.is_equal_approx(Vector3.ZERO):
		var up: Vector3 = Vector3.UP if absf(new_dir.dot(Vector3.UP)) < 0.999 else Vector3.FORWARD
		look_at(global_position + new_dir, up)

func _on_lifetime_expired() -> void:
	if is_instance_valid(self):
		_detonate_and_free()

# Spawn the AoE blast (when explode_radius > 0) plus a quick impact flash, then free. Safe
# to call more than once thanks to the _detonated guard.
func _detonate_and_free() -> void:
	if _detonated:
		return
	_detonated = true

	if explode_radius > 0.0:
		var world: Node = SceneManager.current_world()
		if world != null:
			_spawn_blast(world)
			_spawn_impact_flash(world)
			# A light kick so a magic blast has a touch of weight (purely cosmetic).
			CombatFeel.shake(0.12, 0.12)

	queue_free()

# Build the AoE HitBox: a sphere of explode_radius, same element, aimed at ENEMY, living
# for one brief window then auto-freeing. Mirrors thrown_bomb._spawn_blast.
func _spawn_blast(world: Node) -> void:
	var hitbox := HitBox.new()
	hitbox.amount = _damage
	hitbox.damage_type = _damage_type
	hitbox.target_team = HurtBox.Team.ENEMY
	hitbox.one_shot = false      # one blast should be able to hit a whole crowd
	hitbox.lifetime = 0.12       # brief active window, then auto-free (see hit_box.gd)
	hitbox.active = true
	hitbox.source = _source
	hitbox.is_crit = _is_crit
	hitbox.knockback = _knockback

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = explode_radius
	shape.shape = sphere
	hitbox.add_child(shape)

	world.add_child(hitbox)
	hitbox.global_position = global_position

# A cheap, short-lived glowing sphere so the magic blast reads even without art.
func _spawn_impact_flash(world: Node) -> void:
	var flash := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = explode_radius
	mesh.height = explode_radius * 2.0
	flash.mesh = mesh

	var col: Color = _color_for_type(_damage_type)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(col.r, col.g, col.b, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 4.0
	flash.material_override = mat

	world.add_child(flash)
	flash.global_position = global_position

	var t: SceneTreeTimer = get_tree().create_timer(0.2)
	t.timeout.connect(flash.queue_free)

# Recolour the projectile's emissive mesh to its element so it reads as magic in flight.
func _apply_element_color(damage_type: int) -> void:
	if _mesh == null:
		return
	var col: Color = _color_for_type(damage_type)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 3.0
	# A soft glow that doesn't get muddied by scene lighting.
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh.material_override = mat

# Per-element projectile colour (matches the design brief; arcane/physical = purple).
func _color_for_type(t: int) -> Color:
	match t:
		DamageInfo.DamageType.FIRE:
			return Color(1.0, 0.5, 0.1)      # orange
		DamageInfo.DamageType.ICE:
			return Color(0.4, 0.85, 1.0)     # cyan
		DamageInfo.DamageType.EXPLOSIVE:
			return Color(1.0, 0.9, 0.2)      # yellow
		DamageInfo.DamageType.POISON:
			return Color(0.5, 0.9, 0.2)      # green
		_:
			return Color(0.65, 0.35, 1.0)    # arcane purple
