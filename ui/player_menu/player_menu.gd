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

const Glass = preload("res://ui/glass_style.gd")

signal opened
signal closed

enum Tab { INVENTORY, SKILLS, CRAFTING, QUESTS, MAP }
const TAB_NAMES := ["Inventory", "Skills", "Crafting", "Quests", "Map"]
const BRANCH_TITLES := { 0: "Melee", 1: "Ranged", 2: "Survival" }

## GameState flag key for the accessibility font scale (set in the pause Settings panel).
## Every font_size override below is routed through _fs() so this menu rescales on open.
const FONT_SCALE_FLAG: StringName = &"ui_font_scale"

## GameState flag key for the discovered-areas record that powers the Map tab legend.
## A { scene_path -> {title, color:[r,g,b]} } dictionary, grown each time this menu opens
## (it stamps the area the player is currently standing in). Persisted via the flag API.
const DISCOVERED_FLAG: StringName = &"discovered_stages"

## GameState flag key for the player-chosen HUD-tracked quest id (read by quest_tracker.gd).
## When set to an active quest id, that quest is the one shown in the always-on HUD panel;
## an empty value falls back to the tracker's tier auto-pick.
const TRACKED_QUEST_FLAG: StringName = &"tracked_quest"

## Quest tier ids (mirror Quest.Tier: MAIN=0, SIDE=1, TASK=2) used by the Quests tab.
const Q_TIER_MAIN: int = 0
const Q_TIER_SIDE: int = 1
const Q_TIER_TASK: int = 2
## Section header colour for the Quests tab — a dark slate, distinct from body text.
const Q_HEADER_COLOR: Color = Color(0.16, 0.2, 0.3, 1)
## Amber tint for timed TASK titles + their countdown, so timed work stands out.
const Q_TASK_COLOR: Color = Color(0.72, 0.42, 0.04, 1)
## Per-tier badge colours (indexed by tier id) for the [MAIN]/[SIDE]/[TASK] tag.
const Q_BADGE_COLORS: Array = [
	Color(0.58, 0.36, 0.02, 1),   # MAIN - dark gold
	Color(0.16, 0.20, 0.30, 1),   # SIDE - slate
	Color(0.72, 0.42, 0.04, 1),   # TASK - amber
]
const Q_BADGE_LABELS: Array = ["[MAIN]", "[SIDE]", "[TASK]"]

## Townsfolk shown in the Inventory tab's reputation readout, as {id, name} pairs.
## TUNABLE: this is purely a read-only tier display (via Reputation.get_tier_name) — add
## an NPC here once it's placed in the world and its standing will surface automatically.
const DISPLAYED_NPCS: Array = [
	{"id": &"marlo", "name": "Marlo"},
	{"id": &"sela", "name": "Sela"},
	{"id": &"ember", "name": "Ember"},
	{"id": &"gus", "name": "Gus"},
	{"id": &"mira", "name": "Mira"},
	{"id": &"pip", "name": "Pip"},
]

var is_open: bool = false
var _tab: int = Tab.INVENTORY

## Inventory category filter: -1 = All, otherwise an Item.Category value. Persists
## across live rebuilds so re-filtering survives an item_changed refresh.
var _inventory_category_filter: int = -1

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
	# Live-refresh the Quests tab whenever the quest picture changes. Guarded with
	# has_signal so a missing/old QuestSystem signal can't break boot.
	var qs = get_node_or_null("/root/QuestSystem")
	if qs != null:
		for sig in ["quest_started", "quest_updated", "quest_completed",
				"quest_stage_advanced", "task_offered", "task_expired", "quest_failed"]:
			if qs.has_signal(sig):
				qs.connect(sig, _on_data_changed_void)

