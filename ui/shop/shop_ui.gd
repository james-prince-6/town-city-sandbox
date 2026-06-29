# shop_ui.gd
# Autoload singleton (registered as "ShopUI", pointing at shop_ui.tscn).
#
# A BLOCKING menu that drives ONE shop at a time. Like InventoryUI / BrewingUI it
# owns no data of its own — it reads the ShopSystem (prices + what's for sale/bought),
# the Inventory (what the player holds), and GameState (the player's money), then
# redraws. Because it lives in an autoload it's available in every scene.
#
# A shopkeeper opens it by calling open_for(shop). The panel frees the mouse and
# emits `opened`; the player listens (same pattern as InventoryUI / BrewingUI) to
# stop moving. Closing emits `closed`. ui_cancel (Esc) closes it.
#
# The whole UI is built in code (the .tscn is just a bare CanvasLayer + this script,
# like pause_menu) to match the high-fidelity "Town City" shop mock: a single 920x560
# cream sticker panel with a Buy/Sell toggle, a filterable item list on the left and a
# detail/cart panel with a quantity stepper on the right.

extends CanvasLayer

## Emitted when the menu opens / closes. The player listens so it can stop moving
## and free the mouse (same pattern as InventoryUI / BrewingUI).
signal opened
signal closed

## True while the panel is showing.
var is_open: bool = false

# --- Locked palette (from the design tokens) -------------------------------
const INK := Color(0.055, 0.051, 0.071, 1.0)            # #0e0d12
const TEXT := Color(0.133, 0.122, 0.102, 1.0)           # #221f1a
const DIM := Color(0.416, 0.396, 0.361, 1.0)            # #6a655c
const CREAM := Color(0.906, 0.882, 0.831, 1.0)          # #e7e1d4
const CREAM_92 := Color(0.906, 0.882, 0.831, 0.92)      # cream @ 0.92
const BRIGHT := Color(0.984, 0.973, 0.941, 1.0)         # #fbf8f0
const DARK_CHIP := Color(0.227, 0.196, 0.149, 1.0)      # #3a3226
const TRACK := Color(0.792, 0.749, 0.675, 1.0)          # #cabfac (track / divider)
const THUMB_BG := Color(0.839, 0.804, 0.729, 1.0)       # #d6cdba
const GOLD := Color(0.784, 0.580, 0.118, 1.0)           # #c8941e
const GOLD_ON_DARK := Color(0.906, 0.851, 0.659, 1.0)   # #e7d9a8
const GOLD_DISC_TEXT := Color(0.102, 0.078, 0.027, 1.0) # #1a1407
const GREEN := Color(0.357, 0.639, 0.416, 1.0)          # #5ba36a
const RED := Color(0.937, 0.325, 0.251, 1.0)            # #ef5340
const TOTAL_LABEL := Color(0.804, 0.780, 0.729, 1.0)    # #cdc7ba

# --- Fonts -----------------------------------------------------------------
# Chakra Petch SemiBold: headings / labels / buttons / prices / numbers.
const FONT_CHAKRA := preload("res://ui/fonts/ChakraPetch-SemiBold.ttf")
# Space Grotesk ships as a VARIABLE font that imports thin; pin it to weight 700
# (mirrors the town_city_theme.tres font_body variation) for body / sub / desc.
const _SPACE_RAW := preload("res://ui/fonts/SpaceGrotesk-Bold.ttf")
var _font_body: FontVariation = null

# --- State -----------------------------------------------------------------
## The shop resource we're currently bound to.
var _shop: ShopInventory = null
## "buy" or "sell".
var _mode: String = "buy"
## Selected category pill ("All" or a display category name).
var _category: String = "All"
## Index of the highlighted row within the filtered list.
var _sel: int = 0
## Chosen transaction quantity.
var _qty: int = 1

# --- Persistent nodes ------------------------------------------------------
var _root: Control = null          # full-rect host, rebuilt content each redraw
var _toast: Label = null           # in-panel fallback toast (survives rebuilds)
var _toast_timer: SceneTreeTimer = null

# Item.Category enum int -> display string (for sub-line + pills).
const CAT_NAMES := {
	0: "Ingredients",   # INGREDIENT
	1: "Drinks",        # DRINK
	2: "Tools",         # TOOL
	3: "Materials",     # MATERIAL
	4: "Misc",          # MISC
	5: "Food",          # FOOD
	6: "Weapons",       # WEAPON
	7: "Consumables",   # CONSUMABLE
}

