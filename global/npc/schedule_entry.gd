# schedule_entry.gd
# One line of an NPC's daily routine: "at 8:00, go to the market and work there".
# Pure data (a Resource) so you author routines in the Inspector with no code.
#
# At this entry's time the NPC walks to `location_id` (a WorldLocation marker in the
# scene) and then switches to `activity` once it arrives. Leave location_id empty to
# just change activity wherever the NPC currently is.

class_name ScheduleEntry
extends Resource

## Hour of day this entry begins, 0-23.
@export_range(0, 23) var hour: int = 8
## Minute this entry begins, 0-59.
@export_range(0, 59) var minute: int = 0

## Id of the WorldLocation to walk to (e.g. &"market", &"home", &"bed"). Empty =
## stay put and just change activity.
@export var location_id: StringName = &""

## Which state to enter on arrival. Must match a registered state name:
## &"Idle", &"Sleep", &"Work", or &"Wander". Defaults to standing idle.
@export var activity: StringName = &"Idle"

## Minutes since midnight, for easy comparison/sorting.
func minutes_of_day() -> int:
	return hour * 60 + minute
