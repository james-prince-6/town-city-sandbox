# player_menu.gd
# Autoload singleton (register as "PlayerMenu"). The unified, controller-first menu:
# one Window with TABS — Inventory, Skills, Crafting (recipe book), Quests, Reputation,
# Map. Quick keys jump straight to a tab (the inventory key opens Inventory; the skills
# key opens Skills; the quest key opens Quests), the shoulder buttons (LB/RB, reusing
# hotbar_prev/next) cycle tabs, A/click activates, and B / Esc (ui_cancel) closes.
#
# Built in code (the .tscn is just a CanvasLayer with this script) in the Town City
# sticker style: a centred cream Window over an ink-wash backdrop, a header with the
# title + Esc button, a row of TabButtons, a swappable content area, and a hint line.
# Each tab's content is rebuilt from the data autoloads (Inventory, Progression,
# CraftingSystem, QuestSystem, Reputation) so it's always current; while open it
# live-refreshes on their change signals.
#
# Controller focus: on open / tab change we grab focus on the first interactive control
# in the tab (or the Close button), so a gamepad always has a selection.

extends CanvasLayer

signal opened
signal closed

enum Tab { INVENTORY, SKILLS, CRAFTING, QUESTS, REPUTATION, MAP }
const TAB_NAMES := ["Inventory", "Skills", "Crafting", "Quests", "Reputation", "Map"]

## GameState flag key for the accessibility font scale (set in the pause Settings panel).
const FONT_SCALE_FLAG: StringName = &"ui_font_scale"
## GameState flag key for the discovered-areas record that powers the Map tab legend.
const DISCOVERED_FLAG: StringName = &"discovered_stages"
## GameState flag key for the player-chosen HUD-tracked quest id (read by quest_tracker.gd).
## Empty = auto-pick the top quest; TRACK_NONE = explicitly hide the side tracker;
## any other value = that quest id is featured on the HUD.
const TRACKED_QUEST_FLAG: StringName = &"tracked_quest"
const TRACK_NONE: StringName = &"__none__"

## Quest tier ids (mirror Quest.Tier: MAIN=0, SIDE=1, TASK=2) used by the Quests tab.
const Q_TIER_MAIN: int = 0
const Q_TIER_SIDE: int = 1
const Q_TIER_TASK: int = 2
## Amber tint for timed TASK titles + their countdown, so timed work stands out.
const Q_TASK_COLOR: Color = Color(0.72, 0.42, 0.04, 1)
## Per-tier badge colours (indexed by tier id) for the [MAIN]/[SIDE]/[TASK] tag.
const Q_BADGE_COLORS: Array = [
	Color(0.58, 0.36, 0.02, 1),   # MAIN - dark gold
	Color(0.16, 0.20, 0.30, 1),   # SIDE - slate
	Color(0.72, 0.42, 0.04, 1),   # TASK - amber
]
const Q_BADGE_LABELS: Array = ["[MAIN]", "[SIDE]", "[TASK]"]

## Townsfolk shown in the Reputation tab, as {id, name} pairs.
const DISPLAYED_NPCS: Array = [
	{"id": &"orbo", "name": "Mayor Orbo"},
	{"id": &"george", "name": "George"},
	{"id": &"barry", "name": "Barry"},
	{"id": &"kippie", "name": "Kippie"},
	{"id": &"droghnaut", "name": "Droghnaut"},
	{"id": &"sally", "name": "Sally"},
]

