# scripts/ui/interaction_ui.gd
# Manages the interaction prompt UI element.
extends Control

@onready var label = $Label # Make sure your Label node is named "Label"

func _ready():
	hide() # Start hidden by default

# Call this to show the UI with a specific message.
func show_prompt(prompt_text):
	label.text = prompt_text
	show()

# Call this to hide the UI.
func hide_prompt():
	hide()
