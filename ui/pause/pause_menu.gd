# pause_menu.gd
# Autoload singleton (registered as "PauseMenu"). A full-screen pause overlay
# opened with the "pause" action (Escape). Opening it FULLY pauses the game:
# get_tree().paused = true freezes every pausable node, and we also pause the Clock
# (which runs with PROCESS_MODE_ALWAYS, so it wouldn't stop on its own) so in-game
# time and brewing halt too.
#
# It's built entirely in code (no .tscn) so there's no layout to maintain. Three
# actions: Resume, Settings (a small sub-panel: master volume + fullscreen), Quit.
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

const Glass = preload("res://ui/glass_style.gd")

func _build_ui() -> void:
	# Full-screen frosted-glass backdrop (no black) that also eats clicks behind the menu.
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	Glass.frost(dim)
	add_child(dim)
	_root = dim

	_main_panel = _make_center_column("Paused", [
		{"text": "Resume", "handler": Callable(self, "close")},
		{"text": "Save Game", "handler": Callable(self, "_on_save")},
		{"text": "Load Game", "handler": Callable(self, "_on_load")},
		{"text": "Settings", "handler": Callable(self, "_show_settings")},
		{"text": "Controls", "handler": Callable(self, "_show_controls")},
		{"text": "Main Menu", "handler": Callable(self, "_on_main_menu")},
		{"text": "Quit", "handler": Callable(self, "_on_quit")},
	])
	_root.add_child(_main_panel)

	_settings_panel = _build_settings_panel()
	_root.add_child(_settings_panel)
	_settings_panel.hide()

	_controls_panel = _build_controls_panel()
	_root.add_child(_controls_panel)
	_controls_panel.hide()

# Builds a centered vertical column with a title and a list of buttons.
func _make_center_column(title: String, buttons: Array) -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	# Glass box behind the menu content (the border width doubles as inner padding).
	var panel := PanelContainer.new()
	Glass.apply(panel, 18, 24)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(280, 0)
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 40)
	vbox.add_child(title_label)

	for spec in buttons:
		var btn := Button.new()
		btn.text = spec["text"]
		btn.custom_minimum_size = Vector2(0, 48)
		btn.focus_mode = Control.FOCUS_ALL
		btn.pressed.connect(spec["handler"])
		vbox.add_child(btn)
		# First main-panel button is Resume; remember it to grab focus on open.
		if _resume_button == null:
			_resume_button = btn

	return center

func _build_settings_panel() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(320, 0)
	vbox.add_theme_constant_override("separation", 12)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	vbox.add_child(title)

	# Master volume slider.
	var vol_label := Label.new()
	vol_label.text = "Master Volume"
	vbox.add_child(vol_label)

	var vol := HSlider.new()
	vol.min_value = 0.0
	vol.max_value = 1.0
	vol.step = 0.01
	vol.value = _get_master_volume()
	vol.value_changed.connect(_on_volume_changed)
	vbox.add_child(vol)

	# Per-bus volume sliders. Each resolves its bus index via _bus_or_master so a missing
	# bus degrades gracefully (it just drives Master instead of erroring on index -1).
	_add_bus_slider(vbox, "Music Volume", "Music")
	_add_bus_slider(vbox, "SFX Volume", "SFX")
	_add_bus_slider(vbox, "Ambient Volume", "Ambient")

	# Mouse sensitivity (core FPS accessibility control). Seeded from the live player so the
	# slider reflects the current value whenever Settings is opened.
	var sens_label := Label.new()
	sens_label.text = "Mouse Sensitivity"
	vbox.add_child(sens_label)

	var sens := HSlider.new()
	sens.min_value = 0.1
	sens.max_value = 1.0
	sens.step = 0.05
	sens.value = _get_mouse_sensitivity()
	sens.value_changed.connect(_on_sensitivity_changed)
	vbox.add_child(sens)

	# Fullscreen toggle.
	var fs := CheckButton.new()
	fs.text = "Fullscreen"
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs.toggled.connect(_on_fullscreen_toggled)
	vbox.add_child(fs)

	# Accessibility: UI text size. A radio-style row (Small / Normal / Large) persisted
	# through the GameState flag API; player_menu & crafting_ui read it to rescale their
	# font overrides on next open. Pure UI scale — no gameplay is affected.
	var font_label := Label.new()
	font_label.text = "UI Text Size"
	vbox.add_child(font_label)

	var current_scale: float = _get_font_scale()
	var font_row := HBoxContainer.new()
	font_row.add_theme_constant_override("separation", 6)
	_font_buttons.clear()
	for opt in FONT_SCALE_OPTIONS:
		var opt_scale: float = float(opt["scale"])
		var fb := Button.new()
		fb.text = String(opt["label"])
		fb.toggle_mode = true
		fb.custom_minimum_size = Vector2(0, 40)
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fb.button_pressed = is_equal_approx(current_scale, opt_scale)
		fb.set_meta("scale", opt_scale)
		fb.pressed.connect(_on_font_scale.bind(opt_scale))
		font_row.add_child(fb)
		_font_buttons.append(fb)
	vbox.add_child(font_row)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(_show_main)
	vbox.add_child(back)

	return center

# Read-only key-binding reference: a scrollable 2-column [glyph] Action list built from
# DISPLAYED_ACTIONS. Glyphs come from the InputDevice autoload (active-device aware) and
# degrade to the raw action name if that autoload is absent, so this never blanks out.
func _build_controls_panel() -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	Glass.apply(panel, 16, 22)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(360, 0)
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "Controls"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	vbox.add_child(title)

	# Cap the height so a long action list scrolls rather than overflowing the screen.
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 6)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)

	for entry in DISPLAYED_ACTIONS:
		var action: StringName = entry["action"]
		var glyph := Label.new()
		glyph.text = "[%s]" % _glyph_for(action)
		glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glyph.custom_minimum_size = Vector2(96, 0)
		glyph.modulate = Color(0.95, 0.9, 0.6)
		grid.add_child(glyph)
		var lbl := Label.new()
		lbl.text = String(entry["label"])
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(lbl)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(_show_main)
	vbox.add_child(back)

	return center

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
	var label := Label.new()
	label.text = label_text
	parent.add_child(label)

	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = db_to_linear(AudioServer.get_bus_volume_db(bus_idx))
	slider.value_changed.connect(_on_bus_volume_changed.bind(bus_idx))
	parent.add_child(slider)

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
			fb.button_pressed = is_equal_approx(float(fb.get_meta("scale", 1.0)), scale)

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
