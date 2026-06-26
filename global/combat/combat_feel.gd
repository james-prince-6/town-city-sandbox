# combat_feel.gd
# Autoload singleton (register in Project Settings -> Autoload as "CombatFeel").
# The single home for COMBAT GAME-FEEL: the bits that make a hit land with weight
# without changing what the hit actually *does*. It is purely cosmetic/global and
# never touches damage, knockback, or health — those are owned by the combat
# components and the bodies.
#
# It provides four things, each null-safe (a hit with no active world or no camera
# just does nothing, never crashes):
#   1. HITSTOP  — a tiny global freeze (Engine.time_scale dip) on impact. Restored
#                 by a REAL-TIME timer (ignore_time_scale = true) so a low time
#                 scale can't strand us frozen. Re-entrant safe (won't stack).
#   2. DAMAGE NUMBERS — a floating billboard Label3D at the hit point showing the
#                 FINAL damage, bigger/gold on crits, that rises and fades out.
#   3. IMPACT PARTICLES — a one-shot CPUParticles3D burst at the hit point, tinted
#                 by damage element, that frees itself once it has finished.
#   4. CAMERA SHAKE — a decaying random h/v_offset wobble on the active camera; a
#                 hard shake when the player is hurt, a light tap when the player
#                 lands a blow.
#
# Wire-in (done by the combat components, which call into here):
#   - HurtBox.take_hit(info)        -> report_hit(info, team)   (hitstop/shake/sound)
#   - Health.apply_damage(info)     -> show_damage(info, final) (numbers/particles)
# Team (PLAYER vs ENEMY) decides shake/hitstop intensity.
#
# This node runs with PROCESS_MODE_ALWAYS so its shake keeps updating and its
# hitstop restore keeps working even while the tree is paused or time-scaled.

extends Node

# --- Hitstop tunables ------------------------------------------------------
## How far Engine.time_scale drops during a hitstop (near-freeze, not full stop).
const HITSTOP_TIME_SCALE: float = 0.05
## Real-time length of the freeze when the PLAYER is hit (meatier).
const HITSTOP_DURATION_PLAYER_HIT: float = 0.09
## Real-time length of the freeze when the player LANDS a hit (snappy).
const HITSTOP_DURATION_ENEMY_HIT: float = 0.05

# --- Camera shake tunables -------------------------------------------------
## Shake strength/duration when the PLAYER is hurt (you really feel it).
const SHAKE_PLAYER_HURT_STRENGTH: float = 0.85
const SHAKE_PLAYER_HURT_DURATION: float = 0.35
## Shake strength/duration when the player lands a blow (a small confirm kick).
const SHAKE_LAND_HIT_STRENGTH: float = 0.18
const SHAKE_LAND_HIT_DURATION: float = 0.12
## Maximum camera h/v offset (in Camera3D offset units) at full shake strength.
const SHAKE_MAX_OFFSET: float = 0.28

# --- Damage number tunables ------------------------------------------------
## How far (metres) the number drifts upward over its life.
const DMG_NUMBER_RISE: float = 1.2
## Seconds the number floats before it fades out and frees.
const DMG_NUMBER_LIFETIME: float = 0.7
## Font sizes for normal vs critical hits.
const DMG_NUMBER_FONT_SIZE: int = 48
const DMG_NUMBER_CRIT_FONT_SIZE: int = 76

# --- Impact particle tunables ----------------------------------------------
const IMPACT_PARTICLE_COUNT: int = 14
const IMPACT_PARTICLE_LIFETIME: float = 0.45

