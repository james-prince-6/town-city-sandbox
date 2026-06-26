# reputation.gd
# Autoload singleton (registered as "Reputation").
#
# Tracks how each NPC feels about the player as a single number per NPC. Like
# GameState and Inventory, it lives outside swappable scenes so a townsfolk's
# opinion of you survives walking from scene to scene.
#
# Design notes:
# - Scores are tracked by the NPC's StringName id in `_scores` ({ npc_id -> int }).
#   An unknown NPC is treated as 0 (NEUTRAL), so we never need to pre-register
#   anyone — the first time you do something nice or mean, an entry appears.
# - Scores are clamped to [MIN_REP, MAX_REP]. The raw number maps to a friendlier
#   Tier (HOSTILE..BELOVED) that dialogue/quests can branch on.

extends Node

## Lowest / highest a reputation score can reach. Clamped on every write.
const MIN_REP := -100
const MAX_REP := 100

## Friendly buckets the raw score falls into. Use get_tier() / get_tier_name()
## instead of comparing magic numbers all over the codebase.
enum Tier { HOSTILE, DISLIKED, NEUTRAL, FRIENDLY, BELOVED }

## Emitted whenever an NPC's score changes. UI and NPCs connect to this instead
## of polling. Sends the npc id and the new (clamped) value.
signal reputation_changed(npc_id: StringName, value: int)

## npc_id (StringName) -> int score. Missing entries are treated as 0.
var _scores: Dictionary = {}

# --- Queries ---------------------------------------------------------------

func get_reputation(npc_id: StringName) -> int:
	return _scores.get(npc_id, 0)

## Returns which Tier the NPC's current score falls into.
func get_tier(npc_id: StringName) -> Tier:
	var score := get_reputation(npc_id)
	if score <= -50:
		return Tier.HOSTILE
	elif score <= -15:
		return Tier.DISLIKED
	elif score <= 14:
		return Tier.NEUTRAL
	elif score <= 49:
		return Tier.FRIENDLY
	else:
		return Tier.BELOVED

## A human-readable name for the NPC's current tier, e.g. "Friendly".
func get_tier_name(npc_id: StringName) -> String:
	return Tier.keys()[get_tier(npc_id)].capitalize()

# --- Changing --------------------------------------------------------------

## Nudges an NPC's score by `delta` (positive = friendlier). Result is clamped.
func add_reputation(npc_id: StringName, delta: int) -> void:
	set_reputation(npc_id, get_reputation(npc_id) + delta)

## Sets an NPC's score directly. Always clamped to [MIN_REP, MAX_REP] so callers
## don't have to worry about overshooting.
func set_reputation(npc_id: StringName, value: int) -> void:
	var clamped := clampi(value, MIN_REP, MAX_REP)
	_scores[npc_id] = clamped
	reputation_changed.emit(npc_id, clamped)

# --- Save / load -----------------------------------------------------------

func capture_state() -> Dictionary:
	return { "scores": _scores.duplicate() }

func restore_state(data: Dictionary) -> void:
	_scores = data.get("scores", {}).duplicate()
	for npc_id in _scores:
		reputation_changed.emit(npc_id, _scores[npc_id])
