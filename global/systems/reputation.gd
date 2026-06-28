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
## APPEND-ONLY: never insert or reorder — saved scores and the TIER_* tables below
## are indexed by these values.
enum Tier { HOSTILE, DISLIKED, NEUTRAL, FRIENDLY, BELOVED }

## A display colour per tier, so UI (shop header, dialogue speaker name) can paint
## the relationship at a glance: red when the NPC dislikes you, neutral grey in the
## middle, green once you're friends. Keyed by Tier so it stays in lock-step with the
## enum. Tunable — tweak these to restyle every reputation readout at once.
const TIER_COLORS := {
	Tier.HOSTILE: Color(0.86, 0.32, 0.30),
	Tier.DISLIKED: Color(0.85, 0.50, 0.34),
	Tier.NEUTRAL: Color(0.72, 0.72, 0.72),
	Tier.FRIENDLY: Color(0.50, 0.82, 0.48),
	Tier.BELOVED: Color(0.42, 0.92, 0.58),
}

## Milestone gifts: the FIRST time an NPC's score climbs into one of these tiers,
## the player receives the listed item as a token of gratitude (see add_reputation).
## Keyed by Tier; value is { "item": StringName, "qty": int }. Add/remove tiers here
## to retune which milestones gift and what they give. Items must exist in the item
## database, or the grant is silently skipped.
const GIFT_TIERS := {
	Tier.FRIENDLY: {"item": &"health_potion", "qty": 1},
	Tier.BELOVED: {"item": &"health_potion", "qty": 2},
}

## Emitted whenever an NPC's score changes. UI and NPCs connect to this instead
## of polling. Sends the npc id and the new (clamped) value.
signal reputation_changed(npc_id: StringName, value: int)

## APPENDED, additive companion to reputation_changed. Fires ONLY when an applied
## change is large enough to be worth surfacing to the player (|delta| >=
## REP_TOAST_THRESHOLD), so the notification feed can pop "+10 Reputation with
## Marlo" without spamming a toast for every tiny +1 nudge. `delta` is the ACTUAL
## applied change after clamping (so it carries its own sign and is never 0 here);
## `value` is the resulting clamped score. Existing listeners on
## reputation_changed are unaffected — do NOT route gameplay logic through this
## thresholded signal; it exists purely for player-facing notifications.
signal reputation_shifted(npc_id: StringName, delta: int, value: int)

## Minimum magnitude of an APPLIED reputation change before reputation_shifted
## fires. Small nudges stay silent so the toast feed isn't flooded.
const REP_TOAST_THRESHOLD := 5

## npc_id (StringName) -> int score. Missing entries are treated as 0.
var _scores: Dictionary = {}

## Tracks which milestone gifts have ALREADY been handed out so they're once-only,
## even if the player's score later drops and climbs back up. Keyed by the string
## "<npc_id>:<tier_int>" -> true. Persisted in capture_state/restore_state.
var _gift_awarded: Dictionary = {}

# --- Queries ---------------------------------------------------------------

func get_reputation(npc_id: StringName) -> int:
	return _scores.get(npc_id, 0)

## Maps a raw score to its Tier bucket. Single source of truth so get_tier() and the
## milestone-gift crossing check (which needs the tier of an OLD score) stay in sync.
func _tier_for_score(score: int) -> Tier:
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

## Returns which Tier the NPC's current score falls into.
func get_tier(npc_id: StringName) -> Tier:
	return _tier_for_score(get_reputation(npc_id))

## A human-readable name for the NPC's current tier, e.g. "Friendly".
func get_tier_name(npc_id: StringName) -> String:
	return tier_name_of(get_tier(npc_id))

## A human-readable name for ANY Tier value, e.g. tier_name_of(Tier.BELOVED) -> "Beloved".
## Used by UI that needs to label a gate tier (not just the NPC's current one).
func tier_name_of(tier: int) -> String:
	var keys := Tier.keys()
	if tier < 0 or tier >= keys.size():
		return "Unknown"
	return String(keys[tier]).capitalize()

## The display colour for an NPC's current tier (see TIER_COLORS).
func get_tier_color(npc_id: StringName) -> Color:
	return TIER_COLORS.get(get_tier(npc_id), Color.WHITE)

## Resolves a tier NAME ("FRIENDLY", "beloved", ...) to its Tier int. Lets the
## .dialogue files express tier comparisons by name (Dialogue Manager can't reach the
## Tier enum constants directly). Unknown names fall back to NEUTRAL.
func _tier_from_name(tier_name: String) -> int:
	var idx := Tier.keys().find(tier_name.to_upper())
	return idx if idx >= 0 else int(Tier.NEUTRAL)