# ---------------------------------------------------------------------------

func _ready() -> void:
	# Draw above the world (just under the inventory's layer 10) and keep working
	# even if something pauses the tree.
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS

	_font_body = FontVariation.new()
	_font_body.base_font = _SPACE_RAW
	_font_body.variation_opentype = {2003265652: 700.0}  # 'wght' tag -> Bold

	# A full-rect host that blocks input to the world behind the panel.
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.focus_mode = Control.FOCUS_ALL  # grabbed on open so Esc/keys route here
	add_child(_root)

	# Persistent toast (in-panel fallback when NotificationFeed isn't available).
	_toast = Label.new()
	_toast.add_theme_font_override("font", FONT_CHAKRA)
	_toast.add_theme_font_size_override("font_size", 14)
	_toast.add_theme_color_override("font_color", GOLD_ON_DARK)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.position = Vector2(0, 30)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var toast_sb := _sb(DARK_CHIP, 6)
	toast_sb.content_margin_left = 18.0
	toast_sb.content_margin_right = 18.0
	toast_sb.content_margin_top = 9.0
	toast_sb.content_margin_bottom = 9.0
	_toast.add_theme_stylebox_override("normal", toast_sb)
	_toast.visible = false
	add_child(_toast)

	hide()

	# Rebuild when the bag changes (sell list + affordability) and when money
	# changes (gold counter + buy validity).
	Inventory.item_changed.connect(_on_item_changed)
	GameState.money_changed.connect(_on_money_changed)

func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var handled := true
	match (event as InputEventKey).keycode:
		KEY_Q, KEY_BRACKETLEFT:
			_set_mode("buy")
		KEY_E, KEY_BRACKETRIGHT:
			_set_mode("sell")
		KEY_UP:
			_move_selection(-1)
		KEY_DOWN:
			_move_selection(1)
		KEY_LEFT:
			_step_qty(-1)
		KEY_RIGHT:
			_step_qty(1)
		KEY_ENTER, KEY_KP_ENTER:
			_confirm()
		_:
			handled = false
	if handled:
		get_viewport().set_input_as_handled()

# --- Open / close ----------------------------------------------------------

## Bind to a shop and show the panel.
func open_for(shop: ShopInventory) -> void:
	if shop == null:
		push_warning("ShopUI.open_for: shop is null")
		return
	_shop = shop
	is_open = true
	_mode = "buy"
	_category = "All"
	_sel = 0
	_qty = 1
	_rebuild()
	show()
	# Park keyboard focus on our host so arrow/enter keys reach _unhandled_input
	# (rather than being eaten by GUI focus traversal). Deferred so it exists first.
	_grab_initial_focus.call_deferred()
	opened.emit()

func close() -> void:
	is_open = false
	hide()
	closed.emit()
	_shop = null

func _grab_initial_focus() -> void:
	if is_open and _root != null:
		_root.grab_focus()

# --- Live updates ----------------------------------------------------------

func _on_item_changed(_id: StringName, _count: int) -> void:
	if is_open:
		_rebuild()

func _on_money_changed(_amount: int) -> void:
	if is_open:
		_rebuild()

# --- State transitions -----------------------------------------------------

func _set_mode(mode: String) -> void:
	if _mode == mode:
		return
	_mode = mode
	_category = "All"
	_sel = 0
	_qty = 1
	_rebuild()

func _set_category(cat: String) -> void:
	_category = cat
	_sel = 0
	_qty = 1
	_rebuild()

func _select(index: int) -> void:
	_sel = index
	_qty = 1
	_rebuild()

func _move_selection(delta: int) -> void:
	var rows := _filtered_rows()
	if rows.is_empty():
		return
	_sel = clampi(_sel + delta, 0, rows.size() - 1)
	_qty = 1
	_rebuild()

func _step_qty(delta: int) -> void:
	var rows := _filtered_rows()
	if rows.is_empty():
		return
	var sel: int = clampi(_sel, 0, rows.size() - 1)
	_qty = clampi(_qty + delta, 1, _max_qty(rows[sel]))
	_rebuild()