# --- Hit sounds ------------------------------------------------------------
# Pools of impact sounds (Kenney). On each hit we play a RANDOM one from the
# matching pool with a slight pitch wobble, so repeated hits never sound identical.
# Add/replace .ogg files here to retune. Empty a pool to silence that category.
## Volume for combat impact sounds (dB; negative = quieter).
const SFX_VOLUME_DB: float = -4.0
## Player lands a blow on an enemy (punches / weapon thwacks).
var hit_sounds: Array[AudioStream] = [
	preload("res://assets/audio/combat/hit_punch_a.ogg"),
	preload("res://assets/audio/combat/hit_punch_b.ogg"),
	preload("res://assets/audio/combat/hit_slice.ogg"),
	preload("res://assets/audio/combat/hit_chop.ogg"),
]
## A critical hit — heavier, meatier impacts.
var crit_hit_sounds: Array[AudioStream] = [
	preload("res://assets/audio/combat/crit_a.ogg"),
	preload("res://assets/audio/combat/crit_b.ogg"),
]
## The player takes damage — dull thuds.
var player_hurt_sounds: Array[AudioStream] = [
	preload("res://assets/audio/combat/hurt_a.ogg"),
	preload("res://assets/audio/combat/hurt_b.ogg"),
]
## Whoosh when the player swings a melee weapon (plays even on a miss).
var swing_sounds: Array[AudioStream] = [
	preload("res://assets/audio/combat/swing_a.ogg"),
	preload("res://assets/audio/combat/swing_b.ogg"),
	preload("res://assets/audio/combat/swing_c.ogg"),
]
## Bow release.
var bow_sounds: Array[AudioStream] = [
	preload("res://assets/audio/combat/bow.ogg"),
]
## An enemy dies.
var death_sounds: Array[AudioStream] = [
	preload("res://assets/audio/combat/death_a.ogg"),
	preload("res://assets/audio/combat/death_b.ogg"),
]
## Player footsteps (played on an interval by the player while moving on the ground).
var footstep_sounds: Array[AudioStream] = [
	preload("res://assets/audio/combat/footstep_a.ogg"),
	preload("res://assets/audio/combat/footstep_b.ogg"),
	preload("res://assets/audio/combat/footstep_c.ogg"),
	preload("res://assets/audio/combat/footstep_d.ogg"),
]
## Played once when the player levels up (auto-wired to Progression.leveled_up).
var levelup_sound: Array[AudioStream] = [
	preload("res://assets/audio/ui/levelup.ogg"),
]
## Metallic clink when the player blocks a hit with a shield/block item.
var block_sounds: Array[AudioStream] = [
	preload("res://assets/audio/combat/block_a.ogg"),
	preload("res://assets/audio/combat/block_b.ogg"),
]

# --- Internal state --------------------------------------------------------
# True while a hitstop is in effect, so overlapping hits don't stack/extend it.
var _hitstop_active: bool = false

# Camera-shake bookkeeping. We additively wobble the camera's h/v_offset and
# restore the captured base values when the shake ends.
var _shake_time_left: float = 0.0
var _shake_duration: float = 0.0
var _shake_strength: float = 0.0
var _shaking_camera: Camera3D = null
var _base_h_offset: float = 0.0
var _base_v_offset: float = 0.0

func _ready() -> void:
	# Keep working through pauses and time-scale dips (our own hitstop included).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Play a flourish when the player levels up (Progression autoload loads before us).
	var prog = get_node_or_null("/root/Progression")
	if prog != null and prog.has_signal("leveled_up"):
		prog.leveled_up.connect(_on_level_up)

func _on_level_up(_level: int, _points: int) -> void:
	_play_random(levelup_sound)

## One-shot SFX hooks the rest of the game calls (all null-safe, layered, pitch-varied).
func play_swing() -> void:
	_play_random(swing_sounds)

func play_bow() -> void:
	_play_random(bow_sounds)

func play_death() -> void:
	_play_random(death_sounds)

func play_footstep() -> void:
	_play_random(footstep_sounds)

func play_block() -> void:
	_play_random(block_sounds)

func _process(delta: float) -> void:
	_update_shake(delta)

# ===========================================================================
#  PUBLIC API  (called by the combat components)
# ===========================================================================

