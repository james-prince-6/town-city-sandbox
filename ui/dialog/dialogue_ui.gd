# scripts/ui/dialogue_ui.gd
extends Control

# This new signal will notify the player when the dialogue is finished.
signal dialogue_finished

@onready var label = $Panel/Label
var dialogue_lines = []
var current_line = 0

func start_dialogue(text):
	show()
	# For simplicity, we'll treat the whole text as one line.
	# A more complex system would split text into an array.
	dialogue_lines = [text] 
	current_line = 0
	label.text = dialogue_lines[current_line]

func _input(event):
	# Only advance text if the UI is visible.
	if not self.visible:
		return

	if Input.is_action_just_pressed("ui_accept"): # Spacebar by default
		current_line += 1
		if current_line < dialogue_lines.size():
			label.text = dialogue_lines[current_line]
		else:
			# We're at the end of the dialogue. Emit the signal and hide.
			dialogue_finished.emit()
			hide()