# --- Input -----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	# Open shortcuts (also toggle/close if already on that tab).
	if not is_open:
		if event.is_action_pressed("inventory") and not Dialogue.is_active and not _other_blocking():
			open(Tab.INVENTORY); get_viewport().set_input_as_handled()
		elif event.is_action_pressed("skill_tree") and not Dialogue.is_active and not _other_blocking():
			open(Tab.SKILLS); get_viewport().set_input_as_handled()
		elif event.is_action_pressed("quest_log") and not Dialogue.is_active and not _other_blocking():
			open(Tab.QUESTS); get_viewport().set_input_as_handled()
		return
	# While open:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause") or event.is_action_pressed("inventory") or event.is_action_pressed("quest_log"):
		close(); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("hotbar_next"):
		_cycle_tab(1); get_viewport().set_input_as_handled()
	elif event.is_action_pressed("hotbar_prev"):
		_cycle_tab(-1); get_viewport().set_input_as_handled()

func _other_blocking() -> bool:
	var pm = get_node_or_null("/root/PauseMenu")
	if pm != null and ("is_open" in pm) and pm.is_open:
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
	_record_current_stage()  # stamp the area the player is in so the Map legend fills in
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
	# Full-screen frosted-glass backdrop (no black) that also eats clicks behind the menu.
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	Glass.frost(_dim)
	add_child(_dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(900, 560)
	Glass.apply(panel, 18, 22)
	center.add_child(panel)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	panel.add_child(root)

	var title := Label.new()
	title.text = "Menu"
	title.add_theme_font_size_override("font_size", _fs(30))
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
	hint.add_theme_font_size_override("font_size", _fs(12))
	hint.modulate = Color(0.7, 0.7, 0.7)
	root.add_child(hint)

	# Content area (rebuilt per tab).
	_content = PanelContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Glass.apply(_content, 14, 18)
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
		Tab.QUESTS: body = _build_quests()
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

	# Category filter tabs (All + every Item.Category). Toggle buttons that re-filter
	# the grid without touching any data — purely a view convenience.
	v.add_child(_build_category_filter())

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
		var shown := 0
		for id in keys:
			if _inventory_category_filter != -1:
				var it: Item = Inventory.get_item(id)
				if it == null or int(it.category) != _inventory_category_filter:
					continue
			grid.add_child(_make_inv_slot(id, contents[id]))
			shown += 1
		if shown == 0:
			var none := Label.new()
			none.text = "No items in this category."
			none.modulate = Color(0.7, 0.7, 0.7)
			grid.add_child(none)
	v.add_child(scroll)

	# Discoverability hint for the assign paths (mouse drag + keyboard/controller).
	var hint := Label.new()
	hint.text = "Drag an item onto a hotbar slot below  •  or select an item and press 1-8  (A: first free slot)"
	hint.add_theme_font_size_override("font_size", _fs(12))
	hint.modulate = Color(0.7, 0.7, 0.7)
	v.add_child(hint)

	# Read-only standing with the townsfolk — reinforces that reputation is tracked and
	# worth tending. Built from Reputation.get_tier_name; safe if that autoload is absent.
	v.add_child(_build_reputation_strip())

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

# A row of toggle buttons: All + one per Item.Category. The pressed one matches the
# stored filter so the selection survives live rebuilds.
func _build_category_filter() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var all_btn := Button.new()
	all_btn.text = "All"
	all_btn.toggle_mode = true
	all_btn.button_pressed = (_inventory_category_filter == -1)
	all_btn.pressed.connect(_on_inventory_filter.bind(-1))
	row.add_child(all_btn)

	var cat_names: Array = Item.Category.keys()
	var cat_values: Array = Item.Category.values()
	for ci in cat_values.size():
		var cval: int = int(cat_values[ci])
		var cb := Button.new()
		cb.text = String(cat_names[ci]).capitalize()
		cb.toggle_mode = true
		cb.button_pressed = (_inventory_category_filter == cval)
		cb.pressed.connect(_on_inventory_filter.bind(cval))
		row.add_child(cb)
	return row

# A compact, colour-coded "Townsfolk Reputation" readout (one tier label per NPC in
# DISPLAYED_NPCS). Purely informational — flows across lines so it never blows out the
# tab width. Degrades to just its header when the Reputation autoload isn't registered.
func _build_reputation_strip() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var head := Label.new()
	head.text = "Townsfolk Reputation"
	head.add_theme_font_size_override("font_size", _fs(13))
	head.modulate = Color(0.9, 0.85, 0.5)
	box.add_child(head)

	var rep = get_node_or_null("/root/Reputation")
	if rep == null:
		return box

	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 16)
	flow.add_theme_constant_override("v_separation", 2)
	for npc in DISPLAYED_NPCS:
		var npc_id: StringName = npc["id"]
		var lbl := Label.new()
		lbl.text = "%s: %s" % [String(npc["name"]), rep.get_tier_name(npc_id)]
		lbl.add_theme_font_size_override("font_size", _fs(12))
		lbl.modulate = _tier_color(int(rep.get_tier(npc_id)))
		flow.add_child(lbl)
	box.add_child(flow)
	return box

