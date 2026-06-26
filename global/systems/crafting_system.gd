# crafting_system.gd
# Autoload singleton (registered as "CraftingSystem").
#
# Runs the crafting/brewing machines. The clever bit: brewing progress is stored
# as a *game-time timestamp*, not a countdown. We record what game-minute a brew
# started, and compare that to the current Clock time whenever someone asks. That
# means a brew keeps ticking correctly even if you walk away and the machine's
# scene gets unloaded — the state lives here in the autoload, not in the machine.
#
# Design notes (mirrors inventory.gd):
# - Recipe resources are auto-loaded by scanning a folder of .tres files, so
#   adding a recipe needs no code edits — just drop a Recipe .tres in.
# - Per-machine state is a tiny dictionary so save/load stays trivial.

extends Node

## Folder scanned for Recipe (.tres) resources at startup. Every Recipe found is
## registered into `database` under its `id`.
const RECIPE_DB_PATH := "res://global/crafting/recipes/"

## What a single machine is currently doing.
enum Status {
	IDLE,     ## Empty and ready to start a new brew.
	BREWING,  ## A brew is in progress (time still elapsing).
	DONE,     ## The brew finished; output is waiting to be collected.
}

## Emitted whenever a machine's state changes (started, finished, collected).
## UIs and the machine's own visual listen to this so they don't have to poll.
signal machine_changed(machine_id: StringName)

## id (StringName) -> Recipe resource. Lookup table for every known recipe.
var database: Dictionary = {}

## Persistent per-machine state. This is what makes brewing survive scene changes.
## machine_id (StringName) -> {
##     "recipe_id": StringName,    # which recipe is loaded (&"" when IDLE)
##     "start_minutes": int,       # game-minute the brew started
##     "status": int               # one of Status (stored as int)
## }
var _machines: Dictionary = {}

func _ready() -> void:
	_load_database()

# --- Database --------------------------------------------------------------

