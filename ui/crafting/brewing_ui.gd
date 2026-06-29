# brewing_ui.gd
# Autoload singleton (registered as "BrewingUI", pointing at brewing_ui.tscn).
#
# A BLOCKING menu that drives ONE brewing machine at a time. Like InventoryUI it
# owns no data of its own — it reads the CraftingSystem (recipes + machine state)
# and the Inventory, then redraws. Because it lives in an autoload it's available
# in every scene.
#
# A machine opens it by calling open_for(self). The panel frees the mouse and
# emits `opened`; the player listens (same pattern as InventoryUI) to stop moving.
# Closing emits `closed`. ui_cancel (Esc) closes it.
#
# What it shows depends on CraftingSystem.get_status(machine_id):
# - IDLE:    one row per recipe with its inputs + a "Brew" button (gated by can_craft).
# - BREWING: the recipe name, a live progress bar, and an approximate "ready in N min".
# - DONE:    a "Collect" button that hands the output to the Inventory.

extends CanvasLayer

const Flat = preload("res://ui/ui_style.gd")

## Emitted when the menu opens / closes. The player listens so it can stop moving
## and free the mouse (same pattern as InventoryUI / Dialogue).
signal opened
signal closed

@onready var title: Label = $Panel/Margin/VBox/Title
@onready var rows: VBoxContainer = $Panel/Margin/VBox/Rows
@onready var _panel: PanelContainer = $Panel

var is_open: bool = false

## The machine node we're currently bound to, plus its id cached for convenience.
var _machine: Node = null
var _machine_id: StringName = &""

func _ready() -> void:
	# Draw above the world (just under the inventory's layer 10) and keep working
	# even if something pauses the tree.
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("exclusive_menu")  # so opening another menu closes this one
	# Frosted-glass backdrop instead of the default dark panel box.
	Flat.apply(_panel, 18, 22)
	hide()
	# Rebuild when our machine changes state (brew started / finished / collected),
	# and when the bag changes (so Brew buttons enable/disable as inputs come and go).
	CraftingSystem.machine_changed.connect(_on_machine_changed)
	Inventory.item_changed.connect(_on_item_changed)

func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# --- Open / close ----------------------------------------------------------

## Bind to a machine and show the panel. The machine must expose `machine_id`.
func open_for(machine: Node) -> void:
	if machine == null:
		push_warning("BrewingUI.open_for: machine is null")
		return
	_machine = machine
	_machine_id = machine.machine_id
	is_open = true
	MenuManager.opening(self)  # close any other open menu first (no stacking)
	_rebuild()
	show()
	opened.emit()

func close() -> void:
	is_open = false
	hide()
	closed.emit()
	_machine = null
	_machine_id = &""

# --- Live updates ----------------------------------------------------------

# A brew started/finished/was collected. Only redraw if it's the machine we show.
func _on_machine_changed(machine_id: StringName) -> void:
	if is_open and machine_id == _machine_id:
		_rebuild()

# The bag changed: redraw so the Brew buttons reflect what's now affordable.
func _on_item_changed(_id: StringName, _count: int) -> void:
	if is_open:
		_rebuild()

# While a brew is in progress the time keeps moving even though no signal fires,
# so we poll the progress bar each frame while it's visible.
func _process(_delta: float) -> void:
	if not is_open or _machine == null:
		return
	if CraftingSystem.get_status(_machine_id) == CraftingSystem.Status.BREWING:
		var bar := rows.get_node_or_null("Progress") as ProgressBar
		if bar != null:
			bar.value = CraftingSystem.get_progress(_machine_id)
		var ready_label := rows.get_node_or_null("ReadyIn") as Label
		if ready_label != null:
			ready_label.text = _ready_in_text()
	else:
		# Time elapsed mid-view: CraftingSystem flips to DONE and emits
		# machine_changed, which rebuilds us. Nothing to do here.
		pass

# --- Building the panel ----------------------------------------------------

# Clears and repopulates the panel based on the bound machine's current status.
func _rebuild() -> void:
	for child in rows.get_children():
		child.queue_free()

	if _machine == null:
		return

	# Title shows the machine's name (falls back gracefully if not set).
	var machine_name := "Brewer"
	if "display_name" in _machine:
		machine_name = _machine.display_name
	title.text = machine_name

	match CraftingSystem.get_status(_machine_id):
		CraftingSystem.Status.IDLE:
			_build_idle()
		CraftingSystem.Status.BREWING:
			_build_brewing()
		CraftingSystem.Status.DONE:
			_build_done()

	# Put controller focus on the first usable button so the pad can drive this menu.
	_grab_focus.call_deferred()

# Focus the first enabled button (Brew/Collect). Skips if the player is already
# navigating inside this menu, so live rebuilds don't yank the selection.
func _grab_focus() -> void:
	if not is_open:
		return
	var fo := get_viewport().gui_get_focus_owner()
	if fo != null and is_ancestor_of(fo):
		return
	var btn := _first_button(rows)
	if btn != null:
		btn.grab_focus()

func _first_button(node: Node) -> Button:
	for c in node.get_children():
		if c is Button and not (c as Button).disabled:
			return c
		var deeper := _first_button(c)
		if deeper != null:
			return deeper
	return null

# IDLE: one row per recipe that runs on this machine type.
func _build_idle() -> void:
	var machine_type: Recipe.MachineType = Recipe.MachineType.BREWER
	if "machine_type" in _machine:
		machine_type = _machine.machine_type
	var recipes := CraftingSystem.get_recipes_for(machine_type)

	if recipes.is_empty():
		var none := Label.new()
		none.text = "No recipes available."
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rows.add_child(none)
		return

	for recipe in recipes:
		rows.add_child(_make_recipe_row(recipe))

