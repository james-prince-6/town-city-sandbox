# crafting_ui.gd
# Autoload singleton (register as "CraftingUI"). The ONE drag-to-fill crafting menu used
# by every station type (smelter / workbench / cooking / bar). It's a pure view over
# CraftingSystem + Inventory: pick a recipe on the left, fill its input slots in the
# middle by dragging items from your bag on the right (or hit Auto-fill), then Craft.
#
# Instant recipes (workbench) craft on the spot; timed recipes (smelter/cooking/bar)
# start a job on the station that you collect when it finishes — so the same menu also
# shows a progress bar / collect button when you open a busy station.
#
# Built entirely in code (no hand-authored .tscn beyond the bare root) so the layout is
# self-contained and easy to verify. Drag uses two small inner Control classes.
#
# Pause behaviour mirrors the other menus: it emits `opened`/`closed`; the player listens
# to free the mouse and stop moving.

extends CanvasLayer

const Flat = preload("res://ui/ui_style.gd")

signal opened
signal closed

# --- Bound station (set by open_for) ---------------------------------------
var _station: Node = null
var _machine_id: StringName = &""
var _machine_type: int = 0
var _title: String = "Crafting"

# Currently selected recipe + which input slots the player has filled.
var _selected: Recipe = null
var _slot_filled: Array[bool] = []

# --- Built widgets ---------------------------------------------------------
var _dim: ColorRect
var _window: PanelContainer
var _header: Label
var _recipe_list: VBoxContainer
var _slots_row: HBoxContainer
var _output_label: Label
var _status_label: Label
var _progress: ProgressBar
var _craft_button: Button
var _autofill_button: Button
var _collect_button: Button
var _inv_grid: GridContainer
var _close_button: Button

const STATION_NAMES := {
	Recipe.MachineType.BREWER: "Bar",
	Recipe.MachineType.SMELTER: "Smelter",
	Recipe.MachineType.WORKBENCH: "Workbench",
	Recipe.MachineType.COOKING: "Cooking Station",
}

## GameState flag key for the accessibility font scale (set in the pause Settings panel).
## Every font_size override here is routed through _fs() so this menu honours the setting.
const FONT_SCALE_FLAG: StringName = &"ui_font_scale"

## Optional recipe-rarity tints. A recipe MAY define a `rarity` (int index into this list,
## or a matching name string); when present it colours the recipe row instead of the plain
## ready/unavailable colours. Entirely additive — recipes without a rarity are unaffected.
## TUNABLE: reorder/recolour freely (string lookup is case-insensitive).
const RARITY_COLORS: Array = [
	{"name": "common", "color": Color(0.85, 0.85, 0.85)},
	{"name": "uncommon", "color": Color(0.55, 0.9, 0.55)},
	{"name": "rare", "color": Color(0.5, 0.7, 1.0)},
	{"name": "epic", "color": Color(0.78, 0.55, 0.95)},
	{"name": "legendary", "color": Color(0.98, 0.78, 0.35)},
]

# ===========================================================================
#  A draggable inventory item (drag SOURCE).
# ===========================================================================
class DragItem extends Button:
	var item_id: StringName
	func _get_drag_data(_at: Vector2) -> Variant:
		var preview := Label.new()
		preview.text = text
		set_drag_preview(preview)
		return {"craft_item": item_id}

# ===========================================================================
#  A recipe input slot (drop TARGET). Accepts only the matching item id.
# ===========================================================================
class DropSlot extends PanelContainer:
	var required_id: StringName
	var on_filled: Callable
	func _can_drop_data(_at: Vector2, data: Variant) -> bool:
		return typeof(data) == TYPE_DICTIONARY and data.has("craft_item") and data["craft_item"] == required_id
	func _drop_data(_at: Vector2, _data: Variant) -> void:
		if on_filled.is_valid():
			on_filled.call()

