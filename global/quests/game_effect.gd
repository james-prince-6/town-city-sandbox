# game_effect.gd
# A single, data-driven consequence of something happening in the game.
#
# One GameEffect = one small change to the world: set a flag, give an item, bump
# reputation, hand out money, start a quest, etc. Quests carry a list of them as their
# rewards, applied on completion.
#
# (Dialogue used to share these resources too, but conversations now run on the Dialogue
# Manager addon and express their consequences as inline `do`/`set` GDScript in .dialogue
# files — see entities/npc/dialogue/*.dialogue. This resource lives on purely for quest
# rewards, which are still authored as data .tres in the editor.)
#
# Because each effect is just data (an enum + a target id + an amount), you build them in
# the editor as .tres resources — no code needed to author new outcomes.
# To use: In FileSystem, Right-click -> New -> Resource -> GameEffect.

class_name GameEffect
extends Resource

## What kind of change this effect performs. The other fields are interpreted
## differently depending on which type is chosen (see `apply()` below).
enum EffectType {
	SET_FLAG,            # GameState flag `target` = true
	CLEAR_FLAG,          # erase GameState flag `target`
	GIVE_ITEM,           # Inventory.add(target, amount)
	TAKE_ITEM,           # Inventory.remove(target, amount)
	ADD_REPUTATION,      # Reputation.add_reputation(target, amount)  (amount may be negative)
	ADD_MONEY,           # GameState.add_money(amount)
	START_QUEST,         # QuestSystem.start_quest(target)
	COMPLETE_OBJECTIVE,  # QuestSystem.complete_objective(target, amount)  (amount = objective index)
	COMPLETE_QUEST,      # QuestSystem.complete_quest(target)
	# --- Appended (keep at END so existing serialized int values stay valid) ---
	SET_MOOD,            # NPCMoods.set_mood(target, text_value)
	ADVANCE_TIME,        # Clock.advance_minutes(amount)  (skip `amount` in-game minutes)
	ADD_XP,              # Progression.add_xp(amount)  (grant `amount` progression XP)
}

## Which change to perform.
@export var type: EffectType = EffectType.SET_FLAG

## The id this effect acts on. Meaning depends on `type`:
## flag name, item id, npc id, or quest id.
@export var target: StringName

## A number whose meaning depends on `type`: item count, reputation delta, money
## amount, (for COMPLETE_OBJECTIVE) the objective's index in its quest, or (for
## ADVANCE_TIME) the number of in-game minutes to skip.
@export var amount: int = 1

## A string value some effects use. Used by SET_MOOD (the mood to put the NPC
## `target` into, e.g. &"happy"). Ignored by the other types.
@export var text_value: StringName = &""

## Carry out this effect. Called by the quest system when handing out rewards.
func apply() -> void:
	match type:
		EffectType.SET_FLAG:
			GameState.set_flag(target, true)
		EffectType.CLEAR_FLAG:
			GameState.flags.erase(target)
		EffectType.GIVE_ITEM:
			Inventory.add(target, amount)
		EffectType.TAKE_ITEM:
			Inventory.remove(target, amount)
		EffectType.ADD_REPUTATION:
			Reputation.add_reputation(target, amount)
		EffectType.ADD_MONEY:
			GameState.add_money(amount)
		EffectType.START_QUEST:
			QuestSystem.start_quest(target)
		EffectType.COMPLETE_OBJECTIVE:
			QuestSystem.complete_objective(target, amount)
		EffectType.COMPLETE_QUEST:
			QuestSystem.complete_quest(target)
		EffectType.SET_MOOD:
			NPCMoods.set_mood(target, text_value)
		EffectType.ADVANCE_TIME:
			Clock.advance_minutes(amount)
		EffectType.ADD_XP:
			# Progression is an optional autoload; reach it defensively so quests
			# still apply their other effects if it isn't present.
			var tree := Engine.get_main_loop() as SceneTree
			if tree != null:
				var progression := tree.root.get_node_or_null("/root/Progression")
				if progression != null and progression.has_method("add_xp"):
					progression.add_xp(amount)
		_:
			push_warning("GameEffect.apply: unknown effect type '%s'" % type)