func _on_inventory_filter(category: int) -> void:
	_inventory_category_filter = category
	# Always rebuild (even re-selecting the active tab) so the toggle buttons' pressed
	# state is restored — clicking an already-on toggle would otherwise flip it off.
	if is_open and _tab == Tab.INVENTORY:
		_rebuild()

func _make_inv_slot(id: StringName, count: int) -> Control:
	var slot := InventorySlot.new()
	slot.setup(id, count)
	# Quest-item badge: if an active quest currently needs this item, ring the slot
	# amber so the player knows not to sell/use it. Added after setup() so the slot's
	# own _build() (which clears children) doesn't wipe it.
	if _is_quest_item(id):
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.9, 0.7, 0.2, 0.10)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.9, 0.7, 0.2)
		sb.set_corner_radius_all(6)
		slot.add_theme_stylebox_override("panel", sb)
	return slot

# True if any ACTIVE quest's current-stage objective is a COLLECT_ITEM pointing at
# this item id. Guarded so it's safe even if QuestSystem isn't registered.
func _is_quest_item(id: StringName) -> bool:
	var qs = get_node_or_null("/root/QuestSystem")
	if qs == null:
		return false
	for quest in qs.get_active_quests():
		if quest == null:
			continue
		var objectives: Array = qs.get_current_objectives(quest.id)
		for obj in objectives:
			if obj != null and obj.kind == QuestObjective.Kind.COLLECT_ITEM and obj.target == id:
				return true
	return false

# --- Tab: Skills -----------------------------------------------------------

func _build_skills() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	var lvl := Label.new()
	lvl.text = "Level %d" % Progression.get_level()
	lvl.add_theme_font_size_override("font_size", _fs(20))
	header.add_child(lvl)
	var pts := Label.new()
	pts.text = "Points: %d" % Progression.get_points()
	pts.add_theme_font_size_override("font_size", _fs(20))
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
	h.add_theme_font_size_override("font_size", _fs(22))
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
	desc.add_theme_font_size_override("font_size", _fs(12))
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
		head.add_theme_font_size_override("font_size", _fs(20))
		head.modulate = Color(0.9, 0.85, 0.5)
		v.add_child(head)
		for r in recipes:
			var line := Label.new()
			line.text = "  %s:  %s  →  %s x%d   (%s)" % [
				r.display_name, _inputs_text(r), _item_name(r.output_id), r.output_count,
				("instant" if r.instant else "%d min" % r.brew_minutes)]
			line.add_theme_font_size_override("font_size", _fs(14))
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

# --- Tab: Quests -----------------------------------------------------------

# The quest journal, ported from the old standalone QuestLog overlay into a scrollable
# tab. Active quests are GROUPED by tier (Main / Side / Tasks); multi-stage quests show
# "Stage X/Y" + only the current stage's objectives; timed TASK quests show an amber
# countdown. Each entry carries a Track/Tracked button that picks the HUD-featured quest.
func _build_quests() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "Quest Journal"
	title.add_theme_font_size_override("font_size", _fs(22))
	v.add_child(title)

	var qs = get_node_or_null("/root/QuestSystem")
	if qs == null:
		var miss := Label.new()
		miss.text = "Quests are unavailable."
		miss.modulate = Color(0.7, 0.7, 0.7)
		v.add_child(miss)
		return v

	# Scrollable list — mirrors the Skills/Map tab scroll pattern so long journals never
	# clip off the top/bottom the way the old fixed-size overlay did.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var main_quests: Array = qs.get_active_by_tier(Q_TIER_MAIN)
	var side_quests: Array = qs.get_active_by_tier(Q_TIER_SIDE)
	var tasks: Array = qs.get_active_by_tier(Q_TIER_TASK)

	if main_quests.is_empty() and side_quests.is_empty() and tasks.is_empty():
		var empty := Label.new()
		empty.text = "No active quests. Talk to the townsfolk to find work."
		empty.modulate = Color(0.7, 0.7, 0.7)
		empty.add_theme_font_size_override("font_size", _fs(15))
		list.add_child(empty)
	else:
		_add_quest_section(qs, list, "Main Quests", main_quests, Q_TIER_MAIN)
		_add_quest_section(qs, list, "Side Quests", side_quests, Q_TIER_SIDE)
		_add_quest_section(qs, list, "Tasks", tasks, Q_TIER_TASK)

	v.add_child(scroll)
	return v

