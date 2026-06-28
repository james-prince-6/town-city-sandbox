# house_upgrades.gd
# Autoload singleton (register in Project Settings -> Autoload as "HouseUpgrades").
#
# Owns the player's HOME upgrade progression: which improvements (storage chest,
# comfy bed, kitchen, ...) they've bought. Like the other systems it lives outside
# swappable scenes so the home's state survives walking in and out.
#
# Data-driven: every UpgradeDef (.tres) in res://global/house/upgrades/ is scanned
# into `_catalog` at startup, so adding a new upgrade is just dropping in a .tres —
# no code edits here. Buying spends money (GameState) and optionally an item stack
# (Inventory), then records the id in `_owned`.
#
# NO class_name ON PURPOSE: the autoload singleton is itself named "HouseUpgrades";
# declaring `class_name HouseUpgrades` here would clash with that global symbol.
# Other code reaches this through the autoload (HouseUpgrades.buy(...)).

extends Node

## Folder scanned for UpgradeDef (.tres) resources at startup.
const UPGRADES_PATH: String = "res://global/house/upgrades/"

## Emitted right after an upgrade is successfully bought. The upgrade menu and any
## home fixtures (a chest, a bed) listen so they can appear / refresh without polling.
signal upgrade_purchased(id: StringName)

## id (StringName) -> UpgradeDef. Every known upgrade, populated from the folder.
var _catalog: Dictionary = {}

## id (StringName) -> true for each upgrade the player owns. Absence means "not owned".
var _owned: Dictionary = {}

func _ready() -> void:
	_load_catalog()

# --- Catalog ---------------------------------------------------------------

func _load_catalog() -> void:
	var dir := DirAccess.open(UPGRADES_PATH)
	if dir == null:
		push_warning("HouseUpgrades: upgrades folder not found at %s" % UPGRADES_PATH)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		# Exported builds rename .tres -> .tres.remap; strip that so load() works in both.
		if file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
			var clean := file_name.trim_suffix(".remap")
			var res := load(UPGRADES_PATH + clean)
			if res is UpgradeDef:
				var def := res as UpgradeDef
				if def.id == &"":
					push_warning("HouseUpgrades: %s has an empty id, skipping." % clean)
				else:
					_catalog[def.id] = def
		file_name = dir.get_next()
	dir.list_dir_end()

## Every upgrade definition, sorted by sort_order (then id for stable ties).
func get_catalog() -> Array[UpgradeDef]:
	var defs: Array[UpgradeDef] = []
	for id in _catalog:
		defs.append(_catalog[id])
	defs.sort_custom(func(a: UpgradeDef, b: UpgradeDef) -> bool:
		if a.sort_order == b.sort_order:
			return String(a.id) < String(b.id)
		return a.sort_order < b.sort_order)
	return defs

## The definition for an id, or null if unknown.
func get_def(id: StringName) -> UpgradeDef:
	return _catalog.get(id)

# --- Queries ---------------------------------------------------------------

func is_owned(id: StringName) -> bool:
	return _owned.has(id)

## True when the upgrade can be purchased right now: it exists, isn't already owned,
## its prerequisite (if any) is owned, and the player can afford the money + item cost.
func can_buy(id: StringName) -> bool:
	var def: UpgradeDef = _catalog.get(id)
	if def == null:
		return false
	if is_owned(id):
		return false
	if def.prerequisite != &"" and not is_owned(def.prerequisite):
		return false
	if GameState.money < def.cost_money:
		return false
	if def.cost_item_id != &"" and def.cost_item_count > 0:
		if not Inventory.has(def.cost_item_id, def.cost_item_count):
			return false
	return true

# --- Purchase --------------------------------------------------------------

## Attempts to buy `id`. Re-checks can_buy, then spends money + items and records
## ownership. Returns true on success, false if it couldn't be bought.
func buy(id: StringName) -> bool:
	if not can_buy(id):
		return false
	var def: UpgradeDef = _catalog.get(id)
	if def == null:
		return false
	# Spend the item cost first (only when there is one). If it somehow fails despite
	# the can_buy check, bail before touching money so nothing is half-charged.
	if def.cost_item_id != &"" and def.cost_item_count > 0:
		if not Inventory.remove(def.cost_item_id, def.cost_item_count):
			return false
	# Then the money. spend_money double-checks affordability and deducts.
	if not GameState.spend_money(def.cost_money):
		# Refund the items we just removed so we don't lose them on a failed buy.
		if def.cost_item_id != &"" and def.cost_item_count > 0:
			Inventory.add(def.cost_item_id, def.cost_item_count)
		return false
	_owned[id] = true
	upgrade_purchased.emit(id)
	return true

# --- Save / load -----------------------------------------------------------

func capture_state() -> Dictionary:
	return { "owned": _owned.duplicate() }

func restore_state(data: Dictionary) -> void:
	_owned = {}
	var raw = data.get("owned", {})
	if raw is Dictionary:
		for key in raw:
			# Keys are StringName ids; coerce defensively and keep only truthy entries.
			if bool(raw[key]):
				_owned[StringName(key)] = true
