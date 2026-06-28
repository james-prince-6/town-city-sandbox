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

const Glass = preload("res://ui/glass_style.gd")

## Emitted when the menu opens / closes. The player listens so it can stop moving
## and free the mouse (same pattern as InventoryUI / BrewingUI).
signal opened
signal closed

@onready var title: Label = $Panel/Margin/VBox/Title
@onready var money_label: Label = $Panel/Margin/VBox/Money
@onready var buy_rows: VBoxContainer = $Panel/Margin/VBox/Columns/BuyColumn/BuyScroll/BuyRows
@onready var sell_rows: VBoxContainer = $Panel/Margin/VBox/Columns/SellColumn/SellScroll/SellRows

var is_open: bool = false

## The shop resource we're currently bound to.
var _shop: ShopInventory = null

## "Sell All" quick-action button (added to the sell column header in code), and the
## confirm overlay it spawns. Built once; the overlay is created/torn down on demand.
var _sell_all_btn: Button = null
var _confirm_overlay: Control = null

func _ready() -> void:
	# Draw above the world (just under the inventory's layer 10) and keep working
	# even if something pauses the tree.
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Frosted-glass content box (no dark default-theme panel).
	Glass.apply($Panel, 18, 22)
	# Add a "Sell All" quick action to the sell column header (just under "Sell"),
	# built in code so we never touch the .tscn. Visibility is toggled per rebuild.
	var sell_col := $Panel/Margin/VBox/Columns/SellColumn
	_sell_all_btn = Button.new()
	_sell_all_btn.text = "Sell All"
	_sell_all_btn.pressed.connect(_on_sell_all)
	sell_col.add_child(_sell_all_btn)
	sell_col.move_child(_sell_all_btn, 1)  # right after the "Sell" header label
	hide()
	# Rebuild when the bag changes (sell column + affordability) and when money
	# changes (money label + Buy buttons enable/disable).
	Inventory.item_changed.connect(_on_item_changed)
	GameState.money_changed.connect(_on_money_changed)

func _unhandled_input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("ui_cancel"):
		# If the Sell-All confirm is up, Esc dismisses just that, not the whole shop.
		if _confirm_overlay != null:
			_close_confirm()
		else:
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
	_close_confirm()  # never leave a dangling confirm overlay behind
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

	_apply_title()
	money_label.text = "$%d" % GameState.money

	_build_buy_column()
	_build_sell_column()

# Sets the shop title and, when the shop tracks a reputation NPC, appends a live
# tier + discount readout tinted by tier — teaching the player that being liked is
# saving (or costing) them money. Shops with no reputation npc keep the plain name.
func _apply_title() -> void:
	var npc := _shop.reputation_npc
	if npc == &"":
		title.text = _shop.display_name
		title.remove_theme_color_override("font_color")
		return
	var tier_name := Reputation.get_tier_name(npc)
	var pct := ShopSystem.get_buy_discount_percent(_shop)
	var blurb := "Neutral pricing"
	if pct > 0:
		blurb = "%d%% off" % pct
	elif pct < 0:
		blurb = "%d%% markup" % absi(pct)
	title.text = "%s  -  Reputation: %s (%s)" % [_shop.display_name, tier_name, blurb]
	title.add_theme_color_override("font_color", Reputation.get_tier_color(npc))

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

# BUY: one row per item id the shop sells (infinite stock), followed by teaser
# rows for any reputation-locked stock the player hasn't earned yet.
func _build_buy_column() -> void:
	var unlocked := ShopSystem.get_unlocked_stock(_shop)
	var locked := ShopSystem.get_locked_stock(_shop)

	if unlocked.is_empty() and locked.is_empty():
		var none := Label.new()
		none.text = "Nothing for sale."
		none.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		buy_rows.add_child(none)
		return

	for item_id in unlocked:
		buy_rows.add_child(_make_buy_row(item_id))
	# Locked rows sit at the bottom as a loyalty carrot: a '?' placeholder naming the
	# tier still required, never the item itself.
	for entry in locked:
		buy_rows.add_child(_make_locked_row(entry))

# A teaser row for a reputation-locked item: a masked '?' name and the tier still
# needed to unlock it. No Buy button (nothing to buy yet).
func _make_locked_row(entry: Dictionary) -> Control:
	var panel := PanelContainer.new()
	Glass.apply(panel, 10, 12)
	panel.modulate = Color(1, 1, 1, 0.75)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)

	var name_label := Label.new()
	name_label.text = "? ? ?"
	box.add_child(name_label)

	var gate := Label.new()
	gate.text = "Unlocks at %s reputation" % Reputation.tier_name_of(int(entry["tier"]))
	gate.add_theme_font_size_override("font_size", 12)
	gate.modulate = Color(0.8, 0.75, 0.55)
	box.add_child(gate)

	return panel

# Builds a single buy row: name, price, and a "Buy" button (gated by can_buy).
func _make_buy_row(item_id: StringName) -> Control:
	var panel := PanelContainer.new()
	Glass.apply(panel, 10, 12)
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

	# Line 2b: the item's base value for economic context (dim, only when meaningful).
	if item != null and item.base_value > 0:
		var value_label := Label.new()
		value_label.text = "Base value: $%d" % item.base_value
		value_label.add_theme_font_size_override("font_size", 11)
		value_label.modulate = Color(0.7, 0.7, 0.7)
		box.add_child(value_label)

	# Line 3: the Buy button, only usable if the shop sells it and we can afford it.
	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.disabled = not ShopSystem.can_buy(_shop, item_id)
	buy_btn.pressed.connect(_on_buy_pressed.bind(item_id))
	box.add_child(buy_btn)

	return panel

