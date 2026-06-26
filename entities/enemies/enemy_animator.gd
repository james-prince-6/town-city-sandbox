# enemy_animator.gd
# Gives a monster a real animated 3D body built from the Kenney rigged-character kit,
# and drives it with an AnimationTree so it can WALK AND ATTACK at the same time.
#
# The kit ships the mesh and the animations in SEPARATE files: a base model FBX
# (just the rig + mesh, no AnimationPlayer) and one FBX per animation, each holding
# its clip on the same shared skeleton. This node assembles them at runtime:
#   1. instance the base model under itself,
#   2. pull each clip out of its animation FBX into one shared AnimationLibrary,
#   3. add an AnimationPlayer beneath the model root with that library,
#   4. build an AnimationTree on top of it:
#         locomotion (Blend2: idle <-> walk)  -->  OneShot(.in)
#         attack                              -->  OneShot(.shot)   [upper-body only]
#         OneShot                             -->  output
#      The OneShot's filter is enabled for the upper-body bones (spine, arms, head),
#      so firing an attack swings the arms while the legs keep playing the walk —
#      no more frozen legs mid-stride.
#
# Death is full-body: we switch the tree off and play the death clip straight on the
# AnimationPlayer (it holds its last frame, LOOP_NONE, until enemy.gd frees the body).
#
# It's deliberately tolerant: if the base model is unset or a clip file is missing it
# just does less (no model, or fewer clips) rather than erroring, so an enemy with no
# model assigned keeps its placeholder capsule and every call here is a harmless no-op.

class_name EnemyAnimator
extends Node3D

## Base rigged character mesh, e.g. characterMedium.fbx. Leave null to keep the
## enemy's placeholder capsule and disable animation entirely.
@export var model_scene: PackedScene

## Optional recolor skin (one of the kit's Skins/*.png) applied to the body's
## material albedo. Leave null to use the model's default look.
@export var skin_texture: Texture2D

## Optional self-illumination so a creature reads against dark/busy scenes (e.g. the
## Ash Swarmer's ember glow). emission_energy 0 (default) leaves the body unlit, so
## existing enemies are unaffected. Applied alongside skin_texture.
@export var emission_color: Color = Color(1, 1, 1)
@export var emission_energy: float = 0.0

## Render the body with the stylized toon shader (assets/shaders/stylized_toon.gdshader) instead
## of a plain lit material — gives monsters a cel-shaded, higher-contrast look that reads well in
## combat. Emissive bodies (e.g. the glowing Ash Swarmer) stay on the standard material so their
## glow is preserved. Off by default; enabled on the enemy base scene.
@export var use_toon: bool = false

## The model is uniformly scaled so its total height matches this (metres), since
## kit models don't all import at the same size. Feet sit at the enemy's origin.
@export var target_height: float = 1.8

## Small upward lift (metres) applied after grounding. Grounding aligns the lowest toe
## BONE to the floor, but the foot MESH extends a little below that bone, so without a
## nudge the soles dip underground. ~0.03 reads as planted; raise if feet still clip.
@export var foot_clearance: float = 0.03

## Half-rotate the body. The Kenney characters face +Z, but Godot's look_at aims a
## node's -Z at its target, so the default 180° keeps them facing where they move.
@export var face_offset_degrees: float = 180.0

## How quickly the walk<->idle blend follows the body's real speed (higher = snappier).
@export var locomotion_smoothing: float = 10.0

## Whether to load the Kenney per-clip animation FBXs (ANIM_SOURCES). Set FALSE for models on a
## different rig (e.g. the PSX/Mixamo monster models) so Kenney-rig clips aren't applied to them.
## With this false and no animation_source the model builds STATIC and every animation call no-ops.
@export var use_kit_animations: bool = true

## OPTIONAL shared animation library (one imported scene whose AnimationPlayer holds many named
## clips — e.g. a Mixamo set matching this model's rig). When set, its clips load INSTEAD of the
## Kenney kit. This is the hook for the incoming Mixamo animations.
@export var animation_source: PackedScene

