# ui_style.gd
# Town City flat "sticker" UI helper — the new design language (replaces the retired
# glass_style.gd). Cream panels, a 3px ink outline, gently rounded corners, NO shadow,
# NO blur, NO shader. It mirrors town_city_theme.tres so code-built surfaces match the
# themed ones.
#
# Drop-in for the old Glass helper: it keeps the SAME entry points and signatures, so a
# caller only has to repoint its preload at this file.
#   apply(panel[, corner, border]) -> a Panel/PanelContainer becomes a cream sticker box.
#   frost(colorrect)               -> a full-screen dim ColorRect becomes a flat ink wash.
#   make_frost()                   -> build a fresh full-screen ink-wash backdrop.
#
# Compatibility note: the old `corner`/`border` args were glass-rim sizes. Here the OUTLINE
# is always a crisp 3px ink line; the old `border` value is reused as the panel's CONTENT
# PADDING instead, so existing layouts keep roughly the spacing the glass rim used to give.
#
# NO class_name ON PURPOSE: callers preload this as a const so we never depend on a global
# class symbol (avoids the headless class-cache pitfall).
extends RefCounted

## Locked palette (matches town_city_theme.tres).
const INK: Color = Color(0.055, 0.051, 0.071, 1.0)
const CREAM: Color = Color(0.906, 0.882, 0.831, 1.0)
const CREAM_BRIGHT: Color = Color(0.984, 0.973, 0.941, 1.0)
## Full-screen backdrop behind a menu: a flat ink wash (NOT black, NOT frosted glass).
const SCRIM: Color = Color(0.055, 0.051, 0.071, 0.5)
## Crisp outline thickness, in px — fixed regardless of the old glass-rim arg.
const OUTLINE: int = 3

# Build a cream sticker stylebox: cream fill, 3px ink outline, rounded corners, inner padding.
static func stylebox(corner: int = 14, border: int = 18) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = CREAM
	sb.set_border_width_all(OUTLINE)
	sb.border_color = INK
	sb.set_corner_radius_all(clampi(corner, 4, 10))
	# Reuse the old rim size as content padding so prior layouts keep their spacing.
	var pad: int = clampi(border, 8, 22)
	sb.content_margin_left = float(pad)
	sb.content_margin_right = float(pad)
	sb.content_margin_top = float(maxi(6, pad - 6))
	sb.content_margin_bottom = float(maxi(6, pad - 6))
	return sb

# Give a Panel/PanelContainer the flat sticker look, and strip any leftover glass material.
static func apply(ctrl: Control, corner: int = 14, border: int = 18) -> void:
	if ctrl == null:
		return
	ctrl.add_theme_stylebox_override("panel", stylebox(corner, border))
	ctrl.material = null

# Turn a full-screen dim ColorRect into a flat ink wash (replaces the old glass frost). Also
# drops any glass shader material so nothing blurs.
static func frost(rect: ColorRect) -> void:
	if rect == null:
		return
	rect.color = SCRIM
	rect.material = null

# Build a fresh full-screen ink-wash backdrop ColorRect (anchored to fill its parent).
static func make_frost() -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	frost(r)
	return r