# Adds a tier header + its quest entries, but only if the tier has any quests.
func _add_quest_section(qs, list: VBoxContainer, header: String, quests: Array, tier: int) -> void:
	if quests.is_empty():
		return
	var label := Label.new()
	label.text = header
	label.add_theme_font_size_override("font_size", _fs(18))
	label.add_theme_color_override("font_color", Q_HEADER_COLOR)
	list.add_child(label)
	for quest in quests:
		list.add_child(_make_quest_entry(qs, quest, tier))

# Builds one quest block: a tier badge + title (amber for timed tasks), an optional
# amber "time-sensitive" tag, an optional stage line, an optional countdown, the
# description, then one line per CURRENT-stage objective, then a Track button.
func _make_quest_entry(qs, quest, tier: int) -> Control:
	var is_task: bool = tier == Q_TIER_TASK
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	box.add_child(title_row)

	var badge_index: int = clampi(tier, 0, Q_BADGE_LABELS.size() - 1)
	var badge := Label.new()
	badge.text = Q_BADGE_LABELS[badge_index]
	badge.add_theme_color_override("font_color", Q_BADGE_COLORS[badge_index])
	badge.add_theme_font_size_override("font_size", _fs(13))
	title_row.add_child(badge)

	var title := Label.new()
	title.text = quest.title
	title.add_theme_font_size_override("font_size", _fs(15))
	if is_task:
		title.add_theme_color_override("font_color", Q_TASK_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	# Track / Tracked toggle: writes the player's HUD-featured choice to GameState.
	title_row.add_child(_make_track_button(quest.id))

	# A standalone amber "time-sensitive" tag for any quest currently on a deadline.
	if qs.get_task_minutes_remaining(quest.id) >= 0:
		var urgent := Label.new()
		urgent.text = "[TIME-SENSITIVE]"
		urgent.add_theme_color_override("font_color", Q_TASK_COLOR)
		urgent.add_theme_font_size_override("font_size", _fs(13))
		box.add_child(urgent)

	# Multi-stage quests: show progress through the stages + the current stage's name.
	var stage_count: int = qs.get_stage_count(quest.id)
	if stage_count > 1:
		var stage_index: int = qs.get_current_stage_index(quest.id)
		var stage = qs.get_current_stage(quest.id)
		var stage_title: String = ""
		if stage != null:
			stage_title = stage.title
		var stage_line := Label.new()
		stage_line.text = "Stage %d/%d: %s" % [stage_index + 1, stage_count, stage_title]
		stage_line.add_theme_font_size_override("font_size", _fs(13))
		box.add_child(stage_line)

	# Timed tasks: a "time left" countdown in amber. >= 0 means it's still ticking.
	if is_task:
		var remaining: int = qs.get_task_minutes_remaining(quest.id)
		if remaining >= 0:
			var clock := Label.new()
			clock.text = "time left: %s" % _format_quest_minutes(remaining)
			clock.add_theme_color_override("font_color", Q_TASK_COLOR)
			clock.add_theme_font_size_override("font_size", _fs(13))
			box.add_child(clock)

	var desc := Label.new()
	desc.text = quest.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", _fs(13))
	box.add_child(desc)

	# Only the CURRENT stage's objectives, with their live progress.
	var objectives: Array = qs.get_current_objectives(quest.id)
	var progress: Array = qs.get_objective_progress(quest.id)
	for i in objectives.size():
		var objective = objectives[i]
		var current: int = int(progress[i]) if i < progress.size() else 0
		box.add_child(_make_objective_line(objective, current, i == 0))

	return box

# The Track button for a quest entry. Reads the stored tracked id; when this quest is the
# tracked one it shows "Tracked" and is highlighted, otherwise "Track".
func _make_track_button(id: StringName) -> Button:
	var btn := Button.new()
	var tracked: bool = _tracked_quest_id() == id
	btn.text = "Tracked" if tracked else "Track"
	btn.toggle_mode = true
	btn.button_pressed = tracked
	btn.custom_minimum_size = Vector2(90, 0)
	btn.add_theme_font_size_override("font_size", _fs(13))
	btn.pressed.connect(_on_track_quest.bind(id))
	return btn

# The currently HUD-tracked quest id (empty StringName when none is chosen).
func _tracked_quest_id() -> StringName:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return &""
	return gs.get_flag(TRACKED_QUEST_FLAG, &"")

# Player chose this quest as the HUD-featured one. Toggling the already-tracked quest
# clears the choice (reverting the HUD to its tier auto-pick). Persisted via GameState.
func _on_track_quest(id: StringName) -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	if _tracked_quest_id() == id:
		gs.set_flag(TRACKED_QUEST_FLAG, &"")
	else:
		gs.set_flag(TRACKED_QUEST_FLAG, id)
	_rebuild()

# One objective line. COLLECT shows "(cur/req)" counts; REACH_FLAG just reads done /
# not-done. `primary` (the stage's first objective) renders larger as the next step.
func _make_objective_line(objective, current: int, primary: bool = false) -> Label:
	var line := Label.new()
	if objective.kind == QuestObjective.Kind.REACH_FLAG:
		if current >= 1:
			line.text = "[x] %s" % objective.description
		else:
			line.text = "[ ] %s" % objective.description
	else:
		var required: int = objective.required_count
		if current >= required:
			line.text = "[x] %s" % objective.description
		else:
			line.text = "[ ] %s (%d/%d)" % [objective.description, current, required]
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.add_theme_font_size_override("font_size", _fs(16) if primary else _fs(13))
	return line

# Formats a span of GAME minutes as "1h 20m" (or "45m" when under an hour).
func _format_quest_minutes(total: int) -> String:
	var hours: int = total / 60
	var minutes: int = total % 60
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	return "%dm" % minutes

# --- Tab: Map (discovered-area legend) -------------------------------------

# A read-only legend of the areas the player has actually set foot in (recorded on every
# menu open). Each row is a biome-coloured marker + the area name. No teleport, no map
# image — it just educates the player on where they've been and hints there's more.
func _build_map() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)

	var title := Label.new()
	title.text = "Discovered Areas"
	title.add_theme_font_size_override("font_size", _fs(22))
	v.add_child(title)

	var discovered: Dictionary = {}
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		var raw = gs.get_flag(DISCOVERED_FLAG, {})
		if raw is Dictionary:
			discovered = raw

	if discovered.is_empty():
		var hint := Label.new()
		hint.text = "Explore to build the map."
		hint.modulate = Color(0.7, 0.7, 0.7)
		hint.add_theme_font_size_override("font_size", _fs(16))
		v.add_child(hint)
		return v

	# Cap the height so a long list scrolls inside the tab rather than stretching it.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	# Sort by display title so the legend reads stably regardless of visit order.
	var entries: Array = discovered.values()
	entries.sort_custom(func(a, b): return _entry_title(a) < _entry_title(b))
	for entry in entries:
		list.add_child(_make_map_row(entry))
	v.add_child(scroll)

	var more := Label.new()
	more.text = "(more to discover)"
	more.modulate = Color(0.65, 0.65, 0.65)
	more.add_theme_font_size_override("font_size", _fs(13))
	v.add_child(more)
	return v

