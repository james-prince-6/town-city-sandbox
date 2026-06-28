# area_title_card.gd
# Autoload singleton (registered as "AreaTitleCard") — the cinematic "you have arrived"
# place-name that fades in when the player enters a named area, the way an open-world RPG
# captions a new region. It owns ONE CanvasLayer (above the world + HUD) holding a large
# OUTLINED title Label and a smaller tagline Label, centred in the upper third.
#
# WHY an autoload + a push API (rather than a scene widget): the card must persist across
# the scene swap and sit above the world SubViewport, so it lives outside the swappable
# tree like the HUD. Stages call show_card(title, tagline) at the very end of their _ready
# (WildArea uses its area_title; RoomInterior its area_title/area_tagline), so the caption
# rides in on top of ScreenFade's reveal. show_card is a no-op when the title is blank, so
# unnamed/dev scenes stay silent.
#
# Pure code, no asset dependencies (uses the default font with a thick outline for
# legibility over any background). Self-contained: no other autoload is required, so it is
# safe regardless of load order.
#
# REGISTER AS AUTOLOAD: Name "AreaTitleCard" -> res://global/ui/area_title_card.gd (layer 26).
#
# NOTE: intentionally NO class_name — the autoload global "AreaTitleCard" would collide
# with a matching class_name.

extends CanvasLayer

## CanvasLayer ordering. Above the world (-100), HUD (5) and the screen fade (25) so the
## place-name reads on top of the reveal. Integrator may pick any free layer above those.
const CARD_LAYER: int = 26

## Timing (seconds): ease in, hold fully visible, then ease out.
const FADE_IN: float = 0.8
const HOLD: float = 2.2
const FADE_OUT: float = 1.0

var _root: Control
var _title: Label
var _tagline: Label
var _tween: Tween

func _ready() -> void:
	# Above world + HUD + fade, and keep tweening while the tree is paused.
	layer = CARD_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Full-rect, click-through container we fade as a whole (CanvasLayer has no modulate).
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.modulate = Color(1.0, 1.0, 1.0, 0.0)   # start hidden
	add_child(_root)

	# A centring band in the upper third of the screen.
	var center := CenterContainer.new()
	center.anchor_left = 0.0
	center.anchor_right = 1.0
	center.anchor_top = 0.18
	center.anchor_bottom = 0.5
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(vbox)

	_title = _make_label(64, Color(1.0, 0.97, 0.88), 12)
	vbox.add_child(_title)

	_tagline = _make_label(28, Color(0.85, 0.88, 0.95), 8)
	vbox.add_child(_tagline)

# --- Public API ------------------------------------------------------------

## Fade an area title (+ optional tagline) in, hold, then fade out. No-op when `title`
## is blank/whitespace so unnamed scenes stay silent. Re-calling restarts the card.
## Signature matches a (title, tagline) signal so stages can connect or call directly.
func show_card(title: String, tagline: String = "") -> void:
	if _root == null or _title == null:
		return
	if title.strip_edges() == "":
		return
	_title.text = title
	_tagline.text = tagline
	_tagline.visible = tagline.strip_edges() != ""

	_kill_tween()
	_set_alpha(0.0)
	_tween = create_tween()
	_tween.tween_method(_set_alpha, 0.0, 1.0, FADE_IN)
	_tween.tween_interval(HOLD)
	_tween.tween_method(_set_alpha, 1.0, 0.0, FADE_OUT)

## True while the card is currently animating/visible.
func is_showing() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()

# --- Internals -------------------------------------------------------------

# A centred Label with a thick dark outline so light text stays legible on any sky.
func _make_label(font_size: int, color: Color, outline: int) -> Label:
	var lbl := Label.new()
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	lbl.add_theme_constant_override("outline_size", outline)
	return lbl

func _set_alpha(a: float) -> void:
	if _root == null:
		return
	var c: Color = _root.modulate
	c.a = clampf(a, 0.0, 1.0)
	_root.modulate = c

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
