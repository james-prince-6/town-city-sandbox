# bomb_item.gd
# A thrown explosive consumable. On use it lobs a ThrownBomb out of the player's
# camera; after a short fuse (or on impact) the bomb spawns a big one-frame
# EXPLOSIVE HitBox that damages every ENEMY HurtBox in its radius, then frees.
#
# All the throw / fuse / blast behaviour lives on the ThrownBomb scene; this Item
# just configures it and launches it. We pass our exported tuning (damage, fuse,
# radius) onto the spawned bomb so designers can balance bombs entirely from the
# .tres without touching the scene.

class_name BombItem
extends ConsumableItem

## The thrown-bomb scene to spawn. Defaults to the bundled thrown_bomb.tscn but is
## an export so a variant bomb could swap in a different model/effect.
@export var thrown_scene: PackedScene = preload("res://entities/items/consumables/thrown_bomb.tscn")

## Explosion damage dealt to each enemy caught in the blast (EXPLOSIVE type).
@export var damage: float = 50.0

## Seconds from throw until the bomb detonates if it hasn't already hit something.
@export var fuse_time: float = 1.5

## Blast radius in metres — the size of the spherical HitBox spawned on detonation.
@export var radius: float = 3.5

## How fast the bomb is thrown forward, and how much upward arc it gets, in m/s.
@export var throw_speed: float = 14.0
@export var throw_arc: float = 4.0

func _apply_effect(player: Node) -> bool:
	var bomb: Node3D = _throw_from_camera(player, thrown_scene, throw_speed, throw_arc)
	if bomb == null:
		return false

	# Push our tuning onto the live bomb. Done after spawn so the bomb's @export
	# defaults are overridden by this specific item's values.
	if "damage" in bomb:
		bomb.set("damage", damage)
	if "fuse_time" in bomb:
		bomb.set("fuse_time", fuse_time)
	if "radius" in bomb:
		bomb.set("radius", radius)

	return true