func _entry_title(entry) -> String:
	if entry is Dictionary and entry.has("title"):
		return String(entry["title"])
	return ""

func _make_map_row(entry) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var swatch := ColorRect.new()
	swatch.custom_minimum_size = Vector2(18, 18)
	swatch.color = _entry_color(entry)
	row.add_child(swatch)

	var lbl := Label.new()
	lbl.text = _entry_title(entry) if _entry_title(entry) != "" else "Unknown Area"
	lbl.add_theme_font_size_override("font_size", _fs(16))
	row.add_child(lbl)
	return row

# Rebuild a Color from the stored [r,g,b] float array (defaults to grey if malformed).
func _entry_color(entry) -> Color:
	if entry is Dictionary and entry.has("color"):
		var ca = entry["color"]
		if ca is Array and (ca as Array).size() >= 3:
			return Color(float(ca[0]), float(ca[1]), float(ca[2]))
	return Color(0.7, 0.7, 0.7)

# --- Live refresh ----------------------------------------------------------

func _on_data_changed(_id: StringName, _n: int) -> void:
	if is_open:
		_rebuild()

# Connected to several signals with DIFFERENT argument counts: Progression.skills_changed
# (0 args) and the QuestSystem quest_* / task_* signals (which emit a quest id, and
# quest_stage_advanced an extra index). Godot 4 rejects a 0-arg callable bound to a signal
# that emits args, so we accept up to three optional args and ignore them — we always just
# rebuild the open menu regardless of which signal fired.
func _on_data_changed_void(_a = null, _b = null, _c = null) -> void:
	if is_open:
		_rebuild()