## Item-card colour schemes (design _pal table): per category [card, thumb, selCard],
## plus scheme-level ab-chip + name text colours. B (Muted) is the default.
const PAL := {
	"A": {"ab": Color("f6f1e7"), "name": Color("1b150f"),
		"Weapons": [Color("df6f3c"), Color("c25e30"), Color("f0824a")],
		"Consumables": [Color("57a065"), Color("478554"), Color("6bbd79")],
		"Materials": [Color("4f9ed6"), Color("4187bd"), Color("66b4ea")],
		"Quest": [Color("d2a233"), Color("b88b27"), Color("e8b948")],
		"Junk": [Color("8f8576"), Color("79705f"), Color("a89d8c")]},
	"B": {"ab": Color("3a3226"), "name": Color("2a2218"),
		"Weapons": [Color("cf9279"), Color("b87d63"), Color("dda88f")],
		"Consumables": [Color("8fb89a"), Color("789f83"), Color("a6cbae")],
		"Materials": [Color("93b2cc"), Color("7c9bb6"), Color("a9c6df")],
		"Quest": [Color("cdba88"), Color("b6a374"), Color("ddca98")],
		"Junk": [Color("b1a796"), Color("988e7d"), Color("c3b9a8")]},
	"C": {"ab": Color("f6f1e7"), "name": Color("6a655c"),
		"Weapons": [Color("e7e1d4"), Color("df6f3c"), Color("fbf8f0")],
		"Consumables": [Color("e7e1d4"), Color("57a065"), Color("fbf8f0")],
		"Materials": [Color("e7e1d4"), Color("4f9ed6"), Color("fbf8f0")],
		"Quest": [Color("e7e1d4"), Color("d2a233"), Color("fbf8f0")],
		"Junk": [Color("e7e1d4"), Color("8f8576"), Color("fbf8f0")]},
}
## Category filter pills (design buckets). Our Item.Category enum maps onto these.
const CAT_FILTERS := ["All", "Weapons", "Consumables", "Materials", "Quest", "Junk"]
const SCHEMES := [["A", "Vivid"], ["B", "Muted"], ["C", "Tint"]]

const INK := Color(0.055, 0.051, 0.071)
const CREAM := Color(0.906, 0.882, 0.831)
const BRIGHT := Color(0.984, 0.973, 0.941)
const DIM := Color(0.416, 0.396, 0.361)
const TEXT := Color(0.133, 0.122, 0.102)

var is_open: bool = false
var _tab: int = Tab.INVENTORY

## Inventory category filter: a CAT_FILTERS bucket name ("All" = no filter). Persists
## across live rebuilds so re-filtering survives an item_changed refresh.
var _inventory_category_filter: String = "All"
## Active item-card colour scheme key (A/B/C); Muted (B) by default.
var _scheme: String = "B"
## Info line at the bottom of the Inventory tab (focused item name + category).
var _inv_info: Label = null
## The quest currently featured on the HUD tracker (recomputed each Quests-tab build),
## so the per-quest Track buttons render the right "Track"/"Tracked" state.
var _featured_id: StringName = &""

var _backdrop: ColorRect
var _tab_bar: HBoxContainer
var _content: MarginContainer
var _close_btn: Button
var _tab_buttons: Array[Button] = []

func _ready() -> void:
	layer = 13  # above HUD, below the pause menu (20)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("exclusive_menu")  # so opening another menu closes this one
	_build_shell()
	visible = false
	Inventory.item_changed.connect(_on_data_changed)
	Progression.skills_changed.connect(_on_data_changed_void)
	Progression.xp_changed.connect(_on_xp_changed)
	var qs = get_node_or_null("/root/QuestSystem")
	if qs != null:
		for sig in ["quest_started", "quest_updated", "quest_completed",
				"quest_stage_advanced", "task_offered", "task_expired", "quest_failed"]:
			if qs.has_signal(sig):
				qs.connect(sig, _on_data_changed_void)

# --- Input -----------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if not is_open:
		if event.is_action_pressed("inventory") and not Dialogue.is_active and not _other_blocking():
			open(Tab.INVENTORY); get_viewport().set_input_as_handled()
		elif event.is_action_pressed("skill_tree") and not Dialogue.is_active and not _other_blocking():
			open(Tab.SKILLS); get_viewport().set_input_as_handled()
		elif event.is_action_pressed("quest_log") and not Dialogue.is_active and not _other_blocking():
			open(Tab.QUESTS); get_viewport().set_input_as_handled()
		return
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
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_rebuild()
	opened.emit()

func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	closed.emit()

func _cycle_tab(dir: int) -> void:
	_select_tab((_tab + dir + TAB_NAMES.size()) % TAB_NAMES.size())

func _select_tab(tab: int) -> void:
	_tab = tab
	_rebuild()

# --- Shell (Town City Window) ----------------------------------------------