## True when the NPC's tier is at/above `tier_name` (e.g. is_at_least(&"marlo", "FRIENDLY")).
## Tier-based replacement for the old hardcoded `get_reputation(...) >= 15` checks.
func is_at_least(npc_id: StringName, tier_name: String) -> bool:
	return int(get_tier(npc_id)) >= _tier_from_name(tier_name)

## True when the NPC's tier is at/below `tier_name` (e.g. is_at_most(&"marlo", "HOSTILE")).
func is_at_most(npc_id: StringName, tier_name: String) -> bool:
	return int(get_tier(npc_id)) <= _tier_from_name(tier_name)

# --- Changing --------------------------------------------------------------

## Nudges an NPC's score by `delta` (positive = friendlier). Result is clamped.
func add_reputation(npc_id: StringName, delta: int) -> void:
	set_reputation(npc_id, get_reputation(npc_id) + delta)

## Sets an NPC's score directly. Always clamped to [MIN_REP, MAX_REP] so callers
## don't have to worry about overshooting.
func set_reputation(npc_id: StringName, value: int) -> void:
	var old := get_reputation(npc_id)
	var clamped := clampi(value, MIN_REP, MAX_REP)
	_scores[npc_id] = clamped
	reputation_changed.emit(npc_id, clamped)
	# Only surface a player-facing toast when the change actually landed and is
	# big enough to matter. Clamping at the rep cap can shrink the applied delta
	# below the threshold (or to 0), in which case we stay silent.
	var applied := clamped - old
	if absi(applied) >= REP_TOAST_THRESHOLD:
		reputation_shifted.emit(npc_id, applied, clamped)
	# Milestone gifts: if this change pushed the NPC up into one or more gift tiers
	# for the FIRST time, hand over the token of gratitude. Only ever fires on an
	# upward crossing; restore_state writes _scores directly and never routes here,
	# so loading a save can't re-trigger old gifts.
	var old_tier := _tier_for_score(old)
	var new_tier := _tier_for_score(clamped)
	if new_tier > old_tier:
		_award_tier_gifts(npc_id, old_tier, new_tier)

# --- Milestone gifts -------------------------------------------------------

# Grants any gift tier newly entered in the half-open range (old_tier, new_tier].
func _award_tier_gifts(npc_id: StringName, old_tier: int, new_tier: int) -> void:
	for tier in range(old_tier + 1, new_tier + 1):
		if GIFT_TIERS.has(tier):
			_grant_gift(npc_id, tier)

# Hands the player one milestone gift, once-only per (npc, tier). Reaches the
# Inventory / NotificationFeed autoloads defensively so headless tests and any
# boot order stay graceful.
func _grant_gift(npc_id: StringName, tier: int) -> void:
	var key := "%s:%d" % [String(npc_id), tier]
	if _gift_awarded.get(key, false):
		return
	_gift_awarded[key] = true
	var gift = GIFT_TIERS[tier]
	var item_id: StringName = gift["item"]
	var qty: int = gift["qty"]
	var inv := get_node_or_null("/root/Inventory")
	if inv == null or not inv.has_method("add"):
		return
	inv.add(item_id, qty)
	# Build a friendly toast: "Marlo left you a gift: 2x Health Potion (Beloved)".
	var item_name := String(item_id)
	if inv.has_method("get_item"):
		var item = inv.get_item(item_id)
		if item != null:
			item_name = item.display_name
	var feed := get_node_or_null("/root/NotificationFeed")
	if feed != null and feed.has_method("notify"):
		var who := String(npc_id).capitalize()
		var text := "%s left you a gift: %dx %s (%s)" % [who, qty, item_name, tier_name_of(tier)]
		feed.notify(text, TIER_COLORS.get(tier, Color.WHITE))

# --- Save / load -----------------------------------------------------------

func capture_state() -> Dictionary:
	return {
		"scores": _scores.duplicate(),
		"gift_awarded": _gift_awarded.duplicate(),
	}

func restore_state(data: Dictionary) -> void:
	_scores = data.get("scores", {}).duplicate()
	# Restore the once-only gift ledger so a reloaded save never re-gifts milestones
	# the player already earned. Older saves without this key default to empty.
	_gift_awarded = data.get("gift_awarded", {}).duplicate()
	for npc_id in _scores:
		reputation_changed.emit(npc_id, _scores[npc_id])
