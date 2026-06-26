# throwing_knife_item.gd
# A stackable thrown weapon consumable. On use it hurls a ThrownKnife straight out of the
# player's camera; the knife deals its damage to the first enemy it touches, then frees.
# One knife is consumed from the stack per throw (the ConsumableItem base handles that).
#
# It mirrors BombItem exactly, just with a straight-flying knife instead of an arcing bomb:
# _throw_from_camera spawns + launch()es the knife, then we stamp this throw's `damage`
# onto the live instance so designers can balance knives entirely from the .tres.

class_name ThrowingKnifeItem
extends ConsumableItem

## The thrown-knife scene to spawn. Defaults to the bundled thrown_knife.tscn but is an
## export so a variant knife could swap in a different model/effect.
@export var thrown_scene: PackedScene = preload("res://entities/items/weapons/thrown_knife.tscn")

## Damage dealt to the first enemy the knife hits (PHYSICAL).
@export var damage: float = 10.0

## How fast the knife is thrown forward (m/s). Fast + flat so it flies nearly straight.
@export var throw_speed: float = 26.0

## A tiny upward arc so the knife doesn't drop instantly at range, but stays mostly flat.
@export var throw_arc: float = 1.0

func _apply_effect(player: Node) -> bool:
	var knife: Node3D = _throw_from_camera(player, thrown_scene, throw_speed, throw_arc)
	if knife == null:
		return false

	# Push this throw's tuning onto the live knife. Done after spawn (and after launch())
	# so the knife's @export default is overridden by this specific item's value; the
	# knife re-reads `damage` onto its HitBox each frame, so the value lands in time.
	if "damage" in knife:
		knife.set("damage", damage)

	return true
