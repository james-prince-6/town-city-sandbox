# smoke_cloud.gd
# A short-lived puff of concealment dropped by a thrown smoke grenade. It grows
# from a small sphere to a big translucent one over a moment, holds, then fades its
# alpha to nothing and frees itself. No gameplay stat effect yet — purely visual
# cover. Self-contained and self-cleaning: spawn it, set `duration`, forget it.
#
# We drive a translucent SphereMesh by hand (scale up + alpha fade) so it needs no
# particle assets and reliably disappears. Built in code in _ready so the scene is
# just a Node3D + MeshInstance3D placeholder.

extends Node3D

## Total seconds the cloud exists, start to fully gone. Set by the grenade.
@export var duration: float = 5.0

## Final radius (metres) the cloud expands to at full size.
@export var max_radius: float = 3.0

# The mesh we animate. Resolved in _ready.
var _mesh_instance: MeshInstance3D = null
var _material: StandardMaterial3D = null
# Seconds elapsed since spawn, advanced in _process.
var _elapsed: float = 0.0
# Cached phase lengths (fractions of duration) so _process stays cheap.
const GROW_FRACTION: float = 0.2   # first 20% growing in
const FADE_FRACTION: float = 0.4   # last 40% fading out

func _ready() -> void:
	_mesh_instance = get_node_or_null("Smoke") as MeshInstance3D
	if _mesh_instance == null:
		# Nothing to animate — remove ourselves rather than linger invisibly.
		queue_free()
		return

	# Own a unique material instance so fading this cloud doesn't touch others.
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(0.7, 0.7, 0.72, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material = mat
	_mesh_instance.material_override = mat

	# Start tiny; _process scales us up to max_radius.
	scale = Vector3.ONE * 0.1

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= duration:
		queue_free()
		return

	# 0..1 progress through the cloud's whole life.
	var t: float = _elapsed / duration

	# Grow phase: scale from small to full over the first GROW_FRACTION.
	var grow_t: float = clampf(t / GROW_FRACTION, 0.0, 1.0)
	var s: float = lerpf(0.1, 1.0, grow_t)
	scale = Vector3.ONE * s

	# Fade phase: drop alpha to 0 over the last FADE_FRACTION.
	if _material != null:
		var fade_start: float = 1.0 - FADE_FRACTION
		var alpha: float = 0.55
		if t > fade_start:
			var fade_t: float = (t - fade_start) / FADE_FRACTION
			alpha = lerpf(0.55, 0.0, clampf(fade_t, 0.0, 1.0))
		var c: Color = _material.albedo_color
		c.a = alpha
		_material.albedo_color = c
