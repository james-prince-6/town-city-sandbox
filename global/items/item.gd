# item.gd
# A data-driven definition of a single item type (an ingredient, a finished
# lava drink, a tool, etc.). This is a Resource, NOT a node: you create one
# .tres file per item in the FileSystem dock and fill in the fields in the
# Inspector. Nothing about an item lives in code, which means designers (you!)
# can add new items without touching scripts.
#
# To create one: right-click in the FileSystem -> New Resource... -> Item.

class_name Item
extends Resource

## Broad buckets an item can belong to. Used by the inventory UI for filtering
## and by crafting to decide what fits where. Extend this freely as the game grows.
enum Category {
	INGREDIENT,   ## Raw lava-brewing inputs (ash, minerals, fruit, etc.)
	DRINK,        ## Finished lava drinks you sell or serve
	TOOL,         ## Equipment the player carries/uses
	MATERIAL,     ## Crafting/building materials
	MISC,
	FOOD,         ## Edible/sellable produce and snacks (kept after MISC so existing ids keep their values)
	WEAPON,       ## Melee/ranged combat gear (swords, bows). Appended to preserve existing ids.
	CONSUMABLE,   ## Single-use items with an effect (bombs, potions, smoke grenades).
}

## Unique, stable string id used as the dictionary key everywhere (inventory,
## save files, recipes). NEVER change this once items exist in a save, or those
## items will be orphaned. Example: "lava_ash", "molten_mocha".
@export var id: StringName

## Human-friendly name shown in UI. Safe to change anytime.
@export var display_name: String = "Unnamed Item"

## Flavor text / tooltip description.
@export_multiline var description: String = ""

## Which bucket this item belongs to (see Category enum above).
@export var category: Category = Category.MISC

## The 2D icon shown in inventory slots and shop listings.
@export var icon: Texture2D

## How many of this item can share a single inventory slot. 1 = unstackable.
@export var max_stack: int = 99

## Base buy/sell value in the in-game currency. Shops can mark this up/down.
@export var base_value: int = 0

## Optional 3D model shown when this item is dropped in the world (as a WorldItem)
## and when held in first-person. A Kenney .fbx imports as a PackedScene you can
## drop into this slot. Leave empty to fall back to a small placeholder cube.
@export var world_model: PackedScene

@export_group("Held viewmodel")
## Multiplier on the in-hand size. The viewmodel normalises every model to one base size, then
## applies this — so a greatsword (e.g. 1.5) reads bigger than a dagger (e.g. 0.7) in hand.
@export var held_scale: float = 1.0
## When true (default), the viewmodel ORIENTS this item automatically: it finds the model's
## long axis (blade/shaft), points the business end up-and-forward, and rests the grip in the
## hand — no per-weapon rotation tuning needed. Auto only kicks in for clearly elongated models
## (swords/axes/daggers/staves/wands); chunky models (pickaxe, lantern) fall back to the manual
## base pose. Set false for items whose grip is NOT at one end (bows, crossbows, shields) so they
## keep their hand-authored held_rotation_offset instead.
@export var auto_orient_held: bool = true
## Extra rotation (degrees) for this item's in-hand model. With auto-orient ON this is a small
## fine-tune NUDGE applied in the model's own local axes after auto-orientation (usually leave at
## zero). With auto-orient OFF it is added to the viewmodel's base pose, the classic manual knob.
## Tune so blades point forward, bows sit sideways, staves stand upright, etc.
@export var held_rotation_offset: Vector3 = Vector3.ZERO
## Extra position offset (metres) for this item's in-hand model, on top of the base rest pose.
@export var held_position_offset: Vector3 = Vector3.ZERO

## How well this item can BLOCK incoming melee/ranged damage while held (hold the
## block button). 0 = cannot block at all (most items). When > 0 it is the STAMINA
## cost per 1 point of damage blocked, so a hit is only fully blocked while you have
## the stamina to pay for it — blocking is a costly stopgap, not a free shield.
## Lower = cheaper/better (a sturdy shield ~0.35; a makeshift block ~0.8).
@export var block_modifier: float = 0.0

## Called when the player uses the selected hotbar item (the "use_item" action /
## left-click). The base item does nothing; combat item subclasses override this:
## a weapon swings/fires, a consumable applies or throws its effect. `player` is the
## player node (in group "player"; has $Head/Camera3D and a get_camera() helper).
func use(_player: Node) -> void:
	pass