## Called by HurtBox.take_hit for every landed hit. Fires the "impact feel"
## (hitstop + camera shake + optional sound). Intensity depends on who got hit:
## the player getting hurt is loud; the player landing a blow is a light tap.
## `victim_team` is a HurtBox.Team value.
func report_hit(info: DamageInfo, victim_team: int) -> void:
	if info == null:
		return
	var is_player_hurt := victim_team == HurtBox.Team.PLAYER
	if is_player_hurt:
		hitstop(HITSTOP_DURATION_PLAYER_HIT)
		shake(SHAKE_PLAYER_HURT_STRENGTH, SHAKE_PLAYER_HURT_DURATION)
		_play_random(player_hurt_sounds)
	else:
		hitstop(HITSTOP_DURATION_ENEMY_HIT)
		shake(SHAKE_LAND_HIT_STRENGTH, SHAKE_LAND_HIT_DURATION)
		if info.is_crit and not crit_hit_sounds.is_empty():
			_play_random(crit_hit_sounds)
		else:
			_play_random(hit_sounds)

## Called by Health.apply_damage once the FINAL (post resistance/weakness) damage
## is known. Spawns the floating number and the impact burst at info.hit_position.
func show_damage(info: DamageInfo, final_amount: float, victim: Node) -> void:
	if info == null:
		return
	if final_amount <= 0.0:
		return
	var parent := _fx_parent(victim)
	if parent == null:
		return
	_spawn_damage_number(info, final_amount, parent)
	_spawn_impact_particles(info, parent)

# ===========================================================================
#  HITSTOP
# ===========================================================================

## Briefly dip Engine.time_scale, restoring it after `duration` REAL seconds.
## Re-entrant safe: a hit that arrives mid-hitstop is ignored (no stacking).
func hitstop(duration: float, time_scale: float = HITSTOP_TIME_SCALE) -> void:
	if _hitstop_active or duration <= 0.0:
		return
	_hitstop_active = true
	Engine.time_scale = time_scale
	# 4th arg `ignore_time_scale = true` -> this timer ticks in REAL time, so the
	# low time scale can't keep it from ever firing and unfreezing us.
	var t := get_tree().create_timer(duration, true, false, true)
	t.timeout.connect(_end_hitstop)

func _end_hitstop() -> void:
	Engine.time_scale = 1.0
	_hitstop_active = false

# ===========================================================================
#  CAMERA SHAKE
# ===========================================================================

## Shake the currently active 3D camera. New shakes take the STRONGER strength and
## refresh the timer, so a small tap never weakens a big shake already in progress.
func shake(strength: float, duration: float) -> void:
	if strength <= 0.0 or duration <= 0.0:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Switching/starting on a (new) camera: restore the old one and capture the new
	# camera's resting offsets so our wobble is purely additive.
	if not is_instance_valid(_shaking_camera) or _shaking_camera != cam or _shake_time_left <= 0.0:
		_restore_camera()
		_shaking_camera = cam
		_base_h_offset = cam.h_offset
		_base_v_offset = cam.v_offset
	_shake_strength = max(_shake_strength, strength)
	_shake_duration = duration
	_shake_time_left = duration

func _update_shake(delta: float) -> void:
	if _shake_time_left <= 0.0:
		return
	if not is_instance_valid(_shaking_camera):
		_shake_time_left = 0.0
		_shaking_camera = null
		return
	_shake_time_left -= delta
	if _shake_time_left <= 0.0:
		_restore_camera()
		return
	# Quadratic falloff feels punchier than linear (big at impact, quick settle).
	var factor: float = _shake_time_left / _shake_duration
	var amt: float = _shake_strength * factor * factor * SHAKE_MAX_OFFSET
	_shaking_camera.h_offset = _base_h_offset + randf_range(-amt, amt)
	_shaking_camera.v_offset = _base_v_offset + randf_range(-amt, amt)

func _restore_camera() -> void:
	if is_instance_valid(_shaking_camera):
		_shaking_camera.h_offset = _base_h_offset
		_shaking_camera.v_offset = _base_v_offset
	_shaking_camera = null
	_shake_strength = 0.0
	_shake_time_left = 0.0

