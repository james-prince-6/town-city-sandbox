# inventory.gd
# Autoload singleton (registered as "Inventory").
#
# Holds what the player is carrying. Like GameState, it lives outside swappable
# scenes so the bag isn't emptied every time you walk through a door.
#
# Design notes:
# - Items are tracked by their string `id`, not by object reference. Counts live
#   in `_counts` ({ id -> amount }). This keeps save/load to a tiny dictionary.
# - The full Item resource (name, icon, value...) is resolved through `database`,
#   which is auto-populated by scanning a folder of .tres Item files at startup.
#   Drop a new Item resource in that folder and it "just works" — no code edits.

extends Node

## Folder scanned for Item (.tres) resources at startup. Every Item found is
## registered into `database` under its `id`.
const ITEM_DB_PATH := "res://global/items/resources/"

## Emitted whenever an item's count changes. The inventory UI listens to this
## and redraws the affected slot. Sends the id and the new total.
signal item_changed(id: StringName, new_count: int)

## Emitted only when items are GAINED through `add()` (pickups, loot, crafting,
## buying). Sends the id and how many were just added — the notification feed
## uses this to pop a "+N Name" toast. Deliberately NOT fired by remove() or by
## restore_state(), so loading a save doesn't spam a wall of toasts.
signal item_gained(id: StringName, amount: int)

## id (StringName) -> Item resource. Lookup table for everything an item "is".
var database: Dictionary = {}

## id (StringName) -> int count currently held.
var _counts: Dictionary = {}

func _ready() -> void:
	_load_database()

# --- Database --------------------------------------------------------------

func _load_database() -> void:
	var dir := DirAccess.open(ITEM_DB_PATH)
	if dir == null:
		push_warning("Inventory: item folder not found at %s" % ITEM_DB_PATH)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		# In exported builds Godot renames .tres -> .tres.remap; strip that so
		# the load() path stays valid in both the editor and exports.
		if file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
			var clean := file_name.trim_suffix(".remap")
			var res := load(ITEM_DB_PATH + clean)
			if res is Item:
				if res.id == &"":
					push_warning("Inventory: %s has an empty id, skipping." % clean)
				else:
					database[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()

## Look up the full Item definition for an id (or null if unknown).
func get_item(id: StringName) -> Item:
	return database.get(id)

# --- Adding / removing -----------------------------------------------------

func add(id: StringName, amount: int = 1) -> void:
	if amount <= 0:
		return
	if not database.has(id):
		push_warning("Inventory.add: unknown item id '%s'" % id)
	_counts[id] = count_of(id) + amount
	item_changed.emit(id, _counts[id])
	# Separate "gained" signal carries the DELTA (not the new total) so toasts can
	# show "+N". Only add() emits it, so loot/crafting/buying all pop a toast while
	# a save restore (which sets counts directly below) stays silent.
	item_gained.emit(id, amount)

## Removes up to `amount`. Returns true only if the player had enough to remove
## the full amount; returns false and changes nothing otherwise.
func remove(id: StringName, amount: int = 1) -> bool:
	if amount <= 0:
		return true
	if count_of(id) < amount:
		return false
	_counts[id] -= amount
	if _counts[id] <= 0:
		_counts.erase(id)
	item_changed.emit(id, count_of(id))
	return true

# --- Queries ---------------------------------------------------------------

func count_of(id: StringName) -> int:
	return _counts.get(id, 0)

func has(id: StringName, amount: int = 1) -> bool:
	return count_of(id) >= amount

## Returns every held item as { id -> count }. Handy for drawing the full bag.
func get_all() -> Dictionary:
	return _counts.duplicate()

# --- Save / load -----------------------------------------------------------

func capture_state() -> Dictionary:
	return { "counts": _counts.duplicate() }

func restore_state(data: Dictionary) -> void:
	_counts = data.get("counts", {}).duplicate()
	for id in _counts:
		item_changed.emit(id, _counts[id])
