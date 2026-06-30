# goe_animator.gd
# Body locomotion for a GoeCharacter via Godot HUMANOID RETARGETING. Once the model glTF and
# the Mixamo clip FBXs are both imported with a SkeletonProfileHumanoid bone map + Fix
# Silhouette (see docs/goe_character_pipeline.md §5), their bones share the same names + a
# normalized rest pose. This builds an AnimationPlayer for the character: it pulls each clip
# out of its source FBX scene, keeps only the ROTATION tracks whose bone exists on the model
# (so root drift is dropped and nothing mismatches), repoints them at the model's Skeleton3D,
# and plays them. Fully defensive: until both sides are retargeted (bone names match) it just
# leaves the model at rest — it can't error.

class_name GoeAnimator
extends Node

## logical name -> source FBX (each holds one Mixamo clip). Edit/extend freely.
@export var clips: Dictionary = {
	&"idle": "res://assets/models/characters/psx/anim/Idle.fbx",
	&"walk": "res://assets/models/characters/psx/anim/Walking (1).fbx",
	&"run": "res://assets/models/characters/psx/anim/Running.fbx",
}
@export var default_clip: StringName = &"idle"

var _ap: AnimationPlayer
var _skel: Skeleton3D
var _built: Array[StringName] = []

func setup(model: Node3D) -> void:
	_skel = _find(model, "Skeleton3D") as Skeleton3D
	if _skel == null:
		push_warning("GoeAnimator: no Skeleton3D under model"); return
	var skel_parent := _skel.get_parent()
	_ap = AnimationPlayer.new()
	_ap.name = "GoeAnimPlayer"
	skel_parent.add_child(_ap)  # default root_node ".." = skel_parent, so "Skeleton3D:bone" resolves
	var lib := AnimationLibrary.new()
	for logical in clips.keys():
		var clip := _build_clip(String(clips[logical]))
		if clip != null and clip.get_track_count() > 0:
			lib.add_animation(logical, clip)
			_built.append(logical)
	_ap.add_animation_library("", lib)
	if default_clip in _built:
		play(default_clip)

## Play a built locomotion clip if present (no-op otherwise).
func play(name: StringName) -> void:
	if _ap and name in _built and _ap.current_animation != String(name):
		_ap.play(String(name))

func built_clips() -> Array:
	return _built.duplicate()

# Pull the real motion clip from an animation FBX, prune to the model's bones, repoint tracks.
func _build_clip(path: String) -> Animation:
	if not ResourceLoader.exists(path):
		return null
	var ps := load(path) as PackedScene
	if ps == null: return null
	var inst := ps.instantiate()
	var src_ap := inst.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var anim: Animation = null
	if src_ap:
		var best := -1
		for cn in src_ap.get_animation_list():
			var a := src_ap.get_animation(cn)
			var keys := 0
			for t in a.get_track_count(): keys += a.track_get_key_count(t)
			if keys > best:
				best = keys; anim = a
	inst.queue_free()
	if anim == null:
		return null
	# Duplicate so we don't mutate the imported resource; prune + repoint.
	var out: Animation = anim.duplicate(true)
	for ti in range(out.get_track_count() - 1, -1, -1):
		var ttype := out.track_get_type(ti)
		if ttype != Animation.TYPE_ROTATION_3D:
			out.remove_track(ti)   # drop position (root drift) + scale tracks
			continue
		var p := out.track_get_path(ti)
		var bone := String(p.get_subname(0)) if p.get_subname_count() > 0 else ""
		if bone == "" or _skel.find_bone(bone) == -1:
			out.remove_track(ti)   # bone not on this model (e.g. pre-retarget) -> skip
			continue
		out.track_set_path(ti, NodePath("Skeleton3D:" + bone))
	out.loop_mode = Animation.LOOP_LINEAR
	return out

func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls: return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r: return r
	return null