## Load the curated Mixamo CREATURE clip set (idle/walk/run/attack/death) and apply it to this
## Mixamo-rigged PSX monster. Takes priority over kit / animation_source. PSX monsters use this.
@export var use_mixamo: bool = false

# Logical clip -> Mixamo creature FBX (one clip each, named "Take 001"), mixamorig_-rigged so it
# drives the PSX monster models directly (track node-paths remapped to Skeleton3D, hip drift
# frozen). idle/walk/attack feed the locomotion+oneshot AnimationTree (see _build_tree).
const MIXAMO_DIR := "res://assets/models/characters/psx/anim_creature/"
const MIXAMO_SOURCES := {
	"idle": "mutant idle.fbx",
	"walk": "mutant walking.fbx",
	"run": "mutant run.fbx",
	"attack": "mutant swiping.fbx",   # primary swing
	"attack2": "punch.fbx",            # variety swing
	"jump_attack": "jump_attack.fbx",  # lunge
	"flinch": "flinch.fbx",            # hit reaction (played on stagger)
	"roar": "roar.fbx",                # special wind-up telegraph
	"death": "mutant dying.fbx",
}
const MIXAMO_LOOP := {"idle": true, "walk": true, "run": true}

# Built once and shared across every PSX monster (all share "Skeleton3D" bone paths).
static var _mixamo_cache: Dictionary = {}

# Logical clip name -> animation FBX that contains it. These are the kit defaults;
# the real clip inside each is auto-detected (it's the one that isn't the bind pose).
const ANIM_SOURCES := {
	"idle": "res://assets/models/characters/animated-characters/Animations/idle.fbx",
	"walk": "res://assets/models/characters/animated-characters/Animations/walk.fbx",
	"run": "res://assets/models/characters/animated-characters/Animations/run.fbx",
	"attack": "res://assets/models/characters/animated-characters/Animations/attack.fbx",
	"death": "res://assets/models/characters/animated-characters/Animations/death.fbx",
}

# Clips that should loop while playing. attack/death are deliberately absent: they
# play once and hold their last frame (so a corpse stays down, a swing doesn't repeat).
const LOOPING := {"idle": true, "walk": true, "run": true}

# A bone is "upper body" (gets the attack layer) if its name contains one of these.
# Everything else (Hips + all leg bones) stays on the locomotion layer so it keeps
# walking while the arms swing.
const UPPER_BODY_KEYS := ["Spine", "Chest", "Neck", "Head", "Shoulder", "Arm", "Hand", "Thumb", "Index", "Finger"]

var _anim_player: AnimationPlayer
var _anim_tree: AnimationTree
# The AnimationNodeAnimation feeding the oneshot layer; play_oneshot swaps its clip for variety.
var _oneshot_anim: AnimationNodeAnimation = null
var _model_root: Node3D
var _skeleton: Skeleton3D
var _target_loco: float = 0.0   # 0 = idle, 1 = walk; smoothed toward each frame
var _dead: bool = false         # once true the tree is off and death holds its pose
# Set when a skeleton model needs grounding (see _normalize_height); cleared once grounded.
var _pending_ground: bool = false
var _ground_tries: int = 0

func _ready() -> void:
	if model_scene == null:
		return
	_build_model()

func _process(delta: float) -> void:
	# Ground the body once the skeleton has actually posed. Its bone poses are degenerate for
	# the first few frames after a build, so we retry here until they're real, then stop.
	if _pending_ground:
		_ground_tries += 1
		# Let the idle animation settle first (ground to the shown pose, not the bare rest pose).
		if _ground_tries >= 8 and (_model_root == null or not is_instance_valid(_model_root) \
				or _ground_to_skeleton(_model_root) or _ground_tries > 40):
			_pending_ground = false
	# Smoothly follow the requested locomotion blend so walk<->idle eases in/out.
	if _anim_tree == null or _dead:
		return
	var cur: float = _anim_tree.get("parameters/locomotion/blend_amount")
	var next: float = lerpf(cur, _target_loco, clampf(locomotion_smoothing * delta, 0.0, 1.0))
	_anim_tree.set("parameters/locomotion/blend_amount", next)

