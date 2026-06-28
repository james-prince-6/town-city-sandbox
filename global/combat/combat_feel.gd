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
## Extra shake punch when the landed blow is a critical hit.
const CRIT_SHAKE_MULTIPLIER: float = 1.6

# --- Damage number tunables ------------------------------------------------
## How far (metres) the number drifts upward over its life.
const DMG_NUMBER_RISE: float = 1.2
## Seconds the number floats before it fades out and frees.
const DMG_NUMBER_LIFETIME: float = 0.7
## Font sizes for normal vs critical hits.
const DMG_NUMBER_FONT_SIZE: int = 48
const DMG_NUMBER_CRIT_FONT_SIZE: int = 76

# --- Kill text tunables ----------------------------------------------------
## How far (metres) the floating "KILL" label drifts upward over its life.
const KILL_TEXT_RISE: float = 1.6
## Seconds the "KILL" label floats before it fades out and frees.
const KILL_TEXT_LIFETIME: float = 0.9

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
## A quiet "click/inhale" tell when an enemy begins a TELEGRAPHED normal attack (see
## enemy.gd attack_windup). Left EMPTY by default (assets pending) so the cue is silent
## until a designer drops .ogg files here — play_attack_tell() then no-ops gracefully.
var attack_tell_sounds: Array[AudioStream] = []
## A short warning sting fired the moment the player's stamina hits empty mid-use (sprint /
## dodge / block). Also EMPTY by default (assets pending); play_stamina_warning() no-ops
## until populated. The on-screen stamina vignette (HUD) already covers the visual side.
var stamina_warning_sounds: Array[AudioStream] = []

# --- Per-weapon-class knockback -------------------------------------------
# A landed hit's KNOCKBACK (never its damage) is scaled by the attacking weapon's class, so
# a crossbow bolt or a heavy maul visibly shoves while a light sword merely nudges. Looked up
# when the shove is applied (see enemy.gd _on_hurt); an unknown/!player attacker uses 1.0, so
# nothing changes unless the held weapon classifies into a heavier tier. Tunable: edit the
# multipliers or add new class keys, then map weapons to them in weapon_class_for().
var weapon_knockback_mult: Dictionary = {
	&"sword": 1.0,     # light melee — unchanged baseline shove
	&"bow": 1.2,       # arrows tap a little harder
	&"crossbow": 1.4,  # heavier bolt, meatier punch
	&"heavy": 1.8,     # mauls / great-weapons really throw the target
}
## Multiplier used when a weapon doesn't classify into weapon_knockback_mult (keeps behavior
## identical to before the per-class scaling for anything unrecognized).
const DEFAULT_KNOCKBACK_MULT: float = 1.0
## Melee id substrings that mark a weapon as the "heavy" class. Matched case-insensitively
## against the held item's id, so future hammers/mauls/axes shove hard without code changes.
const HEAVY_WEAPON_KEYWORDS: Array = ["hammer", "maul", "club", "mace", "axe", "greatsword", "great_"]

# --- Landing impact tunables ----------------------------------------------
## Hitstop length (real seconds) at a FULL-intensity landing; scaled down by air-time. 0 = none.
const LANDING_HITSTOP_MAX: float = 0.05
## Camera-shake strength/duration at a full-intensity landing (scaled by air-time).
const LANDING_SHAKE_STRENGTH_MAX: float = 0.35
const LANDING_SHAKE_DURATION: float = 0.18
## Extra footstep volume (dB) added to the landing thud at full intensity (a harder thump).
const LANDING_VOLUME_BOOST_DB: float = 4.0

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

## Quiet "tell" cue when an enemy starts a telegraphed normal attack. A touch quieter than a
## normal impact; silent while attack_tell_sounds is empty (assets pending).
func play_attack_tell() -> void:
	_play_random(attack_tell_sounds, SFX_VOLUME_DB - 8.0)

## Short warning sting when the player's stamina runs dry mid-use. Silent until the pool is
## populated (assets pending), so this is always safe to call.
func play_stamina_warning() -> void:
	_play_random(stamina_warning_sounds)

## Footstep with explicit pitch/volume modifiers (used for surface variation). `pitch_center`
## centres the usual pitch wobble; `volume_db_offset` is added to the base footstep volume.
func play_footstep_modulated(pitch_center: float, volume_db_offset: float) -> void:
	_play_random(footstep_sounds, SFX_VOLUME_DB + volume_db_offset, pitch_center)

## A landing's weight, scaled by air-time (`intensity` 0..1). Layers a touch of hitstop, a
## downward-reading camera shake, and a deeper/louder footstep thud. No-ops for a tiny hop
## (intensity <= 0) and degrades gracefully if the footstep pool is empty.
func report_landing(intensity: float) -> void:
	var t: float = clampf(intensity, 0.0, 1.0)
	if t <= 0.0:
		return
	var stop: float = LANDING_HITSTOP_MAX * t
	if stop > 0.0:
		hitstop(stop)
	shake(LANDING_SHAKE_STRENGTH_MAX * t, LANDING_SHAKE_DURATION)
	# Deeper thud the harder you hit (lower pitch), and a little louder at full intensity.
	var pitch: float = lerpf(0.95, 0.72, t)
	_play_random(footstep_sounds, SFX_VOLUME_DB + LANDING_VOLUME_BOOST_DB * t, pitch)

# --- Per-weapon-class knockback lookups ------------------------------------

