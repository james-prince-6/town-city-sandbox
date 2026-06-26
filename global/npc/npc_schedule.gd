# npc_schedule.gd
# A full day's routine: a list of ScheduleEntry lines. The NPC consults this every
# time the Clock ticks and follows whichever entry is currently in effect.
#
# Entries don't need to be in time order — get_current_entry() sorts a copy. The
# routine wraps around midnight: before the first entry of the day, the last entry
# (from "yesterday") is still in effect, so an NPC sent to bed at 22:00 stays there
# until the morning entry kicks in.

class_name NPCSchedule
extends Resource

## The day's entries, in any order. Each is in effect from its time until the next.
@export var entries: Array[ScheduleEntry] = []

## The entry in effect at the given time, or null if the schedule is empty.
func get_current_entry(hour: int, minute: int) -> ScheduleEntry:
	if entries.is_empty():
		return null
	var sorted := entries.duplicate()
	sorted.sort_custom(func(a, b): return a.minutes_of_day() < b.minutes_of_day())
	var now := hour * 60 + minute
	# Default to the last entry: it covers the pre-dawn hours before today's first.
	var chosen: ScheduleEntry = sorted[sorted.size() - 1]
	for entry in sorted:
		if entry.minutes_of_day() <= now:
			chosen = entry
		else:
			break
	return chosen
