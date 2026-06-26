# descend_portal.gd
# The "stairs down" at the end of a procedural floor. A duck-typed interactable (like the
# dungeon doors / chests): the player's raycast hits its collider and calls interact(), which
# tells the DungeonGenerator to rebuild itself one floor deeper.
#
# On a BOSS floor the portal starts disabled and the generator enables it once the boss dies,
# so you can't skip the fight. On a normal floor it's enabled from the start.

class_name DescendPortal
extends StaticBody3D

## The generator to drive. Set by DungeonGenerator when it places the portal.
var generator: Node = null
## Whether descending is currently allowed (false while a boss is still alive).
var enabled: bool = true
## Floor number we'd descend TO — shown in the prompt so the player knows where they're going.
var next_floor: int = 2
## Prompt shown while locked (boss alive).
var locked_prompt: String = "The way down is sealed — defeat the boss"

func get_interaction_prompt() -> String:
	if not enabled:
		return locked_prompt
	return "Descend to Floor %d" % next_floor

func interact(_player: Node) -> void:
	if not enabled:
		return
	if generator != null and generator.has_method("descend"):
		generator.descend()

## Called by the generator when the boss dies, opening the way down.
func unlock() -> void:
	enabled = true