# Builds a single recipe row: output, inputs, brew time, and a Brew button.
func _make_recipe_row(recipe: Recipe) -> Control:
	var panel := PanelContainer.new()
	Flat.apply(panel, 12, 16)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var affordable := CraftingSystem.can_craft(recipe)
	# Opportunity, not punishment: affordable recipes read bright, the rest dim but
	# still legible (so the player can plan toward them).
	box.modulate = Color(1, 1, 1) if affordable else Color(0.7, 0.7, 0.7)

	# Line 1: "Molten Mocha x1" + a green "Ready" badge when it can be brewed now.
	var out_item := Inventory.get_item(recipe.output_id)
	var out_name := out_item.display_name if out_item else String(recipe.output_id)
	var header := Label.new()
	if affordable:
		header.text = "%s x%d    ✓ Ready" % [out_name, recipe.output_count]
		header.modulate = Color(0.6, 1.0, 0.6)
	else:
		header.text = "%s x%d" % [out_name, recipe.output_count]
	box.add_child(header)

	# Line 2: the inputs ("Lava Ash x2, Lava Vial x1"), resolved to display names.
	var inputs_label := Label.new()
	inputs_label.text = "Needs: %s" % _format_inputs(recipe)
	inputs_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(inputs_label)

	# Line 2b: when unaffordable, spell out the first thing they're short on.
	if not affordable:
		var short_label := Label.new()
		short_label.text = _shortfall_text(recipe)
		short_label.add_theme_font_size_override("font_size", 12)
		short_label.modulate = Color(0.95, 0.6, 0.6)
		box.add_child(short_label)

	# Line 3: how long it takes.
	var time_label := Label.new()
	time_label.text = "Brew time: %d min" % recipe.brew_minutes
	box.add_child(time_label)

	# Line 4: the Brew button, only usable if we can afford the inputs.
	var brew_btn := Button.new()
	brew_btn.text = "Brew"
	brew_btn.disabled = not affordable
	# bind() passes the recipe id along to the handler when the button is pressed.
	brew_btn.pressed.connect(_on_brew_pressed.bind(recipe.id))
	box.add_child(brew_btn)

	return panel

# The first unmet ingredient as a friendly "Need N more <item>" hint, for recipe
# rows the player can't afford yet.
func _shortfall_text(recipe: Recipe) -> String:
	for ingredient: RecipeIngredient in recipe.inputs:
		var have: int = Inventory.count_of(ingredient.item_id)
		if have < ingredient.count:
			var item := Inventory.get_item(ingredient.item_id)
			var item_name := item.display_name if item else String(ingredient.item_id)
			return "Need %d more %s" % [ingredient.count - have, item_name]
	return "Need more materials"

# Turns a recipe's input list into "Lava Ash x2, Lava Vial x1".
func _format_inputs(recipe: Recipe) -> String:
	var parts: PackedStringArray = []
	for ingredient in recipe.inputs:
		var item := Inventory.get_item(ingredient.item_id)
		var item_name := item.display_name if item else String(ingredient.item_id)
		parts.append("%s x%d" % [item_name, ingredient.count])
	return ", ".join(parts)

# BREWING: recipe name + a live progress bar + an approximate "ready in N min".
func _build_brewing() -> void:
	var recipe := CraftingSystem.get_machine_recipe(_machine_id)
	var recipe_name := recipe.display_name if recipe else "Brewing"

	var name_label := Label.new()
	name_label.text = "Brewing: %s" % recipe_name
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(name_label)

	# Named "Progress" so _process can find and poll it for live updates.
	var bar := ProgressBar.new()
	bar.name = "Progress"
	bar.min_value = 0.0
	bar.max_value = 1.0
	bar.value = CraftingSystem.get_progress(_machine_id)
	rows.add_child(bar)

	# Named "ReadyIn" so _process can refresh the remaining-time estimate.
	var ready_label := Label.new()
	ready_label.name = "ReadyIn"
	ready_label.text = _ready_in_text()
	ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(ready_label)

# Approximate game-minutes left on the current brew, as a friendly label.
func _ready_in_text() -> String:
	var recipe := CraftingSystem.get_machine_recipe(_machine_id)
	if recipe == null:
		return ""
	var remaining := int(round((1.0 - CraftingSystem.get_progress(_machine_id)) * recipe.brew_minutes))
	remaining = max(remaining, 0)
	return "Ready in ~%d min" % remaining

# DONE: announce the output and offer a Collect button.
func _build_done() -> void:
	var recipe := CraftingSystem.get_machine_recipe(_machine_id)
	var out_name := "drink"
	if recipe != null:
		var out_item := Inventory.get_item(recipe.output_id)
		out_name = out_item.display_name if out_item else String(recipe.output_id)

	var ready_label := Label.new()
	ready_label.text = "Ready: %s" % out_name
	ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(ready_label)

	var collect_btn := Button.new()
	collect_btn.text = "Collect"
	collect_btn.pressed.connect(_on_collect_pressed)
	rows.add_child(collect_btn)

# --- Button handlers -------------------------------------------------------

func _on_brew_pressed(recipe_id: StringName) -> void:
	# start_brew handles the IDLE/can_craft checks and emits machine_changed,
	# which rebuilds us into the BREWING view.
	CraftingSystem.start_brew(_machine_id, recipe_id)

func _on_collect_pressed() -> void:
	# collect adds the output and resets the machine; machine_changed rebuilds us
	# back into the IDLE view.
	CraftingSystem.collect(_machine_id)
