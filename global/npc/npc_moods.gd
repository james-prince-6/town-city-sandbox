# npc_moods.gd
# Autoload singleton (register in Project Settings -> Autoload as "NPCMoods").
#
# A tiny global registry of every NPC's current mood, keyed by the NPC's stable
# id (e.g. &"marlo" -> &"grumpy"). Like Reputation and GameState, it lives
# OUTSIDE the swappable scene tree so a character's mood survives the player
# walking from scene to scene, and so it can be saved.
#
# Why a global registry instead of a field on the NPC node? Because mood is read and
# written from places with NO reference to any NPC node — .dialogue files (e.g.
# `if NPCMoods.get_mood("ember") == "grumpy"` / `do NPCMoods.set_mood("ember", "happy")`)
# and quest GameEffects. They can only look a mood up by id, so the canonical mood has to
# live somewhere they can reach: here.
#
# Usage:
#   NPCMoods.set_mood(&"marlo", &"happy")
#   if NPCMoods.get_mood(&"marlo") == &"happy": ...

extends Node

## The default mood for any NPC that has never had one set.
const DEFAULT_MOOD := &"neutral"

## Emitted whenever an NPC's mood changes. UI / NPCs connect to this instead of
## polling. Sends the npc id and the new mood.
signal mood_changed(npc_id: StringName, mood: StringName)

## npc_id (StringName) -> mood (StringName). Missing entries read as DEFAULT_MOOD.
var _moods: Dictionary = {}

# --- Queries ---------------------------------------------------------------

## The NPC's current mood, or DEFAULT_MOOD (&"neutral") if none was ever set.
func get_mood(npc_id: StringName) -> StringName:
	return _moods.get(npc_id, DEFAULT_MOOD)

# --- Changing --------------------------------------------------------------

## Set an NPC's mood. Emits mood_changed (even if the value is unchanged, so
## listeners can refresh). Empty ids are ignored so we never key on &"".
func set_mood(npc_id: StringName, mood: StringName) -> void:
	if npc_id == &"":
		return
	_moods[npc_id] = mood
	mood_changed.emit(npc_id, mood)

## Set a starting mood only if this NPC has no mood yet (used when an NPC spawns
## from its definition so a saved/in-progress mood is never clobbered).
func ensure_default(npc_id: StringName, mood: StringName) -> void:
	if npc_id == &"" or _moods.has(npc_id):
		return
	set_mood(npc_id, mood)

# --- Save / load (mirrors Reputation.capture_state/restore_state) -----------

func capture_state() -> Dictionary:
	return { "moods": _moods.duplicate() }

func restore_state(data: Dictionary) -> void:
	var saved: Dictionary = data.get("moods", {})
	_moods = saved.duplicate()
	for npc_id in _moods:
		mood_changed.emit(npc_id, _moods[npc_id])
