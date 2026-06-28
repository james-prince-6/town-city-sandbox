# first_run_panel.gd
# Autoload singleton (register as "FirstRunPanel", pointing at THIS .gd script).
#
# A one-time, top-centre onboarding banner that teaches the four core bindings to a
# brand-new player: '[E] Interact   [I] Inventory   [J] Quests   [Esc] Pause'. It is
# the persistent companion to the main menu's transient first-run TOAST — the toast
# scrolls away in a few seconds, this banner stays put (top-centre, out of the way of
# the HUD) until the player has clearly had time to read it.
#
# WHY a standalone CanvasLayer autoload (not an edit to hud.gd): this keeps the
# onboarding surface completely OFF the combat HUD so the two never collide, and lets
# the banner sit on its own layer between the HUD and the menus. Like the HUD it owns
# no game state — the only state it touches is the GameState `controls_hint_shown`
# flag, which it SETS (once) when the banner is dismissed so it never shows again on a
# returning save.
#
# Lifecycle (a tiny state machine driven from _process):
#   PENDING  - waiting for real gameplay to begin (a player exists, no title/menu up)
#   SHOWN    - banner faded in; counting down the auto-dismiss timer
#   DISMISSED- faded out, hidden, and the seen-flag set; never shows again this session
#
# It auto-dismisses after AUTO_DISMISS_SECONDS, OR the moment any blocking menu opens
# (so it never sits behind the bag/quest log/pause), OR when the player clicks its X.
#
# Robustness: every optional autoload (GameState, InputDevice) is reached via
# get_node_or_null and guarded, so the banner boots cleanly regardless of registration
# order and silently no-ops anything that isn't present.

extends CanvasLayer

const Glass = preload("res://ui/glass_style.gd")

## GameState flag that, once true, suppresses this banner forever (it rides along in
## the normal GameState save, so a returning player is never nagged again).
const SEEN_FLAG: StringName = &"controls_hint_shown"

## Auto-dismiss the banner this many seconds after it first appears, on the assumption
## the player has read it by then. Tunable.
const AUTO_DISMISS_SECONDS: float = 30.0

## Fade timings for the show / hide transitions (seconds).
const FADE_IN_SECONDS: float = 0.4
const FADE_OUT_SECONDS: float = 0.5

## Near-black text so the banner reads on the light frosted glass (project convention).
const TEXT_COLOR: Color = Color(0.10, 0.12, 0.16)
## Slightly muted colour for the dismiss [X] so it reads as secondary to the hint text.
const CLOSE_COLOR: Color = Color(0.28, 0.16, 0.16)

## The four bindings the banner teaches, as (input-action, label) pairs. Rendered with
## live device-aware glyphs when InputDevice is available, else a sensible literal.
const HINTS: Array = [
	[&"interact", "Interact"],
	[&"inventory", "Inventory"],
	[&"quest_log", "Quests"],
	[&"pause", "Pause"],
]
## Literal fallback glyphs (keyboard) used only when InputDevice can't supply one.
const FALLBACK_GLYPHS: Dictionary = {
	&"interact": "E",
	&"inventory": "I",
	&"quest_log": "J",
	&"pause": "Esc",
}

# Built once in _build_ui(); thereafter only their text / visibility / modulate change.
var _panel: PanelContainer
var _label: Label

# Tiny state machine. We start PENDING, reveal once gameplay is live, then DISMISSED.
var _shown: bool = false
var _dismissed: bool = false
# Real-ish seconds the banner has been visible, for the auto-dismiss countdown.
var _visible_elapsed: float = 0.0
# Active fade tween, kept so a dismiss can cancel an in-flight fade-in cleanly.
var _fade_tween: Tween = null

func _ready() -> void:
	# Between the HUD (5) and the toast feed (8) / menus (10+), so the banner draws over
	# the bars but a full-screen menu still covers it. Always-process so its fade keeps
	# running (and its auto-dismiss keeps ticking) even while a menu pauses the tree.
	layer = 7
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	# If this run has already seen the hint (returning save / replay), never build up.
	if _flag_seen():
		_dismissed = true
		_panel.visible = false
	# Re-render glyphs the instant the player swaps input device, so the banner shows the
	# pad's button labels on a controller. Guarded — fine if InputDevice isn't registered.
	var devices: Node = get_node_or_null("/root/InputDevice")
	if devices != null and devices.has_signal("device_changed"):
		devices.connect("device_changed", _on_device_changed)

# --- State machine ---------------------------------------------------------

