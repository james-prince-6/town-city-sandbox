# smoke_grenade_item.gd
# A thrown utility consumable. On use it lobs a grenade that, on landing (or after
# a short fuse), spawns an expanding translucent smoke cloud that lingers for a few
# seconds and then cleans itself up. The effect is purely visual concealment for
# now — no stat changes — but the cloud is a real, self-freeing world object.
#
# Like BombItem, the throw/fuse lives on the thrown scene; this Item configures it
# (cloud duration) and launches it.

class_name SmokeGrenadeItem
extends ConsumableItem

## The thrown-grenade scene that arcs out and pops the cloud on landing.
@export var thrown_scene: PackedScene = preload("res://entities/items/consumables/thrown_grenade.tscn")

## How long (seconds) the smoke cloud persists once it appears before fading/freeing.
@export var duration: float = 5.0

## Throw tuning, same meaning as BombItem.
@export var throw_speed: float = 12.0
@export var throw_arc: float = 4.0

func _apply_effect(player: Node) -> bool:
	var grenade: Node3D = _throw_from_camera(player, thrown_scene, throw_speed, throw_arc)
	if grenade == null:
		return false

	# Pass the cloud lifetime onto the grenade so it can hand it to the cloud it spawns.
	if "duration" in grenade:
		grenade.set("duration", duration)

	return true
