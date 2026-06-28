# screen_fade.gd
# Autoload singleton (registered as "ScreenFade") — a full-screen black overlay that
# eases scene changes from a jarring hard-cut into a cinematic fade. It owns ONE
# CanvasLayer (high layer so it sits above the world and most UI) with a single black
# ColorRect whose alpha is tweened.
#
# WHY a fade-IN (reveal) rather than a fade-OUT-then-load: the only hook the engine
# gives us cheaply is SceneManager.scene_loaded, which fires AFTER the new world is
# built and the player placed. So on every scene load we SNAP to opaque black and then
# fade the black away, revealing the freshly-built scene. That hides the harsh first
# frame (uninitialised cameras, one-frame prop pop-in) and reads as a smooth wipe-in,
# with zero changes to SceneManager. A manual full-cycle is also available via fade().
#
# Pure code, no asset dependencies. Reaches SceneManager defensively through
# get_node_or_null so the autoload is safe even if it loads before SceneManager or if
# SceneManager is ever removed.
#
# REGISTER AS AUTOLOAD: Name "ScreenFade" -> res://global/ui/screen_fade.gd (layer 25).
#
# NOTE: intentionally NO class_name — the autoload global "ScreenFade" would collide
# with a matching class_name.

extends CanvasLayer

## Default fade duration (seconds) for an automatic scene-change reveal.
const DEFAULT_DURATION: float = 0.45

## CanvasLayer ordering. High so the fade covers the world and gameplay HUD, but the
## integrator may pick any free layer; keep it above the world (-100) and the HUD (5).
const FADE_LAYER: int = 25

var _rect: ColorRect
var _tween: Tween

func _ready() -> void:
	# Sit above the world + HUD, and keep working while the tree is paused (menus).
	layer = FADE_LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

	_rect = ColorRect.new()
	_rect.color = Color(0.0, 0.0, 0.0, 0.0)   # start fully transparent (invisible)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Never intercept clicks/hover — the overlay is purely visual.
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)

	# Reveal the world from black whenever a new scene finishes loading. Guarded so we
	# don't hard-depend on SceneManager existing at our _ready time.
	var sm: Node = get_node_or_null("/root/SceneManager")
	if sm != null and sm.has_signal("scene_loaded"):
		if not sm.scene_loaded.is_connected(_on_scene_loaded):
			sm.scene_loaded.connect(_on_scene_loaded)

# --- Public API ------------------------------------------------------------

## Snap to black, then fade the black away over `duration` seconds — a cinematic
## reveal of whatever is currently on screen. Safe to call any time; re-calling
## restarts the fade. Pass duration <= 0 to clear instantly.
func fade(duration: float = DEFAULT_DURATION) -> void:
	_kill_tween()
	if _rect == null:
		return
	if duration <= 0.0:
		_set_alpha(0.0)
		return
	_set_alpha(1.0)
	_tween = create_tween()
	_tween.tween_method(_set_alpha, 1.0, 0.0, duration)

## Fade TO black over `duration` (e.g. for a scripted blackout). Leaves the screen
## black; pair with fade() / fade_from_black() to come back.
func fade_to_black(duration: float = DEFAULT_DURATION) -> void:
	_kill_tween()
	if _rect == null:
		return
	if duration <= 0.0:
		_set_alpha(1.0)
		return
	_tween = create_tween()
	_tween.tween_method(_set_alpha, _rect.color.a, 1.0, duration)

## Fade FROM black to clear over `duration` (the reveal half only, without the snap).
func fade_from_black(duration: float = DEFAULT_DURATION) -> void:
	_kill_tween()
	if _rect == null:
		return
	if duration <= 0.0:
		_set_alpha(0.0)
		return
	_tween = create_tween()
	_tween.tween_method(_set_alpha, _rect.color.a, 0.0, duration)

## True while a fade tween is currently running. Lets callers gate input or wait.
func is_fading() -> bool:
	return _tween != null and _tween.is_valid() and _tween.is_running()

# --- Internals -------------------------------------------------------------

func _on_scene_loaded(_scene_path: String) -> void:
	fade(DEFAULT_DURATION)

func _set_alpha(a: float) -> void:
	if _rect == null:
		return
	var c: Color = _rect.color
	c.a = clampf(a, 0.0, 1.0)
	_rect.color = c

func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