func _confirm() -> void:
	if _shop == null:
		return
	var rows := _filtered_rows()
	if rows.is_empty():
		return
	var sel: int = clampi(_sel, 0, rows.size() - 1)
	var row: Dictionary = rows[sel]
	var item_id: StringName = row["id"]
	var qty: int = clampi(_qty, 1, _max_qty(row))
	var item_name: String = row["name"]
	if _mode == "buy":
		if ShopSystem.buy(_shop, item_id, qty):
			_notify("Bought %d× %s" % [qty, item_name], GOLD_ON_DARK)
			_qty = 1
		else:
			_notify("Not enough gold!", RED)
	else:
		if ShopSystem.sell(_shop, item_id, qty):
			_notify("Sold %d× %s" % [qty, item_name], GREEN)
			_qty = 1
		else:
			_notify("Barry won't buy that.", RED)
	# A successful transaction emits money_changed / item_changed which rebuilds us;
	# on failure rebuild explicitly so any clamp adjustments still show.
	if is_open:
		_rebuild()

# --- Data ------------------------------------------------------------------

# The raw item ids offered in the current mode (buy = unlocked stock; sell = the
# bag's sellable items minus active quest materials).
func _current_ids() -> Array[StringName]:
	if _shop == null:
		return []
	if _mode == "buy":
		return ShopSystem.get_unlocked_stock(_shop)
	var sellable := ShopSystem.get_sellable_item_ids(_shop)
	return _exclude_quest_items(sellable)

# Builds row dictionaries for EVERY item in the current mode (pre-category-filter).
func _all_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id in _current_ids():
		var item := Inventory.get_item(id)
		var item_name := item.display_name if item else String(id)
		var cat_enum := int(item.category) if item else 4
		var cat_str: String = CAT_NAMES.get(cat_enum, "Misc")
		var unit := ShopSystem.get_buy_price(_shop, id) if _mode == "buy" else ShopSystem.get_sell_price(_shop, id)
		out.append({
			"id": id,
			"name": item_name,
			"abbrev": _abbrev(item_name if item else String(id)),
			"cat_str": cat_str,
			"unit": unit,
			"owned": Inventory.count_of(id),
			"desc": item.description if item else "",
		})
	return out

# Distinct category names present in the current mode, "All" first.
func _categories() -> Array[String]:
	var out: Array[String] = ["All"]
	for r in _all_rows():
		if not out.has(r["cat_str"]):
			out.append(r["cat_str"])
	return out

# Rows after applying the selected category pill.
func _filtered_rows() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for r in _all_rows():
		if _category == "All" or r["cat_str"] == _category:
			out.append(r)
	return out

func _max_qty(row: Dictionary) -> int:
	if _mode == "buy":
		return 99
	return maxi(1, int(row["owned"]))

# Removes any item ids the player is actively collecting for a quest, so selling
# never dumps in-progress quest materials. Reached via the QuestSystem autoload and
# guarded by has_method — if absent we filter nothing (behaviour unchanged).
func _exclude_quest_items(ids: Array[StringName]) -> Array[StringName]:
	var quest_sys := get_node_or_null("/root/QuestSystem")
	if quest_sys == null or not quest_sys.has_method("get_active_quest_item_ids"):
		return ids
	var protected = quest_sys.get_active_quest_item_ids()
	if protected == null or protected.is_empty():
		return ids
	var kept: Array[StringName] = []
	for id in ids:
		if not protected.has(id):
			kept.append(id)
	return kept

# A 3-4 letter uppercase code derived from an item name, for the thumbnail chips.
func _abbrev(text: String) -> String:
	var words := text.strip_edges().split(" ", false)
	if words.size() >= 2:
		var code := ""
		for w in words:
			var c := _first_alnum(w)
			if c != "":
				code += c
			if code.length() >= 4:
				break
		if code.length() >= 2:
			return code.to_upper()
	# Single word (or no usable initials): first 3-4 alphanumerics.
	var alnum := ""
	for ch in text:
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			alnum += ch
		if alnum.length() >= 4:
			break
	if alnum == "":
		return "?"
	return alnum.substr(0, 4).to_upper()

func _first_alnum(w: String) -> String:
	for ch in w:
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9"):
			return ch
	return ""

# --- Building the panel ----------------------------------------------------

