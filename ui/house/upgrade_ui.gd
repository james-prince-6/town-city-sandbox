# upgrade_ui.gd
# Autoload singleton (register in Project Settings -> Autoload as "UpgradeUI").
#
# A BLOCKING menu for the HOUSE UPGRADE feature, opened by the upgrade station prop.
# Like ShopUI / BrewingUI it owns no data of its own: it reads the HouseUpgrades
# catalog (what upgrades exist + ownership + affordability), the Inventory (item
# costs), and GameState (money), then redraws. Because it lives in an autoload it's
# available in every scene.
#
# Code-built (no .tscn): the whole panel is constructed in _ready / _rebuild, so there
# is nothing to hand-author. The upgrade station opens it via open(); the panel frees
# the mouse and emits `opened`; the player listens (exact same pattern as ShopUI) to
# stop moving. Closing emits `closed`. ui_cancel (Esc) closes it.
#
# NO class_name ON PURPOSE: the autoload singleton is itself named "UpgradeUI";
# declaring class_name UpgradeUI would clash with that global symbol.

extends CanvasLayer

const Glass = preload("res://ui/glass_style.gd")

## Emitted when the menu opens / closes. The player listens so it can stop moving and
## free the mouse (same pattern as ShopUI / BrewingUI).
signal opened
signal closed

var is_open: bool = false

# Built once in _ready and reused; _rebuild only repopulates the row list.
var _panel: PanelContainer
var _title: Label
var _money_label: Label
var _rows: VBoxContainer

func _ready() -> void:
	# Draw above the world (just under the inventory's layer 10), like ShopUI, and keep
	# working even if something pauses the tree.
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("exclusive_menu")  # so opening another menu closes this one
	_build_ui()
	hide()
	# Rebuild when an upgrade is bought (ownership flips), when the bag changes (item-cost
	# affordability), and when money changes (Buy buttons enable/disable + money label).
	HouseUpgrades.upgrade_purchased.connect(_on_upgrade_purchased)
	Inventory.item_changed.connect(_on_item_changed)
	GameState.money_changed.connect(_on_money_changed)

func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# --- Open / close ----------------------------------------------------------

func open() -> void:
	MenuManager.opening(self)  # close any other open menu first (no stacking)
	is_open = true
	_rebuild()
	show()
	_grab_initial_focus.call_deferred()
	opened.emit()

func close() -> void:
	is_open = false
	hide()
	closed.emit()

# --- Live updates ----------------------------------------------------------

func _on_upgrade_purchased(_id: StringName) -> void:
	if is_open:
		_rebuild()

func _on_item_changed(_id: StringName, _count: int) -> void:
	if is_open:
		_rebuild()

func _on_money_changed(_amount: int) -> void:
	if is_open:
		_rebuild()

# --- Building the panel ----------------------------------------------------

# Builds the static chrome once: a centred frosted panel with a title, a money line,
# and a scrolling row container that _rebuild fills.
func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(440, 520)
	_panel.position = Vector2(-220, -260)
	Glass.apply(_panel, 18, 22)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	margin.add_child(vbox)

	_title = Label.new()
	_title.text = "Improve Home"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 24)
	vbox.add_child(_title)

	_money_label = Label.new()
	_money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_money_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 8)
	scroll.add_child(_rows)

# Clears and repopulates the row list from the current catalog + ownership state.
func _rebuild() -> void:
	for child in _rows.get_children():
		child.queue_free()

	_money_label.text = "$%d" % GameState.money

	var catalog := HouseUpgrades.get_catalog()
	if catalog.is_empty():
		var none := Label.new()
		none.text = "No upgrades available."
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_rows.add_child(none)
		return

	for def in catalog:
		_rows.add_child(_make_row(def))

	# A live rebuild frees the previously focused button, so re-seat the controller focus.
	_grab_initial_focus.call_deferred()

# Builds one upgrade row: name, description, cost line, and either an OWNED tag, a
# Buy button (when can_buy), or a disabled button explaining why it's locked.
func _make_row(def: UpgradeDef) -> Control:
	var panel := PanelContainer.new()
	Glass.apply(panel, 10, 12)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var name_label := Label.new()
	name_label.text = def.display_name
	name_label.add_theme_font_size_override("font_size", 18)
	box.add_child(name_label)

	if def.description != "":
		var desc := Label.new()
		desc.text = def.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(desc)

	var cost_label := Label.new()
	cost_label.text = "Cost: %s" % _cost_text(def)
	box.add_child(cost_label)

	if HouseUpgrades.is_owned(def.id):
		var owned := Label.new()
		owned.text = "OWNED"
		owned.add_theme_color_override("font_color", Color(0.4, 0.85, 0.4))
		box.add_child(owned)
		return panel

	var buy_btn := Button.new()
	if HouseUpgrades.can_buy(def.id):
		buy_btn.text = "Buy"
		buy_btn.disabled = false
	else:
		buy_btn.text = _locked_reason(def)
		buy_btn.disabled = true
	buy_btn.pressed.connect(_on_buy_pressed.bind(def.id))
	box.add_child(buy_btn)

	return panel

# Builds a human-readable cost string, e.g. "$400 + 8x Wood Log".
func _cost_text(def: UpgradeDef) -> String:
	var text := "$%d" % def.cost_money
	if def.cost_item_id != &"" and def.cost_item_count > 0:
		var item := Inventory.get_item(def.cost_item_id)
		var item_name: String = item.display_name if item else String(def.cost_item_id)
		text += " + %dx %s" % [def.cost_item_count, item_name]
	return text

# Explains why a not-owned upgrade can't be bought right now (for the disabled button).
func _locked_reason(def: UpgradeDef) -> String:
	if def.prerequisite != &"" and not HouseUpgrades.is_owned(def.prerequisite):
		var prereq: UpgradeDef = HouseUpgrades.get_def(def.prerequisite)
		var prereq_name: String = prereq.display_name if prereq else String(def.prerequisite)
		return "Requires %s" % prereq_name
	if GameState.money < def.cost_money:
		return "Need more $"
	if def.cost_item_id != &"" and def.cost_item_count > 0 and not Inventory.has(def.cost_item_id, def.cost_item_count):
		var item := Inventory.get_item(def.cost_item_id)
		var item_name: String = item.display_name if item else String(def.cost_item_id)
		return "Need %dx %s" % [def.cost_item_count, item_name]
	return "Unavailable"

# --- Controller focus ------------------------------------------------------

# Focus the first enabled Buy button so navigation works without a mouse. Skips if
# focus is already inside the panel so live updates don't yank the selection around.
func _grab_initial_focus() -> void:
	if not is_open:
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null and _panel.is_ancestor_of(focus_owner):
		return
	var target := _first_button_in(_rows)
	if target != null:
		target.grab_focus()

func _first_button_in(node: Node) -> Button:
	for child in node.get_children():
		if child is Button and not (child as Button).disabled:
			return child
		var found := _first_button_in(child)
		if found != null:
			return found
	return null

# --- Button handlers -------------------------------------------------------

func _on_buy_pressed(id: StringName) -> void:
	# buy() re-validates and, on success, emits upgrade_purchased / money_changed /
	# item_changed — all of which rebuild us — so we don't need to refresh by hand.
	HouseUpgrades.buy(id)
