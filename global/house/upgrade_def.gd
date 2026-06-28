# upgrade_def.gd
# A data-driven definition of a single HOME upgrade the player can buy at the
# upgrade station. Like Item, this is a Resource (NOT a node): you create one
# .tres per upgrade in res://global/house/upgrades/ and fill in the fields in the
# Inspector. The HouseUpgrades autoload scans that folder at startup, so adding a
# new upgrade is just dropping in a new .tres — no code edits.
#
# An upgrade costs money (always) and optionally a stack of one crafting item
# (e.g. some wood_log for the Kitchen). It can also require ANOTHER upgrade to be
# owned first via `prerequisite` (e.g. Cozy Decor needs the Comfy Bed).

class_name UpgradeDef
extends Resource

## Unique, stable id used as the dictionary key everywhere (owned set, save files,
## prerequisite links). NEVER change this once a save exists or the upgrade is orphaned.
@export var id: StringName = &""

## Human-friendly name shown in the upgrade menu. Safe to change anytime.
@export var display_name: String = "Unnamed Upgrade"

## Flavor / what-it-does text shown under the name in the menu.
@export_multiline var description: String = ""

## Money cost. Always charged when buying (see HouseUpgrades.buy).
@export var cost_money: int = 0

## Optional item cost: the id of a crafting item that must also be spent. Empty
## means "no item cost". Pairs with cost_item_count.
@export var cost_item_id: StringName = &""

## How many of cost_item_id to spend. Ignored when cost_item_id is empty.
@export var cost_item_count: int = 0

## Optional prerequisite: the id of another UpgradeDef that must be owned before
## this one can be bought. Empty means "no prerequisite".
@export var prerequisite: StringName = &""

## Lower sorts first in the menu. Lets you order the list independently of ids.
@export var sort_order: int = 0