func _rebuild() -> void:
	for c in _root.get_children():
		c.queue_free()
	if _shop == null:
		return

	# Subtle ink wash so the world behind reads as "paused", and clicks are blocked.
	var scrim := ColorRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.color = Color(INK.r, INK.g, INK.b, 0.4)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(scrim)

	# Centered fixed-size panel.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(920, 560)
	var panel_sb := _sb(CREAM_92, 6)
	panel_sb.content_margin_left = 18.0
	panel_sb.content_margin_right = 18.0
	panel_sb.content_margin_top = 18.0
	panel_sb.content_margin_bottom = 18.0
	panel.add_theme_stylebox_override("panel", panel_sb)
	center.add_child(panel)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)

	col.add_child(_build_header())
	col.add_child(_build_toggle())
	col.add_child(_build_body())

	# Controls hint, anchored to the bottom of the screen, right-aligned.
	var hint := _lbl("LB / RB — buy ↔ sell  ·  ↑↓ browse  ·  ←→ quantity  ·  Enter to confirm  ·  Esc to leave", _font_body, 12, TOTAL_LABEL)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_left = 22
	hint.offset_right = -22
	hint.offset_top = -30
	hint.offset_bottom = -14
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(hint)

func _build_header() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN

	# Vendor chip (abbrev of shop name).
	var chip := _thumb(46, 6, 3, _abbrev(_shop.display_name), 13, DARK_CHIP, CREAM, INK)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(chip)

	# Name + tagline.
	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", 1)
	name_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	name_col.add_child(_lbl(_shop.display_name, FONT_CHAKRA, 22, TEXT))
	name_col.add_child(_lbl(_tagline(), _font_body, 12, DIM))
	row.add_child(name_col)

	# Flexible spacer.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	# Gold counter.
	var gold := PanelContainer.new()
	gold.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var gold_sb := _sb(DARK_CHIP, 6)
	gold_sb.content_margin_left = 13.0
	gold_sb.content_margin_right = 13.0
	gold_sb.content_margin_top = 7.0
	gold_sb.content_margin_bottom = 7.0
	gold.add_theme_stylebox_override("panel", gold_sb)
	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 8)
	gold_row.alignment = BoxContainer.ALIGNMENT_CENTER
	gold_row.add_child(_disc(20, 12))
	gold_row.add_child(_lbl(str(GameState.money), FONT_CHAKRA, 18, GOLD_ON_DARK))
	gold.add_child(gold_row)
	row.add_child(gold)

	# LEAVE · ESC (clickable -> close).
	var leave := HBoxContainer.new()
	leave.add_theme_constant_override("separation", 7)
	leave.alignment = BoxContainer.ALIGNMENT_CENTER
	leave.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	leave.mouse_filter = Control.MOUSE_FILTER_STOP
	leave.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	leave.gui_input.connect(_on_leave_input)
	var leave_lbl := _lbl("LEAVE", _font_body, 11, DIM)
	leave_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	leave.add_child(leave_lbl)
	# ESC key cap: ink-dark fill (#221f1a) with cream text.
	var esc := _chip("ESC", 12, CREAM, TEXT, 4)
	_ignore_mouse(esc)
	leave.add_child(esc)
	row.add_child(leave)

	return row

func _on_leave_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()

func _tagline() -> String:
	# Fold the reputation-aware buy discount into the tagline when present.
	if _shop.reputation_npc != &"":
		var pct := ShopSystem.get_buy_discount_percent(_shop)
		if pct > 0:
			return "Liked customer  ·  %d%% off" % pct
		elif pct < 0:
			return "Cold reception  ·  %d%% markup" % absi(pct)
		return "Buy and sell  ·  Cash only"
	return "Buy and sell  ·  Cash only"

func _build_toggle() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for m in [["buy", "Buy"], ["sell", "Sell"]]:
		var active: bool = _mode == m[0]
		var btn := Button.new()
		btn.text = m[1]
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_override("font", FONT_CHAKRA)
		btn.add_theme_font_size_override("font_size", 15)
		var bg := BRIGHT if active else CREAM
		var fg := TEXT if active else DIM
		_style_button(btn, bg, fg, 5, 4, 8)
		btn.pressed.connect(_set_mode.bind(m[0]))
		row.add_child(btn)
	return row

func _build_body() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL

	row.add_child(_build_list_column())
	row.add_child(_build_detail_panel())
	return row

