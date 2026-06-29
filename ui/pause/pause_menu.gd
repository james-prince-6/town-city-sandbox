# pause_menu.gd
# Autoload singleton (registered as "PauseMenu"). A full-screen pause overlay
# opened with the "pause" action (Escape). Opening it FULLY pauses the game:
# get_tree().paused = true freezes every pausable node, and we also pause the Clock
# (which runs with PROCESS_MODE_ALWAYS, so it wouldn't stop on its own) so in-game
# time and brewing halt too.
#
# It's built entirely in code (no .tscn) so there's no layout to maintain. The main
# panel is a keyboard/controller cursor list (Resume / Save / Load / Settings /
# Controls / Main Menu / Quit); Settings and Controls are sub-panels reached from it.
#
# Visuals follow docs/design/handoff_town_city_ui/Pause Menu.dc.html — the Town City
# flat "sticker" look (cream panels, 3px ink outline, Chakra Petch titles). All the
# StyleBoxFlat/colour work is built inline here so this file owns its whole appearance.
#
# Escape etiquette: this only opens when nothing else is using Escape. If a
# conversation or another menu (inventory/shop/brewing) is open, we leave Escape to
# that UI's own close handler and don't pop the pause menu over it.

extends CanvasLayer

var is_open: bool = false

var _root: Control
var _main_panel: Control
var _settings_panel: Control
# Read-only key-binding reference panel (reached from the main panel's Controls button).
var _controls_panel: Control
# First button on the main panel ("Resume") — grabbed on open so a controller
# immediately has something selected.
var _resume_button: Button = null
# The three font-scale toggle buttons (Small/Normal/Large) so the handler can keep
# them behaving like a radio group (only the chosen size stays pressed).
var _font_buttons: Array[Button] = []

## The actions listed (in order) on the Controls reference panel, each as a
## {action, label} pair. TUNABLE: add/remove/relabel rows here — every entry just
## renders "[glyph] Label" using the active input device's glyph, so the panel
## always reflects the live InputMap (and re-labels itself on keyboard/pad swap).
const DISPLAYED_ACTIONS: Array = [
	{"action": &"move_forward", "label": "Move Forward"},
	{"action": &"move_backward", "label": "Move Backward"},
	{"action": &"move_left", "label": "Move Left"},
	{"action": &"move_right", "label": "Move Right"},
	{"action": &"jump", "label": "Jump"},
	{"action": &"sprint", "label": "Sprint"},
	{"action": &"dodge", "label": "Dodge / Roll"},
	{"action": &"interact", "label": "Interact / Talk"},
	{"action": &"use_item", "label": "Use / Attack"},
	{"action": &"block", "label": "Block"},
	{"action": &"hotbar_prev", "label": "Previous Item / Tab"},
	{"action": &"hotbar_next", "label": "Next Item / Tab"},
	{"action": &"inventory", "label": "Inventory"},
	{"action": &"skill_tree", "label": "Skills"},
	{"action": &"quest_log", "label": "Quest Log"},
	{"action": &"quicksave", "label": "Quick Save"},
	{"action": &"quickload", "label": "Quick Load"},
	{"action": &"pause", "label": "Pause / Back"},
]

## GameState flag key the accessibility font scale is stored under. Kept in lock-step
## with player_menu.gd / crafting_ui.gd (which READ the same key) so changing the size
## here rescales those menus next time they open. Stored via the GameState flag API so
## this bucket never edits game_state.gd.
const FONT_SCALE_FLAG: StringName = &"ui_font_scale"

## The selectable UI text sizes. TUNABLE multipliers applied to menu font overrides.
const FONT_SCALE_OPTIONS: Array = [
	{"label": "Small", "scale": 0.9},
	{"label": "Normal", "scale": 1.0},
	{"label": "Large", "scale": 1.2},
]

