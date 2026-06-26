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
# Two columns:
# - BUY:  one row per item in shop.stock — name, buy price, and a "Buy" button
#         that is enabled only when ShopSystem.can_buy is true (affordable + sold).
# - SELL: one row per item the player currently holds that this shop buys —
#         name + "xN" held, sell price, and a "Sell" button.
# Pressing Buy/Sell runs the matching ShopSystem call, then the panel rebuilds.

extends CanvasLayer

## Emitted when the menu opens / closes. The player listens so it can stop moving
## and free the mouse (same pattern as InventoryUI / BrewingUI).
signal opened
signal closed

@onready var title: Label = $Panel/Margin/VBox/Title
@onready var money_label: Label = $Panel/Margin/VBox/Money
@onready var buy_rows: VBoxContainer = $Panel/Margin/VBox/Columns/BuyColumn/BuyRows
@onready var sell_rows: VBoxContainer = $Panel/Margin/VBox/Columns/SellColumn/SellRows

var is_open: bool = false

## The shop resource we're currently bound to.
var _shop: ShopInventory = null

func _ready() -> void:
	# Draw above the world (just under the inventory's layer 10) and keep working
	# even if something pauses the tree.
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()
	# Rebuild when the bag changes (sell column + affordability) and when money
	# changes (money label + Buy buttons enable/disable).
	Inventory.item_changed.connect(_on_item_changed)
	GameState.money_changed.connect(_on_money_changed)

func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# --- Open / close ----------------------------------------------------------

## Bind to a shop and show the panel.
func open_for(shop: ShopInventory) -> void:
	if shop == null:
		push_warning("ShopUI.open_for: shop is null")
		return
	_shop = shop
	is_open = true
	_rebuild()
	show()
	# Put controller focus on the first Buy/Sell button so navigation works without
	# a mouse. Deferred so the freshly built rows exist.
	_grab_initial_focus.call_deferred()
	opened.emit()

func close() -> void:
	is_open = false
	hide()
	closed.emit()
	_shop = null

# --- Live updates ----------------------------------------------------------

# The bag changed: redraw so the sell column and Buy affordability stay current.
func _on_item_changed(_id: StringName, _count: int) -> void:
	if is_open:
		_rebuild()

# Money changed: redraw so the money label and Buy buttons reflect it.
func _on_money_changed(_amount: int) -> void:
	if is_open:
		_rebuild()

# --- Building the panel ----------------------------------------------------

# Clears and repopulates both columns based on the bound shop's current state.
func _rebuild() -> void:
	for child in buy_rows.get_children():
		child.queue_free()
	for child in sell_rows.get_children():
		child.queue_free()

	if _shop == null:
		return

	title.text = _shop.display_name
	money_label.text = "$%d" % GameState.money

	_build_buy_column()
	_build_sell_column()

	# A live rebuild (bag/money changed) frees the previously focused button, so make
	# sure the controller keeps a valid selection. Guarded so it won't disrupt nav.
	_grab_initial_focus.call_deferred()

# --- Controller focus ------------------------------------------------------

# Focus the first Buy button, falling back to the first Sell button. Skips if focus
# is already inside the panel so live updates don't yank the selection around.
func _grab_initial_focus() -> void:
	if not is_open:
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner != null and is_ancestor_of(focus_owner):
		return
	var target := _first_button_in(buy_rows)
	if target == null:
		target = _first_button_in(sell_rows)
	if target != null:
		target.grab_focus()

# Depth-first search for the first enabled Button under `node`.
func _first_button_in(node: Node) -> Button:
	for child in node.get_children():
		if child is Button and not (child as Button).disabled:
			return child
		var found := _first_button_in(child)
		if found != null:
			return found
	return null

# BUY: one row per item id the shop sells (infinite stock).
func _build_buy_column() -> void:
	if _shop.stock.is_empty():
		var none := Label.new()
		none.text = "Nothing for sale."
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		buy_rows.add_child(none)
		return

	for item_id in _shop.stock:
		buy_rows.add_child(_make_buy_row(item_id))

# Builds a single buy row: name, price, and a "Buy" button (gated by can_buy).
func _make_buy_row(item_id: StringName) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var item := Inventory.get_item(item_id)
	var item_name := item.display_name if item else String(item_id)

	# Line 1: "Lava Vial"
	var name_label := Label.new()
	name_label.text = item_name
	box.add_child(name_label)

	# Line 2: "Buy: $15"
	var price_label := Label.new()
	price_label.text = "Buy: $%d" % ShopSystem.get_buy_price(_shop, item_id)
	box.add_child(price_label)

	# Line 3: the Buy button, only usable if the shop sells it and we can afford it.
	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.disabled = not ShopSystem.can_buy(_shop, item_id)
	buy_btn.pressed.connect(_on_buy_pressed.bind(item_id))
	box.add_child(buy_btn)

	return panel

# SELL: one row per item the player holds that this shop buys.
func _build_sell_column() -> void:
	var sellable := ShopSystem.get_sellable_item_ids(_shop)
	if sellable.is_empty():
		var none := Label.new()
		none.text = "Nothing to sell."
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sell_rows.add_child(none)
		return

	for item_id in sellable:
		sell_rows.add_child(_make_sell_row(item_id))

# Builds a single sell row: name + count held, price, and a "Sell" button.
func _make_sell_row(item_id: StringName) -> Control:
	var panel := PanelContainer.new()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var item := Inventory.get_item(item_id)
	var item_name := item.display_name if item else String(item_id)

	# Line 1: "Molten Mocha x3"
	var name_label := Label.new()
	name_label.text = "%s x%d" % [item_name, Inventory.count_of(item_id)]
	box.add_child(name_label)

	# Line 2: "Sell: $12"
	var price_label := Label.new()
	price_label.text = "Sell: $%d" % ShopSystem.get_sell_price(_shop, item_id)
	box.add_child(price_label)

	# Line 3: the Sell button.
	var sell_btn := Button.new()
	sell_btn.text = "Sell"
	sell_btn.pressed.connect(_on_sell_pressed.bind(item_id))
	box.add_child(sell_btn)

	return panel

# --- Button handlers -------------------------------------------------------

func _on_buy_pressed(item_id: StringName) -> void:
	# buy() validates affordability/stock and emits transaction; the resulting
	# money_changed / item_changed signals rebuild us.
	ShopSystem.buy(_shop, item_id)

func _on_sell_pressed(item_id: StringName) -> void:
	# sell() validates we still hold it and emits transaction; the resulting
	# item_changed / money_changed signals rebuild us.
	ShopSystem.sell(_shop, item_id)
