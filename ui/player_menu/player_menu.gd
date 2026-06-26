# player_menu.gd
# Autoload singleton (register as "PlayerMenu"). The unified, controller-first menu:
# one window with TABS — Inventory, Skills, Crafting (recipe book), Map. Quick keys jump
# straight to a tab (the inventory key opens Inventory; the skills key opens Skills), the
# shoulder buttons (LB/RB, reusing hotbar_prev/next) cycle tabs, A/click activates, and
# B / Esc (ui_cancel) closes. It replaces the old standalone inventory & skill-tree popups.
#
# Built in code (the .tscn is just a CanvasLayer with this script). Each tab's content is
# rebuilt from the data autoloads (Inventory, Progression, CraftingSystem) so it's always
# current; while open it live-refreshes on their change signals.
#
# Controller focus: on open / tab change we grab focus on the first interactive control in
# the tab (or the Close button), so a gamepad always has a selection and d-pad navigation
# just works via Godot's built-in focus system.

extends CanvasLayer

signal opened
signal closed

enum Tab { INVENTORY, SKILLS, CRAFTING, MAP }
const TAB_NAMES := ["Inventory", "Skills", "Crafting", "Map"]
const BRANCH_TITLES := { 0: "Melee", 1: "Ranged", 2: "Survival" }

var is_open: bool = false
var _tab: int = Tab.INVENTORY

var _dim: ColorRect
var _tab_bar: HBoxContainer
var _content: PanelContainer
var _close_btn: Button
var _tab_buttons: Array[Button] = []

func _ready() -> void:
	layer = 13  # above HUD, below the pause menu (20)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("exclusive_menu")  # so opening another menu closes this one
	_build_shell()
	hide()
	Inventory.item_changed.connect(_on_data_changed)
	Progression.skills_changed.connect(_on_data_changed_void)
	Progression.xp_changed.connect(_on_xp_changed)

# --- Input -----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Open shortcuts (also toggle/close if already on that tab).
	if not is_open:
		if event.is_action_pressed("inventory") and not Dialogue.is_active and not _other_blocking():
			open(Tab.INVENTORY); get_viewport().set_input_as_handled()
		elif event.is_action_pressed("skill_tree") and not Dialogue.is_active and not _other_blocking():
			open(Tab.SKILLS); get_viewport().set_input_as_handled()
		return
	# While open:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") or event.is_action_pressed("inventory"):
		close(); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("hotbar_next"):
		_cycle_tab(1); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("hotbar_prev"):
		_cycle_tab(-1); get_viewport().set_input_as_handled()

func _other_blocking() -> bool:
	var pm = get_node_or_null("/root/PauseMenu")
	if pm != null and ("is_paused" in pm) and pm.is_paused:
		return true
	return false

# --- Open / close ----------------------------------------------------------

func open(tab: int = Tab.INVENTORY) -> void:
	if is_open:
		_select_tab(tab)
		return
	MenuManager.opening(self)  # close any other open menu first (no stacking)
	is_open = true
	_tab = tab
	show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_rebuild()
	opened.emit()

func close() -> void:
	if not is_open:
		return
	is_open = false
	hide()
	closed.emit()

func _cycle_tab(dir: int) -> void:
	_select_tab((_tab + dir + TAB_NAMES.size()) % TAB_NAMES.size())

func _select_tab(tab: int) -> void:
	_tab = tab
	_rebuild()

# --- Shell -----------------------------------------------------------------

