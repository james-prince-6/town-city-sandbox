# quest_objective.gd
# One goal inside a Quest, e.g. "Collect 5 lava ash" or "Reach the volcano rim".
# This is a Resource, NOT a node: you make one .tres per objective in the
# FileSystem dock and fill in the fields in the Inspector, then drop it into a
# Quest's `objectives` list.
#
# IMPORTANT: this is a TEMPLATE only. It stores NO runtime progress (how many
# you've gathered so far, whether it's done, etc). That lives in QuestSystem,
# so the same objective .tres can be shared and re-used safely.
#
# To create one: right-click in the FileSystem -> New Resource... -> QuestObjective.

class_name QuestObjective
extends Resource

## How an objective is checked off.
enum Kind {
	## Done when Inventory.count_of(target) >= required_count. QuestSystem watches
	## the inventory and updates progress automatically.
	COLLECT_ITEM,
	## Done "manually": something else completes it, either a complete_objective()
	## call (e.g. from a dialogue `do QuestSystem.complete_objective(...)`) or the
	## GameState flag named `target` becoming truthy.
	REACH_FLAG,
}

## Text shown to the player in the quest log, e.g. "Gather lava ash".
@export var description: String = ""

## Which rule decides if this objective is complete (see Kind above).
@export var kind: Kind = Kind.COLLECT_ITEM

## What this objective points at. For COLLECT_ITEM it's an item id (e.g.
## "lava_ash"); for REACH_FLAG it's a GameState flag name to watch.
@export var target: StringName

## How many are needed (only meaningful for COLLECT_ITEM). REACH_FLAG ignores
## the count and is simply done or not done.
@export var required_count: int = 1
