# hotbar_drop_slot.gd
# One slot of the hotbar row shown at the bottom of the PlayerMenu's Inventory tab.
# It mirrors a single Hotbar slot (drawing its current item) AND acts as a DROP TARGET
# so the player can drag an inventory item onto it to assign that item to the hotbar.
#
# It self-refreshes on Hotbar.slots_changed, so an assign (by drag, number key, or A)
# shows up immediately without rebuilding the whole tab (which would steal focus).

class_name HotbarDropSlot
extends PanelContainer

var slot_index: int = 0

func setup(index: int) -> void:
	slot_index = index
	# A cream cell that stretches to fill the ink hotbar bar (matches the HUD hotbar look).
	custom_minimum_size = Vector2(0, 58)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cell := StyleBoxFlat.new()
	cell.bg_color = Color(0.906, 0.882, 0.831, 1.0)
	cell.set_corner_radius_all(2)
	add_theme_stylebox_override("panel", cell)
	mouse_filter = Control.MOUSE_FILTER_STOP   # required to receive drops
	tooltip_text = "Hotbar slot %d\nDrag an item here to assign it." % (index + 1)
	if not Hotbar.slots_changed.is_connected(_refresh):
		Hotbar.slots_changed.connect(_refresh)
	_refresh()

func _refresh() -> void:
	for c in get_children():
		c.queue_free()

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	add_child(box)

	# Faint slot number so the number-key bindings are discoverable.
	var num := Label.new()
	num.text = str(slot_index + 1)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.add_theme_font_size_override("font_size", 10)
	num.modulate = Color(0.6, 0.6, 0.6)
	num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(num)

	var id: StringName = Hotbar.slots[slot_index]
	if id == &"":
		return
	var visual: Control = ItemThumbnail.make_visual(id, 40.0)
	box.add_child(visual)

# --- Drop target -----------------------------------------------------------

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	return data is Dictionary and (data as Dictionary).has("item_id")

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var id: StringName = StringName((data as Dictionary)["item_id"])
	Hotbar.set_slot(slot_index, id)
