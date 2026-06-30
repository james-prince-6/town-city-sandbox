# goe_animator.gd
# Body locomotion for a GoeCharacter. The GoE model ships with its Mixamo clips already
# RETARGETED AND BAKED onto the Auto-Rig Pro deform skeleton (done in Blender — see
# docs/goe_character_pipeline.md), so the exported GLB carries real idle/walk/run animations
# on its own AnimationPlayer. This just finds that player and plays clips by name; no runtime
# retargeting, no bone map. (To add clips, bake more in the Blender step and list them here.)

class_name GoeAnimator
extends Node

## Logical locomotion clips baked into the GLB.
@export var clips: Array[StringName] = [&"idle", &"walk", &"run"]
@export var default_clip: StringName = &"idle"

var _ap: AnimationPlayer
var _built: Array[StringName] = []
var _key: Dictionary = {}          # logical name -> actual animation key in the player

func setup(model: Node3D) -> void:
	_ap = _find(model, "AnimationPlayer") as AnimationPlayer
	if _ap == null:
		push_warning("GoeAnimator: no AnimationPlayer in GoE model")
		return
	var avail := _ap.get_animation_list()
	for c in clips:
		var key := _resolve(avail, String(c))
		if key != "":
			var a := _ap.get_animation(key)
			if a: a.loop_mode = Animation.LOOP_LINEAR
			_key[c] = key
			_built.append(c)
	if default_clip in _built:
		play(default_clip)

func play(name: StringName) -> void:
	if _ap and name in _built and _ap.current_animation != String(_key[name]):
		_ap.play(String(_key[name]))

func built_clips() -> Array:
	return _built.duplicate()

# Imported GLB animations may sit in the default library ("walk") or a named one ("lib/walk").
func _resolve(avail: PackedStringArray, logical: String) -> String:
	for k in avail:
		if k == logical or k.ends_with("/" + logical):
			return k
	return ""

func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls: return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r: return r
	return null
