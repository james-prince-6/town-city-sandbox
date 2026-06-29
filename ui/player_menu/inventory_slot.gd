# inventory_slot.gd
# One slot in the PlayerMenu's Inventory grid — a category-COLORED sticker card
# (Town City design): a coloured card with a darker thumb well holding the item's
# 3-4 letter abbreviation chip, the item name beneath, and an ×count badge. Beyond
# drawing the item it is the SOURCE for assigning items to the hotbar:
#
# - MOUSE: drag the slot onto a hotbar drop slot (see hotbar_drop_slot.gd).
# - KEYBOARD: focus the slot (arrows) and press number keys 1-8 to assign.
# - CONTROLLER: focus the slot and press A (ui_accept) to assign to the first free slot.
#
# Assigning is non-destructive: it only sets a hotbar slot's referenced id; the item
# stays in the bag (the hotbar stores ids, never counts).

class_name InventorySlot
extends PanelContainer

var item_id: StringName = &""
var _count: int = 0

# Per-card colours, supplied by player_menu from the active colour scheme:
# card (idle bg), sel_card (focused bg, lighter), thumb (well bg), ab (chip text),
# name (label text).
var _c_card: Color = Color(0.906, 0.882, 0.831)
var _c_sel: Color = Color(0.984, 0.973, 0.941)
var _c_thumb: Color = Color(0.839, 0.804, 0.729)
var _c_ab: Color = Color(0.227, 0.196, 0.149)
var _c_name: Color = Color(0.165, 0.133, 0.094)

const INK := Color(0.055, 0.051, 0.071)

func setup(id: StringName, count: int, colors: Dictionary = {}) -> void:
	item_id = id
	_count = count
	if colors.has("card"): _c_card = colors["card"]
	if colors.has("sel"): _c_sel = colors["sel"]
	if colors.has("thumb"): _c_thumb = colors["thumb"]
	if colors.has("ab"): _c_ab = colors["ab"]
	if colors.has("name"): _c_name = colors["name"]

	custom_minimum_size = Vector2(0, 96)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP   # so drag can start from this control
	focus_mode = Control.FOCUS_ALL             # so a gamepad/keyboard can select it

	var item: Item = Inventory.get_item(id)
	if item != null:
		var tip := "%s\n%s\n\n[1-8] assign to hotbar   •   A: first free slot" % [item.display_name, item.description]
		if item.base_value > 0:
			tip += "\n\nBase value: $%d" % item.base_value
		tooltip_text = tip

	if not focus_entered.is_connected(_on_focus_changed):
		focus_entered.connect(_on_focus_changed)
		focus_exited.connect(_on_focus_changed)
	_build()
	_on_focus_changed()

# A 3-4 letter uppercase abbreviation for an item (initials for multi-word names,
# else the first few letters). Static so callers can reuse it.
static func abbrev(item: Item, id: StringName) -> String:
	var src: String = String(id)
	if item != null and item.display_name != "":
		src = item.display_name
	var words: PackedStringArray = src.split(" ", false)
	var ab := ""
	if words.size() >= 2:
		for w in words:
			if w.length() > 0 and ab.length() < 4:
				ab += w[0]
	if ab.length() < 3:
		ab = src.replace(" ", "").substr(0, 4)
	return ab.to_upper()

func _card_box(bg: Color, border: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(3)
	sb.border_color = border
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 5.0
	sb.content_margin_right = 5.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	return sb

func _build() -> void:
	for c in get_children():
		c.queue_free()
	var item: Item = Inventory.get_item(item_id)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	# Thumb well (darker category colour) holding the AB chip + count badge.
	var well := PanelContainer.new()
	well.size_flags_vertical = Control.SIZE_EXPAND_FILL
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var well_box := StyleBoxFlat.new()
	well_box.bg_color = _c_thumb
	well_box.set_corner_radius_all(3)
	well.add_theme_stylebox_override("panel", well_box)
	box.add_child(well)

	var well_inner := Control.new()
	well_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(well_inner)

	var ab := Label.new()
	ab.text = abbrev(item, item_id)
	ab.theme_type_variation = &"Display"  # Chakra Petch
	ab.add_theme_font_size_override("font_size", 15)
	ab.add_theme_color_override("font_color", _c_ab)
	ab.set_anchors_preset(Control.PRESET_FULL_RECT)
	ab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well_inner.add_child(ab)

	if _count > 0:
		var cnt := Label.new()
		cnt.text = "×%d" % _count
		cnt.theme_type_variation = &"Display"
		cnt.add_theme_font_size_override("font_size", 10)
		cnt.add_theme_color_override("font_color", _c_ab)
		cnt.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
		cnt.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		cnt.grow_vertical = Control.GROW_DIRECTION_BEGIN
		cnt.offset_right = -2.0
		cnt.offset_bottom = -1.0
		cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		well_inner.add_child(cnt)

	# Item name beneath the well.
	var nm := Label.new()
	nm.text = item.display_name if item != null else String(item_id)
	nm.add_theme_font_size_override("font_size", 10)
	nm.add_theme_color_override("font_color", _c_name)
	nm.clip_text = true
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(nm)

# Focused = lighter card bg + a white outline (matches the design's grid selection).
func _on_focus_changed() -> void:
	if has_focus():
		add_theme_stylebox_override("panel", _card_box(_c_sel, Color(1, 1, 1)))
	else:
		add_theme_stylebox_override("panel", _card_box(_c_card, INK))

# --- Mouse drag source -----------------------------------------------------

func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_id == &"":
		return null
	var preview := PanelContainer.new()
	preview.add_theme_stylebox_override("panel", _card_box(_c_card, INK))
	var item: Item = Inventory.get_item(item_id)
	var ab := Label.new()
	ab.text = abbrev(item, item_id)
	ab.theme_type_variation = &"Display"
	ab.add_theme_font_size_override("font_size", 15)
	ab.add_theme_color_override("font_color", _c_ab)
	ab.custom_minimum_size = Vector2(56, 48)
	ab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview.add_child(ab)
	set_drag_preview(preview)
	return {"item_id": item_id}

# --- Keyboard / controller assign ------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if item_id == &"":
		return
	for i in Hotbar.SLOT_COUNT:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			Hotbar.set_slot(i, item_id)
			accept_event()
			return
	if event.is_action_pressed("ui_accept"):
		_assign_first_free()
		accept_event()

func _assign_first_free() -> void:
	for i in Hotbar.SLOT_COUNT:
		if Hotbar.slots[i] == &"":
			Hotbar.set_slot(i, item_id)
			return
	Hotbar.set_slot(Hotbar.selected_index, item_id)