func _build_shell() -> void:
	# Ink-wash backdrop that also eats clicks behind the menu (no black, no blur).
	_backdrop = ColorRect.new()
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.color = Color(0.055, 0.051, 0.071, 0.55)
	add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.add_child(center)

	var window := PanelContainer.new()
	window.theme_type_variation = &"MenuWindow"
	window.custom_minimum_size = Vector2(900, 560)
	center.add_child(window)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	window.add_child(vbox)

	# Header: title (left, expanding) + Esc close button (right).
	var header := HBoxContainer.new()
	vbox.add_child(header)
	var title := Label.new()
	title.text = "Menu"
	title.theme_type_variation = &"Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_close_btn = Button.new()
	_close_btn.text = "Esc"
	_close_btn.focus_mode = Control.FOCUS_ALL
	_close_btn.pressed.connect(close)
	header.add_child(_close_btn)

	# Tab bar: six equal-width TabButtons.
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 6)
	vbox.add_child(_tab_bar)
	for i in TAB_NAMES.size():
		var b := Button.new()
		b.text = TAB_NAMES[i]
		b.toggle_mode = true
		b.theme_type_variation = &"TabButton"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(_select_tab.bind(i))
		_tab_bar.add_child(b)
		_tab_buttons.append(b)

	# Content area (rebuilt per tab) — fills the remaining height.
	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("margin_top", 2)
	vbox.add_child(_content)

	# Hint line.
	var hint := Label.new()
	hint.theme_type_variation = &"Dim"
	hint.add_theme_font_size_override("font_size", _fs(12))
	hint.text = "LB / RB or click — switch tabs   ·   1–8 assign to hotbar   ·   Esc to close"
	vbox.add_child(hint)

# --- Rebuild active tab ----------------------------------------------------

func _rebuild() -> void:
	for c in _content.get_children():
		c.queue_free()
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = (i == _tab)

	var body: Control = null
	match _tab:
		Tab.INVENTORY: body = _build_inventory()
		Tab.SKILLS: body = _build_skills()
		Tab.CRAFTING: body = _build_recipe_book()
		Tab.QUESTS: body = _build_quests()
		Tab.REPUTATION: body = _build_reputation()
		_: body = _build_map()
	if body != null:
		body.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_content.add_child(body)

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

# A repeating list-row card (sticker tile) wrapping arbitrary content.
func _card(child: Control) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	card.add_child(child)
	return card

# A vertical scroll area that fills the tab.
func _scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return s

# --- Tab: Inventory --------------------------------------------------------

func _build_inventory() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)

	# Category filter pills (All + the 5 design buckets).
	v.add_child(_build_category_filter())

	# 6-column grid of category-coloured item tiles.
	var scroll := _scroll()
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	var contents: Dictionary = Inventory.get_all()
	if contents.is_empty():
		grid.add_child(_dim_label("Your bag is empty."))
	else:
		var keys := contents.keys()
		keys.sort()
		var shown := 0
		for id in keys:
			var it: Item = Inventory.get_item(id)
			var bucket := _bucket_for(id, it)
			if _inventory_category_filter != "All" and bucket != _inventory_category_filter:
				continue
			grid.add_child(_make_inv_slot(id, contents[id], it, bucket))
			shown += 1
		if shown == 0:
			grid.add_child(_dim_label("No items in this category."))
	v.add_child(scroll)

	# Focused-item info line.
	_inv_info = Label.new()
	_inv_info.theme_type_variation = &"Dim"
	_inv_info.add_theme_font_size_override("font_size", _fs(13))
	_inv_info.text = "Select an item to assign it to your hotbar."
	v.add_child(_inv_info)

	# Hotbar row: label + the ink bar of drop cells.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var lbl := Label.new()
	lbl.text = "HOTBAR"
	lbl.theme_type_variation = &"Subtitle"
	lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lbl)
	var bar := PanelContainer.new()
	bar.theme_type_variation = &"HotbarOuter"
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cells := HBoxContainer.new()
	cells.add_theme_constant_override("separation", 3)
	cells.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in Hotbar.SLOT_COUNT:
		var drop := HotbarDropSlot.new()
		cells.add_child(drop)
		drop.setup(i)
	bar.add_child(cells)
	row.add_child(bar)
	v.add_child(row)

	# Bottom bar: BOX COLORS scheme switcher.
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	var box_lbl := Label.new()
	box_lbl.text = "BOX COLORS"
	box_lbl.theme_type_variation = &"Dim"
	box_lbl.add_theme_font_size_override("font_size", _fs(11))
	box_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(box_lbl)
	for s in SCHEMES:
		bottom.add_child(_pill(s[1], _scheme == s[0], _on_scheme.bind(s[0])))
	v.add_child(bottom)
	return v

