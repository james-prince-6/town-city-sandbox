# inventory_ui.gd
# Autoload singleton (registered as "InventoryUI", pointing at inventory_ui.tscn).
#
# A togglable bag panel that VISUALISES the Inventory autoload. It owns no data
# of its own — it just reads Inventory and redraws. Because it lives in an
# autoload it's available in every scene without re-adding it.
#
# Toggle with the "inventory" input action (bound to I). It stays in sync live:
# whenever Inventory emits item_changed while open, the grid rebuilds.

extends CanvasLayer

## Emitted when the bag opens / closes. The player listens so it can stop moving
## and free the mouse (same pattern as Dialogue).
signal opened
signal closed

@onready var grid: GridContainer = $Panel/Margin/VBox/Grid
@onready var empty_label: Label = $Panel/Margin/VBox/EmptyLabel

var is_open: bool = false

func _ready() -> void:
	# Draw above the world and keep working even if something pauses the tree.
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	Inventory.item_changed.connect(_on_item_changed)

func _unhandled_input(_event: InputEvent) -> void:
	# Retired: the unified PlayerMenu now owns the "inventory" key and opens its Inventory
	# tab. This standalone bag no longer opens itself; the autoload stays only so existing
	# references (e.g. the player's pause hooks) keep resolving.
	pass

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open() -> void:
	is_open = true
	_rebuild()
	show()
	opened.emit()

func close() -> void:
	is_open = false
	hide()
	closed.emit()

# Keep the open bag current as items come and go.
func _on_item_changed(_id: StringName, _count: int) -> void:
	if is_open:
		_rebuild()

# Clears and repopulates the grid from the current inventory contents.
func _rebuild() -> void:
	for child in grid.get_children():
		child.queue_free()

	var contents := Inventory.get_all()
	empty_label.visible = contents.is_empty()

	for id in contents:
		grid.add_child(_make_slot(id, contents[id]))

# Builds one slot widget: an icon (or a text fallback) with an "xN" count.
func _make_slot(id: StringName, count: int) -> Control:
	var item := Inventory.get_item(id)

	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(96, 96)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	slot.add_child(box)

	if item and item.icon:
		var icon := TextureRect.new()
		icon.texture = item.icon
		icon.custom_minimum_size = Vector2(64, 64)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(icon)
	else:
		# No art yet? Show the item's name so the slot is still readable.
		var name_label := Label.new()
		name_label.text = item.display_name if item else String(id)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(name_label)

	var count_label := Label.new()
	count_label.text = "x%d" % count
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(count_label)

	# Hovering a slot shows the description as a tooltip.
	if item:
		slot.tooltip_text = "%s\n%s" % [item.display_name, item.description]

	return slot
