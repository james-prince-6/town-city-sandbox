# shopkeeper.gd
# A villager who runs a shop. Extends the regular NPC so it still stands in the
# world and faces the player, but instead of opening a dialogue it opens the
# shop screen (ShopUI) where the player can buy and sell items.
#
# To make one: instance shopkeeper.tscn, set its `npc_name`, and drag a
# ShopInventory (.tres) resource into the `shop` slot in the Inspector. That
# resource describes what the keeper sells/buys and at what prices.

class_name Shopkeeper
extends NPC

## The storefront this keeper runs (what they sell, what they buy, prices).
## Assigned per-shopkeeper in the Inspector; left empty on the base scene.
@export var shop: ShopInventory

# Override the NPC prompt so it reads "Shop with <name>" instead of "Talk to".
func get_interaction_prompt() -> String:
	return "Shop with %s" % npc_name

# Override interact: turn to face the player (same as NPC does), then open the
# shop UI bound to this keeper's storefront.
func interact(player) -> void:
	if turn_to_face_player and player is Node3D:
		_face_toward(player.global_position)

	if shop == null:
		push_warning("Shopkeeper '%s' has no shop assigned." % npc_name)
		return
	ShopUI.open_for(shop)
