# recipe.gd
# A data-driven definition of a single craftable recipe: what inputs it eats,
# what item it produces, how long the brew takes, and which machine runs it.
# This is a Resource, NOT a node: you create one .tres file per recipe in the
# FileSystem dock and fill in the fields in the Inspector. CraftingSystem scans
# a folder of these at startup, so adding a recipe needs no code edits.
#
# To create one: right-click in the FileSystem -> New Resource... -> Recipe.

class_name Recipe
extends Resource

## Which kind of station can run this recipe. New values are APPENDED so existing
## recipe .tres (which store the int) keep working. Each station prop filters the
## recipe list by this (CraftingSystem.get_recipes_for).
enum MachineType {
	BREWER,     ## Bar mixing station — turns ingredients into drinks.
	SMELTER,    ## Furnace — refines raw materials (ore -> ingots) over time.
	WORKBENCH,  ## Crafts refined materials into tools / gear / parts (usually instant).
	COOKING,    ## Cooking station — its own system: ingredients -> food/meals.
}

## Unique, stable string id used as the dictionary key in CraftingSystem and in
## per-machine state. NEVER change this once it's referenced in a save.
@export var id: StringName

## Human-friendly name shown in the brewing UI. Safe to change anytime.
@export var display_name: String = "Unnamed Recipe"

## The list of required inputs. Each element is a RecipeIngredient
## (item_id + count). All of them must be in the Inventory to start a brew.
@export var inputs: Array[RecipeIngredient] = []

## The Inventory item id produced when the brew is collected (e.g. "molten_mocha").
@export var output_id: StringName

## How many of the output item a single brew yields.
@export var output_count: int = 1

## How long the craft takes, measured in GAME minutes (not real seconds). The
## station compares this against the Clock so timed crafts (smelting/cooking/brewing)
## keep ticking across scene loads. Ignored when `instant` is true.
@export var brew_minutes: int = 30

## If true the craft happens IMMEDIATELY on the Craft button (consume inputs, add
## output) with no timer — used by the workbench. If false the station starts a timed
## job you collect when it finishes (smelter / cooking / bar).
@export var instant: bool = false

## Which station type this recipe belongs to (see MachineType above).
@export var machine_type: MachineType = MachineType.BREWER
