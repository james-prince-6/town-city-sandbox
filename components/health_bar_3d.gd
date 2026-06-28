# health_bar_3d.gd
# A small floating health bar that hovers above an entity and faces the camera.
#
# Drop it in as a child of anything with a Health component (or call setup(health)
# from code, as enemy.gd does). It draws two flat quads — a dark backdrop and a
# coloured fill — and shrinks/recolours the fill (green -> yellow -> red) as the
# entity's `damaged` signal fires. It yaws to face the camera each frame so it reads
# from any angle while staying upright.
#
# Code-only (no scene needed) and lightweight: fine for a handful of on-screen enemies.

class_name HealthBar3D
extends Node3D

## Bar width / height in metres.
@export var width: float = 0.9
@export var height: float = 0.12
## Hide the bar entirely while at full health (keeps the screen clean until a fight).
@export var hide_when_full: bool = true

## How long the on-damage pulse (scale-up + brighten) takes to settle back.
const DAMAGE_PULSE_DURATION: float = 0.25
## Peak scale of the bar during the damage pulse.
const DAMAGE_PULSE_SCALE: float = 1.15

var _fill: MeshInstance3D
var _fill_mat: StandardMaterial3D
var _ratio: float = 1.0
var _max: float = 1.0
# Active damage-pulse tween, kept so a fresh hit can restart it cleanly.
var _pulse_tween: Tween = null
# Current pulse scale factor (1.0 = resting). Driven by the pulse tween and applied
# in _process AFTER look_at, which would otherwise reset our scale every frame.
var _pulse_scale: float = 1.0

func _ready() -> void:
	# Backdrop (slightly larger, dark) then the fill on top.
	var bg := _make_quad(Color(0.05, 0.05, 0.05, 0.65), width + 0.04, height + 0.04, -0.001)
	add_child(bg)
	_fill = _make_quad(Color(0.25, 0.85, 0.3, 1.0), width, height, 0.0)
	_fill_mat = _fill.material_override
	add_child(_fill)
	_refresh()

func _process(_delta: float) -> void:
	# Yaw to face the camera, staying upright (billboard around Y only).
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var dir := global_position - cam.global_position
	dir.y = 0.0
	if dir.length() > 0.01:
		# look_at aims -Z at the target; aim it AWAY from the camera so the quads' +Z
		# faces the camera.
		look_at(global_position + dir, Vector3.UP)
	# look_at rebuilds the basis with UNIT scale, so re-apply the damage-pulse scale
	# AFTER it (otherwise the pop would be wiped out every frame). 1.0 = no pulse.
	scale = Vector3.ONE * _pulse_scale

## Wire to a Health component: seed the current ratio and follow its `damaged` signal.
func setup(health_node: Node) -> void:
	if health_node == null:
		return
	if "max_health" in health_node:
		_max = maxf(float(health_node.max_health), 0.001)
	if "current" in health_node:
		set_value(float(health_node.current))
	if health_node.has_signal("damaged"):
		health_node.damaged.connect(_on_damaged)

func _on_damaged(_amount: float, current: float) -> void:
	set_value(current)

## Set the absolute current health; recomputes the fill ratio against max. A DROP
## (took damage) also fires a brief scale-up + brighten pulse for readable feedback.
func set_value(current: float) -> void:
	var new_ratio: float = clampf(current / _max, 0.0, 1.0)
	var took_damage := new_ratio < _ratio
	_ratio = new_ratio
	_refresh()
	if took_damage:
		_play_damage_pulse()

# Briefly pops the whole bar bigger and brighter, then eases back, so a hit reads at
# a glance. Robust: if a tween can't be created (e.g. outside the tree) we simply
# skip the flourish — the plain value update in _refresh has already applied.
func _play_damage_pulse() -> void:
	if not is_inside_tree():
		return
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	var t := create_tween()
	if t == null:
		# No tween available (e.g. outside the tree): fall back to a plain update,
		# which _refresh has already applied. Just make sure we aren't left scaled up.
		_pulse_scale = 1.0
		return
	_pulse_tween = t
	_pulse_scale = DAMAGE_PULSE_SCALE
	if _fill_mat:
		_fill_mat.emission_enabled = true
		_fill_mat.emission = _fill_mat.albedo_color
		_fill_mat.emission_energy_multiplier = 0.9
	t.set_parallel(true)
	# Drive the scale via a setter (not the "scale" property) so _process's per-frame
	# look_at can re-apply it instead of fighting the tween.
	t.tween_method(_set_pulse_scale, DAMAGE_PULSE_SCALE, 1.0, DAMAGE_PULSE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	if _fill_mat:
		t.tween_property(_fill_mat, "emission_energy_multiplier", 0.0, DAMAGE_PULSE_DURATION) \
			.set_ease(Tween.EASE_OUT)

func _set_pulse_scale(v: float) -> void:
	_pulse_scale = v

func _refresh() -> void:
	if _fill == null:
		return
	visible = not (hide_when_full and _ratio >= 0.999)
	# Anchor the fill to the left: scale its width by the ratio and slide it left so it
	# drains rightward.
	_fill.scale.x = maxf(_ratio, 0.0001)
	_fill.position.x = -width * (1.0 - _ratio) * 0.5
	# Green when healthy, through yellow, to red when low.
	var c: Color
	if _ratio > 0.5:
		c = Color(0.85, 0.8, 0.25).lerp(Color(0.25, 0.85, 0.3), (_ratio - 0.5) * 2.0)
	else:
		c = Color(0.85, 0.2, 0.2).lerp(Color(0.85, 0.8, 0.25), _ratio * 2.0)
	if _fill_mat:
		_fill_mat.albedo_color = c

func _make_quad(color: Color, w: float, h: float, z: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(w, h)
	mi.mesh = q
	mi.position.z = z
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if color.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
