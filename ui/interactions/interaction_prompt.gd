# interaction_prompt.gd
# Script for the UI element that pops up to show an interaction is available.
# Attach this to the root node of your InteractionPrompt.tscn scene.

extends CanvasLayer

# We get the child node here. The '$' syntax is a shortcut for get_node().
@onready var panel_container: PanelContainer = $PanelContainer

func _ready() -> void:
	# The UI should be hidden by default when the game starts.
	hide_prompt()

## Shows the interaction prompt with a specific message.
## For example: show_prompt("Enter Building") or show_prompt("Talk")
func show_prompt(text: String) -> void:
	# Set the label's text. We find the Label node inside the PanelContainer.
	panel_container.get_node("Label").text = "[E] %s" % text
	panel_container.show()

## Hides the interaction prompt.
func hide_prompt() -> void:
	panel_container.hide()
