# npc_animator.gd
# Gives an NPC a real animated 3D body built from the Kenney rigged-character kit.
#
# The kit ships the mesh and the animations in SEPARATE files: a base model FBX
# (just the rig + mesh, no AnimationPlayer) and one FBX per animation, each holding
# its clip on the same shared skeleton. This node assembles them at runtime:
#   1. instance the base model under itself,
#   2. pull each clip out of its animation FBX into one shared AnimationLibrary,
#   3. add an AnimationPlayer beneath the model root with that library,
# so play(&"walk") / play(&"idle") just work. Because every kit file uses the same
# "Root/Skeleton3D" rig, the clips' bone tracks resolve against the base model with
# no retargeting.
#
# It's deliberately tolerant: if the base model is unset or a clip file is missing,
# it just does less (no model, or fewer clips) rather than erroring — so an NPC with
# no model assigned keeps its placeholder capsule and play() is a harmless no-op.

class_name NPCAnimator
extends Node3D

## Base rigged character mesh, e.g. characterMedium.fbx. Leave null to keep the
## NPC's placeholder capsule and disable animation entirely.
@export var model_scene: PackedScene

## Optional recolor skin (one of the kit's Skins/*.png) applied to the body's
## material albedo. Leave null to use the model's default look.
@export var skin_texture: Texture2D

## The model is uniformly scaled so its total height matches this (metres), since
## kit models don't all import at the same size. Feet sit at the NPC's origin.
@export var target_height: float = 1.8

## Small upward lift (metres) applied after grounding. Grounding aligns the lowest toe
## BONE to the floor, but the foot MESH extends a little below that bone, so without a
## nudge the soles dip underground. ~0.03 reads as planted; raise if feet still clip.
@export var foot_clearance: float = 0.03

## Half-rotate the body. The Kenney characters face +Z, but Godot's look_at aims a
## node's -Z at its target, so the default 180° keeps them facing where they walk.
@export var face_offset_degrees: float = 180.0

## Cross-fade time between clips (seconds).
@export var blend_time: float = 0.15

## Whether to load the Kenney per-clip animation FBXs (ANIM_SOURCES). Set FALSE for models on a
## different rig (e.g. the PSX/Mixamo characters) so we don't try to apply Kenney-rig clips to
## them. With this false and no animation_source, the model is built STATIC (idle pose) — play()
## becomes a no-op until an animation_source is provided.
@export var use_kit_animations: bool = true

## OPTIONAL shared animation library (a single imported scene whose AnimationPlayer holds many
## named clips — e.g. a Mixamo set rigged to match this model). When set, its clips are loaded
## INSTEAD of the Kenney kit. This is the hook for the incoming Mixamo animations: drop the
## library scene here and the same rigged model animates from it.
@export var animation_source: PackedScene

## Load the curated Mixamo clip set (MIXAMO_SOURCES) and apply it to this Mixamo-rigged (PSX)
## model. Takes priority over the kit / animation_source. This is what the PSX NPCs use.
@export var use_mixamo: bool = false

# Logical clip name -> Mixamo FBX (one clip each, named "Take 001"). These are mixamorig_-rigged
# so they drive the PSX models directly; we just remap each track's node path to the model's
# Skeleton3D and freeze the hip's horizontal drift (movement is code-driven). Emotes here are
# also used by the interaction system (play_anim).
const MIXAMO_DIR := "res://assets/models/characters/psx/anim/"
const MIXAMO_SOURCES := {
	"idle": "Breathing Idle.fbx",
	"walk": "Walking (1).fbx",
	"run": "Running.fbx",
	"interact": "Picking Up.fbx",
	"talk": "Talking.fbx",
	"wave": "Waving.fbx",
	"sit": "Sitting Idle.fbx",
	"sleep": "Sleeping Idle.fbx",
	"cheer": "Cheering.fbx",
	"angry": "Angry.fbx",
	"salute": "Salute.fbx",
	"look": "Looking Around.fbx",
}
const MIXAMO_LOOP := {"idle": true, "walk": true, "run": true, "talk": true, "sit": true, "sleep": true, "look": true}