# A pill-shaped toggle (rounded 999) used by the category filter + scheme switcher.
func _pill(text: String, selected: bool, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = selected
	b.focus_mode = Control.FOCUS_ALL
	b.theme_type_variation = &"Display"  # Chakra Petch
	b.add_theme_font_size_override("font_size", _fs(12))
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = BRIGHT if (st in ["pressed", "focus", "hover"] or selected) else CREAM
		sb.set_border_width_all(3)
		sb.border_color = INK
		sb.set_corner_radius_all(999)
		sb.content_margin_left = 11.0
		sb.content_margin_right = 11.0
		sb.content_margin_top = 4.0
		sb.content_margin_bottom = 4.0
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_color_override("font_color", TEXT if selected else DIM)
	b.add_theme_color_override("font_hover_color", TEXT)
	b.add_theme_color_override("font_pressed_color", TEXT)
	b.add_theme_color_override("font_focus_color", TEXT)
	b.pressed.connect(on_press)
	return b

# A row of filter pills: All + the 5 design buckets.
func _build_category_filter() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for bucket in CAT_FILTERS:
		row.add_child(_pill(bucket, _inventory_category_filter == bucket, _on_inventory_filter.bind(bucket)))
	return row

func _on_inventory_filter(bucket: String) -> void:
	_inventory_category_filter = bucket
	if is_open and _tab == Tab.INVENTORY:
		_rebuild()

func _on_scheme(key: String) -> void:
	_scheme = key
	if is_open and _tab == Tab.INVENTORY:
		_rebuild()

# Map our Item.Category enum onto the design's 5 colour buckets. Active quest items
# are surfaced in the Quest bucket regardless of their raw category.
func _bucket_for(id: StringName, item: Item) -> String:
	if _is_quest_item(id):
		return "Quest"
	if item == null:
		return "Junk"
	match int(item.category):
		Item.Category.WEAPON, Item.Category.TOOL:
			return "Weapons"
		Item.Category.CONSUMABLE, Item.Category.DRINK, Item.Category.FOOD:
			return "Consumables"
		Item.Category.INGREDIENT, Item.Category.MATERIAL:
			return "Materials"
		_:
			return "Junk"

func _slot_colors(bucket: String) -> Dictionary:
	var sc: Dictionary = PAL[_scheme]
	var arr: Array = sc.get(bucket, [CREAM, Color("d6cdba"), BRIGHT])
	return {"card": arr[0], "thumb": arr[1], "sel": arr[2], "ab": sc["ab"], "name": sc["name"]}

func _make_inv_slot(id: StringName, count: int, item: Item, bucket: String) -> Control:
	var slot := InventorySlot.new()
	slot.setup(id, count, _slot_colors(bucket))
	var label := item.display_name if item != null else String(id)
	slot.focus_entered.connect(func() -> void:
		if is_instance_valid(_inv_info):
			_inv_info.text = "%s   ·   %s" % [label, bucket])
	return slot

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

# --- Tab: Reputation -------------------------------------------------------

func _build_reputation() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(_title_label("Townsfolk Reputation"))

	var rep = get_node_or_null("/root/Reputation")
	if rep == null:
		v.add_child(_dim_label("Reputation is unavailable."))
		return v

	var scroll := _scroll()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for npc in DISPLAYED_NPCS:
		list.add_child(_card(_make_reputation_row(rep, npc)))
	v.add_child(scroll)
	return v

func _make_reputation_row(rep, npc: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var name_lbl := Label.new()
	name_lbl.text = String(npc["name"])
	name_lbl.theme_type_variation = &"Subtitle"
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	var npc_id: StringName = npc["id"]
	var score_text := ""
	if rep.has_method("get_reputation"):
		score_text = "  (%d)" % int(rep.get_reputation(npc_id))
	var tier_lbl := Label.new()
	tier_lbl.text = "%s%s" % [rep.get_tier_name(npc_id), score_text]
	tier_lbl.add_theme_font_size_override("font_size", _fs(16))
	tier_lbl.modulate = _tier_color(int(rep.get_tier(npc_id)))
	row.add_child(tier_lbl)
	return row

# --- Tab: Skills -----------------------------------------------------------

func _build_skills() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	var lvl := Label.new()
	lvl.text = "Character Level %d" % Progression.get_level()
	lvl.theme_type_variation = &"Subtitle"
	header.add_child(lvl)
	var hint := _dim_label("Skills rise as you USE them — spend each skill's perk points on its perks.")
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(hint)
	v.add_child(header)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 14)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for branch in Progression.SKILLS:
		cols.add_child(_build_skill_column(branch))
	var scroll := _scroll()
	scroll.add_child(cols)
	v.add_child(scroll)
	return v

func _build_skill_column(branch: int) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(210, 0)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)

	var head := Label.new()
	head.text = "%s — Lv %d" % [Progression.skill_display_name(branch), Progression.get_skill_level(branch)]
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.theme_type_variation = &"Subtitle"
	col.add_child(head)

	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 12)
	bar.max_value = maxf(1.0, Progression.get_skill_xp_to_next(branch))
	bar.value = Progression.get_skill_xp(branch)
	col.add_child(bar)

	var bonus := Label.new()
	bonus.text = _skill_bonus_text(branch)
	bonus.theme_type_variation = &"DisplayGold"
	bonus.add_theme_font_size_override("font_size", _fs(12))
	bonus.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(bonus)

	var pts := Label.new()
	pts.text = "Perk points: %d" % Progression.get_perk_points(branch)
	pts.add_theme_font_size_override("font_size", _fs(13))
	col.add_child(pts)

	for perk in Progression.get_perks_in_branch(branch):
		col.add_child(_build_skill_row(perk))
	return col

