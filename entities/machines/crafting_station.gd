# crafting_station.gd
# A generic, placeable crafting station — smelter, workbench, cooking station, or bar
# mixing station. It's the physical thing the player looks at and uses; the recipe /
# timing logic lives in the CraftingSystem autoload and the drag-to-fill menu lives in
# the CraftingUI autoload. This node just routes interaction into that menu.
#
# Duck-typed interaction (no special-casing in player.gd): the player's raycast hits
# this StaticBody3D, calls get_interaction_prompt() for the label and interact(player)
# on press, which opens CraftingUI for this station.
#
# Set per placed station in the Inspector:
#   - machine_id    : a UNIQUE id (e.g. &"town_smelter_1"). CraftingSystem keys timed
#                     jobs off it so they survive scene changes; duplicates clobber.
#   - machine_type  : SMELTER / WORKBENCH / COOKING / BREWER (filters the recipe list).
#   - display_name  : shown in the prompt and the menu header.

extends StaticBody3D

@export var machine_id: StringName = &""
@export var machine_type: Recipe.MachineType = Recipe.MachineType.WORKBENCH
@export var display_name: String = "Workbench"

## Emission energy used to make a finished (DONE) timed station glow so a ready job is
## visible from a distance.
const DONE_EMISSION_ENERGY: float = 1.5

@onready var _mesh: MeshInstance3D = get_node_or_null("MeshInstance3D")

func _ready() -> void:
	if machine_id == &"":
		push_warning("CraftingStation '%s' has no machine_id — timed jobs won't persist. Give it a unique id." % name)
	CraftingSystem.register_machine(machine_id)
	CraftingSystem.machine_changed.connect(_on_machine_changed)
	add_to_group("machine")
	_refresh_visual()

# --- Interaction (duck-typed by the player's RayCast3D) --------------------

func get_interaction_prompt() -> String:
	match CraftingSystem.get_status(machine_id):
		CraftingSystem.Status.BREWING:
			var pct: int = int(round(CraftingSystem.get_progress(machine_id) * 100.0))
			return "%s (%d%%)" % [display_name, pct]
		CraftingSystem.Status.DONE:
			return "Collect %s" % _output_display_name()
		_:
			return "Use %s" % display_name

func interact(_player: Node) -> void:
	# CraftingUI handles every state: a recipe list when idle, progress while a timed
	# job runs, and a collect button when one is done.
	CraftingUI.open_for(self)

# --- Helpers ---------------------------------------------------------------

func _output_display_name() -> String:
	var recipe: Recipe = CraftingSystem.get_machine_recipe(machine_id)
	if recipe == null:
		return "item"
	var item: Item = Inventory.get_item(recipe.output_id)
	return item.display_name if item != null else String(recipe.output_id)

func _on_machine_changed(changed_id: StringName) -> void:
	if changed_id == machine_id:
		_refresh_visual()

func _refresh_visual() -> void:
	if _mesh == null:
		return
	var mat: StandardMaterial3D = _mesh.get_surface_override_material(0) as StandardMaterial3D
	if mat == null:
		return
	if CraftingSystem.get_status(machine_id) == CraftingSystem.Status.DONE:
		mat.emission_enabled = true
		mat.emission = mat.albedo_color
		mat.emission_energy_multiplier = DONE_EMISSION_ENERGY
	else:
		mat.emission_enabled = false
