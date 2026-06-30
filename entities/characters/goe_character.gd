# goe_character.gd
# A reusable GoE character: wraps the exported model (skeleton + skinned meshes), wires up
# the facial-expression controller, and exposes a small API. Body locomotion plays from the
# idle/walk/run clips baked into the GLB (see docs/goe_character_pipeline.md §5 +
# tools/blender/goe_bake_character.py). Drop this scene under an NPC/CharacterBody3D, or standalone.

class_name GoeCharacter
extends Node3D

## Facial expression shown on spawn (see GoeFacialController.EMOTIONS).
@export var start_emotion: StringName = &"neutral"

var facial: Node            # GoeFacialController (loaded by path to stay headless-safe)
var animator: Node          # GoeAnimator (body locomotion via humanoid retarget)
var skeleton: Skeleton3D
var _model: Node3D

const FACIAL := preload("res://entities/characters/goe_facial_controller.gd")
const ANIMATOR := preload("res://entities/characters/goe_animator.gd")

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
	# Body locomotion (plays once the model + clips are humanoid-retargeted; inert until then).
	animator = ANIMATOR.new()
	animator.name = "Animator"
	add_child(animator)
	animator.setup(_model)

## Play a body locomotion clip (idle/walk/run) — no-op until humanoid retarget is applied.
func play_anim(name: StringName) -> void:
	if animator: animator.play(name)

## Logical clips that actually built (empty until the retarget reimport is done).
func built_clips() -> Array:
	return animator.built_clips() if animator else []

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
