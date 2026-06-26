# melee_weapon_item.gd
# A first-person melee weapon (sword, obsidian blade, etc.) defined as a data
# Resource (.tres). Because it EXTENDS Item it stacks in the Inventory and sits in
# Hotbar slots like any other item; the player calls use(self) on left-click and
# THIS is where the swing happens.
#
# The swing is modelled the same way every attack in the game is (see docs/combat.md):
# we spawn a short-lived HitBox (target_team ENEMY) a little in front of the camera.
# Any enemy HurtBox that overlaps it during its brief lifetime takes the damage.
# No raycast — an overlapping sphere reads like a swing arc and can clip several foes.
#
# Items are SHARED single instances, so we keep no per-swing state on the resource
# except a cooldown timestamp (Time.get_ticks_msec()), which is fine to live here.

class_name MeleeWeaponItem
extends Item

## Damage dealt to each enemy the swing overlaps (before the target's multiplier).
@export var damage: float = 20.0

## Element of the hit. PHYSICAL for plain blades; FIRE for a lava/obsidian weapon to
## exploit fire-weak enemies (see Health.damage_multipliers).
@export var damage_type: DamageInfo.DamageType = DamageInfo.DamageType.PHYSICAL

## Reach of the swing, in metres. Used as the radius of the spawned HitBox sphere and
## how far in front of the camera that sphere is centred.
@export var range: float = 2.0

## PlayerStats stamina spent per swing. If the player can't afford it the swing fizzles.
@export var stamina_cost: float = 12.0

## Minimum seconds between swings. Enforced with Time.get_ticks_msec() timestamps.
@export var cooldown: float = 0.5

## How long the swing's HitBox stays live (seconds). Long enough to register an
## overlap for a frame or two, short enough to feel like a single swing.
@export var swing_lifetime: float = 0.15

## How hard a landed swing shoves the target (passed into the HitBox -> DamageInfo, read
## by a body's apply_knockback()). The Cleave perk amplifies this so it sweeps groups.
@export var knockback: float = 6.0

## --- Perk tuning ---
## Cleave widens the swing sphere by this factor and multiplies its knockback so one blow
## carries through a cluster of foes (HitBox hits every overlapping enemy once).
const CLEAVE_RADIUS_MULT: float = 1.6
const CLEAVE_KNOCKBACK_MULT: float = 1.5

# Millisecond timestamp (Time.get_ticks_msec()) of the last successful swing. Lives on
# the shared resource — a simple int, safe to share; just gates the fire rate.
# Start far in the past so the FIRST swing is never blocked (ticks start near 0).
var _last_swing_ms: int = -100000

## Left-click entry point. Respects cooldown, spends stamina, then spawns the swing.
func use(player: Node) -> void:
	# Cooldown gate. get_ticks_msec() is an int count of ms since launch.
	var now: int = Time.get_ticks_msec()
	if now - _last_swing_ms < int(cooldown * 1000.0):
		return

	# Stamina gate. use_stamina spends nothing and returns false when too low.
	if not PlayerStats.use_stamina(stamina_cost):
		return

	var camera: Camera3D = player.get_camera()
	if camera == null:
		return

	_last_swing_ms = now
	CombatFeel.play_swing()

	# Scale damage by the player's Melee-branch progression: a base multiplier plus a
	# chance-based crit from the Crit Edge skill. Progression is an autoload, always
	# present once registered, so a plain call is safe.
	var is_crit: bool = randf() < Progression.crit_chance()
	var final_damage: float = damage * Progression.melee_damage_mult()
	if is_crit:
		final_damage *= 2.0

	# Cleave perk: a wider sweep sphere and a heavier shove so one swing carries through a
	# cluster. Without the perk the swing keeps its base reach and knockback.
	var swing_radius: float = range
	var swing_knockback: float = knockback
	if Progression.has_perk(&"cleave"):
		swing_radius = range * CLEAVE_RADIUS_MULT
		swing_knockback = knockback * CLEAVE_KNOCKBACK_MULT

	# Build the swing HitBox: target enemies, deal our damage/element, auto-free.
	var hit := HitBox.new()
	hit.amount = final_damage
	hit.damage_type = damage_type
	hit.target_team = HurtBox.Team.ENEMY
	hit.one_shot = false        # one swing can sweep several foes
	hit.lifetime = swing_lifetime
	hit.source = player         # kill credit / knockback origin
	hit.is_crit = is_crit       # carried into the DamageInfo for crit FX / numbers
	hit.knockback = swing_knockback  # shove the target along the hit direction

	# A sphere sized to the weapon's reach (widened by Cleave) is the swing's volume.
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = swing_radius
	shape.shape = sphere
	hit.add_child(shape)

	# Add to the live scene, then place it in front of the camera along its forward
	# axis (-z). Placing AFTER add_child so global_position takes effect in the tree.
	var scene := SceneManager.current_world()
	if scene == null:
		hit.queue_free()  # world is tearing down mid-swing; don't leak the orphaned HitBox
		return
	scene.add_child(hit)
	var forward: Vector3 = -camera.global_transform.basis.z
	hit.global_position = camera.global_position + forward * range

	# Lifesteal perk: recover a fraction of the swing's damage as health. heal() no-ops at
	# full health or when dead, so this is safe to call unconditionally on a committed swing.
	var lifesteal: float = Progression.melee_lifesteal()
	if lifesteal > 0.0:
		PlayerStats.heal(final_damage * lifesteal)
