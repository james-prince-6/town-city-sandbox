# goe_animator.gd
# Body locomotion for a GoeCharacter. The GoE model ships with the Quaternius Universal Animation
# Library (43 clips) already RETARGETED AND BAKED onto its Auto-Rig Pro deform skeleton in Blender
# (see docs/goe_character_pipeline.md + tools/blender/goe_bake_ual.py), so the exported GLB carries
# real animations on its own AnimationPlayer. This finds that player and plays clips by name.
#
# Play either a friendly name (idle/walk/run/...) via ALIAS, or any clip name directly
# (e.g. play(&"Sword_Attack")). NOTE: Godot strips the "_Loop" suffix on import, so the in-engine
# names are "Idle"/"Walk"/"Sprint"/... (not "Idle_Loop"). LOOP lists which ones loop.

class_name GoeAnimator
extends Node

## Friendly name -> in-engine clip name (Godot-stripped, no "_Loop").
const ALIAS := {
	&"idle": "Idle", &"walk": "Walk", &"run": "Sprint", &"jog": "Jog_Fwd", &"sprint": "Sprint",
	&"crouch": "Crouch_Idle", &"crouch_walk": "Crouch_Fwd",
	&"jump": "Jump", &"jump_start": "Jump_Start", &"jump_land": "Jump_Land",
	&"punch": "Punch_Cross", &"jab": "Punch_Jab", &"attack": "Sword_Attack", &"sword_idle": "Sword_Idle",
	&"hit": "Hit_Chest", &"hit_head": "Hit_Head", &"death": "Death01", &"roll": "Roll",
	&"sit": "Sitting_Idle", &"talk": "Idle_Talking", &"pickup": "PickUp_Table", &"interact": "Interact",
	&"push": "Push", &"dance": "Dance", &"swim": "Swim_Fwd", &"cast": "Spell_Simple_Idle",
}

## In-engine clip names that should loop (continuous states). Everything else is one-shot.
const LOOP := {
	"Idle": true, "Walk": true, "Walk_Formal": true, "Jog_Fwd": true, "Sprint": true,
	"Crouch_Idle": true, "Crouch_Fwd": true, "Jump": true, "Idle_Talking": true, "Idle_Torch": true,
	"Pistol_Idle": true, "Sitting_Idle": true, "Sitting_Talking": true, "Spell_Simple_Idle": true,
	"Swim_Fwd": true, "Swim_Idle": true, "Push": true, "Dance": true, "Driving": true, "Sword_Idle": true,
}

@export var default_clip: StringName = &"idle"

var _ap: AnimationPlayer
var _key: Dictionary = {}        # resolved friendly/clip name -> actual key in the player
var _clips: PackedStringArray    # playable clip names (excludes the morph-target tracks)

func setup(model: Node3D) -> void:
	_ap = _find(model, "AnimationPlayer") as AnimationPlayer
	if _ap == null:
		push_warning("GoeAnimator: no AnimationPlayer in GoE model")
		return
	_clips = PackedStringArray()
	for k in _ap.get_animation_list():
		if k.begins_with("F_Basemesh"):   # facial morph-target tracks, not body clips
			continue
		_clips.append(k)
		var a := _ap.get_animation(k)
		if a:
			a.loop_mode = Animation.LOOP_LINEAR if LOOP.has(k) else Animation.LOOP_NONE
	if has_clip(default_clip):
		play(default_clip)

## Play a friendly name (ALIAS) or a literal clip name. No-op if it doesn't exist.
func play(name: StringName) -> void:
	if _ap == null: return
	var key := _resolve(name)
	if key != "" and _ap.current_animation != key:
		_ap.play(key)

func has_clip(name: StringName) -> bool:
	return _resolve(name) != ""

## All playable clip names in the GLB (in-engine names).
func built_clips() -> Array:
	return Array(_clips)

func _resolve(name: StringName) -> String:
	var s := String(name)
	if _key.has(s): return _key[s]
	var cand := String(ALIAS.get(name, s))
	var bare := cand.trim_suffix("_Loop")   # tolerate either "Idle_Loop" or "Idle"
	for k in _clips:
		if k == cand or k == bare or k.trim_suffix("_Loop") == bare:
			_key[s] = k
			return k
	return ""

func _find(n: Node, cls: String) -> Node:
	if n.get_class() == cls: return n
	for c in n.get_children():
		var r := _find(c, cls)
		if r: return r
	return null