func _build_list_column() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL

	# Category pills (wrap).
	var pills := HFlowContainer.new()
	pills.add_theme_constant_override("h_separation", 6)
	pills.add_theme_constant_override("v_separation", 6)
	for cat in _categories():
		var active: bool = cat == _category
		var btn := Button.new()
		btn.text = cat
		btn.focus_mode = Control.FOCUS_NONE
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.add_theme_font_override("font", _font_body)
		btn.add_theme_font_size_override("font_size", 12)
		var bg := BRIGHT if active else CREAM
		var fg := TEXT if active else DIM
		_style_button(btn, bg, fg, 999, 4, 11)
		btn.pressed.connect(_set_category.bind(cat))
		pills.add_child(btn)
	col.add_child(pills)

	# Scrollable rows.
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var rows_box := VBoxContainer.new()
	rows_box.add_theme_constant_override("separation", 6)
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows_box)

	var rows := _filtered_rows()
	if rows.is_empty():
		var none := _lbl("Nothing for sale." if _mode == "buy" else "Nothing to sell.", _font_body, 13, DIM)
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rows_box.add_child(none)
	else:
		var sel: int = clampi(_sel, 0, rows.size() - 1)
		for i in rows.size():
			rows_box.add_child(_make_row(rows[i], i, i == sel))
	return col

func _make_row(row: Dictionary, index: int, selected: bool) -> Control:
	var pc := PanelContainer.new()
	var sb := _sb(BRIGHT if selected else CREAM, 5)
	sb.border_color = Color(1, 1, 1, 1) if selected else INK
	sb.content_margin_left = 11.0
	sb.content_margin_right = 11.0
	sb.content_margin_top = 7.0
	sb.content_margin_bottom = 7.0
	pc.add_theme_stylebox_override("panel", sb)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	pc.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pc.gui_input.connect(_on_row_input.bind(index))

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 11)
	hb.alignment = BoxContainer.ALIGNMENT_BEGIN
	pc.add_child(hb)

	# Thumb.
	var thumb := _thumb(40, 4, 2, row["abbrev"], 12, THUMB_BG, DIM, INK)
	thumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(thumb)

	# Name + sub.
	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", 1)
	name_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var name_lbl := _lbl(row["name"], FONT_CHAKRA, 14, TEXT)
	name_lbl.clip_text = true
	name_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_col.add_child(name_lbl)
	var sub: String = str(row["cat_str"]) if _mode == "buy" else "%s  ·  own ×%d" % [str(row["cat_str"]), int(row["owned"])]
	name_col.add_child(_lbl(sub, _font_body, 11, DIM))
	hb.add_child(name_col)

	# Price group.
	var price_group := HBoxContainer.new()
	price_group.add_theme_constant_override("separation", 5)
	price_group.alignment = BoxContainer.ALIGNMENT_CENTER
	price_group.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var unit := int(row["unit"])
	price_group.add_child(_disc(15, 9))
	if _mode == "sell" and unit <= 0:
		price_group.add_child(_lbl("—", FONT_CHAKRA, 15, DIM))
	else:
		var pcol := TEXT if _mode == "buy" else GREEN
		price_group.add_child(_lbl(str(unit), FONT_CHAKRA, 15, pcol))
	hb.add_child(price_group)

	# Make the whole row a single click target: decorative children ignore picking
	# so the click reaches the PanelContainer's gui_input.
	_ignore_mouse(hb)
	return pc

func _on_row_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_select(index)