## Knockback multiplier for a weapon class StringName (sword/bow/crossbow/heavy); unknown
## classes fall back to DEFAULT_KNOCKBACK_MULT (1.0, unchanged behavior).
func knockback_mult_for_class(weapon_class: StringName) -> float:
	var m = weapon_knockback_mult.get(weapon_class, DEFAULT_KNOCKBACK_MULT)
	return float(m)

## Classify a held weapon Item into a knockback class. Ranged splits crossbow vs bow (wands
## read as bow); melee is "heavy" if its id contains a heavy keyword, else "sword". A null /
## unrecognized item reads as "sword" (mult 1.0), so unclassified attacks shove as before.
## Duck-typed (a ranged weapon exposes projectile_speed, melee doesn't) so this autoload never
## hard-depends on the weapon class scripts.
func weapon_class_for(item: Object) -> StringName:
	if item == null:
		return &"sword"
	var id_str: String = ""
	var raw_id = item.get(&"id")
	if raw_id != null:
		id_str = String(raw_id).to_lower()
	if item.get(&"projectile_speed") != null:
		# A ranged weapon (bow / crossbow / wand).
		if id_str.contains("crossbow"):
			return &"crossbow"
		return &"bow"
	# Melee: heavy if the id names a heavy weapon, otherwise a light sword.
	for kw in HEAVY_WEAPON_KEYWORDS:
		if id_str.contains(String(kw)):
			return &"heavy"
	return &"sword"

## Knockback multiplier for whatever weapon `source` is attacking with. Only the PLAYER's
## currently-held hotbar weapon is tiered; any other attacker returns 1.0 (unchanged). Fully
## guarded so a missing Hotbar autoload simply yields the default.
func weapon_knockback_mult_for_source(source: Object) -> float:
	if not (source is Node):
		return DEFAULT_KNOCKBACK_MULT
	if not (source as Node).is_in_group(&"player"):
		return DEFAULT_KNOCKBACK_MULT
	var hb = get_node_or_null("/root/Hotbar")
	if hb == null or not hb.has_method("get_selected_item"):
		return DEFAULT_KNOCKBACK_MULT
	var item = hb.get_selected_item()
	return knockback_mult_for_class(weapon_class_for(item))

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
		# The player LANDED a blow: snappy hitstop + a slightly heavier shake on crits.
		hitstop(HITSTOP_DURATION_ENEMY_HIT)
		var land_strength: float = SHAKE_LAND_HIT_STRENGTH * (CRIT_SHAKE_MULTIPLIER if info.is_crit else 1.0)
		shake(land_strength, SHAKE_LAND_HIT_DURATION)
		if info.is_crit and not crit_hit_sounds.is_empty():
			_play_random(crit_hit_sounds)
		else:
			_play_random(hit_sounds)
		# HUD juice (guarded): pop the crosshair hit-marker; flash white on a crit.
		var hud = get_node_or_null("/root/HUD")
		if hud != null:
			if hud.has_method("_flash_crosshair"):
				hud._flash_crosshair()
			if info.is_crit and hud.has_method("show_crit_flash"):
				hud.show_crit_flash()

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
	# Killing blow? Health.apply_damage calls us right AFTER take_damage, so the victim
	# is already flagged dead here. Guarded: a victim without is_dead() simply skips it.
	if is_instance_valid(victim) and victim.has_method("is_dead") and victim.is_dead():
		_on_enemy_killed(info.hit_position, parent)

# Reacts to a confirmed kill: a golden HUD flash plus a floating "KILL" label at the
# death position. Both are best-effort and guarded so a missing HUD/parent is a no-op.
func _on_enemy_killed(world_pos: Vector3, parent: Node) -> void:
	var hud = get_node_or_null("/root/HUD")
	if hud != null and hud.has_method("show_kill_flash"):
		hud.show_kill_flash()
	show_kill_text(world_pos, parent)

## Spawns a lightweight billboard "KILL" Label3D at `world_pos` that floats up, fades
## out and frees itself. `parent` is the world node the FX should live under.
func show_kill_text(world_pos: Vector3, parent: Node) -> void:
	if not is_instance_valid(parent):
		return
	var label := Label3D.new()
	label.text = "KILL"
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.fixed_size = true
	label.shaded = false
	label.double_sided = true
	label.render_priority = 11
	label.outline_render_priority = 10
	label.outline_size = 12
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.font_size = DMG_NUMBER_CRIT_FONT_SIZE
	label.modulate = Color(1.0, 0.85, 0.1)  # gold, matching the kill flash
	label.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(label)
	label.global_position = world_pos + Vector3(0.0, 0.6, 0.0)

	var rise_to: float = label.position.y + KILL_TEXT_RISE
	var tween := label.create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", rise_to, KILL_TEXT_LIFETIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, KILL_TEXT_LIFETIME) \
		.set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)

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
# instead of cutting each other off), with a small pitch wobble for variety. The optional
# `volume_db` / `pitch_center` let callers retune a single play (surface footsteps, a quiet
# tell, a heavy landing thud); their defaults reproduce the original behavior exactly.
func _play_random(pool: Array[AudioStream], volume_db: float = SFX_VOLUME_DB, pitch_center: float = 1.0) -> void:
	if pool.is_empty():
		return
	var stream: AudioStream = pool[randi() % pool.size()]
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	if AudioServer.get_bus_index(&"SFX") != -1:
		p.bus = &"SFX"
	p.pitch_scale = pitch_center * randf_range(0.92, 1.08)
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
