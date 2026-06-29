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

## Parks this teleporter without deleting it (v1 scope lock — M-A). When true the
## gate shows `locked_prompt` instead of `prompt_text` and refuses to teleport (a
## soft toast fires if NotificationFeed is present). Lets us narrow the v1 reachable
## set to one wild area + one dungeon while leaving the parked destinations on disk
## and visible in town as future content — flip back to false to re-open. Additive
## and backward-compatible: existing gates default to unlocked and behave exactly as before.
@export var locked: bool = false

## Prompt shown while `locked`. Kept generic so any parked gate reads sensibly under
## its own sign (e.g. an "Iron Hills" sign over a "[E] Closed for now" prompt).
@export var locked_prompt: String = "Closed for now"

# The player will call this to get the UI text.
func get_interaction_prompt():
	if locked:
		return locked_prompt
	return prompt_text

# The player will call this when 'E' is pressed.
func interact(player):
	if locked:
		# Parked destination: don't teleport. Nudge the player with a soft toast if the
		# notification feed autoload is present; otherwise stay silent (guarded no-op).
		var feed := get_node_or_null("/root/NotificationFeed")
		if feed != null and feed.has_method("notify"):
			feed.notify("This area isn't open yet.")
		return
	if target_scene_path == "":
		push_error("Teleport error: Target Scene Path is not set on %s" % name)
		return
	# Route through SceneManager so persistent state survives and the player is
	# placed at the right spawn point, instead of a raw change_scene_to_file().
	SceneManager.change_scene(target_scene_path, target_spawn_point)