func _on_xp_changed(_xp: int, _level: int, _to_next: int) -> void:
	if is_open and _tab == Tab.SKILLS:
		_rebuild()

# --- Helpers ---------------------------------------------------------------

func _item_name(id: StringName) -> String:
	var item: Item = Inventory.get_item(id)
	return item.display_name if item != null else String(id)

# --- Accessibility font scale ----------------------------------------------

# The stored UI font multiplier (1.0 when unset / GameState missing), clamped to a sane
# band so a corrupt flag can't make text vanish or explode.
func _font_scale() -> float:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return 1.0
	var raw = gs.get_flag(FONT_SCALE_FLAG, 1.0)
	return clampf(float(raw), 0.7, 1.6)

# Scale a base font size by the stored UI text-size setting. Used in place of literal
# sizes on every font_size override so the whole menu honours the accessibility option.
func _fs(base: int) -> int:
	return int(round(base * _font_scale()))

# --- Map discovery ---------------------------------------------------------

# Record the area the player is currently in into the persisted discovered-areas set, so
# the Map tab can show a legend of where they've been. Reads the current scene's optional
# `area_title` (and `ground_color` as the marker tint); falls back to a humanised scene
# name so town/dungeons still register. Read-only w.r.t. gameplay — just a breadcrumb.
func _record_current_stage() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	var scene := get_tree().current_scene
	if scene == null:
		return
	var title := ""
	if "area_title" in scene:
		title = String(scene.area_title).strip_edges()
	if title == "":
		title = String(scene.name).capitalize()
	var col := Color(0.7, 0.7, 0.7)
	if "ground_color" in scene:
		col = scene.ground_color
	var key := scene.scene_file_path
	if key == "":
		key = String(scene.name)
	var raw = gs.get_flag(DISCOVERED_FLAG, {})
	var discovered: Dictionary = (raw as Dictionary).duplicate() if raw is Dictionary else {}
	# Store the colour as a plain float array so it survives any save serializer.
	discovered[key] = {"title": title, "color": [col.r, col.g, col.b]}
	gs.set_flag(DISCOVERED_FLAG, discovered)

# Tier -> colour for the reputation readout. Integer literals match Reputation.Tier
# (HOSTILE..BELOVED), whose order is append-only, so they stay aligned.
func _tier_color(tier: int) -> Color:
	match tier:
		0: return Color(0.9, 0.4, 0.4)    # HOSTILE
		1: return Color(0.85, 0.6, 0.4)   # DISLIKED
		2: return Color(0.8, 0.8, 0.8)    # NEUTRAL
		3: return Color(0.55, 0.85, 0.55) # FRIENDLY
		_: return Color(0.5, 0.8, 1.0)    # BELOVED