# Built once and shared across every PSX NPC (all share the "Skeleton3D" bone paths), so we don't
# re-instance a dozen animation FBX per character. Keyed by MIXAMO_DIR.
static var _mixamo_cache: Dictionary = {}

# Logical clip name -> animation FBX that contains it. These are the kit defaults;
# the real clip inside each is auto-detected (it's the one that isn't the bind pose).
const ANIM_SOURCES := {
	"idle": "res://assets/models/characters/animated-characters/Animations/idle.fbx",
	"walk": "res://assets/models/characters/animated-characters/Animations/walk.fbx",
	"run": "res://assets/models/characters/animated-characters/Animations/run.fbx",
	"interact": "res://assets/models/characters/animated-characters/Animations/interactStanding.fbx",
}

# Clips that should loop while playing.
const LOOPING := {"idle": true, "walk": true, "run": true, "interact": true}

var _anim_player: AnimationPlayer
var _model_root: Node3D
var _current: StringName = &""
# Set when a skeleton model needs grounding (see _normalize_height); cleared once grounded.
var _pending_ground: bool = false
var _ground_tries: int = 0

func _ready() -> void:
	if model_scene == null:
		return
	_build_model()
	if _anim_player and _anim_player.has_animation("idle"):
		play(&"idle")

# Skeleton bone poses aren't valid for the first few frames after a build (the skeleton only
# reports real foot heights once the AnimationPlayer has applied a pose), so grounding retries
# here until the skeleton is actually posed, then stops processing.
func _process(_delta: float) -> void:
	if not _pending_ground:
		set_process(false)
		return
	_ground_tries += 1
	# Let the idle animation settle first, then ground to the pose that's actually shown (a few
	# frames in), so the planted feet match the displayed stance rather than the bare rest pose.
	if _ground_tries < 8:
		return
	if _model_root == null or not is_instance_valid(_model_root) \
			or _ground_to_skeleton(_model_root) or _ground_tries > 40:
		_pending_ground = false
		set_process(false)

## Reconfigure this animator from an NPCDefinition and (re)build the body.
##
## Children _ready() before their parent, so when npc.gd applies a definition the
## animator has usually ALREADY built from whatever model_scene the scene set. This
## lets npc.gd push the definition's visuals in afterwards: it swaps the fields,
## tears down any model built from the old ones, and rebuilds. Tolerant of a null
## model_scene (clears back to the placeholder capsule). Additive — nothing else
## calls this, so animators configured purely in the Inspector are unaffected.
func apply_definition(def_model_scene: PackedScene, def_skin: Texture2D, def_target_height: float) -> void:
	model_scene = def_model_scene
	skin_texture = def_skin
	target_height = def_target_height
	rebuild()

## Tear down the current body (if any) and build it again from the current
## model_scene / skin_texture / target_height. No-op-safe with a null model_scene.
func rebuild() -> void:
	if _model_root and is_instance_valid(_model_root):
		_model_root.queue_free()
	_model_root = null
	_anim_player = null
	_current = &""
	if model_scene == null:
		return
	_build_model()
	if _anim_player and _anim_player.has_animation("idle"):
		play(&"idle")

## True once a real model has been built (npc.gd uses this to hide the capsule).
func has_model() -> bool:
	return _model_root != null

## Number of animation clips successfully loaded (0 if none / no model). Handy for tests.
func clip_count() -> int:
	if _anim_player == null:
		return 0
	return _anim_player.get_animation_list().size()

## Play a logical clip by name (&"idle", &"walk", ...). Falls back to idle for any
## name we don't have, and no-ops entirely when there's no model.
func play(anim_name: StringName) -> void:
	if _anim_player == null:
		return
	var key := String(anim_name)
	if not _anim_player.has_animation(key):
		key = "idle"
	if not _anim_player.has_animation(key):
		return
	if _current == StringName(key) and _anim_player.is_playing():
		return
	_current = StringName(key)
	_anim_player.play(key, blend_time)

# --- Build -----------------------------------------------------------------

func _build_model() -> void:
	_model_root = model_scene.instantiate() as Node3D
	if _model_root == null:
		push_warning("NPCAnimator: model_scene did not instance a Node3D.")
		return
	add_child(_model_root)
	_normalize_height(_model_root)
	_model_root.rotation_degrees.y += face_offset_degrees
	_apply_skin(_model_root)
	_build_clips()