# --- Design tokens (from the handoff HTML) ---------------------------------
const C_INK: Color = Color(0.0549, 0.0510, 0.0706, 1.0)        # #0e0d12
const C_TEXT: Color = Color(0.1333, 0.1216, 0.1020, 1.0)       # #221f1a
const C_DIM: Color = Color(0.4157, 0.3961, 0.3608, 1.0)        # #6a655c
const C_CREAM: Color = Color(0.9059, 0.8824, 0.8314, 1.0)      # #e7e1d4
const C_BRIGHT: Color = Color(0.9843, 0.9725, 0.9412, 1.0)     # #fbf8f0
const C_TRACK: Color = Color(0.7922, 0.7490, 0.6745, 1.0)      # #cabfac
const C_GOLD: Color = Color(0.7843, 0.5804, 0.1176, 1.0)       # #c8941e
const C_KEYCAP: Color = Color(0.9059, 0.8510, 0.6588, 1.0)     # #e7d9a8
const C_DIVIDER: Color = Color(0.8392, 0.8039, 0.7294, 1.0)    # #d6cdba
const C_PANEL: Color = Color(0.9059, 0.8824, 0.8314, 0.95)     # cream @ .95
const C_CLEAR: Color = Color(0, 0, 0, 0)

# Chakra Petch SemiBold for titles/labels; Space Grotesk Bold for body/values.
const FONT_TITLE: FontFile = preload("res://ui/fonts/ChakraPetch-SemiBold.ttf")
const FONT_BODY: FontFile = preload("res://ui/fonts/SpaceGrotesk-Bold.ttf")

# Round gold slider thumb (built once, shared by every slider).
var _thumb_cache: ImageTexture = null

func _ready() -> void:
	# Above everything else (dialogue is 11) and always processing so the menu still
	# works while the tree is paused.
	layer = 20
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide()

func _unhandled_input(event: InputEvent) -> void:
	# Esc / B (ui_cancel) while open: step back from Settings, otherwise resume.
	# Handled before the "pause" branch so a single Esc closes rather than re-toggles.
	if is_open and event.is_action_pressed("ui_cancel"):
		if _sub_panel_visible():
			_show_main()
		else:
			close()
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("pause"):
		return
	if is_open:
		close()
		get_viewport().set_input_as_handled()
	elif _other_ui_blocking():
		# Let the open conversation / menu handle Escape itself (it closes on ui_cancel).
		return
	else:
		open()
		get_viewport().set_input_as_handled()

# True when some other UI already owns the screen, so we shouldn't pop over it.
func _other_ui_blocking() -> bool:
	# PlayerMenu is a CanvasLayer the orchestrator adds; reference it safely (it may
	# not exist yet). If it's up, leave Esc to it so it closes instead of stacking
	# pause on top. Untyped var so .visible resolves dynamically (Node has no .visible).
	var player_menu = get_node_or_null("/root/PlayerMenu")
	if player_menu != null and player_menu.visible:
		return true
	if Dialogue.is_active:
		return true
	if InventoryUI.is_open:
		return true
	# Shop/Brewing are CanvasLayers that hide() when closed; treat visible as open.
	if is_instance_valid(ShopUI) and ShopUI.visible:
		return true
	if is_instance_valid(BrewingUI) and BrewingUI.visible:
		return true
	# CraftingUI/UpgradeUI are also blocking CanvasLayers; the joypad "pause" button isn't
	# ui_cancel, so guard against popping pause on top of them (keyboard is already covered
	# by ui_cancel consumption + autoload ordering). Referenced safely in case unregistered.
	var crafting_ui = get_node_or_null("/root/CraftingUI")
	if crafting_ui != null and crafting_ui.visible:
		return true
	var upgrade_ui = get_node_or_null("/root/UpgradeUI")
	if upgrade_ui != null and upgrade_ui.visible:
		return true
	return false

# --- Open / close ----------------------------------------------------------

func open() -> void:
	if is_open:
		return
	is_open = true
	_show_main()
	show()
	get_tree().paused = true
	# Clock runs with PROCESS_MODE_ALWAYS, so the tree pause won't stop it — do it explicitly.
	if Clock:
		Clock.pause()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func close() -> void:
	if not is_open:
		return
	is_open = false
	hide()
	get_tree().paused = false
	if Clock:
		Clock.resume()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# --- UI construction (all in code) -----------------------------------------

const Flat = preload("res://ui/ui_style.gd")