# ===========================================================================
#  DAMAGE NUMBERS
# ===========================================================================

func _spawn_damage_number(info: DamageInfo, final_amount: float, parent: Node) -> void:
	var label := Label3D.new()
	label.text = str(int(round(final_amount)))
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.shaded = false
	label.double_sided = true
	label.render_priority = 10
	label.outline_render_priority = 9
	label.outline_size = 12
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	# Keep animating during hitstop / pause.
	label.process_mode = Node.PROCESS_MODE_ALWAYS
	if info.is_crit:
		label.font_size = DMG_NUMBER_CRIT_FONT_SIZE
		label.modulate = Color(1.0, 0.85, 0.1)  # gold crit
		label.text += "!"
	else:
		label.font_size = DMG_NUMBER_FONT_SIZE
		label.modulate = _color_for_type(info.type)
	parent.add_child(label)
	# A little jitter so stacked hits don't draw exactly on top of each other.
	label.global_position = info.hit_position + Vector3(randf_range(-0.2, 0.2), 0.3, randf_range(-0.2, 0.2))

	# Float up while fading, then free.
	var rise_to: float = label.position.y + DMG_NUMBER_RISE
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", rise_to, DMG_NUMBER_LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, DMG_NUMBER_LIFETIME) \
		.set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)

# ===========================================================================
#  IMPACT PARTICLES
# ===========================================================================

func _spawn_impact_particles(info: DamageInfo, parent: Node) -> void:
	var p := CPUParticles3D.new()
	p.emitting = false
	p.one_shot = true
	p.amount = IMPACT_PARTICLE_COUNT
	p.lifetime = IMPACT_PARTICLE_LIFETIME
	p.explosiveness = 1.0
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = 2.0
	p.initial_velocity_max = 4.5
	p.gravity = Vector3(0.0, -9.0, 0.0)
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.12
	p.color = _color_for_type(info.type)
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(p)
	p.global_position = info.hit_position
	p.emitting = true
	# Free once the burst has fully played out. Real-time timer so a concurrent
	# hitstop can't keep it alive forever.
	var t := get_tree().create_timer(p.lifetime + 0.2, true, false, true)
	t.timeout.connect(p.queue_free)

# ===========================================================================
#  HELPERS
# ===========================================================================

## Where world-space FX should be parented: the active gameplay world if the
## SceneManager autoload exposes it, otherwise the victim's current scene (or the
## victim itself as a last resort). Returns null if nothing usable is in the tree.
func _fx_parent(victim: Node) -> Node:
	var sm = get_node_or_null("/root/SceneManager")
	if sm != null and sm.has_method("current_world"):
		var w: Node = sm.call("current_world")
		if is_instance_valid(w):
			return w
	if is_instance_valid(victim) and victim.is_inside_tree():
		var cs := victim.get_tree().current_scene
		if is_instance_valid(cs):
			return cs
		return victim
	return null

## Per-element colour for numbers/particles (physical = white).
func _color_for_type(t: int) -> Color:
	match t:
		DamageInfo.DamageType.FIRE:
			return Color(1.0, 0.45, 0.1)
		DamageInfo.DamageType.ICE:
			return Color(0.5, 0.85, 1.0)
		DamageInfo.DamageType.POISON:
			return Color(0.5, 0.9, 0.2)
		DamageInfo.DamageType.EXPLOSIVE:
			return Color(1.0, 0.75, 0.2)
		_:
			return Color(1.0, 1.0, 1.0)

# Play a random stream from `pool` on a throwaway player (so rapid hits layer
# instead of cutting each other off), with a small pitch wobble for variety.
func _play_random(pool: Array[AudioStream]) -> void:
	if pool.is_empty():
		return
	var stream: AudioStream = pool[randi() % pool.size()]
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = SFX_VOLUME_DB
	if AudioServer.get_bus_index(&"SFX") != -1:
		p.bus = &"SFX"
	p.pitch_scale = randf_range(0.92, 1.08)
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
