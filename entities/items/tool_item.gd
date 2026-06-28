# tool_item.gd
# A specialised Item that the player can equip and USE to do work in the world:
# mining rocks, chopping driftwood, ladling lava, or swinging as a weapon.
#
# Because it EXTENDS Item, a ToolItem is still just a data resource (.tres). It
# loads from res://global/items/resources/ exactly like a plain Item, stacks in
# the Inventory, and sits in Hotbar slots transparently. The extra fields below
# only matter to systems that care about tools (harvestables, combat).
#
# To create one: right-click in the FileSystem -> New Resource... -> ToolItem,
# fill in the normal Item fields PLUS the tool fields, and save as a .tres.

class_name ToolItem
extends Item

## What kind of tool this is. Harvestables/critters compare their required tool
## against this to decide whether a swing does anything. NONE = not a real tool.
enum ToolType {
	PICKAXE,   ## Mines rock/ore harvestables.
	HATCHET,   ## Chops wood/plant harvestables.
	LADLE,     ## Scoops lava and other liquids.
	WEAPON,    ## Deals damage to entities with a Health component.
	NONE,      ## Inert; usable as a generic held item only.
}

## Which job this tool performs (see ToolType above).
@export var tool_type: ToolType = ToolType.NONE

## Mining/harvest strength. A harvestable that requires power N is only worked by
## a tool whose power >= N. Higher power = can break tougher nodes.
@export var power: int = 1

## How much PlayerStats stamina a single use costs. The harvest/combat code calls
## PlayerStats.use_stamina(stamina_cost) and only proceeds if it returns true.
@export var stamina_cost: float = 10.0

## Damage dealt per hit when tool_type == WEAPON. Ignored for non-weapon tools.
@export var damage: float = 10.0

## Reach in metres: how far the camera-forward ray looks for a harvestable to work, and how
## far in front of the camera a WEAPON tool centres its swing hitbox.
@export var reach: float = 3.0

## Minimum seconds between swings. Gates the EFFECT (harvest/damage) so a held/spammed click
## doesn't fire every frame. The viewmodel swing animation is independent of this.
@export var cooldown: float = 0.4

## WEAPON only: element of the hit (PHYSICAL for plain tools; FIRE for a lava-forged one).
@export var damage_type: DamageInfo.DamageType = DamageInfo.DamageType.PHYSICAL

## WEAPON only: how hard a landed swing shoves the target (passed into the HitBox/DamageInfo).
@export var knockback: float = 5.0

# Millisecond timestamp of the last committed swing (gates the fire rate). Lives on the shared
# resource — a simple int, safe to share. Starts far in the past so the first swing never blocks.
var _last_swing_ms: int = -100000

## Left-click entry point (player.gd calls this on "use_item"). A WEAPON tool swings for damage;
## any other tool swings to WORK whatever harvestable the player is aiming at. The held-item
## viewmodel plays the swing animation separately (player emits item_used after this returns).
func use(player: Node) -> void:
	# Cooldown gate (shared by both branches). get_ticks_msec() is ms since launch.
	var now: int = Time.get_ticks_msec()
	if now - _last_swing_ms < int(cooldown * 1000.0):
		return
	_last_swing_ms = now
	CombatFeel.play_swing()  # a quick whoosh so the swing reads even on a miss
	if tool_type == ToolType.WEAPON:
		_swing_weapon(player)
	else:
		_swing_harvest(player)

## Non-weapon swing: raycast straight out from the camera and, if it lands on a harvestable
## within reach, work it. harvest() does its own tool-type/power gating + stamina spend, so a
## wrong/weak tool simply makes no progress (same rule the old E path used).
func _swing_harvest(player: Node) -> void:
	var camera: Camera3D = player.get_camera()
	if camera == null:
		return
	var world: World3D = (player as Node3D).get_world_3d() if player is Node3D else null
	if world == null:
		return
	var space: PhysicsDirectSpaceState3D = world.direct_space_state
	var from: Vector3 = camera.global_position
	var to: Vector3 = from + (-camera.global_transform.basis.z) * reach
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	if player is CollisionObject3D:
		q.exclude = [(player as CollisionObject3D).get_rid()]
	var hit: Dictionary = space.intersect_ray(q)
	if hit.is_empty():
		return
	var collider = hit.get("collider")
	if collider != null and collider.has_method("harvest"):
		collider.harvest(player)

## WEAPON swing: mirror MeleeWeaponItem — spend stamina, then spawn a short-lived HitBox sphere
## in front of the camera that damages any enemy HurtBox it overlaps. Scales with the Melee
## progression branch (damage mult + crit) so a ToolItem(WEAPON) fights like a real blade.
func _swing_weapon(player: Node) -> void:
	if not PlayerStats.use_stamina(stamina_cost):
		return
	var camera: Camera3D = player.get_camera()
	if camera == null:
		return
	var is_crit: bool = randf() < Progression.crit_chance()
	var final_damage: float = damage * Progression.melee_damage_mult()
	if is_crit:
		final_damage *= 2.0
	var radius: float = maxf(1.2, reach * 0.6)
	var hit := HitBox.new()
	hit.amount = final_damage
	hit.damage_type = damage_type
	hit.target_team = HurtBox.Team.ENEMY
	hit.one_shot = false
	hit.lifetime = 0.15
	hit.source = player
	hit.is_crit = is_crit
	hit.knockback = knockback
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	hit.add_child(shape)
	var scene := SceneManager.current_world()
	if scene == null:
		hit.queue_free()  # world tearing down mid-swing; don't leak the orphan
		return
	scene.add_child(hit)
	var forward: Vector3 = -camera.global_transform.basis.z
	hit.global_position = camera.global_position + forward * radius
