# collector.gd
# A generic automated resource collector you place in the world (a node that slowly
# "harvests" something for you). Over game-time it banks a configured item into an
# internal buffer up to a cap; walk up and interact to gather whatever it has stored.
#
# Which resource it produces is left to design — set `resource_id` per placement (e.g.
# a mining drill on an ore node sets it to &"copper_ore"; a trap that yields hides sets
# it to a hide id). Leave it blank and it just sits there until configured.
#
# Time-based like the crafting stations: it computes how much to add from the elapsed
# Clock minutes whenever queried, rather than ticking every frame, so it keeps working
# while its scene is unloaded.
extends StaticBody3D

## The item id this collector produces. Set per placement; blank = inert.
@export var resource_id: StringName = &""
## Friendly name for the prompt.
@export var display_name: String = "Collector"
## Game-minutes of elapsed time to bank one unit.
@export var minutes_per_unit: int = 30
## Maximum units it will hold before it stops accruing (collect to free it up).
@export var capacity: int = 10

var _buffer: int = 0
var _last_minute: int = 0

func _ready() -> void:
	add_to_group("machine")
	_last_minute = _now_minutes()

func _now_minutes() -> int:
	return ((GameState.day - 1) * 1440) + (Clock.hour * 60) + Clock.minute

# Top up the buffer based on how many whole units' worth of game-time has elapsed.
func _accrue() -> void:
	if resource_id == &"" or minutes_per_unit <= 0:
		return
	var now: int = _now_minutes()
	var elapsed: int = now - _last_minute
	if elapsed <= 0:
		return
	var produced: int = elapsed / minutes_per_unit
	if produced <= 0:
		return
	_buffer = mini(capacity, _buffer + produced)
	if _buffer >= capacity:
		_last_minute = now  # full: stop banking time we can't store
	else:
		_last_minute += produced * minutes_per_unit  # keep the leftover minutes

# --- Interaction -----------------------------------------------------------

func get_interaction_prompt() -> String:
	_accrue()
	if resource_id == &"":
		return "%s (no resource set)" % display_name
	if _buffer <= 0:
		return "%s (empty)" % display_name
	return "Collect %d %s" % [_buffer, _item_name()]

func interact(_player: Node) -> void:
	_accrue()
	if _buffer > 0 and resource_id != &"":
		Inventory.add(resource_id, _buffer)
		_buffer = 0
		_last_minute = _now_minutes()

func _item_name() -> String:
	var item: Item = Inventory.get_item(resource_id)
	return item.display_name if item != null else String(resource_id)
