# loot_table.gd
# A small data Resource describing "what spills out of this thing when it opens or
# breaks". Chests, breakable crates and (potentially) anything else share the same
# loot description so designers author drops in one consistent place in the Inspector.
#
# Each entry is one item type plus an inclusive min..max count. roll() picks a count
# per entry and returns a flat { item_id : total_count } dictionary that callers feed
# straight into Inventory.add() or WorldItem.spawn().
#
# Authoring in the Inspector: `entries` is an Array of LootEntry sub-resources. Add a
# LootEntry, set its item_id (must match an Inventory id, e.g. &"stone"), and a
# min/max range. Set min == max for a fixed amount.

class_name LootTable
extends Resource

## The drops this table can produce. Every entry rolls independently when roll()
## is called, so a chest can grant several different items at once.
@export var entries: Array[LootEntry] = []

## Roll every entry and merge the results into one { StringName : int } dictionary.
## Counts for the same id stack. Entries that roll 0 (or have an empty id) are
## skipped so callers never have to filter junk. `rng` is optional — pass one in for
## reproducible drops (saves/tests); omit it to use the global generator.
func roll(rng: RandomNumberGenerator = null) -> Dictionary:
	var result: Dictionary = {}
	for entry in entries:
		if entry == null or entry.item_id == &"":
			continue
		var count: int = entry.roll_count(rng)
		if count <= 0:
			continue
		# Stack with anything already rolled for this id (two entries of the same item).
		var existing: int = result.get(entry.item_id, 0)
		result[entry.item_id] = existing + count
	return result
