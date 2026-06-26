# world_location.gd
# A named spot NPCs can be told to walk to from their schedule ("home", "market",
# "bed"). Drop these Marker3D nodes around a scene, give each a unique location_id,
# and reference those ids in a ScheduleEntry.
#
# They register themselves in the "world_location" group so NPC.resolve_location()
# can find them by id without hard-coded node paths. Locations are per-scene: an NPC
# only finds markers in the scene it currently lives in.

class_name WorldLocation
extends Marker3D

## The id schedules use to refer to this spot. Make it unique within a scene.
@export var location_id: StringName = &""

func _ready() -> void:
	add_to_group("world_location")
