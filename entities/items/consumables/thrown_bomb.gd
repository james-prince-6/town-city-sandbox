# thrown_bomb.gd
# The physical bomb in flight. A RigidBody3D so it arcs and bounces realistically.
# It detonates on the first of two triggers: a fuse timer running out, or hitting
# something solid (contact_monitor). Detonating spawns a big one-frame EXPLOSIVE
# HitBox (target_team = ENEMY) at the bomb's position, pops a brief flash, and
# frees the bomb. Damage flows the proper way: HitBox -> enemy HurtBox -> Health.
#
# BombItem configures damage / fuse_time / radius after instancing (see bomb_item.gd).
# `launch()` is called once by the thrower to give it its initial velocity and set
# the kill-credit source.

extends RigidBody3D

## Explosion damage per enemy. Overwritten by BombItem on spawn.
@export var damage: float = 50.0
## Seconds until auto-detonation if it hasn't struck anything.
@export var fuse_time: float = 1.5
## Blast radius in metres (the spawned HitBox's sphere radius).
@export var radius: float = 3.5

# The player who threw this, so the explosion's damage is credited to them.
var _source: Node = null
# Guard so a simultaneous fuse + impact can't detonate twice.
var _exploded: bool = false

func _ready() -> void:
	# Enable contact reporting so we get body_entered for impact detonation.
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

	# Start the fuse. Even if it never hits anything, it goes off.
	var fuse: SceneTreeTimer = get_tree().create_timer(fuse_time)
	fuse.timeout.connect(_explode)

## Called once by the thrower (ConsumableItem._throw_from_camera) to send the bomb
## flying. `velocity` is m/s in world space; `source` is the attacker for credit.
func launch(velocity: Vector3, source: Node) -> void:
	_source = source
	linear_velocity = velocity
	# A little spin so it tumbles instead of sliding flat.
	angular_velocity = Vector3(6.0, 2.0, 0.0)

func _on_body_entered(_body: Node) -> void:
	# Hit the ground / a wall / an enemy body — blow up on contact.
	_explode()

# Spawn the blast HitBox, flash, and remove the bomb. The HitBox lives for a
# fraction of a second (lifetime) and auto-frees itself; one_shot is OFF so it can
# hit several enemies in the radius in that window.
func _explode() -> void:
	if _exploded:
		return
	_exploded = true

	var world: Node = SceneManager.current_world()
	if world == null:
		# Scene is tearing down; nothing to attach the blast to.
		queue_free()
		return

	_spawn_blast(world)
	_spawn_flash(world)

	queue_free()

# Build the AoE HitBox: a sphere of `radius`, EXPLOSIVE, aimed at the ENEMY team,
# living for one short window then freeing itself.
func _spawn_blast(world: Node) -> void:
	var hitbox := HitBox.new()
	hitbox.amount = damage
	hitbox.damage_type = DamageInfo.DamageType.EXPLOSIVE
	hitbox.target_team = HurtBox.Team.ENEMY
	hitbox.one_shot = false      # one blast should be able to hit a whole crowd
	hitbox.lifetime = 0.12       # brief active window, then auto-free (see hit_box.gd)
	hitbox.active = true
	hitbox.source = _source

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	hitbox.add_child(shape)

	world.add_child(hitbox)
	hitbox.global_position = global_position

# A cheap, short-lived visual pop so the explosion reads even without art: a
# self-illuminated sphere that we free on a timer. Purely cosmetic.
func _spawn_flash(world: Node) -> void:
	var flash := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	flash.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.1, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.05)
	mat.emission_energy_multiplier = 4.0
	flash.material_override = mat

	world.add_child(flash)
	flash.global_position = global_position

	# Remove the flash shortly after the blast window.
	var t: SceneTreeTimer = get_tree().create_timer(0.2)
	t.timeout.connect(flash.queue_free)
