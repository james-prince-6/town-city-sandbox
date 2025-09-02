# dialogue_resource.gd
# A custom resource to hold dialogue data. This is not attached to a node.
# To use: In FileSystem, Right-click -> New -> Resource -> DialogueResource.

class_name DialogueResource
extends Resource

## The name of the character speaking.
@export var speaker_name: String

## An array of dialogue lines. Each line is a string.
@export var dialogue_lines: Array[String]

## An array of player choices. Each choice is a 'DialogueChoice' resource file.
@export var player_choices: Array[DialogueChoice]

# A signal to emit when this part of the conversation is finished.
signal finished
