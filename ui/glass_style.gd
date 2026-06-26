# glass_style.gd
# Shared helper for the frosted-glass UI look, so every HUD/menu surface gets the same treatment
# from one place. The glass shader (assets/shaders/ui/glass_panel.gdshader) reads a Control's
# per-pixel alpha as its edge mask: a transparent centre shows the blurred game view behind, a
# blended white border becomes the bright glass rim.
#
# Three entry points:
#   apply(panel)    -> a Panel/PanelContainer becomes a frosted glass box (rim + blurred centre).
#   frost(colorrect)-> an existing full-screen dim ColorRect becomes a uniform glass FROST (blurs
#                      the scene instead of blackening it) — the menu backdrop, no black.
#   make_frost()    -> build a fresh full-screen frost ColorRect.
#
# NO class_name ON PURPOSE: callers preload this as a const (const Glass = preload(...)) so we
# never depend on a global class symbol being registered (avoids the headless class-cache
# pitfall), and the static material cache is still shared (preload returns the one cached script).
extends RefCounted

const SHADER_PATH: String = "res://assets/shaders/ui/glass_panel.gdshader"

# One shared ShaderMaterial for every glass surface — the shader has no per-panel state, so sharing
# is correct and cheap.
static var _material: ShaderMaterial = null

# The shared glass material, or null if the shader is missing (callers then degrade to plain).
static func material() -> ShaderMaterial:
	if _material == null:
		var sh: Shader = load(SHADER_PATH) as Shader
		if sh == null:
			return null
		_material = ShaderMaterial.new()
		_material.shader = sh
	return _material

# A glass stylebox: transparent centre (the shader fills it with the blurred view), a blended white
# border that becomes the bright rim, rounded corners. `border` is the rim thickness in px.
static func stylebox(corner: int = 14, border: int = 18) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1, 1, 1, 0)
	sb.set_border_width_all(border)
	sb.border_color = Color(1, 1, 1, 1)
	sb.border_blend = true
	sb.set_corner_radius_all(corner)
	sb.anti_aliasing_size = 0.01
	return sb

# Give a Panel/PanelContainer the frosted-glass look. No-op-safe if the shader is missing.
static func apply(ctrl: Control, corner: int = 14, border: int = 18) -> void:
	if ctrl == null:
		return
	ctrl.add_theme_stylebox_override("panel", stylebox(corner, border))
	var m: ShaderMaterial = material()
	if m != null:
		ctrl.material = m

# Turn an existing full-screen dim ColorRect into a uniform glass FROST: a low, even alpha makes
# the shader blur the whole screen behind the menu (no bright rim, no black). Replaces the old
# Color(0,0,0,0.x) dims.
static func frost(rect: ColorRect) -> void:
	if rect == null:
		return
	rect.color = Color(1, 1, 1, 0.16)
	var m: ShaderMaterial = material()
	if m != null:
		rect.material = m

# Build a fresh full-screen frost backdrop ColorRect (anchored to fill its parent).
static func make_frost() -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	frost(r)
	return r