# Build the animation library from whichever source applies, attach a player. With neither a
# source nor the kit (e.g. a PSX model awaiting Mixamo clips) the model stays static and _anim_player
# is left null, so play() harmlessly no-ops.
func _build_clips() -> void:
	var library := AnimationLibrary.new()
	if use_mixamo:
		_collect_mixamo_clips(library)
	elif animation_source != null:
		_collect_source_clips(library)
	elif use_kit_animations:
		_collect_kit_clips(library)
	else:
		return  # static model

	if library.get_animation_list().is_empty():
		return
	_anim_player = AnimationPlayer.new()
	_model_root.add_child(_anim_player)
	# Clip tracks are authored relative to the model root (Root/Skeleton3D:bone),
	# which is this AnimationPlayer's parent — the default root_node, so it resolves.
	_anim_player.add_animation_library("", library)

# The original Kenney path: one FBX per clip (ANIM_SOURCES), each holding a single real clip.
func _collect_kit_clips(library: AnimationLibrary) -> void:
	for key in ANIM_SOURCES:
		var clip := _extract_clip(ANIM_SOURCES[key])
		if clip == null:
			continue
		# Defensive: drop any whole-body translation track so locomotion clips animate in place.
		_strip_root_motion(clip)
		if LOOPING.get(key, false):
			clip.loop_mode = Animation.LOOP_LINEAR
		library.add_animation(StringName(key), clip)

# Shared-library path: copy every clip out of animation_source's AnimationPlayer, keyed by a
# normalized name (lowercased, stripped of "Armature|"/"mixamo" cruft) so play(&"idle") resolves.
# Locomotion-ish clips loop. (Finalize the name map once the Mixamo clip names are known.)
func _collect_source_clips(library: AnimationLibrary) -> void:
	var ps := animation_source
	var scene := ps.instantiate()
	var ap := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null:
		for clip_name in ap.get_animation_list():
			var clip := ap.get_animation(clip_name).duplicate() as Animation
			_strip_root_motion(clip)
			var norm := _normalize_clip_name(String(clip_name))
			if norm.contains("idle") or norm.contains("walk") or norm.contains("run"):
				clip.loop_mode = Animation.LOOP_LINEAR
			library.add_animation(StringName(norm), clip)
	scene.free()

func _normalize_clip_name(raw: String) -> String:
	var n := raw
	if n.contains("|"):
		n = n.get_slice("|", n.get_slice_count("|") - 1)
	return n.to_lower()

# --- Mixamo clip set (PSX characters), RETARGETED to this model's rig -------
#
# The Mixamo ANIMATION fbxs and the PSX MODEL fbxs share bone NAMES but bind in DIFFERENT rest
# poses AND use different per-bone axis conventions (hips ~90° off, arms ~175°). A closed-form
# rotation transfer either twists the body or swaps the arms left/right. So we RETARGET by AIM:
# each frame we point every model bone's primary-child direction the same WORLD way the source
# bone points its child, preserving the model's own bone roll. Matching limb DIRECTIONS (the
# silhouette) reproduces the pose with left/right correct, from the model's own upright rest.
# Rotation-only — positions stay at the model's rest (proportions are the model's, no root slide;
# grounding handles vertical). See _bake_retargeted_clip.
#
# Each source fbx exposes a static 1-key "Take 001" plus the real multi-key "mixamo_com" clip;
# we pick the one with the most keyframes. The finished library is cached statically and shared
# across every PSX body on this rig, so the (heavier) bake runs only once.
const RETARGET_FPS: float = 30.0

func _collect_mixamo_clips(library: AnimationLibrary) -> void:
	var cached = _mixamo_cache.get(MIXAMO_DIR)
	if cached != null:
		var lib: AnimationLibrary = cached
		for clip_name in lib.get_animation_list():
			library.add_animation(clip_name, lib.get_animation(clip_name))
		return

	var model_skel := _model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if model_skel == null:
		return

	for key in MIXAMO_SOURCES:
		var baked := _load_and_retarget(MIXAMO_DIR + MIXAMO_SOURCES[key], model_skel, MIXAMO_LOOP.get(key, false))
		if baked != null:
			library.add_animation(StringName(key), baked)

	_mixamo_cache[MIXAMO_DIR] = library