func _process(delta: float) -> void:
	if _dismissed:
		return
	if not _shown:
		# Still waiting for gameplay to actually begin before we reveal.
		if _should_reveal():
			_reveal()
		return
	# Visible: count down to the auto-dismiss, and bail the moment a menu opens over us.
	_visible_elapsed += delta
	if _visible_elapsed >= AUTO_DISMISS_SECONDS or _a_menu_is_open():
		dismiss()

# Reveal only once we're truly in gameplay: the seen-flag is unset, the title screen is
# down, and a player actually exists in the world. This keeps the banner from flashing
# behind the main menu at boot.
func _should_reveal() -> bool:
	if _flag_seen():
		_dismissed = true
		return false
	if _main_menu_open():
		return false
	return get_tree().get_first_node_in_group("player") != null

func _reveal() -> void:
	_shown = true
	_visible_elapsed = 0.0
	_rebuild_text()
	_panel.visible = true
	_panel.modulate = Color(1, 1, 1, 0)
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_panel, "modulate:a", 1.0, FADE_IN_SECONDS)

## Fade the banner out, hide it, and set the seen-flag so it never returns. Public so the
## [X] button (and any future caller) can dismiss it. Idempotent.
func dismiss() -> void:
	if _dismissed:
		return
	_dismissed = true
	_mark_seen()
	if _fade_tween and _fade_tween.is_valid():
		_fade_tween.kill()
	if _panel == null:
		return
	_fade_tween = create_tween()
	_fade_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_fade_tween.tween_property(_panel, "modulate:a", 0.0, FADE_OUT_SECONDS)
	_fade_tween.tween_callback(func() -> void:
		if is_instance_valid(_panel):
			_panel.visible = false)

# --- Flag helpers (guarded) ------------------------------------------------

func _flag_seen() -> bool:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("get_flag"):
		return bool(gs.get_flag(SEEN_FLAG, false))
	return false

func _mark_seen() -> void:
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("set_flag"):
		gs.set_flag(SEEN_FLAG, true)

func _main_menu_open() -> bool:
	var menu: Node = get_node_or_null("/root/MainMenu")
	return menu != null and ("is_open" in menu) and menu.is_open

# A blocking menu is up if the tree is paused (pause menu) or any exclusive menu — the
# bag, quest log, shop — is currently open. The banner steps aside for all of them.
func _a_menu_is_open() -> bool:
	if get_tree().paused:
		return true
	for m in get_tree().get_nodes_in_group("exclusive_menu"):
		if is_instance_valid(m) and ("visible" in m) and m.visible:
			return true
	return false

# --- Text ------------------------------------------------------------------

func _on_device_changed(_device: int) -> void:
	if _shown and not _dismissed:
		_rebuild_text()

# Builds the single-line hint string with live, device-aware glyphs. Falls back to the
# literal keyboard glyph for any action InputDevice can't resolve, so it's never blank.
func _rebuild_text() -> void:
	if _label == null:
		return
	var devices: Node = get_node_or_null("/root/InputDevice")
	var parts: Array[String] = []
	for hint in HINTS:
		var action: StringName = hint[0]
		var label: String = hint[1]
		var glyph: String = ""
		if devices != null and devices.has_method("action_glyph"):
			glyph = String(devices.action_glyph(action))
		if glyph == "" or glyph == "?":
			glyph = String(FALLBACK_GLYPHS.get(action, "?"))
		parts.append("[%s] %s" % [glyph, label])
	# Wide spacing between groups so the four bindings read as four distinct chunks.
	_label.text = "   ".join(parts)

# --- UI construction (all in code) -----------------------------------------

func _build_ui() -> void:
	_panel = PanelContainer.new()
	# Pinned top-centre: anchored to the top edge, centred horizontally, nudged down a
	# touch so it clears the very top of the screen.
	_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.position = Vector2(0, 12)
	# Frosted-glass box (rim + blurred game view behind it), like the other panels.
	Glass.apply(_panel, 12, 14)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 8)
	_panel.add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	margin.add_child(row)

	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 15)
	_label.add_theme_color_override("font_color", TEXT_COLOR)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_label)
	_rebuild_text()

	# A small dismiss [X]. Only usable while the mouse is free (it's captured during FPS
	# play), so it's a convenience — the banner also auto-dismisses on a timer / menu open.
	var close := Button.new()
	close.text = "X"
	close.flat = true
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_color_override("font_color", CLOSE_COLOR)
	close.add_theme_font_size_override("font_size", 15)
	close.tooltip_text = "Dismiss"
	close.pressed.connect(dismiss)
	row.add_child(close)

	_panel.visible = false