# ===========================================================================
func _ready() -> void:
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("exclusive_menu")  # so opening another menu closes this one
	_build_ui()
	hide()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("inventory") or event.is_action_pressed("interact") or event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# --- Public API ------------------------------------------------------------

## Open the menu bound to a CraftingStation (reads machine_id / machine_type / name).
func open_for(station: Node) -> void:
	_station = station
	_machine_id = station.machine_id
	_machine_type = station.machine_type
	_title = station.display_name
	_selected = null
	MenuManager.opening(self)  # close any other open menu first (no stacking)
	show()
	# Guard the connects: open_for re-entered while already open would otherwise throw
	# "signal already connected" (close() disconnects, but re-open without a close can't).
	if not Inventory.item_changed.is_connected(_on_inventory_changed):
		Inventory.item_changed.connect(_on_inventory_changed)
	if not CraftingSystem.machine_changed.is_connected(_on_machine_changed):
		CraftingSystem.machine_changed.connect(_on_machine_changed)
	_refresh()
	opened.emit()

func close() -> void:
	if not visible:
		return
	hide()
	if Inventory.item_changed.is_connected(_on_inventory_changed):
		Inventory.item_changed.disconnect(_on_inventory_changed)
	if CraftingSystem.machine_changed.is_connected(_on_machine_changed):
		CraftingSystem.machine_changed.disconnect(_on_machine_changed)
	closed.emit()

# --- Controller focus ------------------------------------------------------

# Ensure the controller always has something selected after a (re)build. Picks the
# Collect button when shown, else the first recipe button, else the Craft button,
# else Close. Skips if focus is already somewhere inside this menu so navigation
# isn't yanked back to the top on every live refresh.
func _grab_initial_focus() -> void:
	if not visible:
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null and is_ancestor_of(focus_owner):
		return
	var target := _first_focus_target()
	if target != null:
		target.grab_focus()

func _first_focus_target() -> Control:
	if _collect_button != null and _collect_button.visible:
		return _collect_button
	for c in _recipe_list.get_children():
		if c is Button and not (c as Button).disabled:
			return c
	if _craft_button != null and _craft_button.visible:
		return _craft_button
	return _close_button

# --- Signal reactions ------------------------------------------------------

func _on_inventory_changed(_id: StringName, _n: int) -> void:
	if visible:
		_refresh()

func _on_machine_changed(changed: StringName) -> void:
	if visible and changed == _machine_id:
		_refresh()

# --- Build the static shell once -------------------------------------------

func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	Flat.frost(_dim)

	_window = PanelContainer.new()
	_window.set_anchors_preset(Control.PRESET_CENTER)
	_window.custom_minimum_size = Vector2(820, 480)
	# Center it.
	_window.anchor_left = 0.5
	_window.anchor_top = 0.5
	_window.anchor_right = 0.5
	_window.anchor_bottom = 0.5
	_window.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_window.grow_vertical = Control.GROW_DIRECTION_BOTH
	Flat.apply(_window, 18, 22)
	_dim.add_child(_window)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	_window.add_child(root)

	_header = Label.new()
	_header.add_theme_font_size_override("font_size", _fs(24))
	_header.text = "Crafting"
	root.add_child(_header)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 10)
	root.add_child(cols)

	# --- Left: recipe list ---
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(230, 0)
	cols.add_child(left)
	var left_title := Label.new()
	left_title.text = "Recipes"
	left.add_child(left_title)
	var left_scroll := ScrollContainer.new()
	left_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Recipes scroll vertically only — no stray horizontal scrollbar from row padding.
	left_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(left_scroll)
	_recipe_list = VBoxContainer.new()
	_recipe_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_scroll.add_child(_recipe_list)

	# --- Center: selected recipe detail ---
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 8)
	cols.add_child(center)
	var center_title := Label.new()
	center_title.text = "Ingredients"
	center.add_child(center_title)
	_slots_row = HBoxContainer.new()
	_slots_row.add_theme_constant_override("separation", 6)
	center.add_child(_slots_row)
	_output_label = Label.new()
	_output_label.text = ""
	center.add_child(_output_label)
	_status_label = Label.new()
	_status_label.text = ""
	center.add_child(_status_label)
	_progress = ProgressBar.new()
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.visible = false
	center.add_child(_progress)
	var btns := HBoxContainer.new()
	center.add_child(btns)
	_autofill_button = Button.new()
	_autofill_button.text = "Auto-fill"
	_autofill_button.pressed.connect(_on_autofill)
	btns.add_child(_autofill_button)
	_craft_button = Button.new()
	_craft_button.text = "Craft"
	_craft_button.pressed.connect(_on_craft)
	btns.add_child(_craft_button)
	_collect_button = Button.new()
	_collect_button.text = "Collect"
	_collect_button.visible = false
	_collect_button.pressed.connect(_on_collect)
	btns.add_child(_collect_button)
	center.add_child(_spacer())

	# --- Right: inventory (drag source) ---
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(220, 0)
	cols.add_child(right)
	var right_title := Label.new()
	right_title.text = "Your Bag"
	right.add_child(right_title)
	var inv_scroll := ScrollContainer.new()
	inv_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inv_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(inv_scroll)
	_inv_grid = GridContainer.new()
	_inv_grid.columns = 1
	_inv_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inv_scroll.add_child(_inv_grid)

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.pressed.connect(close)
	root.add_child(_close_button)