func _build_shell() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.7)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 560)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var title := Label.new()
	title.text = "Menu"
	title.add_theme_font_size_override("font_size", 30)
	root.add_child(title)

	# Tab bar.
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 6)
	root.add_child(_tab_bar)
	for i in TAB_NAMES.size():
		var b := Button.new()
		b.text = TAB_NAMES[i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(150, 40)
		b.pressed.connect(_select_tab.bind(i))
		_tab_bar.add_child(b)
		_tab_buttons.append(b)

	var hint := Label.new()
	hint.text = "LB / RB or click to switch tabs    •    B / Esc to close"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.7, 0.7, 0.7)
	root.add_child(hint)

	# Content area (rebuilt per tab).
	_content = PanelContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_content)

	_close_btn = Button.new()
	_close_btn.text = "Close"
	_close_btn.custom_minimum_size = Vector2(0, 40)
	_close_btn.pressed.connect(close)
	root.add_child(_close_btn)

# --- Rebuild active tab ----------------------------------------------------

func _rebuild() -> void:
	for c in _content.get_children():
		c.queue_free()
	# Tab button highlight.
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = (i == _tab)

	var body: Control = null
	match _tab:
		Tab.INVENTORY: body = _build_inventory()
		Tab.SKILLS: body = _build_skills()
		Tab.CRAFTING: body = _build_recipe_book()
		_: body = _build_map()
	if body != null:
		_content.add_child(body)

	# Put controller focus somewhere sensible in the new tab.
	_grab_first_focus.call_deferred()

func _grab_first_focus() -> void:
	if not is_open:
		return
	var first := _first_focusable(_content)
	if first != null:
		first.grab_focus()
	elif _tab < _tab_buttons.size():
		_tab_buttons[_tab].grab_focus()

func _first_focusable(node: Node) -> Control:
	for c in node.get_children():
		if c is Control:
			var ctl := c as Control
			var ok: bool = ctl.focus_mode == Control.FOCUS_ALL and ctl.visible
			if ctl is Button and (ctl as Button).disabled:
				ok = false
			if ok:
				return ctl
		var deeper := _first_focusable(c)
		if deeper != null:
			return deeper
	return null

# --- Tab: Inventory --------------------------------------------------------

func _build_inventory() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)
	var contents: Dictionary = Inventory.get_all()
	if contents.is_empty():
		var empty := Label.new()
		empty.text = "Your bag is empty."
		grid.add_child(empty)
	else:
		var keys := contents.keys()
		keys.sort()
		for id in keys:
			grid.add_child(_make_inv_slot(id, contents[id]))
	v.add_child(scroll)

	# Discoverability hint for the assign paths (mouse drag + keyboard/controller).
	var hint := Label.new()
	hint.text = "Drag an item onto a hotbar slot below  •  or select an item and press 1-8  (A: first free slot)"
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.7, 0.7, 0.7)
	v.add_child(hint)

	# A live hotbar row that doubles as the drag-and-drop target for assignment.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in Hotbar.SLOT_COUNT:
		var drop := HotbarDropSlot.new()
		row.add_child(drop)
		drop.setup(i)
	v.add_child(row)
	return v

func _make_inv_slot(id: StringName, count: int) -> Control:
	var slot := InventorySlot.new()
	slot.setup(id, count)
	return slot

# --- Tab: Skills -----------------------------------------------------------

func _build_skills() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	var lvl := Label.new()
	lvl.text = "Level %d" % Progression.get_level()
	lvl.add_theme_font_size_override("font_size", 20)
	header.add_child(lvl)
	var pts := Label.new()
	pts.text = "Points: %d" % Progression.get_points()
	pts.add_theme_font_size_override("font_size", 20)
	header.add_child(pts)
	var xp := Label.new()
	var lvl_now: int = Progression.get_level()
	xp.text = "%d / %d XP" % [Progression.get_xp(), Progression.xp_to_next(lvl_now)]
	header.add_child(xp)
	v.add_child(header)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for branch in [0, 1, 2]:
		cols.add_child(_build_branch_col(branch))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(cols)
	v.add_child(scroll)
	return v

func _build_branch_col(branch: int) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(260, 0)
	col.add_theme_constant_override("separation", 6)
	var h := Label.new()
	h.text = String(BRANCH_TITLES.get(branch, "Branch"))
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	h.add_theme_font_size_override("font_size", 22)
	col.add_child(h)
	for skill in Progression.get_skills_in_branch(branch):
		col.add_child(_build_skill_row(skill))
	return col

