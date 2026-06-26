# shop_inventory.gd
# A data-driven definition of one shop's storefront (what it sells, what it
# buys, and how it prices things). Like Item, this is a Resource, NOT a node:
# you create one .tres file per shop in the FileSystem dock and fill in the
# fields in the Inspector, then drop it onto a Shopkeeper's `shop` slot.
#
# Nothing about a shop's pricing lives in code — ShopSystem reads these fields
# to compute buy/sell prices. That lets you add new shops without scripting.
#
# To create one: right-click in the FileSystem -> New Resource... -> ShopInventory.

class_name ShopInventory
extends Resource

## Unique, stable string id for this shop. Used in transaction signals and any
## bookkeeping. Example: "potion_stall", "ore_trader".
@export var shop_id: StringName

## Human-friendly name shown at the top of the shop UI. Safe to change anytime.
@export var display_name: String = "Shop"

## Item ids this shop SELLS to the player. The shop has infinite quantity of
## each — buying never depletes the stock. Fill with ids from the item database
## (e.g. "lava_vial", "iron_ore").
@export var stock: Array[StringName] = []

## Price multiplier when the player BUYS. The player pays
## round(item.base_value * buy_markup). >1.0 means the shop profits.
@export var buy_markup: float = 1.25

## Price multiplier when the player SELLS. The player receives
## round(item.base_value * sell_markup). <1.0 means the shop profits.
@export var sell_markup: float = 0.5

## If true, this shop buys ANY item with base_value > 0 (a general fence).
## When true, `buy_categories` below is ignored.
@export var buys_all: bool = false

## Item.Category ints this shop buys from the player. Only used when `buys_all`
## is false. Example: [Item.Category.DRINK] to buy finished drinks only.
@export var buy_categories: Array[int] = []

## Optional npc_id whose reputation tweaks this shop's prices. Higher rep makes
## buying cheaper and selling more profitable. Leave empty for fixed prices.
@export var reputation_npc: StringName = &""