# Load one Mixamo fbx, grab its motion clip + source skeleton, and bake a model-retargeted clip.
func _load_and_retarget(path: String, model_skel: Skeleton3D, loop: bool) -> Animation:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var scene := ps.instantiate()
	var src_skel := scene.find_child("Skeleton3D", true, false) as Skeleton3D
	var src_ap := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var baked: Animation = null
	if src_skel != null and src_ap != null:
		var src_clip := _pick_motion_clip(src_ap)
		if src_clip != null:
			baked = _bake_retargeted_clip(src_clip, src_skel, model_skel, loop)
	scene.free()
	return baked

# Of an fbx's clips, the one with the most keyframes (the real animation, not the static
# single-key "Take 001"); skips the import "RESET" pose.
func _pick_motion_clip(ap: AnimationPlayer) -> Animation:
	var best: Animation = null
	var best_keys := -1
	for clip_name in ap.get_animation_list():
		if String(clip_name) == "RESET":
			continue
		var clip := ap.get_animation(clip_name)
		var total := 0
		for ti in range(clip.get_track_count()):
			total += clip.track_get_key_count(ti)
		if total > best_keys:
			best_keys = total
			best = clip
	return best

# Bake `src_clip` into a NEW rotation-only clip for `model_skel` using AIM (silhouette)
# retargeting: each frame, point every model bone's primary-child direction the same world way
# the source bone points its child, while preserving the model's OWN bone roll. The two rigs use
# different bone-axis conventions (a closed-form rotation transfer swaps the arms), but matching
# limb DIRECTIONS reproduces the pose with left/right correct. Positions stay at the model's rest.
func _bake_retargeted_clip(src_clip: Animation, src_skel: Skeleton3D, model_skel: Skeleton3D, loop: bool) -> Animation:
	var length: float = src_clip.length
	if length <= 0.0:
		return null
	var frames: int = maxi(2, int(ceil(length * RETARGET_FPS)) + 1)

	# Source rig: local rest transform, parent, and any rotation track driving each bone.
	var s_count: int = src_skel.get_bone_count()
	var s_parent := PackedInt32Array()
	var s_rest: Array = []
	for i in range(s_count):
		s_parent.append(src_skel.get_bone_parent(i))
		s_rest.append(src_skel.get_bone_rest(i))
	var s_track: Dictionary = {}
	for ti in range(src_clip.get_track_count()):
		if src_clip.track_get_type(ti) != Animation.TYPE_ROTATION_3D:
			continue
		var sbi := src_skel.find_bone(String(src_clip.track_get_path(ti).get_concatenated_subnames()))
		if sbi >= 0:
			s_track[sbi] = ti

	# Model rig: rest rotation per bone; the primary child (the one with the most descendants, i.e.
	# the limb's continuation) and the rest direction toward it (in parent frame); a source index;
	# and an output track. Subtree sizes pick the primary child for branch bones (hips/spine).
	var m_count: int = model_skel.get_bone_count()
	var subtree: Array = []
	subtree.resize(m_count)
	for i in range(m_count):
		subtree[i] = 1
	for i in range(m_count - 1, 0, -1):
		var pp: int = model_skel.get_bone_parent(i)
		if pp >= 0:
			subtree[pp] = int(subtree[pp]) + int(subtree[i])
	var out := Animation.new()
	out.length = length
	out.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var m_rest_q: Dictionary = {}
	var m_prim: Dictionary = {}
	var m_rest_dir: Dictionary = {}
	var m_to_s: Dictionary = {}
	var m_track: Dictionary = {}
	for i in range(m_count):
		m_rest_q[i] = model_skel.get_bone_rest(i).basis.get_rotation_quaternion()
		var nm := model_skel.get_bone_name(i)
		var si := src_skel.find_bone(nm)
		if si >= 0:
			m_to_s[i] = si
			var out_ti := out.add_track(Animation.TYPE_ROTATION_3D)
			out.track_set_path(out_ti, NodePath("Skeleton3D:" + nm))
			m_track[i] = out_ti
		var best := -1
		var best_sz := -1
		for j in range(m_count):
			if model_skel.get_bone_parent(j) == i and int(subtree[j]) > best_sz:
				best_sz = int(subtree[j])
				best = j
		if best >= 0:
			m_prim[i] = best
			var clp: Vector3 = model_skel.get_bone_rest(best).origin
			var dbc: Vector3 = clp.normalized() if clp.length() > 0.0001 else Vector3.UP
			m_rest_dir[i] = (m_rest_q[i] as Quaternion) * dbc

	# Per frame: build the source global transforms analytically, then aim each model bone.
	var s_glob: Array = []
	s_glob.resize(s_count)
	for f in range(frames):
		var t: float = (float(f) / float(frames - 1)) * length
		for i in range(s_count):
			var st: Transform3D = s_rest[i]
			var rot: Quaternion = st.basis.get_rotation_quaternion()
			if s_track.has(i):
				rot = src_clip.rotation_track_interpolate(int(s_track[i]), t)
			var local := Transform3D(Basis(rot), st.origin)
			var p: int = s_parent[i]
			if p < 0:
				s_glob[i] = local
			else:
				var pgt: Transform3D = s_glob[p]
				s_glob[i] = pgt * local
		var m_glob: Dictionary = {}
		for i in range(m_count):
			var q: Quaternion = m_rest_q[i]
			if m_prim.has(i) and m_to_s.has(i) and m_to_s.has(int(m_prim[i])):
				var si2: int = m_to_s[i]
				var sc: int = m_to_s[int(m_prim[i])]
				var sgt_i: Transform3D = s_glob[si2]
				var sgt_c: Transform3D = s_glob[sc]
				var a_src: Vector3 = sgt_c.origin - sgt_i.origin
				if a_src.length() > 0.0001:
					a_src = a_src.normalized()
					var pp2: int = model_skel.get_bone_parent(i)
					var par_basis := Basis()
					if pp2 >= 0 and m_glob.has(pp2):
						par_basis = m_glob[pp2]
					var a_target: Vector3 = par_basis.inverse() * a_src
					q = _from_to_quat(m_rest_dir[i], a_target) * (m_rest_q[i] as Quaternion)
			var pp3: int = model_skel.get_bone_parent(i)
			var pb := Basis()
			if pp3 >= 0 and m_glob.has(pp3):
				pb = m_glob[pp3]
			m_glob[i] = pb * Basis(q)
			if m_track.has(i):
				out.rotation_track_insert_key(int(m_track[i]), t, q.normalized())
	return out