func _build_ui() -> void:
	# Full-screen frosted-glass backdrop (no black) that also eats clicks behind the menu.
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	Flat.frost(dim)
	add_child(dim)
	_root = dim

	_main_panel = _build_main_panel()
	_root.add_child(_main_panel)

	_settings_panel = _build_settings_panel()
	_root.add_child(_settings_panel)
	_settings_panel.hide()

	_controls_panel = _build_controls_panel()
	_root.add_child(_controls_panel)
	_controls_panel.hide()

	# Persistent footer hint, right-aligned along the bottom edge (over every panel).
	var hint := Label.new()
	hint.text = "↑↓ navigate · Enter select · Esc back / resume"
	hint.add_theme_font_override("font", FONT_BODY)
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", C_CREAM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.anchor_left = 0.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = 24.0
	hint.offset_right = -24.0
	hint.offset_top = -40.0
	hint.offset_bottom = -14.0
	_root.add_child(hint)

# --- Shared style builders -------------------------------------------------

# Cream sticker panel: cream@.95 fill, 3px ink outline, radius 8, `pad` content margin.
func _panel_stylebox(pad: int = 22) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.set_border_width_all(3)
	sb.border_color = C_INK
	sb.set_corner_radius_all(8)
	sb.content_margin_left = float(pad)
	sb.content_margin_right = float(pad)
	sb.content_margin_top = float(pad)
	sb.content_margin_bottom = float(pad)
	return sb

# A flat horizontal rule used under titles (track colour) or between rows.
func _rule(height: int, col: Color) -> ColorRect:
	var c := ColorRect.new()
	c.color = col
	c.custom_minimum_size = Vector2(0, height)
	return c

# The little 34x34 "‹" back chip used by both sub-panel headers.
func _make_back_button() -> Button:
	var b := Button.new()
	b.text = "‹"
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(34, 34)
	b.add_theme_font_override("font", FONT_TITLE)
	b.add_theme_font_size_override("font_size", 18)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_BRIGHT
	sb.set_border_width_all(3)
	sb.border_color = C_INK
	sb.set_corner_radius_all(6)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(st, sb)
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(st, C_TEXT)
	b.pressed.connect(_show_main)
	return b

# A left-aligned Chakra title for a sub-panel header.
func _make_header_title(text: String) -> Label:
	var t := Label.new()
	t.text = text
	t.add_theme_font_override("font", FONT_TITLE)
	t.add_theme_font_size_override("font_size", 28)
	t.add_theme_color_override("font_color", C_TEXT)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return t

# --- Main panel (cursor list) ----------------------------------------------

func _build_main_panel() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_stylebox(22))
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(316, 0)   # 360 panel − 2*22 padding
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 38)
	title.add_theme_color_override("font_color", C_TEXT)
	vbox.add_child(title)

	vbox.add_child(_rule(3, C_TRACK))

	var specs := [
		{"text": "Resume", "handler": Callable(self, "close")},
		{"text": "Save Game", "handler": Callable(self, "_on_save")},
		{"text": "Load Game", "handler": Callable(self, "_on_load")},
		{"text": "Settings", "handler": Callable(self, "_show_settings")},
		{"text": "Controls", "handler": Callable(self, "_show_controls")},
		{"text": "Main Menu", "handler": Callable(self, "_on_main_menu")},
		{"text": "Quit", "handler": Callable(self, "_on_quit")},
	]
	_resume_button = null
	for spec in specs:
		var row := _make_row(String(spec["text"]), spec["handler"])
		vbox.add_child(row)
		# First main-panel row is Resume; remember it to grab focus on open.
		if _resume_button == null:
			_resume_button = row

	return center

# One selectable cursor row: a focusable Button whose look tracks keyboard focus
# (and mouse hover, which grabs focus). Selected = bright fill + ink border + gold
# caret + ink text; unselected = transparent fill + a 3px TRANSPARENT border (so the
# row reserves the same space) + hidden caret + dim text.
func _make_row(label_text: String, handler: Callable) -> Button:
	var row := Button.new()
	row.focus_mode = Control.FOCUS_ALL
	row.custom_minimum_size = Vector2(0, 44)
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND

	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 14.0
	hb.offset_right = -14.0
	hb.offset_top = 0.0
	hb.offset_bottom = 0.0
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(hb)

	var caret := Label.new()
	caret.text = "▸"
	caret.custom_minimum_size = Vector2(14, 0)
	caret.add_theme_font_override("font", FONT_TITLE)
	caret.add_theme_font_size_override("font_size", 15)
	caret.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caret.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(caret)

	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_override("font", FONT_TITLE)
	lbl.add_theme_font_size_override("font_size", 19)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(lbl)

	row.set_meta("caret", caret)
	row.set_meta("lbl", lbl)
	row.focus_entered.connect(_on_row_focus.bind(row, true))
	row.focus_exited.connect(_on_row_focus.bind(row, false))
	row.mouse_entered.connect(row.grab_focus)
	row.pressed.connect(handler)
	_set_row_selected(row, false)
	return row

