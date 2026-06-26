# scripts/world/door.gd
# A teleporter that works with the player's raycast.
extends StaticBody3D

@export_file("*.tscn") var target_scene_path: String
@export var prompt_text: String = "Enter"

## Name of a Marker3D in the destination scene where the player should appear.
## Leave blank to use wherever the destination scene places the player.
## Example: the bar's door sets this to "from_town", and barinside.tscn contains
## a Marker3D named "from_town" just inside the entrance.
@export var target_spawn_point: StringName = &""

# The player will call this to get the UI text.
func get_interaction_prompt():
	return prompt_text

# The player will call this when 'E' is pressed.
func interact(player):
	if target_scene_path == "":
		push_error("Teleport error: Target Scene Path is not set on %s" % name)
		return
	# Route through SceneManager so persistent state survives and the player is
	# placed at the right spawn point, instead of a raw change_scene_to_file().
	SceneManager.change_scene(target_scene_path, target_spawn_point)
