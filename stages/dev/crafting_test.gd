extends Node3D
# Dev scene helper: stock the player with materials so you can immediately try every
# station (smelter, workbench, cooking, bar) and the collector.
func _ready() -> void:
	await get_tree().process_frame
	Inventory.add(&"copper_ore", 12)   # smelter -> copper_ingot
	Inventory.add(&"copper_ingot", 6)  # workbench -> copper_pickaxe
	Inventory.add(&"raw_meat", 6)       # cooking -> cooked_meat
	Inventory.add(&"lava_ash", 12)      # bar -> Amber Ale (ember_ale recipe)