func _on_row_focus(row: Button, selected: bool) -> void:
	_set_row_selected(row, selected)

func _set_row_selected(row: Button, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(7)
	sb.set_border_width_all(3)
	if selected:
		sb.bg_color = C_BRIGHT
		sb.border_color = C_INK
	else:
		sb.bg_color = C_CLEAR
		sb.border_color = C_CLEAR   # transparent but 3px → reserves the same width
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		row.add_theme_stylebox_override(st, sb)
	var caret := row.get_meta("caret") as Label
	var lbl := row.get_meta("lbl") as Label
	if caret:
		caret.add_theme_color_override("font_color", C_GOLD if selected else C_CLEAR)
	if lbl:
		lbl.add_theme_color_override("font_color", C_TEXT if selected else C_DIM)

# --- Settings panel --------------------------------------------------------

func _build_settings_panel() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_stylebox(22))
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(396, 0)   # 440 panel − 2*22 padding
	vbox.add_theme_constant_override("separation", 13)
	panel.add_child(vbox)

	# Header: ‹ back chip + left-aligned title + track divider.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.add_child(_make_back_button())
	header.add_child(_make_header_title("Settings"))
	vbox.add_child(header)
	vbox.add_child(_rule(3, C_TRACK))

	# Master volume.
	_add_slider_block(vbox, "Master Volume", 0.0, 1.0, 0.01, _get_master_volume(), true, Callable(self, "_on_volume_changed"))

	# Per-bus volume sliders. Each resolves its bus index via _bus_or_master so a missing
	# bus degrades gracefully (it just drives Master instead of erroring on index -1).
	_add_bus_slider(vbox, "Music Volume", "Music")
	_add_bus_slider(vbox, "SFX Volume", "SFX")
	_add_bus_slider(vbox, "Ambient Volume", "Ambient")

	# Mouse sensitivity (core FPS accessibility control). Seeded from the live player so the
	# slider reflects the current value whenever Settings is opened.
	_add_slider_block(vbox, "Mouse Sensitivity", 0.1, 1.0, 0.05, _get_mouse_sensitivity(), false, Callable(self, "_on_sensitivity_changed"))

	# Fullscreen pill toggle.
	_add_fullscreen_row(vbox)

	# Accessibility: UI text size. A radio-style segmented row (Small / Normal / Large)
	# persisted through the GameState flag API; player_menu & crafting_ui read it to rescale
	# their font overrides on next open. Pure UI scale — no gameplay is affected.
	_add_font_scale_row(vbox)

	return center

# A labelled slider block: [label .......... value] over a track + round gold thumb.
func _add_slider_block(parent: Node, label_text: String, vmin: float, vmax: float, vstep: float, value: float, is_pct: bool, on_change: Callable) -> void:
	var block := VBoxContainer.new()
	block.add_theme_constant_override("separation", 5)

	var head := HBoxContainer.new()
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_override("font", FONT_TITLE)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(lbl)

	var val := Label.new()
	val.add_theme_font_override("font", FONT_BODY)
	val.add_theme_font_size_override("font_size", 13)
	val.add_theme_color_override("font_color", C_DIM)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(val)
	block.add_child(head)

	var slider := _make_slider(vmin, vmax, vstep, value)
	block.add_child(slider)
	parent.add_child(block)

	var updater := func(v: float) -> void:
		if is_pct:
			val.text = "%d%%" % int(round(v * 100.0))
		else:
			val.text = "%.2f" % v
	updater.call(value)
	slider.value_changed.connect(on_change)
	slider.value_changed.connect(updater)