# Removes any item ids the player is actively collecting for a quest, so bulk
# selling never dumps in-progress quest materials. Reached via the QuestSystem
# autoload and guarded by has_method — if the method is absent we filter nothing,
# so behaviour is unchanged. Returns {ids, skipped} where `skipped` is how many
# ids were removed.
func _exclude_quest_items(ids: Array[StringName]) -> Dictionary:
	var quest_sys := get_node_or_null("/root/QuestSystem")
	if quest_sys == null or not quest_sys.has_method("get_active_quest_item_ids"):
		return {"ids": ids, "skipped": 0}
	var protected = quest_sys.get_active_quest_item_ids()
	if protected == null or protected.is_empty():
		return {"ids": ids, "skipped": 0}
	var kept: Array[StringName] = []
	var skipped := 0
	for id in ids:
		if protected.has(id):
			skipped += 1
		else:
			kept.append(id)
	return {"ids": kept, "skipped": skipped}

# SELL: one row per item the player holds that this shop buys.
func _build_sell_column() -> void:
	var sellable := ShopSystem.get_sellable_item_ids(_shop)
	# Don't list items the player is actively collecting for a quest, so they can't
	# be bulk- or accidentally individually-sold from the shop.
	var filtered = _exclude_quest_items(sellable)
	sellable = filtered["ids"]
	# Only offer the bulk action when there's actually something to sell.
	if _sell_all_btn != null:
		_sell_all_btn.visible = not sellable.is_empty()
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
	Glass.apply(panel, 10, 12)
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

	# Line 2b: the item's base value for economic context (dim, only when meaningful).
	if item != null and item.base_value > 0:
		var value_label := Label.new()
		value_label.text = "Base value: $%d" % item.base_value
		value_label.add_theme_font_size_override("font_size", 11)
		value_label.modulate = Color(0.7, 0.7, 0.7)
		box.add_child(value_label)

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

# --- Sell All quick action -------------------------------------------------

# Opens a confirm panel listing everything the shop will buy + the total payout,
# so a careless click can't dump the whole bag.
func _on_sell_all() -> void:
	if _shop == null:
		return
	var ids := ShopSystem.get_sellable_item_ids(_shop)
	# Never bulk-sell items the player is actively collecting for a quest.
	var filtered = _exclude_quest_items(ids)
	ids = filtered["ids"]
	var skipped: int = filtered["skipped"]
	if ids.is_empty():
		return
	_show_sell_all_confirm(ids, skipped)

func _show_sell_all_confirm(ids: Array[StringName], skipped: int = 0) -> void:
	_close_confirm()  # only ever one overlay at a time

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP  # eat clicks to the shop behind
	Glass.frost(dim)
	add_child(dim)
	_confirm_overlay = dim

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(380, 0)
	Glass.apply(panel, 16, 20)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)

	var head := Label.new()
	head.text = "Sell everything this shop buys?"
	head.add_theme_font_size_override("font_size", 20)
	v.add_child(head)

	var list_scroll := ScrollContainer.new()
	list_scroll.custom_minimum_size = Vector2(0, 220)
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(list_scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(list)

	var total := 0
	for id in ids:
		var cnt: int = Inventory.count_of(id)
		if cnt <= 0:
			continue
		var unit: int = ShopSystem.get_sell_price(_shop, id)
		var line_total: int = unit * cnt
		total += line_total
		var item := Inventory.get_item(id)
		var nm := item.display_name if item else String(id)
		var row := Label.new()
		row.text = "%s x%d   →   $%d" % [nm, cnt, line_total]
		list.add_child(row)

	var total_lbl := Label.new()
	total_lbl.text = "Total: $%d" % total
	total_lbl.add_theme_font_size_override("font_size", 18)
	total_lbl.modulate = Color(0.6, 1.0, 0.6)
	v.add_child(total_lbl)

	# Reassure the player that in-progress quest materials were left untouched.
	if skipped > 0:
		var skip_lbl := Label.new()
		skip_lbl.text = "(%d quest item%s kept)" % [skipped, "" if skipped == 1 else "s"]
		skip_lbl.add_theme_font_size_override("font_size", 12)
		skip_lbl.modulate = Color(0.8, 0.8, 0.55)
		v.add_child(skip_lbl)

	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(btns)

	var confirm := Button.new()
	confirm.text = "Confirm"
	confirm.custom_minimum_size = Vector2(130, 40)
	confirm.pressed.connect(_on_sell_all_confirmed)
	btns.add_child(confirm)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(130, 40)
	cancel.pressed.connect(_close_confirm)
	btns.add_child(cancel)

	confirm.grab_focus.call_deferred()

func _on_sell_all_confirmed() -> void:
	_close_confirm()
	if _shop == null:
		return
	# Re-fetch the sellable set at confirm time (bag may have shifted). Sell each
	# stack in one call; the resulting signals rebuild the panel.
	var ids := ShopSystem.get_sellable_item_ids(_shop)
	# Re-apply the quest-item filter at confirm time too — the active quest set may
	# have changed while the confirm overlay was up.
	var filtered = _exclude_quest_items(ids)
	ids = filtered["ids"]
	for id in ids:
		var have: int = Inventory.count_of(id)
		if have > 0:
			ShopSystem.sell(_shop, id, have)

func _close_confirm() -> void:
	if _confirm_overlay != null:
		_confirm_overlay.queue_free()
		_confirm_overlay = null
