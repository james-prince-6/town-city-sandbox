# dialogue_choice.gd
# A custom resource to define a single player choice in a conversation.
# To use: In FileSystem, Right-click -> New -> Resource -> DialogueChoice.

class_name DialogueChoice
extends Resource

## The text displayed for this choice (e.g., "Yes, I'll help!").
@export var choice_text: String

## The next DialogueResource to load if this choice is selected.
## If this is empty, the conversation ends after this choice.
@export var next_dialogue: DialogueResource
