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
# First button on the main panel ("Resume") — grabbed on open so a controller
# immediately has something selected.
var _resume_button: Button = null

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
		if _settings_panel and _settings_panel.visible:
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

func _build_ui() -> void:
	# Dim backdrop that also eats clicks behind the menu.
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_root = dim

	_main_panel = _make_center_column("Paused", [
		{"text": "Resume", "handler": Callable(self, "close")},
		{"text": "Save Game", "handler": Callable(self, "_on_save")},
		{"text": "Load Game", "handler": Callable(self, "_on_load")},
		{"text": "Settings", "handler": Callable(self, "_show_settings")},
		{"text": "Main Menu", "handler": Callable(self, "_on_main_menu")},
		{"text": "Quit", "handler": Callable(self, "_on_quit")},
	])
	_root.add_child(_main_panel)

	_settings_panel = _build_settings_panel()
	_root.add_child(_settings_panel)
	_settings_panel.hide()

# Builds a centered vertical column with a title and a list of buttons.
func _make_center_column(title: String, buttons: Array) -> Control:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(280, 0)
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

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

	# Fullscreen toggle.
	var fs := CheckButton.new()
	fs.text = "Fullscreen"
	fs.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fs.toggled.connect(_on_fullscreen_toggled)
	vbox.add_child(fs)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 48)
	back.pressed.connect(_show_main)
	vbox.add_child(back)

	return center

# --- Panel switching -------------------------------------------------------

func _show_main() -> void:
	if _settings_panel:
		_settings_panel.hide()
	if _main_panel:
		_main_panel.show()
		# Put controller focus on Resume whenever the main panel comes up.
		if _resume_button:
			_resume_button.grab_focus.call_deferred()

func _show_settings() -> void:
	if _main_panel:
		_main_panel.hide()
	if _settings_panel:
		_settings_panel.show()
		# Move focus into the settings panel so the controller isn't stranded on the
		# now-hidden "Settings" button (which would trap navigation).
		var target := _first_focusable(_settings_panel)
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
	# Pop the title over the paused game; entering the world from there unpauses.
	MainMenu.open()
	close()

func _on_quit() -> void:
	get_tree().quit()
