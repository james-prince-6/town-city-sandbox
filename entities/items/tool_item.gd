# tool_item.gd
# A specialised Item that the player can equip and USE to do work in the world:
# mining rocks, chopping driftwood, ladling lava, or swinging as a weapon.
#
# Because it EXTENDS Item, a ToolItem is still just a data resource (.tres). It
# loads from res://global/items/resources/ exactly like a plain Item, stacks in
# the Inventory, and sits in Hotbar slots transparently. The extra fields below
# only matter to systems that care about tools (harvestables, combat).
#
# To create one: right-click in the FileSystem -> New Resource... -> ToolItem,
# fill in the normal Item fields PLUS the tool fields, and save as a .tres.

class_name ToolItem
extends Item

## What kind of tool this is. Harvestables/critters compare their required tool
## against this to decide whether a swing does anything. NONE = not a real tool.
enum ToolType {
	PICKAXE,   ## Mines rock/ore harvestables.
	HATCHET,   ## Chops wood/plant harvestables.
	LADLE,     ## Scoops lava and other liquids.
	WEAPON,    ## Deals damage to entities with a Health component.
	NONE,      ## Inert; usable as a generic held item only.
}

## Which job this tool performs (see ToolType above).
@export var tool_type: ToolType = ToolType.NONE

## Mining/harvest strength. A harvestable that requires power N is only worked by
## a tool whose power >= N. Higher power = can break tougher nodes.
@export var power: int = 1

## How much PlayerStats stamina a single use costs. The harvest/combat code calls
## PlayerStats.use_stamina(stamina_cost) and only proceeds if it returns true.
@export var stamina_cost: float = 10.0

## Damage dealt per hit when tool_type == WEAPON. Ignored for non-weapon tools.
@export var damage: float = 10.0
