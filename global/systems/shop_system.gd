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

## Buy-price multiplier per reputation Tier, indexed by Reputation.Tier
## (0 HOSTILE .. 4 BELOVED). HOSTILE pays a 20% surcharge; BELOVED gets 20% off;
## NEUTRAL is exactly the shop's listed price (1.0) so behaviour at zero reputation
## is unchanged. The sell side is MIRRORED (sell multiplier = 2.0 - buy multiplier),
## so a Beloved customer both pays less and is paid more. Tunable — edit this ladder
## to retune the whole reputation economy. Order matches the Tier enum (append-only).
const TIER_BUY_MULT := [1.2, 1.1, 1.0, 0.9, 0.8]

## Legacy continuous-swing constant, kept for any external reference. No longer used
## by pricing (superseded by the TIER_BUY_MULT ladder above).
const REP_PRICE_SWING := 0.2

## Emitted after every successful buy or sell. UIs and quests can listen to react
## (play a sound, count sales, etc.). `is_buy` is true for a purchase by the
## player, false for a sale. `total` is the full money moved (price * qty).
signal transaction(shop_id: StringName, item_id: StringName, is_buy: bool, qty: int, total: int)

# --- Reputation-aware pricing ---------------------------------------------

## Returns the buy/sell price multipliers for a shop's reputation npc as
## { "buy": float, "sell": float }. With no npc (empty), prices are unchanged
## (both 1.0). Otherwise the NPC's reputation Tier picks a step off TIER_BUY_MULT,
## and the sell factor is its mirror (2.0 - buy) so higher reputation makes buying
## cheaper AND selling more profitable.
func _rep_factor(reputation_npc: StringName) -> Dictionary:
	if reputation_npc == &"":
		return {"buy": 1.0, "sell": 1.0}
	var tier := int(Reputation.get_tier(reputation_npc))
	var buy := 1.0
	if tier >= 0 and tier < TIER_BUY_MULT.size():
		buy = TIER_BUY_MULT[tier]
	return {"buy": buy, "sell": 2.0 - buy}

## The buy discount the player currently enjoys at `shop`, as a whole-number percent
## off the listed price: positive = cheaper (Friendly/Beloved), negative = surcharge
## (Disliked/Hostile), 0 at Neutral or for a shop with no reputation npc. Drives the
## shop header readout.
func get_buy_discount_percent(shop: ShopInventory) -> int:
	var factor: float = _rep_factor(shop.reputation_npc)["buy"]
	return int(round((1.0 - factor) * 100.0))

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

# --- Reputation-gated stock -----------------------------------------------

## The item ids `shop` currently offers: its always-on `stock` plus any
## tier_gated_stock entries the player has unlocked by reaching the gate tier.
## Order is base stock first, then unlocked gated items (deduplicated).
func get_unlocked_stock(shop: ShopInventory) -> Array[StringName]:
	var result: Array[StringName] = []
	for id in shop.stock:
		if id not in result:
			result.append(id)
	if shop.tier_gated_stock.is_empty() or shop.reputation_npc == &"":
		return result
	var tier := int(Reputation.get_tier(shop.reputation_npc))
	for gate_tier in shop.tier_gated_stock:
		if int(gate_tier) <= tier:
			for id in shop.tier_gated_stock[gate_tier]:
				if id not in result:
					result.append(id)
	return result

## The gated items the player has NOT yet unlocked, as an array of
## { "id": StringName, "tier": int } so the UI can show a teaser placeholder with
## the tier still required. Excludes anything already in base stock.
func get_locked_stock(shop: ShopInventory) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if shop.tier_gated_stock.is_empty():
		return result
	var tier := -1
	if shop.reputation_npc != &"":
		tier = int(Reputation.get_tier(shop.reputation_npc))
	for gate_tier in shop.tier_gated_stock:
		if int(gate_tier) <= tier:
			continue
		for id in shop.tier_gated_stock[gate_tier]:
			if id in shop.stock:
				continue
			result.append({"id": id, "tier": int(gate_tier)})
	return result

# --- What a shop will trade -----------------------------------------------

## True if this shop offers `item_id` for sale to the player right now — either it's
## in the always-on stock, or it's a tier-gated item the player has unlocked.
func shop_sells(shop: ShopInventory, item_id: StringName) -> bool:
	if item_id in shop.stock:
		return true
	if shop.tier_gated_stock.is_empty() or shop.reputation_npc == &"":
		return false
	var tier := int(Reputation.get_tier(shop.reputation_npc))
	for gate_tier in shop.tier_gated_stock:
		if int(gate_tier) <= tier and item_id in shop.tier_gated_stock[gate_tier]:
			return true
	return false

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