# A styled HSlider: #cabfac track, 3px ink border, radius 5, round gold thumb.
func _make_slider(vmin: float, vmax: float, vstep: float, value: float) -> HSlider:
	var slider := HSlider.new()
	slider.min_value = vmin
	slider.max_value = vmax
	slider.step = vstep
	slider.value = value
	slider.custom_minimum_size = Vector2(0, 22)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var track := StyleBoxFlat.new()
	track.bg_color = C_TRACK
	track.set_border_width_all(3)
	track.border_color = C_INK
	track.set_corner_radius_all(5)
	track.content_margin_top = 5.0
	track.content_margin_bottom = 5.0
	track.content_margin_left = 5.0
	track.content_margin_right = 5.0
	slider.add_theme_stylebox_override("slider", track)

	# No separate "filled" highlight — the track is a single uniform colour.
	var empty := StyleBoxEmpty.new()
	slider.add_theme_stylebox_override("grabber_area", empty)
	slider.add_theme_stylebox_override("grabber_area_highlight", empty)

	var thumb := _thumb_texture()
	slider.add_theme_icon_override("grabber", thumb)
	slider.add_theme_icon_override("grabber_highlight", thumb)
	slider.add_theme_icon_override("grabber_disabled", thumb)
	return slider

# Build (once) a 20x20 round gold thumb with a 3px ink ring.
func _thumb_texture() -> ImageTexture:
	if _thumb_cache != null:
		return _thumb_cache
	var s := 20
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(C_CLEAR)
	var c := (s - 1) / 2.0
	var outer := 9.5
	var inner := outer - 3.0
	for y in s:
		for x in s:
			var d := Vector2(float(x) - c, float(y) - c).length()
			if d <= inner:
				img.set_pixel(x, y, C_GOLD)
			elif d <= outer:
				img.set_pixel(x, y, C_INK)
	_thumb_cache = ImageTexture.create_from_image(img)
	return _thumb_cache

# Fullscreen toggle row: label + a 52x28 pill switch (gold on / cream off, sliding knob).
func _add_fullscreen_row(parent: Node) -> void:
	var row := HBoxContainer.new()

	var lbl := Label.new()
	lbl.text = "Fullscreen"
	lbl.add_theme_font_override("font", FONT_TITLE)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

	var pill := Button.new()
	pill.toggle_mode = true
	pill.focus_mode = Control.FOCUS_ALL
	pill.custom_minimum_size = Vector2(52, 28)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_END
	pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var knob := Panel.new()
	var ksb := StyleBoxFlat.new()
	ksb.bg_color = C_INK
	ksb.set_corner_radius_all(10)
	knob.add_theme_stylebox_override("panel", ksb)
	knob.set_size(Vector2(20, 20))
	knob.custom_minimum_size = Vector2(20, 20)
	knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pill.add_child(knob)

	pill.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	pill.toggled.connect(_on_fullscreen_toggled)
	pill.toggled.connect(func(on: bool) -> void: _update_fs_visual(pill, knob, on))
	_update_fs_visual(pill, knob, pill.button_pressed)

	row.add_child(pill)
	parent.add_child(row)