func _spacer() -> Control:
	var s := Control.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return s

# --- Refresh ---------------------------------------------------------------

func _refresh() -> void:
	_header.text = "%s  (%s)" % [_title, STATION_NAMES.get(_machine_type, "Crafting")]
	var status: int = CraftingSystem.get_status(_machine_id)

	# A timed station that is busy or finished takes over the centre panel.
	if status == CraftingSystem.Status.BREWING:
		_show_busy()
		_rebuild_recipe_list(true)
		_rebuild_inventory()
		_grab_initial_focus.call_deferred()
		return
	if status == CraftingSystem.Status.DONE:
		_show_done()
		_rebuild_recipe_list(true)
		_rebuild_inventory()
		_grab_initial_focus.call_deferred()
		return

	# IDLE: pick-and-craft.
	_progress.visible = false
	_collect_button.visible = false
	_craft_button.visible = true
	_autofill_button.visible = true
	_rebuild_recipe_list(false)
	_rebuild_inventory()
	_rebuild_slots()
	_update_craft_enabled()
	# Make sure a controller always has something selected. Deferred so the freshly
	# built buttons exist; the helper won't yank focus if it's already inside the menu.
	_grab_initial_focus.call_deferred()

func _show_busy() -> void:
	_clear(_slots_row)
	_output_label.text = ""
	_progress.visible = true
	_progress.value = CraftingSystem.get_progress(_machine_id)
	var r: Recipe = CraftingSystem.get_machine_recipe(_machine_id)
	_status_label.text = "Working on %s..." % (r.display_name if r != null else "something")
	_craft_button.visible = false
	_autofill_button.visible = false
	_collect_button.visible = false

func _show_done() -> void:
	_clear(_slots_row)
	_output_label.text = ""
	_progress.visible = false
	var r: Recipe = CraftingSystem.get_machine_recipe(_machine_id)
	_status_label.text = "Ready to collect!"
	_craft_button.visible = false
	_autofill_button.visible = false
	_collect_button.visible = true

