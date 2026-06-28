# scripts/ui/interaction_ui.gd
# Manages the interaction prompt UI element.
extends Control

## Emitted the moment a fresh interactable comes into focus (the prompt goes from
## hidden -> shown, or switches straight to a different target). Carries the prompt
## text as the target token so listeners (e.g. UISound) can play a soft "acquire"
## pip. We key off the prompt text because that's all this widget is handed; if a
## collider reference is ever threaded through, swap it in as the payload.
signal target_acquired(target)
## Emitted when focus leaves an interactable (prompt hidden, or replaced by a new
## one). Carries the text of the target that was lost.
signal target_lost(target)

@onready var label = $Label # Make sure your Label node is named "Label"

# The prompt text currently in focus ("" == nothing focused). Drives the
# acquire/lost edge detection so each cue fires exactly once per transition.
var _current_target: String = ""

func _ready():
	hide() # Start hidden by default

# Call this to show the UI with a specific message.
func show_prompt(prompt_text):
	label.text = prompt_text
	show()
	var as_text: String = str(prompt_text)
	if as_text != _current_target:
		# Switching directly from one interactable to another counts as losing the
		# old then acquiring the new, so both edges fire.
		if _current_target != "":
			target_lost.emit(_current_target)
		_current_target = as_text
		target_acquired.emit(as_text)

# Call this to hide the UI.
func hide_prompt():
	hide()
	if _current_target != "":
		var prev: String = _current_target
		_current_target = ""
		target_lost.emit(prev)
