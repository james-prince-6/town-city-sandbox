# scripts/world/door.gd
# A teleporter that works with the player's raycast.
extends StaticBody3D

@export_file("*.tscn") var target_scene_path: String
@export var prompt_text: String = "Enter"

# The player will call this to get the UI text.
func get_interaction_prompt():
	return prompt_text

# The player will call this when 'E' is pressed.
func interact(player):
	print("Player interacted with door. Changing scene...")
	if target_scene_path != "":
		get_tree().change_scene_to_file(target_scene_path)
	else:
		print("Teleport error: Target Scene Path is not set!")
