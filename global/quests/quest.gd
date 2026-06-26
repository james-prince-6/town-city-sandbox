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

## Unique, stable string id used as the dictionary key in QuestSystem and in
## save files. NEVER change this once a save references it. Example: "first_brew".
@export var id: StringName

## Human-friendly name shown in the quest log header. Safe to change anytime.
@export var title: String = "Untitled Quest"

## Flavor text / overview shown under the title.
@export_multiline var description: String = ""

## The goals that make up this quest. The quest is complete once every objective
## here is satisfied. Each entry is a shared QuestObjective template.
@export var objectives: Array[QuestObjective] = []

## What the player gets when the quest completes: items, money, reputation,
## flags, etc. Data-driven GameEffect resources, applied in order by
## QuestSystem.complete_quest().
@export var rewards: Array[GameEffect] = []