## True once a real model has been built (enemy.gd uses this to hide the capsule).
func has_model() -> bool:
	return _model_root != null

## Number of animation clips successfully loaded (0 if none / no model). Handy for tests.
func clip_count() -> int:
	if _anim_player == null:
		return 0
	return _anim_player.get_animation_list().size()

## The underlying AnimationPlayer (or null if there's no model).
func animation_player() -> AnimationPlayer:
	return _anim_player

## Length (seconds) of a loaded clip, or 0.0 if absent / no model.
func clip_length(anim_name: StringName) -> float:
	if _anim_player == null:
		return 0.0
	var key := String(anim_name)
	if not _anim_player.has_animation(key):
		return 0.0
	return _anim_player.get_animation(key).length

## Convenience: length of the death clip (0.0 if there's no model / no death clip).
func death_length() -> float:
	return clip_length(&"death")

## Drive the legs: 0 = standing (idle), 1 = full walk. enemy.gd feeds it the body's
## real speed each frame so the walk cycle matches actual movement. Independent of the
## attack layer, so the legs keep stepping while the arms swing.
func set_locomotion(amount: float) -> void:
	_target_loco = clampf(amount, 0.0, 1.0)

## Compatibility shim: older callers used play(&"walk"/&"idle"/&"run").
func play(anim_name: StringName) -> void:
	match String(anim_name):
		"walk", "run":
			set_locomotion(1.0)
		_:
			set_locomotion(0.0)