func _build_skill_row(skill) -> Control:
	var rank: int = Progression.get_rank(skill.id)
	var maxed: bool = rank >= skill.max_rank
	var affordable: bool = Progression.can_allocate(skill.id)
	var box := VBoxContainer.new()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)
	var nm := Label.new()
	var tag: String = "  [Perk]" if skill.is_perk else ""
	nm.text = "%s (%d/%d)%s" % [skill.display_name, rank, skill.max_rank, tag]
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(nm)
	var plus := Button.new()
	plus.text = "MAX" if maxed else "+"
	plus.custom_minimum_size = Vector2(48, 0)
	plus.disabled = maxed or not affordable
	plus.pressed.connect(_on_allocate.bind(skill.id))
	top.add_child(plus)
	var desc := Label.new()
	desc.text = skill.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 12)
	if not maxed and not affordable and rank == 0:
		desc.modulate = Color(0.7, 0.7, 0.7)
	box.add_child(desc)
	return box

func _on_allocate(skill_id: StringName) -> void:
	if Progression.allocate(skill_id):
		_rebuild()

# --- Tab: Crafting (recipe book) -------------------------------------------

func _build_recipe_book() -> Control:
	var scroll := ScrollContainer.new()
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	scroll.add_child(v)
	var station_names := {
		Recipe.MachineType.SMELTER: "Smelter",
		Recipe.MachineType.WORKBENCH: "Workbench",
		Recipe.MachineType.COOKING: "Cooking Station",
		Recipe.MachineType.BREWER: "Bar Mixing Station",
	}
	for station in [Recipe.MachineType.SMELTER, Recipe.MachineType.WORKBENCH, Recipe.MachineType.COOKING, Recipe.MachineType.BREWER]:
		var recipes: Array[Recipe] = CraftingSystem.get_recipes_for(station)
		if recipes.is_empty():
			continue
		var head := Label.new()
		head.text = String(station_names.get(station, "Station"))
		head.add_theme_font_size_override("font_size", 20)
		head.modulate = Color(0.9, 0.85, 0.5)
		v.add_child(head)
		for r in recipes:
			var line := Label.new()
			line.text = "  %s:  %s  →  %s x%d   (%s)" % [
				r.display_name, _inputs_text(r), _item_name(r.output_id), r.output_count,
				("instant" if r.instant else "%d min" % r.brew_minutes)]
			line.add_theme_font_size_override("font_size", 14)
			v.add_child(line)
	if v.get_child_count() == 0:
		var none := Label.new()
		none.text = "No recipes known yet."
		v.add_child(none)
	return scroll

func _inputs_text(r: Recipe) -> String:
	var parts: Array[String] = []
	for ing in r.inputs:
		parts.append("%s x%d" % [_item_name(ing.item_id), ing.count])
	return ", ".join(parts)

# --- Tab: Map (placeholder) ------------------------------------------------

func _build_map() -> Control:
	var c := CenterContainer.new()
	var l := Label.new()
	l.text = "Map — coming soon."
	l.add_theme_font_size_override("font_size", 22)
	l.modulate = Color(0.7, 0.7, 0.7)
	c.add_child(l)
	return c

# --- Live refresh ----------------------------------------------------------

func _on_data_changed(_id: StringName, _n: int) -> void:
	if is_open:
		_rebuild()

func _on_data_changed_void() -> void:
	if is_open:
		_rebuild()

func _on_xp_changed(_xp: int, _level: int, _to_next: int) -> void:
	if is_open and _tab == Tab.SKILLS:
		_rebuild()

# --- Helpers ---------------------------------------------------------------

func _item_name(id: StringName) -> String:
	var item: Item = Inventory.get_item(id)
	return item.display_name if item != null else String(id)