func _rebuild_recipe_list(disabled: bool) -> void:
	_clear(_recipe_list)
	var recipes: Array[Recipe] = CraftingSystem.get_recipes_for(_machine_type)
	for r in recipes:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var affordable := CraftingSystem.can_craft(r)
		# Base tint: a recipe's optional `rarity` wins (so legendaries read special even
		# when craftable); otherwise fall back to the ready/unavailable scan colours.
		var rarity_col: Color = _rarity_color(r)
		var have_rarity: bool = rarity_col.a > 0.0
		if affordable:
			# Bright + an explicit "ready" badge so the player can scan the list and
			# instantly see what they can make right now.
			b.text = "%s    ✓ Ready" % r.display_name
			b.modulate = rarity_col if have_rarity else Color(0.7, 1.0, 0.7)
		else:
			# Opportunity, not punishment: tell them exactly what's missing instead of
			# a flat gray-out. Rarity tint is dimmed so "can't afford yet" still reads.
			b.text = "%s    %s" % [r.display_name, _shortfall_text(r)]
			b.modulate = rarity_col.darkened(0.35) if have_rarity else Color(0.62, 0.62, 0.62)
		b.disabled = disabled
		b.pressed.connect(_select_recipe.bind(r))
		_recipe_list.add_child(b)
	if recipes.is_empty():
		var none := Label.new()
		none.text = "No recipes."
		_recipe_list.add_child(none)

func _select_recipe(r: Recipe) -> void:
	_selected = r
	_slot_filled.clear()
	for _i in r.inputs.size():
		_slot_filled.append(false)
	_rebuild_slots()
	_update_craft_enabled()

func _rebuild_slots() -> void:
	_clear(_slots_row)
	if _selected == null:
		_output_label.text = "Select a recipe."
		return
	for i in _selected.inputs.size():
		var ing: RecipeIngredient = _selected.inputs[i]
		var slot := DropSlot.new()
		slot.required_id = ing.item_id
		slot.custom_minimum_size = Vector2(96, 70)
		slot.on_filled = _make_fill_cb(i)
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(box)
		var name_lbl := Label.new()
		name_lbl.text = _item_name(ing.item_id)
		name_lbl.add_theme_font_size_override("font_size", _fs(11))
		box.add_child(name_lbl)
		# Colored at-a-glance stock readout replaces the old plain "have / need" line:
		# green = enough, yellow = partial, red = none. Pure presentation off the bag.
		var have: int = Inventory.count_of(ing.item_id)
		var need: int = ing.count
		var status := Label.new()
		status.add_theme_font_size_override("font_size", _fs(11))
		if have >= need:
			status.text = "✓ Have %d/%d" % [have, need]
			status.modulate = Color(0.45, 0.9, 0.45)
		elif have > 0:
			status.text = "~ %d/%d" % [have, need]
			status.modulate = Color(0.9, 0.85, 0.4)
		else:
			status.text = "✗ 0/%d" % need
			status.modulate = Color(0.95, 0.5, 0.5)
		box.add_child(status)
		# Keep the drag-staging feedback (unchanged behaviour): shows whether this slot
		# has been filled toward the craft.
		var state := Label.new()
		state.text = "● staged" if _slot_filled[i] else "[drag here]"
		state.add_theme_font_size_override("font_size", _fs(10))
		state.modulate = Color(0.4, 0.9, 0.4) if _slot_filled[i] else Color(0.75, 0.75, 0.75)
		box.add_child(state)
		_slots_row.add_child(slot)
	var out_item := _item_name(_selected.output_id)
	_output_label.text = "→  %s x%d   (%s)" % [out_item, _selected.output_count, ("instant" if _selected.instant else "%d min" % _selected.brew_minutes)]

func _make_fill_cb(index: int) -> Callable:
	return func() -> void:
		# Only "fills" if the player actually owns the required count.
		if _selected == null or index >= _selected.inputs.size():
			return
		var ing: RecipeIngredient = _selected.inputs[index]
		if Inventory.has(ing.item_id, ing.count):
			_slot_filled[index] = true
			_rebuild_slots()
			_update_craft_enabled()

func _rebuild_inventory() -> void:
	_clear(_inv_grid)
	var all: Dictionary = Inventory.get_all()
	var keys := all.keys()
	keys.sort()
	for id in keys:
		var di := DragItem.new()
		di.item_id = id
		di.text = "%s  x%d" % [_item_name(id), all[id]]
		di.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_inv_grid.add_child(di)
	if keys.is_empty():
		var none := Label.new()
		none.text = "(empty)"
		_inv_grid.add_child(none)

