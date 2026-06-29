# hotbar.gd
# Autoload singleton (registered in Project Settings -> Autoload as "Hotbar").
#
# The hotbar is the row of quick-access slots along the bottom of the screen.
# Each slot remembers an item *id* (a StringName), and exactly one slot is
# "selected" at a time — that selected item is what the player is holding /
# about to use (the pickaxe to mine, the club to swing, etc.).
#
# Design notes (mirrors Inventory's approach):
# - Slots store ids only, NOT full Item objects. The actual Item definition is
#   always resolved through the Inventory database via Inventory.get_item(id).
#   This keeps the hotbar tiny to save/load and means it can never go stale.
# - An empty slot is the empty StringName &"". We never store null here so the
#   slots array always has a clean, typed value.
# - Like the other systems this lives outside swappable scenes, so the hotbar
#   layout survives walking from the town into the bar.
#
# Access from anywhere: Hotbar.select(2), Hotbar.get_selected_item(), etc.

extends Node

## How many slots the hotbar has. The number keys 1-8 map onto these, so this
## is fixed at 8. selected_index always wraps inside 0..SLOT_COUNT-1.
const SLOT_COUNT := 8

## Emitted whenever the *contents* of any slot change (an item set or cleared).
## The hotbar UI listens to this and redraws every slot's icon.
signal slots_changed

## Emitted whenever a different slot becomes selected. The UI uses this to move
## the highlight; gameplay uses it to know which tool is now equipped.
signal selection_changed(index: int)

# --- Core persistent state -------------------------------------------------

## One entry per slot. Each holds an item id, or &"" when the slot is empty.
## Sized to SLOT_COUNT in _ready() so indexes 0..7 are always valid.
var slots: Array[StringName] = []

## Which slot is currently active. Stays inside 0..SLOT_COUNT-1 at all times.
var selected_index: int = 0

func _ready() -> void:
	# Start every slot empty, then optionally seed the first two with the
	# starting tools below.
	slots.clear()
	for i in SLOT_COUNT:
		slots.append(&"")

	# Seed the default tools — but ONLY if the item actually exists in the
	# Inventory database. If the .tres resources aren't there yet we just leave
	# the slots empty rather than pointing at ids that resolve to nothing.
	_seed_slot_if_known(0, &"pickaxe")
	_seed_slot_if_known(1, &"hatchet")
	_seed_slot_if_known(2, &"iron_sword")
	_seed_slot_if_known(3, &"bow")

	# Keep the hotbar in step with the bag (player request):
	#  - a newly ACQUIRED item drops into the first free slot, so fresh gear/consumables
	#    are usable straight away (item_gained only fires on add(), so loading a save never
	#    reshuffles the layout);
	#  - an item that RUNS OUT (count hits 0) vanishes from the hotbar, mirroring the bag,
	#    which erases 0-count entries.
	# Connected AFTER seeding so the four seed tools don't get double-placed.
	Inventory.item_gained.connect(_on_item_gained)
	Inventory.item_changed.connect(_on_item_changed)

## Helper for _ready(): place `id` into slot `i`, but only when the Inventory
## database can resolve it to a real Item. Keeps the startup seeding safe.
func _seed_slot_if_known(i: int, id: StringName) -> void:
	if Inventory.get_item(id) != null:
		slots[i] = id

# --- Bag sync (auto place new items / drop emptied ones) --------------------

## A freshly-acquired item that isn't already on the hotbar drops into the first empty slot,
## so new gear/consumables are immediately usable. If the hotbar is full it just stays in the
## bag. Only GAINS trigger this (via Inventory.item_gained), so a save restore never reshuffles.
func _on_item_gained(id: StringName, _amount: int) -> void:
	if id == &"" or _is_on_hotbar(id):
		return
	var free: int = _first_empty_slot()
	if free == -1:
		return
	slots[free] = id
	slots_changed.emit()

