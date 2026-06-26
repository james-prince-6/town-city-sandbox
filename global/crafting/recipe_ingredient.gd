# recipe_ingredient.gd
# One required input line for a Recipe (e.g. "Lava Ash x2"). This is a Resource,
# NOT a node: a Recipe holds an array of these to describe everything it needs.
#
# You don't usually create these as standalone .tres files. Instead, when editing
# a Recipe in the Inspector, you add elements to its `inputs` array and each one
# becomes a RecipeIngredient you fill in right there.

class_name RecipeIngredient
extends Resource

## The Inventory item id this line requires. Must match an Item's `id`
## (e.g. "lava_ash", "lava_vial"). Used directly with Inventory.has/remove.
@export var item_id: StringName

## How many of that item the recipe consumes. Defaults to 1.
@export var count: int = 1