# Shortest-arc rotation taking direction `a` onto direction `b`, with a stable fallback when
# they're ~antiparallel (the two-vector Quaternion ctor is undefined at exactly 180°).
func _from_to_quat(a: Vector3, b: Vector3) -> Quaternion:
	if a.dot(b) < -0.99999:
		var axis: Vector3 = a.cross(Vector3.RIGHT)
		if axis.length() < 0.01:
			axis = a.cross(Vector3.FORWARD)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(a, b)

# Pull the real clip out of an animation FBX: instance it, find its AnimationPlayer,
# and grab the animation that isn't the bind/"Targeting Pose". Returns a duplicate
# (so we own a mutable copy we can set looping on) or null on any problem.
func _extract_clip(path: String) -> Animation:
	var ps := load(path) as PackedScene
	if ps == null:
		return null
	var scene := ps.instantiate()
	var ap := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var result: Animation = null
	if ap:
		for clip_name in ap.get_animation_list():
			if String(clip_name).contains("Targeting Pose"):
				continue
			result = ap.get_animation(clip_name).duplicate()
			break
	scene.free()
	return result

# Remove position tracks that move the WHOLE body forward (root motion), so a clip
# animates in place on our code-driven NPC. We only target the rig root itself —
# a position track on the "Root" node or the "Skeleton3D" node (NOT a track on a bone
# *inside* the skeleton, written as ".../Skeleton3D:BoneName"), and only when the track
# actually moves over its length. The kit's clips put all motion on bones, so nothing
# matches here; this purely future-proofs against an imported clip that carries root motion.
func _strip_root_motion(clip: Animation) -> void:
	for ti in range(clip.get_track_count() - 1, -1, -1):
		if clip.track_get_type(ti) != Animation.TYPE_POSITION_3D:
			continue
		var path := String(clip.track_get_path(ti))
		if not _is_root_translation_path(path):
			continue
		if _position_track_moves(clip, ti):
			clip.remove_track(ti)