## When an item runs out (count reaches 0) it disappears from the hotbar, mirroring the bag
## (which erases 0-count entries). Clears every slot holding that id; emits once if anything
## changed. Non-zero counts are ignored, so partial use leaves the slot in place.
func _on_item_changed(id: StringName, new_count: int) -> void:
	if new_count > 0:
		return
	var changed := false
	for i in SLOT_COUNT:
		if slots[i] == id:
			slots[i] = &""
			changed = true
	if changed:
		slots_changed.emit()

## True if `id` already occupies any hotbar slot (so we don't add a duplicate).
func _is_on_hotbar(id: StringName) -> bool:
	for s in slots:
		if s == id:
			return true
	return false

## The index of the first empty slot, or -1 when the hotbar is full.
func _first_empty_slot() -> int:
	for i in SLOT_COUNT:
		if slots[i] == &"":
			return i
	return -1

# --- Slot contents ---------------------------------------------------------

## Put an item id into a slot. Pass &"" to empty it (or use clear_slot()).
func set_slot(i: int, id: StringName) -> void:
	if i < 0 or i >= SLOT_COUNT:
		push_warning("Hotbar.set_slot: index %d out of range 0..%d" % [i, SLOT_COUNT - 1])
		return
	slots[i] = id
	slots_changed.emit()

## Empty a single slot. Convenience wrapper around set_slot(i, &"").
func clear_slot(i: int) -> void:
	if i < 0 or i >= SLOT_COUNT:
		push_warning("Hotbar.clear_slot: index %d out of range 0..%d" % [i, SLOT_COUNT - 1])
		return
	slots[i] = &""
	slots_changed.emit()

# --- Selection -------------------------------------------------------------

## Select a specific slot by index. Out-of-range indexes are ignored with a
## warning so a stray number key can't crash the game.
func select(index: int) -> void:
	if index < 0 or index >= SLOT_COUNT:
		push_warning("Hotbar.select: index %d out of range 0..%d" % [index, SLOT_COUNT - 1])
		return
	if index == selected_index:
		return
	selected_index = index
	selection_changed.emit(selected_index)

## Move the selection one slot to the right, wrapping past the end back to 0.
## Bound to the mouse wheel (hotbar_next).
func select_next() -> void:
	select((selected_index + 1) % SLOT_COUNT)

## Move the selection one slot to the left, wrapping past 0 to the last slot.
## Bound to the mouse wheel (hotbar_prev).
func select_prev() -> void:
	# Adding SLOT_COUNT before the modulo keeps the result non-negative.
	select((selected_index - 1 + SLOT_COUNT) % SLOT_COUNT)

# --- Queries ---------------------------------------------------------------

## The id sitting in the selected slot (&"" when that slot is empty).
func get_selected_id() -> StringName:
	return slots[selected_index]

## The full Item resource for the selected slot, resolved through Inventory.
## Returns null when the slot is empty or the id can't be found — callers that
## need a tool should cast this to ToolItem and null-check before using it.
func get_selected_item() -> Item:
	var id := get_selected_id()
	if id == &"":
		return null
	return Inventory.get_item(id)

# --- Save / load -----------------------------------------------------------
# A single dictionary snapshot, matching the other systems. The save system
# gathers one of these from each autoload and writes them out together.

func capture_state() -> Dictionary:
	return {
		"slots": slots.duplicate(),
		"selected_index": selected_index,
	}

func restore_state(data: Dictionary) -> void:
	# Rebuild the slots array defensively: always end up with exactly SLOT_COUNT
	# entries even if the saved data was shorter, longer, or missing.
	var saved: Array = data.get("slots", [])
	slots.clear()
	for i in SLOT_COUNT:
		if i < saved.size():
			slots.append(StringName(saved[i]))
		else:
			slots.append(&"")
	slots_changed.emit()

	# Restore selection, clamped so it can never point outside the valid range.
	selected_index = clampi(int(data.get("selected_index", 0)), 0, SLOT_COUNT - 1)
	selection_changed.emit(selected_index)