func _update_fs_visual(pill: Button, knob: Panel, on: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_GOLD if on else C_CREAM
	sb.set_border_width_all(3)
	sb.border_color = C_INK
	sb.set_corner_radius_all(14)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		pill.add_theme_stylebox_override(st, sb)
	knob.position = Vector2(28.0 if on else 4.0, 4.0)

# UI Text Size: a label + 3 equal-flex segmented radio buttons.
func _add_font_scale_row(parent: Node) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var lbl := Label.new()
	lbl.text = "UI Text Size"
	lbl.add_theme_font_override("font", FONT_TITLE)
	lbl.add_theme_font_size_override("font_size", 14)
	lbl.add_theme_color_override("font_color", C_TEXT)
	row.add_child(lbl)

	var seg := HBoxContainer.new()
	seg.add_theme_constant_override("separation", 5)
	seg.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var current_scale: float = _get_font_scale()
	_font_buttons.clear()
	for opt in FONT_SCALE_OPTIONS:
		var opt_scale: float = float(opt["scale"])
		var fb := Button.new()
		fb.text = String(opt["label"])
		fb.toggle_mode = true
		fb.focus_mode = Control.FOCUS_ALL
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fb.add_theme_font_override("font", FONT_TITLE)
		fb.add_theme_font_size_override("font_size", 13)
		fb.button_pressed = is_equal_approx(current_scale, opt_scale)
		fb.set_meta("scale", opt_scale)
		fb.pressed.connect(_on_font_scale.bind(opt_scale))
		_style_font_button(fb, fb.button_pressed)
		seg.add_child(fb)
		_font_buttons.append(fb)

	row.add_child(seg)
	parent.add_child(row)

func _style_font_button(fb: Button, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_BRIGHT if selected else C_CREAM
	sb.set_border_width_all(3)
	sb.border_color = C_INK
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 7.0
	sb.content_margin_right = 7.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		fb.add_theme_stylebox_override(st, sb)
	var col := C_TEXT if selected else C_DIM
	for st in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		fb.add_theme_color_override(st, col)

# --- Controls panel --------------------------------------------------------

# Read-only key-binding reference: a scrollable list of [keycap] Action rows built from
# DISPLAYED_ACTIONS. Glyphs come from the InputDevice autoload (active-device aware) and
# degrade to the raw action name if that autoload is absent, so this never blanks out.
func _build_controls_panel() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_stylebox(22))
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(416, 0)   # 460 panel − 2*22 padding
	vbox.add_theme_constant_override("separation", 13)
	panel.add_child(vbox)

	# Header: ‹ back chip + left-aligned title + track divider.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	header.add_child(_make_back_button())
	header.add_child(_make_header_title("Controls"))
	vbox.add_child(header)
	vbox.add_child(_rule(3, C_TRACK))

	# Scroll body sized so the whole panel is ~520 tall and long lists scroll.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 0)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	for entry in DISPLAYED_ACTIONS:
		var action: StringName = entry["action"]
		var mc := MarginContainer.new()
		mc.add_theme_constant_override("margin_left", 4)
		mc.add_theme_constant_override("margin_right", 4)
		mc.add_theme_constant_override("margin_top", 6)
		mc.add_theme_constant_override("margin_bottom", 6)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		hb.add_child(_make_keycap(_glyph_for(action)))
		var lbl := Label.new()
		lbl.text = String(entry["label"])
		lbl.add_theme_font_override("font", FONT_BODY)
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.add_theme_color_override("font_color", C_TEXT)
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(lbl)
		mc.add_child(hb)
		list.add_child(mc)
		# 2px row divider (#d6cdba), matching the HTML border-bottom.
		list.add_child(_rule(2, C_DIVIDER))

	return center

# A dark ink keycap chip with a centred Chakra glyph (#e7d9a8), min width 74.
func _make_keycap(txt: String) -> Control:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_INK
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 9.0
	sb.content_margin_right = 9.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(74, 26)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.size_flags_vertical = Control.SIZE_SHRINK_CENTER

	var l := Label.new()
	l.text = txt
	l.add_theme_font_override("font", FONT_TITLE)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", C_KEYCAP)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

# Short label for an action's active-device binding, via the InputDevice autoload.
# Falls back to the bare action name when that autoload isn't registered.
func _glyph_for(action: StringName) -> String:
	var dev = get_node_or_null("/root/InputDevice")
	if dev != null and dev.has_method("action_glyph"):
		return str(dev.action_glyph(action))
	return String(action)

# --- Panel switching -------------------------------------------------------

# True when any sub-panel (Settings or Controls) is currently up, so ui_cancel steps
# back to the main panel instead of closing the whole menu.
func _sub_panel_visible() -> bool:
	if _settings_panel and _settings_panel.visible:
		return true
	if _controls_panel and _controls_panel.visible:
		return true
	return false

func _show_main() -> void:
	if _settings_panel:
		_settings_panel.hide()
	if _controls_panel:
		_controls_panel.hide()
	if _main_panel:
		_main_panel.show()
		# Put controller focus on Resume whenever the main panel comes up.
		if _resume_button:
			_resume_button.grab_focus.call_deferred()

func _show_settings() -> void:
	if _main_panel:
		_main_panel.hide()
	if _controls_panel:
		_controls_panel.hide()
	if _settings_panel:
		_settings_panel.show()
		# Move focus into the settings panel so the controller isn't stranded on the
		# now-hidden "Settings" button (which would trap navigation).
		var target := _first_focusable(_settings_panel)
		if target:
			target.grab_focus.call_deferred()

func _show_controls() -> void:
	if _main_panel:
		_main_panel.hide()
	if _settings_panel:
		_settings_panel.hide()
	if _controls_panel:
		_controls_panel.show()
		# Land focus on the panel's Back button so a controller can always step out.
		var target := _first_focusable(_controls_panel)
		if target:
			target.grab_focus.call_deferred()

# Depth-first search for the first focusable Control under `node` (focus_mode != NONE).
func _first_focusable(node: Node) -> Control:
	for child in node.get_children():
		if child is Control and (child as Control).focus_mode != Control.FOCUS_NONE:
			return child
		var found := _first_focusable(child)
		if found != null:
			return found
	return null

# --- Setting handlers ------------------------------------------------------

func _get_master_volume() -> float:
	var bus := AudioServer.get_bus_index("Master")
	return db_to_linear(AudioServer.get_bus_volume_db(bus))

func _on_volume_changed(value: float) -> void:
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(value, 0.0001)))

