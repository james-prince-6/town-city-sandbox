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
## How much the GLASS PANELS blur the view behind them (shader `blur_amount`; default 2.0).
## Higher = blurrier/softer. The panels are intentionally blurrier than the backdrop below.
const BLUR_AMOUNT: float = 1.5
## Film-grain noise on the glass (shader `grain_amount`; default 0.05). 0 = clean, no speckle.
const GRAIN_AMOUNT: float = 0.0
## Backdrop frost: kept LESS blurry than the panels so the glass always reads as blurrier on top.
const FROST_BLUR: float = 0.4
## Negative brightness darkens the backdrop a bit so the menu pops (shader `brightness`).
const FROST_BRIGHTNESS: float = -0.1
## Alpha of the full-screen frost backdrop ColorRect (its rgb tint multiplies the blurred scene).
const FROST_ALPHA: float = 0.12
## rgb tint multiplied onto the blurred scene behind a menu — below white = darker.
const FROST_TINT: Color = Color(0.82, 0.82, 0.86)

# Shared materials — the shader has no per-panel state, so sharing per role is correct and cheap.
# Panels and the backdrop use SEPARATE materials so they can have different blur/brightness.
static var _material: ShaderMaterial = null
static var _frost_material: ShaderMaterial = null

# The shared glass-PANEL material, or null if the shader is missing (callers then degrade to plain).
static func material() -> ShaderMaterial:
	if _material == null:
		var sh: Shader = load(SHADER_PATH) as Shader
		if sh == null:
			return null
		_material = ShaderMaterial.new()
		_material.shader = sh
		_material.set_shader_parameter("blur_amount", BLUR_AMOUNT)
		_material.set_shader_parameter("grain_amount", GRAIN_AMOUNT)
	return _material

# The shared full-screen BACKDROP material: less blur than the panels + a slight darken, so the
# glass panels on top always look blurrier and the menu stands out.
static func frost_material() -> ShaderMaterial:
	if _frost_material == null:
		var sh: Shader = load(SHADER_PATH) as Shader
		if sh == null:
			return null
		_frost_material = ShaderMaterial.new()
		_frost_material.shader = sh
		_frost_material.set_shader_parameter("blur_amount", FROST_BLUR)
		_frost_material.set_shader_parameter("grain_amount", GRAIN_AMOUNT)
		_frost_material.set_shader_parameter("brightness", FROST_BRIGHTNESS)
	return _frost_material

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
	rect.color = Color(FROST_TINT.r, FROST_TINT.g, FROST_TINT.b, FROST_ALPHA)
	var m: ShaderMaterial = frost_material()
	if m != null:
		rect.material = m

# Build a fresh full-screen frost backdrop ColorRect (anchored to fill its parent).
static func make_frost() -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	frost(r)
	return r