func _load_database() -> void:
	var dir := DirAccess.open(RECIPE_DB_PATH)
	if dir == null:
		push_warning("CraftingSystem: recipe folder not found at %s" % RECIPE_DB_PATH)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		# In exported builds Godot renames .tres -> .tres.remap; strip that so
		# the load() path stays valid in both the editor and exports.
		if file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
			var clean := file_name.trim_suffix(".remap")
			var res := load(RECIPE_DB_PATH + clean)
			if res is Recipe:
				if res.id == &"":
					push_warning("CraftingSystem: %s has an empty id, skipping." % clean)
				else:
					database[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()

# --- Time helper -----------------------------------------------------------

## Current game time expressed as a single running minute count. There's no
## total-minutes accessor on Clock, so we compute it from day + hour + minute.
func _now_minutes() -> int:
	return ((GameState.day - 1) * 1440) + (Clock.hour * 60) + Clock.minute

# --- Recipe queries --------------------------------------------------------

## Look up a Recipe by id (or null if unknown).
func get_recipe(id: StringName) -> Recipe:
	return database.get(id)

## Every known recipe that runs on the given machine type.
func get_recipes_for(machine_type: Recipe.MachineType) -> Array[Recipe]:
	var result: Array[Recipe] = []
	for recipe in database.values():
		if recipe.machine_type == machine_type:
			result.append(recipe)
	return result

## True only if the Inventory holds every input at its required count.
func can_craft(recipe: Recipe) -> bool:
	if recipe == null:
		return false
	for ingredient in recipe.inputs:
		if not Inventory.has(ingredient.item_id, ingredient.count):
			return false
	return true

## Instant craft (workbench-style): consume the recipe's inputs from the Inventory and
## add its output immediately, no station timer involved. Returns false and changes
## nothing if the player can't afford every input. Used by the crafting UI for recipes
## flagged `instant`.
func craft_instant(recipe_id: StringName) -> bool:
	var recipe := get_recipe(recipe_id)
	if recipe == null or not can_craft(recipe):
		return false
	for ingredient in recipe.inputs:
		Inventory.remove(ingredient.item_id, ingredient.count)
	Inventory.add(recipe.output_id, recipe.output_count)
	return true

# --- Machine registration --------------------------------------------------

## Make sure a machine has an entry (IDLE if brand new). Idempotent: calling it
## again for an existing machine leaves its state untouched. Machines call this
## from _ready so their id is known even before anyone interacts with them.
func register_machine(machine_id: StringName) -> void:
	if _machines.has(machine_id):
		return
	_machines[machine_id] = {
		"recipe_id": &"",
		"start_minutes": 0,
		"status": Status.IDLE,
	}

# --- Brewing ---------------------------------------------------------------

## Start a brew on a machine. Returns false and changes nothing unless the
## machine is IDLE and the player can afford the recipe's inputs. On success it
## consumes the inputs and records the start time.
func start_brew(machine_id: StringName, recipe_id: StringName) -> bool:
	if not _machines.has(machine_id):
		push_warning("CraftingSystem.start_brew: unknown machine '%s'" % machine_id)
		return false
	var state: Dictionary = _machines[machine_id]
	if state["status"] != Status.IDLE:
		return false
	var recipe := get_recipe(recipe_id)
	if recipe == null:
		push_warning("CraftingSystem.start_brew: unknown recipe '%s'" % recipe_id)
		return false
	if not can_craft(recipe):
		return false
	# Consume the inputs. can_craft already verified we have them all, so these
	# removes won't fail partway through.
	for ingredient in recipe.inputs:
		Inventory.remove(ingredient.item_id, ingredient.count)
	state["recipe_id"] = recipe_id
	state["start_minutes"] = _now_minutes()
	state["status"] = Status.BREWING
	machine_changed.emit(machine_id)
	return true

## The machine's current status. If it's BREWING and enough game-time has passed,
## this reports DONE (the _process loop will also flip the stored status soon, but
## this keeps callers correct the instant the time elapses).
func get_status(machine_id: StringName) -> Status:
	if not _machines.has(machine_id):
		return Status.IDLE
	var state: Dictionary = _machines[machine_id]
	if state["status"] == Status.BREWING:
		var recipe := get_recipe(state["recipe_id"])
		if recipe != null and _now_minutes() - state["start_minutes"] >= recipe.brew_minutes:
			return Status.DONE
	return state["status"]

## Brew progress as 0.0..1.0. 0 when IDLE, 1 when DONE, fractional while BREWING.
func get_progress(machine_id: StringName) -> float:
	if not _machines.has(machine_id):
		return 0.0
	var state: Dictionary = _machines[machine_id]
	if state["status"] == Status.IDLE:
		return 0.0
	if state["status"] == Status.DONE:
		return 1.0
	# BREWING: compare elapsed game-minutes to the recipe's total.
	var recipe := get_recipe(state["recipe_id"])
	if recipe == null or recipe.brew_minutes <= 0:
		return 1.0
	var elapsed: int = _now_minutes() - state["start_minutes"]
	return clampf(float(elapsed) / float(recipe.brew_minutes), 0.0, 1.0)

## The Recipe a machine is currently running (or null if IDLE/unknown).
func get_machine_recipe(machine_id: StringName) -> Recipe:
	if not _machines.has(machine_id):
		return null
	var state: Dictionary = _machines[machine_id]
	if state["status"] == Status.IDLE:
		return null
	return get_recipe(state["recipe_id"])

## Collect a finished brew: adds the output to the Inventory and resets the
## machine to IDLE. Returns false if the machine isn't actually DONE.
func collect(machine_id: StringName) -> bool:
	if not _machines.has(machine_id):
		return false
	if get_status(machine_id) != Status.DONE:
		return false
	var state: Dictionary = _machines[machine_id]
	var recipe := get_recipe(state["recipe_id"])
	if recipe != null:
		Inventory.add(recipe.output_id, recipe.output_count)
	# Reset to IDLE so the machine is ready for the next brew.
	state["recipe_id"] = &""
	state["start_minutes"] = 0
	state["status"] = Status.IDLE
	machine_changed.emit(machine_id)
	return true

# --- Tick ------------------------------------------------------------------

## Watch for brews that have finished and flip them to DONE exactly once, so the
## machine visuals and any open UI react without polling. Kept light: just a scan
## of the machine dictionary. Brewing itself is time-based off the Clock, so this
## stays correct even if the loop is skipped for a while (e.g. across scene loads).
func _process(_delta: float) -> void:
	for machine_id in _machines:
		var state: Dictionary = _machines[machine_id]
		if state["status"] != Status.BREWING:
			continue
		var recipe := get_recipe(state["recipe_id"])
		if recipe != null and _now_minutes() - state["start_minutes"] >= recipe.brew_minutes:
			state["status"] = Status.DONE
			machine_changed.emit(machine_id)

# --- Save / load -----------------------------------------------------------

func capture_state() -> Dictionary:
	# Deep-duplicate so saved snapshots don't alias the live per-machine dicts.
	return { "machines": _machines.duplicate(true) }

func restore_state(data: Dictionary) -> void:
	_machines = data.get("machines", {}).duplicate(true)
	# Let listeners refresh to match the restored state.
	for machine_id in _machines:
		machine_changed.emit(machine_id)