func _on_autofill() -> void:
	if _selected == null:
		return
	for i in _selected.inputs.size():
		var ing: RecipeIngredient = _selected.inputs[i]
		_slot_filled[i] = Inventory.has(ing.item_id, ing.count)
	_rebuild_slots()
	_update_craft_enabled()

func _all_filled() -> bool:
	if _selected == null or _slot_filled.is_empty():
		return false
	for f in _slot_filled:
		if not f:
			return false
	return true

func _update_craft_enabled() -> void:
	_craft_button.disabled = not (_selected != null and _all_filled() and CraftingSystem.can_craft(_selected))

func _on_craft() -> void:
	if _selected == null or not _all_filled() or not CraftingSystem.can_craft(_selected):
		return
	if _selected.instant:
		CraftingSystem.craft_instant(_selected.id)
	else:
		# Timed job on this station; consumes inputs and starts the clock.
		CraftingSystem.start_brew(_machine_id, _selected.id)
	# Reset staging; _refresh redraws (busy state for timed, fresh slots for instant).
	_selected = null
	_slot_filled.clear()
	_refresh()

func _on_collect() -> void:
	CraftingSystem.collect(_machine_id)
	_refresh()

# --- Small helpers ---------------------------------------------------------

func _item_name(id: StringName) -> String:
	var item: Item = Inventory.get_item(id)
	return item.display_name if item != null else String(id)

# The first unmet ingredient as a friendly "Need N more <item>" hint (for recipe
# rows the player can't afford yet). Falls back to a generic note if nothing is
# obviously short (shouldn't happen when can_craft is false, but be safe). When the
# missing item defines an optional `item_source`, appends a " - Found: <source>" hint
# so players learn WHERE to gather the resource.
func _shortfall_text(r: Recipe) -> String:
	for ing: RecipeIngredient in r.inputs:
		var have: int = Inventory.count_of(ing.item_id)
		if have < ing.count:
			var line := "Need %d more %s" % [ing.count - have, _item_name(ing.item_id)]
			var src := _item_source(ing.item_id)
			if src != "":
				line += " - Found: %s" % src
			return line
	return "Need mats"

# Optional gather-source hint for an item. Items that define an `item_source` string
# surface it here; everything else returns "" (no hint). Safe via the `in` check, so
# this never errors on the base Item which has no such property.
func _item_source(id: StringName) -> String:
	var item: Item = Inventory.get_item(id)
	if item != null and "item_source" in item:
		return String(item.item_source).strip_edges()
	return ""

# Resolve a recipe's OPTIONAL rarity to a tint. Accepts either an int index or a name
# string (case-insensitive). Returns a fully-transparent colour (a < 0) when the recipe
# has no rarity / it doesn't resolve, which callers treat as "no rarity tint".
func _rarity_color(r: Recipe) -> Color:
	if not ("rarity" in r):
		return Color(0, 0, 0, 0)
	var raw = r.rarity
	if raw is int or raw is float:
		var idx: int = int(raw)
		if idx >= 0 and idx < RARITY_COLORS.size():
			return RARITY_COLORS[idx]["color"]
	elif raw is String or raw is StringName:
		var want := String(raw).strip_edges().to_lower()
		for entry in RARITY_COLORS:
			if String(entry["name"]).to_lower() == want:
				return entry["color"]
	return Color(0, 0, 0, 0)

# --- Accessibility font scale ----------------------------------------------

# Stored UI font multiplier (1.0 when unset / GameState missing), clamped to a sane band.
func _font_scale() -> float:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return 1.0
	var raw = gs.get_flag(FONT_SCALE_FLAG, 1.0)
	return clampf(float(raw), 0.7, 1.6)

# Scale a base font size by the stored UI text-size setting (used on every override).
func _fs(base: int) -> int:
	return int(round(base * _font_scale()))

func _clear(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()