# Build a labelled 0..1 slider that drives the named audio bus. The bus index is resolved
# once (with a Master fallback) and bound into the change handler.
func _add_bus_slider(parent: Node, label_text: String, bus_name: String) -> void:
	var bus_idx: int = _bus_or_master(bus_name)
	var value: float = db_to_linear(AudioServer.get_bus_volume_db(bus_idx))
	_add_slider_block(parent, label_text, 0.0, 1.0, 0.01, value, true, _on_bus_volume_changed.bind(bus_idx))

func _on_bus_volume_changed(value: float, bus_idx: int) -> void:
	AudioServer.set_bus_volume_db(bus_idx, linear_to_db(maxf(value, 0.0001)))

# Index of the named bus, or Master's index if that bus doesn't exist, so a missing bus
# never yields a -1 index (which would error on set_bus_volume_db).
func _bus_or_master(bus_name: String) -> int:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx == -1:
		idx = AudioServer.get_bus_index("Master")
	return idx

# --- Mouse sensitivity -----------------------------------------------------

# Read the live player's sensitivity so the slider seeds correctly; fall back to the
# player.gd default (0.25) when no player is in the tree (e.g. settings from the title).
func _get_mouse_sensitivity() -> float:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and "mouse_sensitivity" in player:
		return float(player.mouse_sensitivity)
	return 0.25

func _on_sensitivity_changed(value: float) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player != null and "mouse_sensitivity" in player:
		player.mouse_sensitivity = value

# --- Accessibility font scale ----------------------------------------------

# Current stored UI font scale (1.0 when unset or GameState is missing). Read via the
# flag API so this bucket never touches game_state.gd.
func _get_font_scale() -> float:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return 1.0
	var raw = gs.get_flag(FONT_SCALE_FLAG, 1.0)
	return float(raw)

# Persist the chosen scale and keep the three toggles behaving like a radio group
# (only the picked size stays pressed — clicking re-presses the active one harmlessly).
func _on_font_scale(scale: float) -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		gs.set_flag(FONT_SCALE_FLAG, scale)
	for fb in _font_buttons:
		if is_instance_valid(fb):
			var sel := is_equal_approx(float(fb.get_meta("scale", 1.0)), scale)
			fb.button_pressed = sel
			_style_font_button(fb, sel)

func _on_fullscreen_toggled(on: bool) -> void:
	DisplayServer.window_set_mode(
		DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED
	)

func _on_save() -> void:
	# Both save/load overlays process while paused and sit above this menu.
	SaveSlotMenu.open(SaveSlotMenu.Mode.SAVE)

func _on_load() -> void:
	SaveSlotMenu.open(SaveSlotMenu.Mode.LOAD)

func _on_main_menu() -> void:
	# Tear down the pause overlay FIRST (close() recaptures the mouse), THEN open the title.
	# Order matters: MainMenu.open() frees the mouse, so it must run last or close()'s
	# MOUSE_MODE_CAPTURED would strand the cursor hidden on the title screen.
	close()
	MainMenu.open()

func _on_quit() -> void:
	get_tree().quit()