func _build_detail_panel() -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(320, 0)
	pc.size_flags_horizontal = Control.SIZE_FILL
	pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := _sb(CREAM, 6)
	sb.content_margin_left = 16.0
	sb.content_margin_right = 16.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 16.0
	pc.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 13)
	pc.add_child(v)

	var rows := _filtered_rows()
	var has_sel := not rows.is_empty()
	var sel_row: Dictionary = rows[clampi(_sel, 0, rows.size() - 1)] if has_sel else {}

	# Header: thumb + name + category.
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 13)
	head.alignment = BoxContainer.ALIGNMENT_BEGIN
	var ab: String = sel_row.get("abbrev", "") if has_sel else ""
	var dthumb := _thumb(66, 5, 3, ab, 16, THUMB_BG, DIM, INK)
	dthumb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(dthumb)
	var head_col := VBoxContainer.new()
	head_col.add_theme_constant_override("separation", 3)
	head_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dname: String = sel_row.get("name", "—") if has_sel else "—"
	var dname_lbl := _lbl(dname, FONT_CHAKRA, 18, TEXT)
	dname_lbl.clip_text = true
	dname_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head_col.add_child(dname_lbl)
	var dcat: String = String(sel_row.get("cat_str", "")).to_upper() if has_sel else ""
	head_col.add_child(_lbl(dcat, _font_body, 11, DIM))
	head.add_child(head_col)
	v.add_child(head)

	# Flavor description.
	var desc_text: String = sel_row.get("desc", "") if has_sel else "Nothing selected."
	if desc_text == "":
		desc_text = "Nothing selected." if not has_sel else ""
	var desc := _lbl(desc_text, _font_body, 12, DIM)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_constant_override("line_spacing", 4)
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(desc)

	# Divider.
	var divider := ColorRect.new()
	divider.color = TRACK
	divider.custom_minimum_size = Vector2(0, 2)
	v.add_child(divider)

	# Compute pricing.
	var unit := int(sel_row.get("unit", 0)) if has_sel else 0
	var max_q := _max_qty(sel_row) if has_sel else 1
	var qty: int = clampi(_qty, 1, max_q)
	_qty = qty
	var total := unit * qty
	var buy := _mode == "buy"
	var can := (total <= GameState.money) if buy else (unit > 0)

	# Unit / sell price row.
	v.add_child(_kv_row(
		"UNIT PRICE" if buy else "SELL PRICE",
		_value_with_disc(str(unit), 16, 8, TEXT)
	))

	# Quantity stepper.
	var qrow := HBoxContainer.new()
	qrow.alignment = BoxContainer.ALIGNMENT_BEGIN
	qrow.add_child(_lbl("QUANTITY", FONT_CHAKRA, 11, DIM))
	var qspace := Control.new()
	qspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	qrow.add_child(qspace)
	var qctrl := HBoxContainer.new()
	qctrl.add_theme_constant_override("separation", 8)
	qctrl.alignment = BoxContainer.ALIGNMENT_CENTER
	qctrl.add_child(_stepper_btn("–", -1))  # en-dash glyph
	var qval := _lbl(str(qty), FONT_CHAKRA, 18, TEXT)
	qval.custom_minimum_size = Vector2(36, 0)
	qval.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	qval.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	qctrl.add_child(qval)
	qctrl.add_child(_stepper_btn("+", 1))
	qrow.add_child(qctrl)
	v.add_child(qrow)

	# Spacer pushes total + confirm to the bottom.
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(spacer)

	# Total chip.
	var total_chip := PanelContainer.new()
	var tsb := _sb(DARK_CHIP, 6)
	tsb.content_margin_left = 13.0
	tsb.content_margin_right = 13.0
	tsb.content_margin_top = 9.0
	tsb.content_margin_bottom = 9.0
	total_chip.add_theme_stylebox_override("panel", tsb)
	var trow := HBoxContainer.new()
	trow.alignment = BoxContainer.ALIGNMENT_BEGIN
	trow.add_child(_lbl("TOTAL COST" if buy else "YOU GET", FONT_CHAKRA, 13, TOTAL_LABEL))
	var tspace := Control.new()
	tspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	trow.add_child(tspace)
	var tgroup := HBoxContainer.new()
	tgroup.add_theme_constant_override("separation", 7)
	tgroup.alignment = BoxContainer.ALIGNMENT_CENTER
	tgroup.add_child(_disc(18, 10))
	tgroup.add_child(_lbl(str(total), FONT_CHAKRA, 20, GOLD_ON_DARK))
	trow.add_child(tgroup)
	total_chip.add_child(trow)
	v.add_child(total_chip)

	# Confirm button.
	var confirm := Button.new()
	confirm.focus_mode = Control.FOCUS_NONE
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm.add_theme_font_override("font", FONT_CHAKRA)
	confirm.add_theme_font_size_override("font_size", 16)
	if buy:
		confirm.text = "Buy" if can else "Not enough gold"
	else:
		confirm.text = "Sell" if can else "Not for sale"
	if can:
		confirm.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		_style_button(confirm, GOLD, GOLD_DISC_TEXT, 6, 11, 11)
		confirm.disabled = false
		confirm.pressed.connect(_confirm)
	else:
		_style_button(confirm, CREAM, DIM, 6, 11, 11)
		confirm.disabled = true
	v.add_child(confirm)

	return pc