func _skill_bonus_text(branch: int) -> String:
	match branch:
		Progression.SKILL_MELEE:
			return "+%d%% melee damage" % int(round((Progression.melee_damage_mult() - 1.0) * 100.0))
		Progression.SKILL_RANGED:
			return "+%d%% ranged damage, faster draw" % int(round((Progression.ranged_damage_mult() - 1.0) * 100.0))
		Progression.SKILL_MAGIC:
			return "+%d%% spell damage, faster cast" % int(round((Progression.magic_damage_mult() - 1.0) * 100.0))
		Progression.SKILL_SURVIVAL:
			return "+%d max HP, %d%% resist" % [int(round(Progression.bonus_max_health())), int(round(Progression.damage_reduction() * 100.0))]
	return ""

func _build_skill_row(perk) -> Control:
	var rank: int = Progression.get_rank(perk.id)
	var maxed: bool = rank >= perk.max_rank
	var affordable: bool = Progression.can_allocate(perk.id)
	var box := VBoxContainer.new()
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)
	var nm := Label.new()
	nm.text = "%s (%d/%d)" % [perk.display_name, rank, perk.max_rank]
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.add_theme_font_size_override("font_size", _fs(13))
	top.add_child(nm)
	var plus := Button.new()
	plus.text = "MAX" if maxed else ("%d pt" % perk.cost)
	plus.custom_minimum_size = Vector2(54, 0)
	plus.disabled = maxed or not affordable
	plus.add_theme_font_size_override("font_size", _fs(12))
	plus.pressed.connect(_on_allocate.bind(perk.id))
	top.add_child(plus)
	var desc := Label.new()
	desc.text = perk.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", _fs(11))
	if not maxed and not affordable and rank == 0:
		desc.modulate = Color(0.7, 0.7, 0.7)
		var need_lvl: int = perk.required_level
		if Progression.get_skill_level(int(perk.branch)) < need_lvl:
			desc.text = "[Requires %s Lv %d]  %s" % [Progression.skill_display_name(int(perk.branch)), need_lvl, perk.description]
	box.add_child(desc)
	return box

func _on_allocate(skill_id: StringName) -> void:
	if Progression.allocate(skill_id):
		_rebuild()

