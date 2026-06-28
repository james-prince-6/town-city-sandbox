# quest_stage.gd
# One STAGE (chapter) of a multi-part quest. A quest's `stages` array is a list
# of these; the player works through them in order. A stage is "done" once every
# objective inside it is satisfied; when that happens its `on_complete` effects
# fire and the quest advances to the next stage (or finishes, if it was last).
#
# Like Quest / QuestObjective / GameEffect this is a pure data Resource — it
# holds NO runtime progress (that lives in QuestSystem keyed by the active quest
# id + stage index), so the same .tres can be shared and saved safely.
#
# To author one: build it as a sub_resource inside a Quest .tres (mirror the
# multi-sub_resource layout of global/quests/resources/sela_harvest.tres), or
# right-click in FileSystem -> New Resource... -> QuestStage.

class_name QuestStage
extends Resource

## Short label for this chapter, shown in the quest log when stages are used,
## e.g. "Find the trapped miners" then "Return to Gus".
@export var title: String = ""

## The goals for THIS stage. The stage completes once every objective here is
## satisfied. Each entry is a shared QuestObjective template (COLLECT_ITEM or
## REACH_FLAG), exactly like the legacy flat Quest.objectives list.
@export var objectives: Array[QuestObjective] = []

## Effects applied the moment THIS stage finishes, BEFORE advancing to the next
## stage. Use them for mid-quest payouts / flag flips / mood changes. Final
## quest rewards still live on Quest.rewards (granted on the LAST stage).
@export var on_complete: Array[GameEffect] = []