# A label-left / value-right row used inside the detail panel.
func _kv_row(label_text: String, value_node: Control) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_child(_lbl(label_text, FONT_CHAKRA, 11, DIM))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(sp)
	row.add_child(value_node)
	return row

# A gold disc + value text group (used for the unit price readout).
func _value_with_disc(value: String, disc_d: int, disc_f: int, color: Color) -> Control:
	var g := HBoxContainer.new()
	g.add_theme_constant_override("separation", 6)
	g.alignment = BoxContainer.ALIGNMENT_CENTER
	g.add_child(_disc(disc_d, disc_f))
	g.add_child(_lbl(value, FONT_CHAKRA, 15, color))
	return g

func _stepper_btn(glyph: String, delta: int) -> Button:
	var b := Button.new()
	b.text = glyph
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(30, 30)
	b.add_theme_font_override("font", FONT_CHAKRA)
	b.add_theme_font_size_override("font_size", 18)
	_style_button(b, BRIGHT, TEXT, 5, 0, 0)
	b.pressed.connect(_step_qty.bind(delta))
	return b

# --- Toast -----------------------------------------------------------------

func _notify(text: String, color: Color) -> void:
	var feed := get_node_or_null("/root/NotificationFeed")
	if feed != null and feed.has_method("notify"):
		feed.notify(text, color)
		return
	# Fallback in-panel toast.
	_toast.text = text
	_toast.add_theme_color_override("font_color", color)
	_toast.visible = true
	_toast_timer = get_tree().create_timer(2.2, true, false, true)
	_toast_timer.timeout.connect(_hide_toast)

func _hide_toast() -> void:
	if _toast != null:
		_toast.visible = false

# --- Small builders --------------------------------------------------------

# Recursively make a control subtree transparent to mouse picking, so a click lands
# on the clickable ancestor (a row PanelContainer / the leave group) instead.
func _ignore_mouse(node: Control) -> void:
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children():
		if child is Control:
			_ignore_mouse(child)

# A flat cream/ink StyleBoxFlat with the given fill and corner radius.
func _sb(bg: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(3)
	sb.border_color = INK
	sb.set_corner_radius_all(radius)
	return sb

func _lbl(text: String, font: Font, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

# A fixed circular gold disc with a centered "G".
func _disc(d: int, fsize: int) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(d, d)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = GOLD
	sb.set_corner_radius_all(int(d / 2.0))
	p.add_theme_stylebox_override("panel", sb)
	var l := _lbl("G", FONT_CHAKRA, fsize, GOLD_DISC_TEXT)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p

# A fixed square thumbnail tile with a centered abbreviation.
func _thumb(size: int, radius: int, border_w: int, abbrev: String, fsize: int, bg: Color, fg: Color, border_col: Color) -> Control:
	var p := Panel.new()
	p.custom_minimum_size = Vector2(size, size)
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border_w)
	sb.border_color = border_col
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	var l := _lbl(abbrev, FONT_CHAKRA, fsize, fg)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	return p

# A small inline chip (the ESC key cap).
func _chip(text: String, fsize: int, fg: Color, bg: Color, radius: int) -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(24, 24)
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := _sb(bg, radius)
	sb.content_margin_left = 6.0
	sb.content_margin_right = 6.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	p.add_theme_stylebox_override("panel", sb)
	var l := _lbl(text, FONT_CHAKRA, fsize, fg)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

# Gives a Button a flat fill/text with matching normal/hover/pressed/disabled boxes.
func _style_button(btn: Button, bg: Color, fg: Color, radius: int, pad_v: int, pad_h: int) -> void:
	var sb := _sb(bg, radius)
	sb.content_margin_left = float(pad_h)
	sb.content_margin_right = float(pad_h)
	sb.content_margin_top = float(pad_v)
	sb.content_margin_bottom = float(pad_v)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_color", fg)
	btn.add_theme_color_override("font_hover_color", fg)
	btn.add_theme_color_override("font_pressed_color", fg)
	btn.add_theme_color_override("font_focus_color", fg)
	btn.add_theme_color_override("font_disabled_color", fg)
