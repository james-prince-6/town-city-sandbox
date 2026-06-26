# arcade_cabinet.gd
# An interactable arcade cabinet. Extends Prop, so it inherits the auto-fit box
# collider and the duck-typed interaction contract (get_interaction_prompt() +
# interact(player)). The player walks up, the interaction raycast picks up the
# prompt, and interacting launches this cabinet's minigame through the
# MinigameManager autoload.
#
# The same prop hosts EITHER game: `minigame_scene` is an exported PackedScene,
# so arcade_cabinet.tscn launches the Whack game and claw_machine.tscn (same
# script, different model + scene) launches Simon. To add more cabinets, make a
# scene with this script on a StaticBody3D, drop the model under it as "Model",
# and point `minigame_scene` at any scene whose root extends Minigame.

class_name ArcadeCabinet
extends Prop

## The minigame this cabinet launches. Its scene root must extend Minigame.
## Wired up in the .tscn (Whack for arcade-machine, Simon for claw-machine).
@export var minigame_scene: PackedScene

func _ready() -> void:
	# Default prompt if the scene didn't set one; keeps cabinets self-describing.
	if interaction_prompt == "":
		interaction_prompt = "Play"
	# Let Prop build the auto collider.
	super._ready()

# Duck-typed entry point called by the interaction raycast. Hands off to the
# MinigameManager, which pauses the world and runs the game.
func interact(_player) -> void:
	if minigame_scene == null:
		push_warning("ArcadeCabinet '%s' has no minigame_scene assigned." % name)
		return
	MinigameManager.play(minigame_scene)
