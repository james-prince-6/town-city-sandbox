# game_state.gd
# Autoload singleton (registered in Project Settings -> Autoload as "GameState").
#
# This node lives OUTSIDE the scene tree's swappable part, so it survives every
# scene change. Anything that must persist while the player walks from the town
# into the bar — money, the current day, story flags — belongs here, NOT inside
# a scene. This is the single most important rule for avoiding lost state.
#
# Access from anywhere: GameState.money, GameState.add_money(50), etc.

extends Node

## Emitted whenever the player's money changes. UI (a cash label, the shop)
## connects to this instead of polling every frame.
signal money_changed(new_amount: int)

## Emitted when the in-game day advances. NPC schedules, brewing timers, and
## shop hours will hang off this later.
signal day_changed(new_day: int)

# --- Core persistent state -------------------------------------------------

var money: int = 0:
	set(value):
		money = max(value, 0)
		money_changed.emit(money)

var day: int = 1:
	set(value):
		day = value
		day_changed.emit(day)

## Free-form story/quest flags, e.g. flags["met_mayor"] = true. Using a single
## dictionary keeps save/load trivial and lets quests check arbitrary conditions
## without each one needing its own variable here.
var flags: Dictionary = {}

# --- Money helpers ---------------------------------------------------------

func add_money(amount: int) -> void:
	money += amount

## Tries to spend `amount`. Returns true if the player could afford it (and the
## money was deducted), false otherwise. Always check the return value before
## handing over goods.
func spend_money(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	return true

# --- Flag helpers ----------------------------------------------------------

func set_flag(flag_name: StringName, value: Variant = true) -> void:
	flags[flag_name] = value

func get_flag(flag_name: StringName, default: Variant = false) -> Variant:
	return flags.get(flag_name, default)

# --- Day helpers -----------------------------------------------------------

func advance_day() -> void:
	day += 1

# --- Save / load (foundation) ---------------------------------------------
# A single dictionary snapshot. When we add a real save system, it will gather
# one of these from each system (GameState, Inventory, ...) and write them out.

func capture_state() -> Dictionary:
	return {
		"money": money,
		"day": day,
		"flags": flags.duplicate(true),
	}

func restore_state(data: Dictionary) -> void:
	money = data.get("money", 0)
	day = data.get("day", 1)
	flags = data.get("flags", {}).duplicate(true)
