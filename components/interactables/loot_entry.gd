# loot_entry.gd
# One line of a LootTable: "give between `min_count` and `max_count` of `item_id`".
# Kept as its own tiny Resource so designers can build a table out of inline
# sub-resources in the Inspector and reorder/reuse them freely.

class_name LootEntry
extends Resource

## The item this entry drops. Must match an id known to the Inventory database
## (e.g. &"stone", &"iron_ore", &"health_potion").
@export var item_id: StringName = &""

## Smallest amount this entry can roll (inclusive). Clamped to >= 0.
@export var min_count: int = 1

## Largest amount this entry can roll (inclusive). If it ends up below min_count
## we treat the range as just min_count (a fixed amount).
@export var max_count: int = 1

## Pick a count in [min_count, max_count]. Pass an RNG for reproducible results;
## without one we fall back to the global randi_range(). Negative mins are floored
## to 0 and an inverted range collapses to the min so authoring mistakes stay sane.
func roll_count(rng: RandomNumberGenerator = null) -> int:
	var lo: int = max(min_count, 0)
	var hi: int = max(max_count, lo)
	if rng != null:
		return rng.randi_range(lo, hi)
	return randi_range(lo, hi)
