# goe_character.gd
# A reusable GoE character: wraps the exported model (skeleton + skinned meshes), wires up
# the facial-expression controller, and exposes a small API. Body locomotion is played by an
# AnimationPlayer once the model is humanoid-retargeted (see goe_arp_bonemap.tres + the import
# step in docs). Drop this scene under an NPC/CharacterBody3D, or use it standalone.

class_name GoeCharacter
extends Node3D

## Facial expression shown on spawn (see GoeFacialController.EMOTIONS).
@export var start_emotion: StringName = &"neutral"

var facial: Node            # GoeFacialController (loaded by path to stay headless-safe)
var skeleton: Skeleton3D
var _model: Node3D

const FACIAL := preload("res://entities/characters/goe_facial_controller.gd")

func _ready() -> void:
	_model = get_node_or_null("Model")
	if _model == null:
		push_warning("GoeCharacter: expected a 'Model' child (the GoE glTF instance).")
		return
	skeleton = _find(_model, "Skeleton3D")
	facial = FACIAL.new()
	facial.name = "Facial"
	add_child(facial)
	facial.setup(_model)
	if start_emotion != &"neutral":
		facial.set_emotion(start_emotion)

## Blend the face to a semantic emotion (happy/sad/angry/surprised/…).
func set_emotion(emotion: StringName, weight: float = 1.0) -> void:
	if facial: facial.set_emotion(emotion, weight)

## Direct single-shape control (fine-grained faces).
func set_face_shape(shape: StringName, weight: float) -> void:
	if facial: facial.set_shape(shape, weight)

func available_emotions() -> Array:
	return facial.available_emotions() if facial else []

func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls: return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r: return r
	return null
