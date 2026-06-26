# save_slot_menu.gd
# Autoload singleton (register as "SaveSlotMenu"). A full-screen overlay that lists the
# save slots and lets the player either WRITE to one (SAVE mode) or READ from one
# (LOAD mode). Opened from the main menu's "Load Game" button and (via a future hook)
# from the pause menu.
#
# Built entirely in code (no .tscn), mirroring pause_menu.gd / death_screen.gd. It is a
# CanvasLayer that processes ALWAYS so it works even while the tree is paused (the pause
# menu pauses the game before opening this for an in-game Save/Load).
#
# SaveManager is slot-based with an open-ended number of slots (slot_path() just formats
# the number; quicksave/quickload use slot 0). There is no hard maximum, so we expose a
# fixed handful — SLOT_COUNT — as the UI's browsable set.
#
# Modes:
#   open(Mode.SAVE) -> each row calls SaveManager.save_game(slot); rows refresh in place.
#   open(Mode.LOAD) -> each row calls SaveManager.load_game(slot), but ONLY for slots
#                      that actually have a save (empty rows are disabled).
#
# Controller etiquette: focus grabs the first slot row on open; ui_cancel (Esc / B)
# closes the overlay. UISound auto-hooks the buttons, so no manual click sounds.
#
# NOTE: intentionally NO class_name. The autoload is registered as "SaveSlotMenu";
# a matching class_name would collide with that global singleton name.

extends CanvasLayer

const Glass = preload("res://ui/glass_style.gd")

## The two things this screen can do with a slot.
enum Mode { SAVE, LOAD }

## How many slots to show. SaveManager itself is open-ended; this is just the UI's set.
const SLOT_COUNT: int = 3

## True while the overlay is visible. Mirrors the flag the other menus expose so
## MenuManager can tell we're open.
var is_open: bool = false

# Whichever Mode we were last opened in. Untyped-safe: it's always a Mode int.
var _mode: int = Mode.LOAD

var _root: Control
var _title_label: Label
# The column the slot rows are rebuilt into each time we open (so has_save / timestamps
# are always current).
var _list_vbox: VBoxContainer
# First slot button — grabbed on open for controller users.
var _first_row: Button = null

func _ready() -> void:
	# Above the main menu (30) so the slot browser overlays the title, and above the
	# pause menu (20) for the in-game Save/Load case. Always-process so it survives a
	# paused tree.
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Opt into the exclusive-menu group so opening a DIFFERENT full-screen menu closes
	# this one (and vice-versa) instead of stacking. The main menu is deliberately NOT
	# in this group, so it stays visible behind us as our parent.
	add_to_group("exclusive_menu")
	_build_shell()
	hide()

func _unhandled_input(event: InputEvent) -> void:
	# Esc / B closes the overlay and hands focus back to whoever opened it.
	if is_open and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

# --- Public API ------------------------------------------------------------

## Show the slot browser in the given Mode (Mode.SAVE or Mode.LOAD).
func open(mode: int) -> void:
	_mode = mode
	is_open = true
	# Close any OTHER exclusive menu so we never stack over a gameplay menu.
	if get_node_or_null("/root/MenuManager") != null:
		MenuManager.opening(self)
	_title_label.text = "Save Game" if _mode == Mode.SAVE else "Load Game"
	_rebuild_rows()
	show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if _first_row != null:
		_first_row.grab_focus.call_deferred()

## Hide the overlay. If the main menu is still up underneath (the Load Game path),
## return controller focus to it so navigation isn't stranded.
func close() -> void:
	if not is_open:
		return
	is_open = false
	hide()
	# Untyped var so .visible resolves dynamically (Node has no .visible statically).
	var main_menu = get_node_or_null("/root/MainMenu")
	if main_menu != null and main_menu.visible and main_menu.has_method("focus_first"):
		main_menu.focus_first()

# --- Row actions -----------------------------------------------------------