# --- Tab: Crafting (recipe book) -------------------------------------------

func _build_recipe_book() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(_title_label("Recipe Book"))

	var scroll := _scroll()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 8)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
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
		head.theme_type_variation = &"Subtitle"
		list.add_child(head)
		for r in recipes:
			var line := Label.new()
			line.text = "%s:  %s  →  %s x%d   (%s)" % [
				r.display_name, _inputs_text(r), _item_name(r.output_id), r.output_count,
				("instant" if r.instant else "%d min" % r.brew_minutes)]
			line.add_theme_font_size_override("font_size", _fs(14))
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list.add_child(_card(line))
	if list.get_child_count() == 0:
		list.add_child(_dim_label("No recipes known yet."))
	v.add_child(scroll)
	return v

func _inputs_text(r: Recipe) -> String:
	var parts: Array[String] = []
	for ing in r.inputs:
		parts.append("%s x%d" % [_item_name(ing.item_id), ing.count])
	return ", ".join(parts)

# --- Tab: Quests -----------------------------------------------------------

func _build_quests() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(_title_label("Quest Journal"))

	var qs = get_node_or_null("/root/QuestSystem")
	if qs == null:
		v.add_child(_dim_label("Quests are unavailable."))
		return v

	# Which quest is currently FEATURED on the HUD side tracker (the one whose Track
	# button should read "Tracked"). Computed once per rebuild for all the entries.
	_featured_id = _featured_quest_id(qs)

	var scroll := _scroll()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 10)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var main_quests: Array = qs.get_active_by_tier(Q_TIER_MAIN)
	var side_quests: Array = qs.get_active_by_tier(Q_TIER_SIDE)
	var tasks: Array = qs.get_active_by_tier(Q_TIER_TASK)

	if main_quests.is_empty() and side_quests.is_empty() and tasks.is_empty():
		list.add_child(_dim_label("No active quests. Talk to the townsfolk to find work."))
	else:
		_add_quest_section(qs, list, "Main Quests", main_quests, Q_TIER_MAIN)
		_add_quest_section(qs, list, "Side Quests", side_quests, Q_TIER_SIDE)
		_add_quest_section(qs, list, "Tasks", tasks, Q_TIER_TASK)

	v.add_child(scroll)
	return v

func _add_quest_section(qs, list: VBoxContainer, header: String, quests: Array, tier: int) -> void:
	if quests.is_empty():
		return
	var label := Label.new()
	label.text = header
	label.theme_type_variation = &"Subtitle"
	list.add_child(label)
	for quest in quests:
		list.add_child(_card(_make_quest_entry(qs, quest, tier)))

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
	title.theme_type_variation = &"Subtitle"
	if is_task:
		title.add_theme_color_override("font_color", Q_TASK_COLOR)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	title_row.add_child(_make_track_button(quest.id))

	if qs.get_task_minutes_remaining(quest.id) >= 0:
		var urgent := Label.new()
		urgent.text = "[TIME-SENSITIVE]"
		urgent.add_theme_color_override("font_color", Q_TASK_COLOR)
		urgent.add_theme_font_size_override("font_size", _fs(13))
		box.add_child(urgent)

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

	var objectives: Array = qs.get_current_objectives(quest.id)
	var progress: Array = qs.get_objective_progress(quest.id)
	for i in objectives.size():
		var objective = objectives[i]
		var current: int = int(progress[i]) if i < progress.size() else 0
		box.add_child(_make_objective_line(objective, current, i == 0))

	return box

func _make_track_button(id: StringName) -> Button:
	var btn := Button.new()
	# "Tracked" (gold) when this quest is the one shown on the HUD side bar, else "Track".
	var tracked: bool = _featured_id == id
	btn.text = "Tracked" if tracked else "Track"
	btn.toggle_mode = true
	btn.button_pressed = tracked
	if tracked:
		btn.theme_type_variation = &"ButtonPrimary"
	btn.custom_minimum_size = Vector2(96, 0)
	btn.add_theme_font_size_override("font_size", _fs(13))
	btn.tooltip_text = "Stop tracking on the HUD" if tracked else "Track this quest on the HUD"
	btn.pressed.connect(_on_track_quest.bind(id))
	return btn

