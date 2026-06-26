# brewing_machine.gd
# A placeable crafting machine you walk up to and use to brew lava drinks. This is
# the in-world half of the brewing feature; the actual recipe/timing logic lives in
# the CraftingSystem autoload, and the brewing menu lives in the BrewingUI autoload.
# This node is just the physical thing in the scene the player looks at and uses.
#
# Hybrid / duck-typed interaction (no special-casing in player.gd):
# - The player's interaction RayCast3D hits this StaticBody3D, calls
#   get_interaction_prompt() to show e.g. "[E] Use Lava Brewer", and interact(player)
#   on press, which just opens the BrewingUI bound to this machine.
#
# IMPORTANT — machine_id MUST be unique per placed machine:
# - The CraftingSystem tracks brewing state per machine_id so a brew survives scene
#   changes. If two placed machines share an id they'd share (and clobber) one brew.
#   Give every BrewingMachine you drop in a scene its own machine_id in the Inspector
#   (e.g. &"shop_brewer_1", &"kitchen_brewer").

extends StaticBody3D

# --- Configuration (set per placed machine in the Inspector) ----------------

## Unique id for THIS placed machine. Used by CraftingSystem to store/restore this
## machine's brewing state. MUST be unique across every machine in the game — see
## the file header note. Leaving it empty is a misuse and is warned about in _ready.
@export var machine_id: StringName = &""

## Which kind of machine this is. Drives which recipes show up in the BrewingUI
## (CraftingSystem.get_recipes_for). Only BREWER exists for now.
@export var machine_type: Recipe.MachineType = Recipe.MachineType.BREWER

## Friendly name shown in prompts and the brewing menu, e.g. "Brew Kettle".
@export var display_name: String = "Brew Kettle"

# --- Visual feedback --------------------------------------------------------

## How much to brighten/emit the mesh material when a brew is DONE so the player can
## spot a ready machine from a distance. Pulled out as a const so it's easy to tweak.
const DONE_EMISSION_ENERGY: float = 1.5

## Cached reference to the placeholder mesh so refreshing the visual is cheap.
@onready var _mesh: MeshInstance3D = $MeshInstance3D

func _ready() -> void:
	# Warn (don't crash) if someone forgot to give this machine a unique id — the
	# CraftingSystem keys everything off it, so an empty id means broken brewing.
	if machine_id == &"":
		push_warning("BrewingMachine '%s' has no machine_id set — brewing state won't work. Give it a unique id in the Inspector." % name)

	# Make sure the CraftingSystem has an IDLE slot for us (idempotent — safe to call
	# every load even if state was already restored for this id).
	CraftingSystem.register_machine(machine_id)

	# React when OUR machine's brewing state changes (e.g. brew finished while the
	# player was standing here) so the visual tint updates without polling.
	CraftingSystem.machine_changed.connect(_on_machine_changed)

	# So other systems (and the player's interaction) can find all machines at once.
	add_to_group("machine")

	# Set the initial tint to match whatever state we restored into.
	_refresh_visual()

# --- Interaction (duck-typed by the player's RayCast3D) ---------------------

## Text shown in the player's prompt while they look at this machine. Reflects the
## current brewing status so the player knows what using it will do.
func get_interaction_prompt() -> String:
	match CraftingSystem.get_status(machine_id):
		CraftingSystem.Status.BREWING:
			# Show rough progress as a percentage so they know how long is left.
			var pct: int = int(round(CraftingSystem.get_progress(machine_id) * 100.0))
			return "%s (brewing %d%%)" % [display_name, pct]
		CraftingSystem.Status.DONE:
			# Name the drink that's ready to collect, resolved via the Inventory db.
			return "Collect %s" % _output_display_name()
		_:
			# IDLE (or unknown): just an invitation to open the menu.
			return "Use %s" % display_name

## Called when the player presses interact while aiming at this machine. Opens the
## brewing menu bound to this machine; all the real work happens in there.
func interact(_player: Node) -> void:
	BrewingUI.open_for(self)

# --- Helpers ----------------------------------------------------------------

## The display name of whatever this machine is currently brewing's output, resolved
## through the Inventory item database. Falls back to a generic word if unknown.
func _output_display_name() -> String:
	var recipe: Recipe = CraftingSystem.get_machine_recipe(machine_id)
	if recipe == null:
		return "drink"
	var item: Item = Inventory.get_item(recipe.output_id)
	if item == null:
		# No matching item resource; show the raw id so it's at least informative.
		return String(recipe.output_id)
	return item.display_name

## CraftingSystem.machine_changed handler. Only cares about our own machine.
func _on_machine_changed(changed_id: StringName) -> void:
	if changed_id == machine_id:
		_refresh_visual()

## Tints the placeholder mesh based on status: a DONE machine glows so it stands out;
## otherwise it sits dark. Safe to call any time after _ready.
func _refresh_visual() -> void:
	if _mesh == null:
		return
	var mat: StandardMaterial3D = _mesh.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	if CraftingSystem.get_status(machine_id) == CraftingSystem.Status.DONE:
		# Glow to advertise "come collect me".
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = DONE_EMISSION_ENERGY
	else:
		mat.emission_enabled = false