func _on_slot_pressed(slot: int) -> void:
	if _mode == Mode.SAVE:
		# Write this slot, then refresh the rows so the just-saved slot shows its new
		# "saved" state and timestamp. Stay open so the player can confirm / pick another.
		SaveManager.save_game(slot)
		_rebuild_rows()
		if _first_row != null:
			_first_row.grab_focus.call_deferred()
	else:
		# LOAD: only act if there's actually something in the slot (empty rows are
		# disabled anyway, but guard regardless).
		if not SaveManager.has_save(slot):
			return
		# Loading restores systems AND swaps to the saved scene via SceneManager. Tear
		# down the menu stack, unpause, and recapture the mouse for gameplay.
		close()
		var main_menu = get_node_or_null("/root/MainMenu")
		if main_menu != null and main_menu.has_method("close"):
			main_menu.close()
		get_tree().paused = false
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		SaveManager.load_game(slot)

# --- UI construction (all in code) -----------------------------------------

# Builds the persistent shell (backdrop, title, empty row column). The rows themselves
# are (re)built per-open in _rebuild_rows() so save state stays current.
func _build_shell() -> void:
	var dim := ColorRect.new()
	# Full-screen frosted-glass backdrop (no black) that also eats clicks behind the menu.
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	Glass.frost(dim)
	add_child(dim)
	_root = dim

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	# Glass box behind the menu content (the border width doubles as inner padding).
	var panel := PanelContainer.new()
	Glass.apply(panel, 18, 22)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "Load Game"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 44)
	vbox.add_child(_title_label)

	_list_vbox = VBoxContainer.new()
	_list_vbox.add_theme_constant_override("separation", 10)
	vbox.add_child(_list_vbox)

	# A back/cancel button so mouse users have an obvious way out (controller uses B).
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(0, 44)
	back.focus_mode = Control.FOCUS_ALL
	back.pressed.connect(close)
	vbox.add_child(back)

# Clears and rebuilds one Button per slot, labelled with its current save state. In LOAD
# mode, empty slots are disabled.
func _rebuild_rows() -> void:
	_first_row = null
	for child in _list_vbox.get_children():
		child.queue_free()

	for slot in range(SLOT_COUNT):
		var has_save: bool = SaveManager.has_save(slot)
		var btn := Button.new()
		btn.text = _slot_label(slot, has_save)
		btn.custom_minimum_size = Vector2(0, 52)
		btn.focus_mode = Control.FOCUS_ALL
		# In LOAD mode an empty slot has nothing to load, so disable it.
		btn.disabled = (_mode == Mode.LOAD and not has_save)
		btn.pressed.connect(_on_slot_pressed.bind(slot))
		_list_vbox.add_child(btn)
		# Remember the first ENABLED row so controller focus lands somewhere usable.
		if _first_row == null and not btn.disabled:
			_first_row = btn

	# If every row was disabled (LOAD mode, no saves at all), fall back to focusing the
	# first row anyway so the overlay isn't focus-dead (player backs out with B/Back).
	if _first_row == null and _list_vbox.get_child_count() > 0:
		var first = _list_vbox.get_child(0)
		if first is Button:
			_first_row = first as Button

# Human-readable label for a slot row, e.g. "Slot 1  -  Empty" or
# "Slot 1  -  Saved (2026-06-25 14:03)".
func _slot_label(slot: int, has_save: bool) -> String:
	# Show 1-based numbers to players even though SaveManager is 0-indexed.
	var human_number: int = slot + 1
	if not has_save:
		return "Slot %d  -  Empty" % human_number
	# Cheap timestamp marker from the file's modified time (local time).
	var path: String = SaveManager.slot_path(slot)
	var mtime: int = FileAccess.get_modified_time(path)
	if mtime <= 0:
		return "Slot %d  -  Saved" % human_number
	var when: String = Time.get_datetime_string_from_unix_time(mtime, true).replace("T", " ")
	return "Slot %d  -  Saved (%s)" % [human_number, when]
