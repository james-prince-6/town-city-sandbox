# boot.gd
# The project's main scene is this tiny bootstrap. Its only job is to hand off to the
# real first level THROUGH SceneManager, so that even the opening scene is parented
# under the global pixel-art world SubViewport (see scene_manager.gd). Without this, the
# main scene would load directly under the tree root and render full-resolution.
extends Node

## The first real scene to show on launch. Points at the blank town template you
## build out; the old fully-built town is archived at res://stages/archive/town.tscn.
const FIRST_SCENE: String = "res://stages/overworld/town_template.tscn"

func _ready() -> void:
	# Show the title screen first; its New Game / Continue / Load buttons enter the world
	# through SceneManager. (MainMenu holds its own copy of the first-scene path.)
	MainMenu.open()
