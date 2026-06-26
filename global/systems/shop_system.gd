# shop_system.gd
# Autoload singleton (registered as "ShopSystem").
#
# The pricing + transaction "brain" for shops. A ShopInventory resource is pure
# data (what a shop sells, what it buys, its markups); this node turns that data
# into actual prices and carries out buy/sell transactions by talking to
# GameState (money) and Inventory (the player's bag).
#
# Design notes:
# - There is NO per-shop persistence here. Shops have infinite stock, and the
#   only things that change (the player's money and items) already live in the
#   GameState and Inventory autoloads, which save themselves.
# - Prices can flex with reputation: if a shop names a `reputation_npc`, being
#   liked makes buying cheaper and selling more profitable (see _rep_factor).
#
# Access from anywhere: ShopSystem.buy(shop, "lava_vial"), etc.

extends Node

## How far reputation can move prices, as a fraction. 0.2 means a maxed-out
## reputation shifts prices by up to 20% in the player's favour (and a maxed-out
## NEGATIVE reputation shifts them 20% against the player).
const REP_PRICE_SWING := 0.2

## Emitted after every successful buy or sell. UIs and quests can listen to react
## (play a sound, count sales, etc.). `is_buy` is true for a purchase by the
## player, false for a sale. `total` is the full money moved (price * qty).
signal transaction(shop_id: StringName, item_id: StringName, is_buy: bool, qty: int, total: int)

# --- Reputation-aware pricing ---------------------------------------------

## Returns the buy/sell price multipliers for a shop's reputation npc as
## { "buy": float, "sell": float }. With no npc (empty), prices are unchanged
## (both 1.0). Otherwise reputation is normalised to -1..1 and applied so that
## HIGHER reputation makes buying cheaper and selling more profitable.
func _rep_factor(reputation_npc: StringName) -> Dictionary:
	if reputation_npc == &"":
		return {"buy": 1.0, "sell": 1.0}
	var rep_norm := clampf(Reputation.get_reputation(reputation_npc) / 100.0, -1.0, 1.0)
	# Higher rep -> buy factor below 1.0 (cheaper); sell factor above 1.0 (more).
	var buy := 1.0 - rep_norm * REP_PRICE_SWING
	var sell := 1.0 + rep_norm * REP_PRICE_SWING
	return {"buy": buy, "sell": sell}

## What the player pays to BUY one unit of `item_id` from `shop`. Returns 0 if
## the item is unknown to the database; otherwise at least 1 (never free).
func get_buy_price(shop: ShopInventory, item_id: StringName) -> int:
	var item := Inventory.get_item(item_id)
	if item == null:
		return 0
	var factor: float = _rep_factor(shop.reputation_npc)["buy"]
	return max(int(round(item.base_value * shop.buy_markup * factor)), 1)

## What the player RECEIVES to SELL one unit of `item_id` to `shop`. Returns 0 if
## the item is unknown to the database; otherwise at least 1.
func get_sell_price(shop: ShopInventory, item_id: StringName) -> int:
	var item := Inventory.get_item(item_id)
	if item == null:
		return 0
	var factor: float = _rep_factor(shop.reputation_npc)["sell"]
	return max(int(round(item.base_value * shop.sell_markup * factor)), 1)

# --- What a shop will trade -----------------------------------------------

## True if this shop offers `item_id` for sale to the player.
func shop_sells(shop: ShopInventory, item_id: StringName) -> bool:
	return item_id in shop.stock

## True if this shop is willing to buy `item_id` from the player. A `buys_all`
## shop takes anything worth more than nothing; otherwise the item's category
## must be in the shop's `buy_categories` list.
func shop_buys(shop: ShopInventory, item_id: StringName) -> bool:
	var item := Inventory.get_item(item_id)
	if item == null:
		return false
	if shop.buys_all:
		return item.base_value > 0
	return item.category in shop.buy_categories

# --- Buying ----------------------------------------------------------------

## True if the player could buy one `item_id` right now (the shop sells it and
## the player can afford it).
func can_buy(shop: ShopInventory, item_id: StringName) -> bool:
	if not shop_sells(shop, item_id):
		return false
	return GameState.money >= get_buy_price(shop, item_id)

## Buys `qty` of `item_id` from `shop`. Returns true on success (money spent,
## items added, transaction emitted). On any failure nothing changes and it
## returns false.
func buy(shop: ShopInventory, item_id: StringName, qty: int = 1) -> bool:
	if qty <= 0:
		return false
	if not shop_sells(shop, item_id):
		return false
	var price := get_buy_price(shop, item_id)
	if price <= 0:
		return false
	var total := price * qty
	if not GameState.spend_money(total):
		return false
	Inventory.add(item_id, qty)
	transaction.emit(shop.shop_id, item_id, true, qty, total)
	return true

# --- Selling ---------------------------------------------------------------

## True if the player could sell one `item_id` right now (the shop buys it and
## the player holds at least one).
func can_sell(shop: ShopInventory, item_id: StringName) -> bool:
	if not shop_buys(shop, item_id):
		return false
	return Inventory.has(item_id)

## Sells `qty` of `item_id` to `shop`. Returns true on success (items removed,
## money paid, transaction emitted). On any failure nothing changes and it
## returns false.
func sell(shop: ShopInventory, item_id: StringName, qty: int = 1) -> bool:
	if qty <= 0:
		return false
	if not shop_buys(shop, item_id):
		return false
	if not Inventory.has(item_id, qty):
		return false
	var price := get_sell_price(shop, item_id)
	if price <= 0:
		return false
	# remove() can't fail here since we just checked has(), but honour its result.
	if not Inventory.remove(item_id, qty):
		return false
	var total := price * qty
	GameState.add_money(total)
	transaction.emit(shop.shop_id, item_id, false, qty, total)
	return true

# --- Queries ---------------------------------------------------------------

## The ids of items the player currently holds that this shop is willing to buy.
## Used by the shop UI to build the SELL column.
func get_sellable_item_ids(shop: ShopInventory) -> Array[StringName]:
	var result: Array[StringName] = []
	for id: StringName in Inventory.get_all():
		if shop_buys(shop, id):
			result.append(id)
	return result
