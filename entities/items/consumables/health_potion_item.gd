# health_potion_item.gd
# A drink-it-now consumable: on use it restores some of the player's health via
# PlayerStats and is gone. No projectile, no throwing — instant.
#
# It's a ConsumableItem, so the "use one out of the inventory on success" logic
# is inherited; we only implement the effect. We report failure (return false)
# when the player is already at full health, so a wasted click doesn't burn a
# potion.

class_name HealthPotionItem
extends ConsumableItem

## How much health a single potion restores. PlayerStats.heal clamps to max, so
## an over-heal simply tops the player off.
@export var heal_amount: float = 40.0

func _apply_effect(_player: Node) -> bool:
	# Don't waste a potion if there's nothing to heal.
	if PlayerStats.health >= PlayerStats.max_health:
		return false

	PlayerStats.heal(heal_amount)
	return true