## Fire a one-shot clip layered over the legs' locomotion (upper body) — used for attack
## variety, hit flinches, and the special wind-up roar. "death" is full-body: switch the tree
## off and play it straight on the AnimationPlayer. Any other name plays through the swappable
## oneshot layer if that clip exists.
func play_oneshot(anim_name: StringName) -> void:
	if _anim_player == null:
		return
	var key := String(anim_name)
	if key == "death":
		_dead = true
		if _anim_tree:
			_anim_tree.active = false
		if _anim_player.has_animation("death"):
			_anim_player.play("death")
		return
	if _anim_tree == null or _oneshot_anim == null:
		return
	# Swap which clip the oneshot layer plays, then (re)fire it. Falls back to "attack" when the
	# requested clip isn't loaded, so callers can ask for variety safely.
	var clip := key if _anim_player.has_animation(key) else "attack"
	if not _anim_player.has_animation(clip):
		return
	_oneshot_anim.animation = clip
	_anim_tree.set("parameters/oneshot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)

# --- Build -----------------------------------------------------------------

func _build_model() -> void:
	_model_root = model_scene.instantiate() as Node3D
	if _model_root == null:
		push_warning("EnemyAnimator: model_scene did not instance a Node3D.")
		return
	add_child(_model_root)
	_normalize_height(_model_root)
	_model_root.rotation_degrees.y += face_offset_degrees
	_apply_skin(_model_root)
	_skeleton = _model_root.find_child("Skeleton3D", true, false) as Skeleton3D

	# Build the clip library from whichever source applies. With neither the kit nor a source
	# (e.g. a PSX model awaiting Mixamo clips), the body stays static and the locomotion/oneshot
	# tree is skipped — all animation calls then harmlessly no-op.
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

	_build_tree()

# The original Kenney path: one FBX per clip (ANIM_SOURCES).
func _collect_kit_clips(library: AnimationLibrary) -> void:
	for key in ANIM_SOURCES:
		var clip := _extract_clip(ANIM_SOURCES[key])
		if clip == null:
			continue
		_strip_root_motion(clip)
		if LOOPING.get(key, false):
			clip.loop_mode = Animation.LOOP_LINEAR
		else:
			clip.loop_mode = Animation.LOOP_NONE
		library.add_animation(StringName(key), clip)

# --- Mixamo creature clip set (PSX monsters), RETARGETED to this model's rig -
#
# Same story as the NPC animator: the Mixamo creature ANIMATION fbxs and the PSX MONSTER MODEL
# fbxs share bone names but bind in different rest poses + axis conventions, so a closed-form
# rotation transfer twists the body or swaps the limbs. We RETARGET by AIM — each frame point
# every model bone's primary-child direction the same world way the source does, preserving the
# model's own roll (matches the silhouette, keeps left/right correct). Rotation-only (positions
# stay at the model's rest; grounding handles height). Each source fbx has a static "Take 001"
# plus the real multi-key "mixamo_com" clip — we pick the one with the most keyframes. Cached
# statically + shared across all PSX monsters on this rig.
const RETARGET_FPS: float = 30.0

func _collect_mixamo_clips(library: AnimationLibrary) -> void:
	# Key the cache per MODEL, not just per source directory: the bake is retargeted against
	# THIS model's skeleton (rest pose, proportions, hip height), so a differently-rigged model
	# must not reuse another's baked clips. Same model -> same key -> the bake still runs once.
	var cache_key: String = MIXAMO_DIR + "::" + (model_scene.resource_path if model_scene != null else "")
	var cached = _mixamo_cache.get(cache_key)
	if cached != null:
		var lib: AnimationLibrary = cached
		for clip_name in lib.get_animation_list():
			library.add_animation(clip_name, lib.get_animation(clip_name))
		return

	var model_skel := _skeleton
	if model_skel == null:
		model_skel = _model_root.find_child("Skeleton3D", true, false) as Skeleton3D
	if model_skel == null:
		return

	for key in MIXAMO_SOURCES:
		var baked := _load_and_retarget(MIXAMO_DIR + MIXAMO_SOURCES[key], model_skel, MIXAMO_LOOP.get(key, false))
		if baked != null:
			library.add_animation(StringName(key), baked)

	_mixamo_cache[cache_key] = library

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
# different bone-axis conventions (a closed-form rotation transfer swaps the limbs), but matching
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

	# Model rig: rest rotation, primary child (most descendants) + rest direction to it, source
	# index, output track. Subtree sizes pick the primary child for branch bones (hips/spine).
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

	# Vertical root motion: the aim is rotation-only, so a clip that drops the body (death/fall)
	# or lifts it (jump) wouldn't move vertically — a dying monster would tip over yet hover at hip
	# height. Re-add the HIPS' VERTICAL travel only (horizontal stays frozen so locomotion never
	# slides), re-based onto the model's rest hip height and scaled for the rig-size difference.
	var s_hips := -1
	for i in range(s_count):
		if src_skel.get_bone_name(i).ends_with("Hips"):
			s_hips = i
			break
	var s_hips_pos_track := -1
	for ti in range(src_clip.get_track_count()):
		if src_clip.track_get_type(ti) == Animation.TYPE_POSITION_3D and String(src_clip.track_get_path(ti).get_concatenated_subnames()).ends_with("Hips"):
			s_hips_pos_track = ti
			break
	var m_hips := -1
	for i in range(m_count):
		if model_skel.get_bone_name(i).ends_with("Hips"):
			m_hips = i
			break
	var hips_track := -1
	var m_hips_rest := Vector3.ZERO
	var hips_y0 := 0.0
	var hips_scale := 1.0
	if m_hips >= 0 and s_hips >= 0 and s_hips_pos_track >= 0:
		m_hips_rest = model_skel.get_bone_rest(m_hips).origin
		var s_hips_rest_y: float = (s_rest[s_hips] as Transform3D).origin.y
		if absf(s_hips_rest_y) > 0.0001:
			hips_scale = m_hips_rest.y / s_hips_rest_y
		hips_y0 = src_clip.position_track_interpolate(s_hips_pos_track, 0.0).y
		hips_track = out.add_track(Animation.TYPE_POSITION_3D)
		out.track_set_path(hips_track, NodePath("Skeleton3D:" + model_skel.get_bone_name(m_hips)))

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
		if hips_track >= 0:
			var hp_y: float = src_clip.position_track_interpolate(s_hips_pos_track, t).y
			out.position_track_insert_key(hips_track, t, Vector3(m_hips_rest.x, m_hips_rest.y + (hp_y - hips_y0) * hips_scale, m_hips_rest.z))
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


# Shared-library path: copy every clip out of animation_source's AnimationPlayer, keyed by a
# normalized name so play(&"idle"/&"walk"/&"attack") resolves. (Finalize the name map once the
# Mixamo clip names are known.)
func _collect_source_clips(library: AnimationLibrary) -> void:
	var scene := animation_source.instantiate()
	var ap := scene.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if ap != null:
		for clip_name in ap.get_animation_list():
			var clip := ap.get_animation(clip_name).duplicate() as Animation
			_strip_root_motion(clip)
			var norm := String(clip_name)
			if norm.contains("|"):
				norm = norm.get_slice("|", norm.get_slice_count("|") - 1)
			norm = norm.to_lower()
			if norm.contains("idle") or norm.contains("walk") or norm.contains("run"):
				clip.loop_mode = Animation.LOOP_LINEAR
			else:
				clip.loop_mode = Animation.LOOP_NONE
			library.add_animation(StringName(norm), clip)
	scene.free()

# Build the locomotion + layered-attack AnimationTree on top of the AnimationPlayer.
# Falls back to leaving _anim_tree null (play() then drives the AnimationPlayer pose
# only via the shim) if the needed clips are missing.
func _build_tree() -> void:
	if not (_anim_player.has_animation("idle") and _anim_player.has_animation("walk") and _anim_player.has_animation("attack")):
		return

	var idle_n := AnimationNodeAnimation.new()
	idle_n.animation = "idle"
	var walk_n := AnimationNodeAnimation.new()
	walk_n.animation = "walk"
	var attack_n := AnimationNodeAnimation.new()
	attack_n.animation = "attack"
	# Remember the oneshot's clip node so play_oneshot can SWAP which clip fires (attack variety,
	# flinch, roar) while still layering it over the legs' locomotion.
	_oneshot_anim = attack_n

	var loco := AnimationNodeBlend2.new()
	var oneshot := AnimationNodeOneShot.new()
	oneshot.fadein_time = 0.06
	oneshot.fadeout_time = 0.12
	oneshot.break_loop_at_end = true
	# Layer the attack onto the upper body only, so the legs keep walking.
	_apply_upper_body_filter(oneshot)

	var tree := AnimationNodeBlendTree.new()
	tree.add_node("idle", idle_n, Vector2(0, 0))
	tree.add_node("walk", walk_n, Vector2(0, 160))
	tree.add_node("locomotion", loco, Vector2(260, 60))
	tree.add_node("attack", attack_n, Vector2(260, 260))
	tree.add_node("oneshot", oneshot, Vector2(520, 120))
	tree.connect_node("locomotion", 0, "idle")
	tree.connect_node("locomotion", 1, "walk")
	tree.connect_node("oneshot", 0, "locomotion")
	tree.connect_node("oneshot", 1, "attack")
	tree.connect_node("output", 0, "oneshot")

	_anim_tree = AnimationTree.new()
	_anim_tree.tree_root = tree
	_model_root.add_child(_anim_tree)
	# Same root resolution as the AnimationPlayer (parent = model root).
	_anim_tree.anim_player = _anim_tree.get_path_to(_anim_player)
	_anim_tree.active = true
	_anim_tree.set("parameters/locomotion/blend_amount", 0.0)

# Enable the OneShot's filter for every upper-body bone track, so the attack clip only
# affects spine/arms/head and the locomotion (legs) shows through everywhere else.
func _apply_upper_body_filter(oneshot: AnimationNodeOneShot) -> void:
	if _skeleton == null:
		return
	var skel_path := String(_model_root.get_path_to(_skeleton))  # "Root/Skeleton3D"
	oneshot.filter_enabled = true
	for i in range(_skeleton.get_bone_count()):
		var bone := _skeleton.get_bone_name(i)
		if _is_upper_body(bone):
			oneshot.set_filter_path(NodePath(skel_path + ":" + bone), true)

func _is_upper_body(bone_name: String) -> bool:
	for key in UPPER_BODY_KEYS:
		if bone_name.contains(key):
			return true
	return false

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
# animates in place on our code-driven monster. Only the rig root itself (the "Root" or
# "Skeleton3D" node, NOT a bone inside the skeleton) and only when it actually moves.
func _strip_root_motion(clip: Animation) -> void:
	for ti in range(clip.get_track_count() - 1, -1, -1):
		if clip.track_get_type(ti) != Animation.TYPE_POSITION_3D:
			continue
		var path := String(clip.track_get_path(ti))
		if not _is_root_translation_path(path):
			continue
		if _position_track_moves(clip, ti):
			clip.remove_track(ti)

func _is_root_translation_path(path: String) -> bool:
	if path.contains(":"):
		return false
	var node_name := path.get_slice("/", path.get_slice_count("/") - 1)
	return node_name == "Root" or node_name == "Skeleton3D" or path == "." or path == ""

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
	# A skeleton-less model grounds off the AABB right now.
	if model.find_child("Skeleton3D", true, false) == null:
		if aabb.size.y > 0.0:
			model.position.y = -aabb.position.y * model.scale.y
	else:
		_pending_ground = true
		_ground_tries = 0

# Offset the model so its lowest skeleton bone rests at this animator's origin (y = 0, the
# enemy's feet). Measured in the animator's local space so model scale is accounted for.
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
	# Nothing to do if neither a recolor skin, a glow, nor toon shading was requested.
	if skin_texture == null and emission_energy <= 0.0 and not use_toon:
		return
	var mat: Material = _build_body_material()
	for vi in _find_meshes(model):
		vi.material_override = mat

# Choose the body material: the stylized toon shader when use_toon is on and the body isn't
# emissive; otherwise a standard lit material (which also carries the optional emission glow).
func _build_body_material() -> Material:
	if use_toon and skin_texture != null and emission_energy <= 0.0:
		var sm := ShaderMaterial.new()
		sm.shader = load("res://assets/shaders/stylized_toon.gdshader")
		sm.set_shader_parameter("albedo_texture", skin_texture)
		sm.set_shader_parameter("use_pattern", false)        # no pattern texture supplied
		sm.set_shader_parameter("use_stepped", true)
		sm.set_shader_parameter("steps", 3.0)
		sm.set_shader_parameter("step_smoothness", 0.25)
		sm.set_shader_parameter("shadow_tint", Color(0.18, 0.16, 0.26))
		sm.set_shader_parameter("shadow_tint_amount", 0.45)
		sm.set_shader_parameter("use_rim", true)
		sm.set_shader_parameter("rim_color", Color(1, 1, 1))
		sm.set_shader_parameter("rim_amount", 3.0)
		sm.set_shader_parameter("rim_smoothness", 0.2)
		return sm
	var std := StandardMaterial3D.new()
	if skin_texture != null:
		std.albedo_texture = skin_texture
	if emission_energy > 0.0:
		std.emission_enabled = true
		std.emission = emission_color
		std.emission_energy_multiplier = emission_energy
	return std

# --- small geometry helpers (mirror npc_animator.gd) -----------------------

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
