# inventory_slot.gd
# One slot in the PlayerMenu's Inventory grid. Beyond just drawing an item (icon /
# 3D thumbnail / name + count) it is the SOURCE for assigning items to the hotbar:
#
# - MOUSE: drag the slot onto a hotbar drop slot (see hotbar_drop_slot.gd). Godot's
#   built-in drag system calls _get_drag_data here and _drop_data on the target.
# - KEYBOARD: focus the slot (d-pad / arrows) and press number keys 1-8 to drop the
#   item into that hotbar slot.
# - CONTROLLER: focus the slot and press A (ui_accept) to drop it into the first free
#   hotbar slot.
#
# Assigning is non-destructive: it only sets a hotbar slot's referenced id; the item
# stays in the bag (the hotbar stores ids, never counts — see global/systems/hotbar.gd).

class_name InventorySlot
extends PanelContainer

var item_id: StringName = &""
var _count: int = 0

func setup(id: StringName, count: int) -> void:
	item_id = id
	_count = count
	custom_minimum_size = Vector2(120, 96)
	mouse_filter = Control.MOUSE_FILTER_STOP   # so drag can start from this control
	focus_mode = Control.FOCUS_ALL             # so a gamepad/keyboard can select it
	var item: Item = Inventory.get_item(id)
	if item != null:
		var tip := "%s\n%s\n\n[1-8] assign to hotbar   •   A: first free slot" % [item.display_name, item.description]
		# Surface the item's worth so players can reason about what to keep vs sell.
		if item.base_value > 0:
			tip += "\n\nBase value: $%d" % item.base_value
		tooltip_text = tip
	if not focus_entered.is_connected(_on_focus_changed):
		focus_entered.connect(_on_focus_changed)
		focus_exited.connect(_on_focus_changed)
	_build()
	_on_focus_changed()

func _build() -> void:
	for c in get_children():
		c.queue_free()
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)

	var visual: Control = ItemThumbnail.make_visual(item_id, 56.0)
	box.add_child(visual)

	var cnt := Label.new()
	cnt.text = "x%d" % _count
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(cnt)

# Brighten slightly while focused so the controller/keyboard selection is obvious.
func _on_focus_changed() -> void:
	modulate = Color(1.0, 1.0, 0.8) if has_focus() else Color(1, 1, 1)

# --- Mouse drag source -----------------------------------------------------

func _get_drag_data(_at_position: Vector2) -> Variant:
	if item_id == &"":
		return null
	var preview := PanelContainer.new()
	var inner: Control = ItemThumbnail.make_visual(item_id, 48.0)
	inner.custom_minimum_size = Vector2(48, 48)
	preview.add_child(inner)
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
	# No empty slot: fall back to the currently selected slot.
	Hotbar.set_slot(Hotbar.selected_index, item_id)
