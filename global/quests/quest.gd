# quest.gd
# A whole quest: a title, a description, a list of objectives to complete, and
# the rewards handed out when every objective is done.
#
# Like Item and QuestObjective, this is a data-driven Resource: you build one
# .tres per quest in the FileSystem dock and QuestSystem loads them all from
# res://global/quests/resources/ at startup (keyed by `id`).
#
# IMPORTANT: this is a TEMPLATE only. It holds NO runtime state (active,
# completed, per-objective progress). All of that lives in QuestSystem so the
# Quest resource can be shared and saved without being mutated.
#
# To create one: right-click in the FileSystem -> New Resource... -> Quest.

class_name Quest
extends Resource

## How "important" a quest is — drives grouping/sorting in the quest log and
## which quests are offered as repeatable tasks. KEEP these int values stable
## (they are serialized): only APPEND new tiers at the end.
enum Tier {
	## Backbone story quests. Always tracked, never timed.
	MAIN,
	## Optional one-off content given by NPCs.
	SIDE,
	## Small (often repeatable / timed) errands handed out by task-giver NPCs.
	TASK,
}

## Unique, stable string id used as the dictionary key in QuestSystem and in
## save files. NEVER change this once a save references it. Example: "first_brew".
@export var id: StringName

## Human-friendly name shown in the quest log header. Safe to change anytime.
@export var title: String = "Untitled Quest"

## Flavor text / overview shown under the title.
@export_multiline var description: String = ""

## How this quest is classified (see Tier). Defaults to SIDE so existing quests
## that omit it stay optional side content.
@export var tier: Tier = Tier.SIDE

## LEGACY single-stage goals. Used ONLY when `stages` is empty, so the original
## quests keep working unchanged. When `stages` is non-empty this is ignored.
## The quest is complete once every objective here is satisfied.
@export var objectives: Array[QuestObjective] = []

## PREFERRED multi-part progression. When non-empty, the player works through
## these QuestStages in order and `objectives` above is ignored. Each stage has
## its own objectives + on_complete effects; final `rewards` fire on the last.
@export var stages: Array[QuestStage] = []

## What the player gets when the WHOLE quest completes (last/only stage done):
## items, money, reputation, flags, etc. Data-driven GameEffect resources,
## applied in order by QuestSystem.complete_quest().
@export var rewards: Array[GameEffect] = []

# --- Gating / prerequisites ------------------------------------------------
# These let designers build a natural arc: a quest can refuse to start until an
# earlier quest is finished, or until the main story is underway. QuestSystem.
# start_quest() enforces both (returning early if a gate isn't satisfied), so a
# stray dialogue/effect can't kick off a quest out of order. Both default to
# "ungated" so every existing quest keeps starting exactly as before.

## If set, this quest cannot START until the quest with this id is COMPLETED.
## Empty (the default) means no prerequisite. Use it to chain a follow-up quest
## behind the one it continues from.
@export var prerequisite_quest_id: StringName = &""

## If true, this quest cannot START until at least one MAIN-tier quest has been
## started (i.e. the story is underway). Lets side content wait for the player to
## have begun the main arc. Defaults false so quests are freely startable.
@export var gate_on_main_quest_start: bool = false

# --- TASK-tier only (ignored for MAIN/SIDE) --------------------------------

## If > 0 and tier == TASK, this is a TIMED task: it expires this many in-GAME
## minutes after it is started. 0 = no time limit.
@export var time_limit_minutes: int = 0

## Which NPC offers this task and whose reputation it targets. Empty = not tied
## to a specific giver. Used by QuestSystem's task-offering API.
@export var giver_npc_id: StringName = &""

## If true, this task can be taken again after completing/expiring (subject to
## `cooldown_minutes`) instead of being permanently marked completed.
@export var repeatable: bool = false

## For a repeatable task: how many in-game minutes must pass after it
## completes/expires before it can be re-offered. 0 = immediately re-offerable.
@export var cooldown_minutes: int = 0
