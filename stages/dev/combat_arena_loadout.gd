# combat_arena_loadout.gd
# Dev-only helper for the combat test arena: on load it hands the player the full
# combat kit and lays it out on the hotbar, so you can walk in and immediately try
# melee, the bow, bombs, smoke, and potions against the monsters. Not used outside
# this test scene.

extends Node3D

func _ready() -> void:
	# Wait one frame so the player and autoloads are fully ready before we equip.
	await get_tree().process_frame

	# Melee + defence.
	Inventory.add(&"steel_sword", 1)
	Inventory.add(&"obsidian_blade", 1)
	Inventory.add(&"wooden_shield", 1)
	# Ranged kit (the new arsenal): bow, crossbow, the three wands, and throwing knives.
	Inventory.add(&"bow", 1)
	Inventory.add(&"crossbow", 1)
	Inventory.add(&"flame_wand", 1)
	Inventory.add(&"frost_wand", 1)
	Inventory.add(&"arcane_wand", 1)
	Inventory.add(&"throwing_knife", 32)
	# Throwables + consumables (reach via the player menu / shuffle onto the hotbar).
	Inventory.add(&"fire_bomb", 5)
	Inventory.add(&"smoke_grenade", 3)
	Inventory.add(&"health_potion", 5)

	# Hotbar showcases the new ranged/spell arsenal alongside a sword + shield.
	Hotbar.set_slot(0, &"steel_sword")
	Hotbar.set_slot(1, &"bow")
	Hotbar.set_slot(2, &"crossbow")
	Hotbar.set_slot(3, &"flame_wand")
	Hotbar.set_slot(4, &"frost_wand")
	Hotbar.set_slot(5, &"arcane_wand")
	Hotbar.set_slot(6, &"throwing_knife")
	Hotbar.set_slot(7, &"wooden_shield")
	Hotbar.select(0)