# A path targets the rig root translation if it has no bone sub-name (no ":") and the
# node it points at is the rig "Root" or "Skeleton3D". A bone track looks like
# "Root/Skeleton3D:Hips" (a ":subname") and is left alone.
func _is_root_translation_path(path: String) -> bool:
	if path.contains(":"):
		return false
	var node_name := path.get_slice("/", path.get_slice_count("/") - 1)
	return node_name == "Root" or node_name == "Skeleton3D" or path == "." or path == ""

# True if a position track's keys vary (i.e. it imparts movement) rather than holding a
# constant offset. Constant-offset tracks are harmless and kept.
func _position_track_moves(clip: Animation, ti: int) -> bool:
	var n := clip.track_get_key_count(ti)
	if n < 2:
		return false
	var first: Vector3 = clip.track_get_key_value(ti, 0)
	for ki in range(1, n):
		var v: Vector3 = clip.track_get_key_value(ti, ki)
		if not v.is_equal_approx(first):
			return true
	return false

func _normalize_height(model: Node3D) -> void:
	var aabb := _combined_aabb(model)
	if aabb.size.y > 0.0:
		var s := target_height / aabb.size.y
		model.scale = Vector3.ONE * s
	# Ground the model. Skinned-mesh AABBs are unreliable vertically on these PSX/Mixamo
	# rigs (they report the feet near the origin while the real skeleton sits ~0.8 m lower,
	# which buried the body in the floor). With a skeleton we ground on its actual posed
	# bones, but only NEXT frame (at _ready the skeleton hasn't posed yet) — see _process.
	# A skeleton-less model (static prop) grounds off the AABB right now.
	if model.find_child("Skeleton3D", true, false) == null:
		if aabb.size.y > 0.0:
			model.position.y = -aabb.position.y * model.scale.y
	else:
		_pending_ground = true
		_ground_tries = 0
		set_process(true)

# Offset the model so its lowest skeleton bone rests at this animator's origin (y = 0, the
# NPC's feet). Measured in the animator's local space so model scale is accounted for.
# Returns false while the skeleton is still un-posed (degenerate bone span) so the caller
# retries next frame; returns true once grounding is applied (or there's nothing to do).
func _ground_to_skeleton(model: Node3D) -> bool:
	var skel := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if skel == null:
		return true
	skel.force_update_all_bone_transforms()
	var inv := global_transform.affine_inverse()
	var lowest := INF
	var highest := -INF
	for bi in range(skel.get_bone_count()):
		var bone_world: Vector3 = (skel.global_transform * skel.get_bone_global_pose(bi)).origin
		var local_y: float = (inv * bone_world).y
		if local_y < lowest:
			lowest = local_y
		if local_y > highest:
			highest = local_y
	if lowest == INF:
		return true
	# An un-posed skeleton reports every bone at ~0 (near-zero span); wait for a real pose.
	if highest - lowest < 0.2:
		return false
	# Lift so the lowest bone sits foot_clearance above the floor (the sole mesh hangs below it).
	model.position.y -= lowest - foot_clearance
	return true

func _apply_skin(model: Node3D) -> void:
	if skin_texture == null:
		return
	for vi in _find_meshes(model):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = skin_texture
		vi.material_override = mat

# --- small geometry helpers (mirror prop.gd / world_item.gd) ---------------

func _combined_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for vi in _find_meshes(root):
		var local := root.global_transform.affine_inverse() * vi.global_transform
		var box := local * vi.get_aabb()
		if not found:
			result = box
			found = true
		else:
			result = result.merge(box)
	return result

func _find_meshes(node: Node) -> Array[VisualInstance3D]:
	var out: Array[VisualInstance3D] = []
	if node is VisualInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_meshes(c))
	return out