# The quest the HUD tracker currently features: the explicit pick if set + active,
# else the auto-picked top quest (Main → Side → Task). Empty if the bar is hidden /
# nothing active. Mirrors quest_tracker.gd::_pick_quest so the menu stays in sync.
func _featured_quest_id(qs) -> StringName:
	var gs = get_node_or_null("/root/GameState")
	var tid: StringName = &""
	if gs != null:
		tid = gs.get_flag(TRACKED_QUEST_FLAG, &"")
	if tid == TRACK_NONE:
		return &""  # player explicitly hid the bar
	if tid != &"" and qs.has_method("is_active") and qs.is_active(tid):
		return tid
	# Auto-pick fallback: highest tier first, first active in that tier.
	for tier in [Q_TIER_MAIN, Q_TIER_SIDE, Q_TIER_TASK]:
		var arr: Array = qs.get_active_by_tier(tier)
		if arr != null and not arr.is_empty():
			return arr[0].id
	return &""

# Toggle the HUD-tracked quest. Clicking the currently-featured quest UNTRACKS it
# (hides the side bar); clicking any other quest TRACKS it (features it on the bar).
# Writing the GameState flag fires flag_changed, so the tracker updates live.
func _on_track_quest(id: StringName) -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	if _featured_id == id:
		gs.set_flag(TRACKED_QUEST_FLAG, TRACK_NONE)
	else:
		gs.set_flag(TRACKED_QUEST_FLAG, id)
	_rebuild()

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

func _format_quest_minutes(total: int) -> String:
	var hours: int = total / 60
	var minutes: int = total % 60
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	return "%dm" % minutes

# --- Tab: Map (discovered-area legend) -------------------------------------

func _build_map() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.add_child(_title_label("Discovered Areas"))

	var discovered: Dictionary = {}
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		var raw = gs.get_flag(DISCOVERED_FLAG, {})
		if raw is Dictionary:
			discovered = raw

	if discovered.is_empty():
		v.add_child(_dim_label("Explore to build the map."))
		return v

	var scroll := _scroll()
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var entries: Array = discovered.values()
	entries.sort_custom(func(a, b): return _entry_title(a) < _entry_title(b))
	for entry in entries:
		list.add_child(_card(_make_map_row(entry)))
	v.add_child(scroll)

	v.add_child(_dim_label("(more to discover)"))
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
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.color = _entry_color(entry)
	row.add_child(swatch)

	var lbl := Label.new()
	lbl.text = _entry_title(entry) if _entry_title(entry) != "" else "Unknown Area"
	lbl.theme_type_variation = &"Subtitle"
	row.add_child(lbl)
	return row

func _entry_color(entry) -> Color:
	if entry is Dictionary and entry.has("color"):
		var ca = entry["color"]
		if ca is Array and (ca as Array).size() >= 3:
			return Color(float(ca[0]), float(ca[1]), float(ca[2]))
	return Color(0.7, 0.7, 0.7)

# --- Shared small builders -------------------------------------------------

func _title_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Title"
	return l

func _dim_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"Dim"
	l.add_theme_font_size_override("font_size", _fs(14))
	return l

# --- Live refresh ----------------------------------------------------------

func _on_data_changed(_id: StringName, _n: int) -> void:
	if is_open:
		_rebuild()

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

func _font_scale() -> float:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return 1.0
	var raw = gs.get_flag(FONT_SCALE_FLAG, 1.0)
	return clampf(float(raw), 0.7, 1.6)

func _fs(base: int) -> int:
	return int(round(base * _font_scale()))

# --- Map discovery ---------------------------------------------------------

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
	discovered[key] = {"title": title, "color": [col.r, col.g, col.b]}
	gs.set_flag(DISCOVERED_FLAG, discovered)

func _tier_color(tier: int) -> Color:
	match tier:
		0: return Color(0.9, 0.4, 0.4)    # HOSTILE
		1: return Color(0.85, 0.6, 0.4)   # DISLIKED
		2: return Color(0.8, 0.8, 0.8)    # NEUTRAL
		3: return Color(0.55, 0.85, 0.55) # FRIENDLY
		_: return Color(0.5, 0.8, 1.0)    # BELOVED
