# consumable_item.gd
# Base class for single-use items that DO something when the player left-clicks
# them: drink a potion, lob a bomb, pop a smoke grenade. Like every other item
# it's a data Resource (.tres) — one shared instance — so it must never store
# per-use mutable state on itself; all of that lives on the spawned scenes.
#
# The shared bit every consumable wants is "use one up out of the inventory when
# it actually fires". We centralise that here: use() checks the player has at
# least one, runs the subclass's effect, and only then decrements the stack.
# Subclasses override _apply_effect(player) and return true if the use should be
# counted (false = nothing happened, so don't burn an item).
#
# To create one: right-click the FileSystem -> New Resource... -> (a subclass,
# e.g. HealthPotionItem) and fill in the Item fields plus the consumable fields.

class_name ConsumableItem
extends Item

## Called by the player on left-click (see Item.use). We guard on having at least
## one in the Inventory, run the effect, and consume exactly one on success. If the
## effect reports failure (returned false) we leave the stack untouched so the
## player isn't charged for a use that did nothing.
func use(player: Node) -> void:
	# Nothing to use — bail before doing any work.
	if Inventory.count_of(id) <= 0:
		return

	# Run the actual effect. Subclasses decide what happens and whether it "took".
	var consumed: bool = _apply_effect(player)
	if not consumed:
		return

	# Success: spend one from the stack.
	Inventory.remove(id, 1)

## Override in subclasses to do the consumable's thing (heal, throw a bomb, etc.).
## Return true if the use should be counted (and one item removed), false to skip
## consuming (e.g. couldn't find the camera, already at full health, etc.).
## The base does nothing and reports failure so a misconfigured item is harmless.
func _apply_effect(_player: Node) -> bool:
	return false

# --- Shared helpers for thrown consumables --------------------------------

## Spawn `scene` into the current world, positioned just in front of the player's
## camera, and launch it along the camera's forward (with an optional upward arc).
## Returns the spawned node (a Node3D) or null if we couldn't aim. Bomb / smoke
## grenade subclasses use this so the throwing math lives in one place.
##
## We add to the active level (SceneManager.current_world()) rather than parenting to
## the player, so the projectile keeps flying after it leaves the hand and isn't
## dragged around by player movement.
func _throw_from_camera(player: Node, scene: PackedScene, throw_speed: float, arc: float) -> Node3D:
	if scene == null:
		return null
	if not player.has_method("get_camera"):
		return null

	var camera: Camera3D = player.get_camera()
	if camera == null:
		return null

	var thrown: Node3D = scene.instantiate() as Node3D
	if thrown == null:
		return null

	# Forward is -Z of the camera basis (Godot cameras look down their local -Z).
	var forward: Vector3 = -camera.global_transform.basis.z
	var spawn_pos: Vector3 = camera.global_position + forward * 0.6

	# Add to the live scene first, THEN place it (global_position needs the tree).
	var world: Node = SceneManager.current_world()
	world.add_child(thrown)
	thrown.global_position = spawn_pos

	# Hand the launch to the projectile if it knows how to be thrown; otherwise
	# leave it where it landed (a no-physics fallback).
	if thrown.has_method("launch"):
		var velocity: Vector3 = forward * throw_speed + Vector3.UP * arc
		thrown.call("launch", velocity, player)

	return thrown
