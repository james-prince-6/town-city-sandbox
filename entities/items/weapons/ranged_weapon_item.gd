# ranged_weapon_item.gd
# A first-person ranged weapon (a bow) defined as a data Resource (.tres). Like the
# melee weapon it EXTENDS Item, so it stacks/equips normally; on left-click the player
# calls use(self) and we fire a projectile.
#
# Instead of a HitBox of our own, a bow spawns an ARROW scene (projectile_scene) at the
# camera, aimed along the camera's forward axis. The arrow carries its OWN one_shot
# HitBox and travels under its own power; we just hand it the damage/element/source and
# its starting velocity via its setup() method (see arrow.gd).
#
# Shared single instance, so the only per-shot state kept here is the cooldown stamp.

class_name RangedWeaponItem
extends Item

## Damage the fired arrow deals on hit (before the target's multiplier).
@export var damage: float = 14.0

## Element carried by the arrow. PHYSICAL for a normal arrow.
@export var damage_type: DamageInfo.DamageType = DamageInfo.DamageType.PHYSICAL

## Launch speed of the arrow in metres/second along the aim direction.
@export var projectile_speed: float = 30.0

## Minimum seconds between shots. Enforced with Time.get_ticks_msec().
@export var cooldown: float = 0.6

## Optional stamina cost per shot (drawing the bow). 0 = free to fire.
@export var stamina_cost: float = 0.0

## Optional mana cost per shot. 0 = costs no mana (a normal bow/crossbow). Wands set this
## so spells draw from the mana pool instead of stamina. If both costs are set, BOTH must
## be affordable for the shot to fire.
@export var mana_cost: float = 0.0

## The arrow scene to fire. Must instance to something with a setup() method (arrow.tscn).
@export var projectile_scene: PackedScene

## How hard a landed arrow shoves the target (passed into the arrow's HitBox -> DamageInfo).
## A small nudge compared to a melee shove — arrows tap rather than bludgeon.
@export var knockback: float = 2.0

# Millisecond timestamp of the last successful shot; gates the fire rate.
# Start far in the past so the FIRST shot is never blocked (ticks start near 0).
var _last_shot_ms: int = -100000

## Left-click entry point. Respects cooldown + optional stamina, then fires an arrow.
func use(player: Node) -> void:
	if projectile_scene == null:
		push_warning("RangedWeaponItem '%s' has no projectile_scene; nothing to fire." % str(id))
		return

	# A wand (mana_cost > 0) trains + reads the MAGIC skill; a bow trains + reads RANGED. The
	# Mana Surge magic perk lowers the effective mana cost (use-based rework, D1).
	var is_magic: bool = mana_cost > 0.0
	var effective_mana: float = mana_cost * Progression.mana_cost_mult()

	# Cooldown gate, shortened by the relevant skill's level (faster draw / faster casting).
	# Progression clamps the multiplier so cooldown never drops below 30% of the weapon's base.
	var now: int = Time.get_ticks_msec()
	var effective_cooldown: float = cooldown * (Progression.magic_cooldown_mult() if is_magic else Progression.ranged_cooldown_mult())
	if now - _last_shot_ms < int(effective_cooldown * 1000.0):
		return

	# Peek mana BEFORE spending anything so a failed cast never half-charges the player
	# (consumes stamina but not mana). For a normal bow mana_cost is 0, so this is a no-op.
	if is_magic and PlayerStats.mana < effective_mana:
		return

	# Optional stamina gate (use_stamina returns true for cost <= 0).
	if not PlayerStats.use_stamina(stamina_cost):
		return

	# Optional mana gate (use_mana returns true for cost <= 0). Already peeked above, so a
	# wand only reaches here when it can afford the cast.
	if not PlayerStats.use_mana(effective_mana):
		return

	var camera: Camera3D = player.get_camera()
	if camera == null:
		return

	_last_shot_ms = now
	CombatFeel.play_bow()
	# Train Magic (wand) or Ranged (bow) on every committed shot (resource-gated, no free grind).
	Progression.register_use(Progression.SKILL_MAGIC if is_magic else Progression.SKILL_RANGED)

	# Spawn the arrow into the live scene at the camera, aimed down camera forward (-z).
	var forward: Vector3 = -camera.global_transform.basis.z
	var arrow := projectile_scene.instantiate()
	var scene := SceneManager.current_world()
	if scene == null:
		arrow.queue_free()  # world is tearing down mid-shot; don't leak the orphaned projectile
		return
	scene.add_child(arrow)
	arrow.global_position = camera.global_position + forward * 0.5  # nudge clear of the camera
	# Face the arrow along its travel direction so the mesh points where it flies. Use a side
	# up-vector when firing near-vertically, so look_at doesn't error on a parallel up/forward.
	if not forward.is_equal_approx(Vector3.ZERO):
		var up: Vector3 = Vector3.UP if absf(forward.normalized().dot(Vector3.UP)) < 0.999 else Vector3.FORWARD
		arrow.look_at(arrow.global_position + forward, up)

	# Scale damage by the Ranged-branch progression (with a crit roll), then hand the
	# arrow everything it needs to deal damage and move. The Piercing Shot perk makes the
	# arrow pass through enemies instead of stopping at the first.
	var is_crit: bool = randf() < Progression.crit_chance()
	var final_damage: float = damage * (Progression.magic_damage_mult() if is_magic else Progression.ranged_damage_mult())
	if is_crit:
		final_damage *= 2.0
	var piercing: bool = Progression.has_perk(&"piercing_shot") or (is_magic and Progression.has_perk(&"arcane_pierce"))
	if arrow.has_method("setup"):
		arrow.setup(final_damage, damage_type, player, forward * projectile_speed, is_crit, knockback, piercing)
	else:
		push_warning("RangedWeaponItem: projectile_scene root has no setup() method.")
