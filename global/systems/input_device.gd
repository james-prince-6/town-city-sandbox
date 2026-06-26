# input_device.gd
# Autoload singleton (registered as "InputDevice").
#
# Tracks which kind of input the player is CURRENTLY using — keyboard/mouse or a
# gamepad — and exposes that so UI can render device-appropriate button glyphs
# (e.g. "[E] Talk" on keyboard, "[X] Talk" on a controller).
#
# Design notes:
# - We sniff every InputEvent in _input(). A key or mouse event flips us to
#   KEYBOARD; a joypad button press or a stick/trigger push past a deadzone flips
#   us to GAMEPAD. We only emit device_changed when the value actually changes, so
#   listeners (like the interaction prompt) can cheaply re-render on swap.
# - action_glyph() reads the live InputMap so it stays correct even if bindings
#   are remapped at runtime. It returns the FIRST event matching the active device
#   and, if the active device has no binding for that action, falls back to the
#   OTHER device's glyph so a prompt is never blank.
# - This is a plain Node autoload (no scene needed): it only listens to input and
#   holds a little state.

extends Node

## The two input families we distinguish between. Mouse counts as KEYBOARD.
enum Device { KEYBOARD, GAMEPAD }

## Emitted whenever the active input device changes. UI connects to this instead
## of polling so it can re-render glyphs the instant the player swaps.
signal device_changed(device: int)

## The input family the player is using right now. Starts on KEYBOARD because the
## game launches mouse-captured for desktop.
var current_device: int = Device.KEYBOARD

## How far a stick/trigger must move before we treat it as an intentional gamepad
## input (and switch device). Matches the engine's usual stick deadzone.
const JOY_MOTION_THRESHOLD: float = 0.5

# Readable (Xbox-style) names for joypad buttons. Indices follow Godot 4's JoyButton
# enum, which normalises every controller to the SDL game-controller layout — so
# shoulders are 9/10 and the stick-clicks are 7/8 (NOT the raw XInput numbering).
# Used by action_glyph() to label gamepad bindings; must stay in lock-step with the
# button indices the input-map bindings actually use.
const JOY_BUTTON_NAMES: Dictionary = {
	0: "A",          # JOY_BUTTON_A
	1: "B",          # JOY_BUTTON_B
	2: "X",          # JOY_BUTTON_X
	3: "Y",          # JOY_BUTTON_Y
	4: "View",       # JOY_BUTTON_BACK
	5: "Guide",      # JOY_BUTTON_GUIDE
	6: "Menu",       # JOY_BUTTON_START
	7: "L3",         # JOY_BUTTON_LEFT_STICK
	8: "R3",         # JOY_BUTTON_RIGHT_STICK
	9: "LB",         # JOY_BUTTON_LEFT_SHOULDER
	10: "RB",        # JOY_BUTTON_RIGHT_SHOULDER
	11: "D-Up",      # JOY_BUTTON_DPAD_UP
	12: "D-Down",    # JOY_BUTTON_DPAD_DOWN
	13: "D-Left",    # JOY_BUTTON_DPAD_LEFT
	14: "D-Right",   # JOY_BUTTON_DPAD_RIGHT
}

# Readable names for joypad axes. 0/1 = left stick, 2/3 = right stick, 4/5 = triggers.
const JOY_AXIS_NAMES: Dictionary = {
	0: "L-Stick",
	1: "L-Stick",
	2: "R-Stick",
	3: "R-Stick",
	4: "LT",
	5: "RT",
}


func _ready() -> void:
	# Keep listening even while the tree is paused (menus pause the game but still
	# show prompts/navigation that want correct glyphs).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# CRITICAL for controller menus: Godot's built-in ui_up/down/left/right ship with
	# gamepad bindings (d-pad / left stick), but ui_accept and ui_cancel do NOT — so a
	# pad could move focus but never press (A) or back out (B). Add those here so every
	# menu's buttons activate with A and close with B, with zero per-menu work. Also map
	# the shoulders to focus-next/prev for completeness.
	_add_pad_button(&"ui_accept", JOY_BUTTON_A)            # A activates the focused control
	_add_pad_button(&"ui_cancel", JOY_BUTTON_B)            # B cancels / closes
	# (Menu navigation uses the d-pad / left stick via ui_up/down/left/right, which already
	#  ship with gamepad bindings. We deliberately DON'T bind the shoulders to focus-nav so
	#  they stay free for the Player Menu's tab cycling.)

# Append a joypad-button event to a UI action if it isn't already bound there. Safe to
# run every launch (deduped); never removes the existing keyboard bindings.
func _add_pad_button(action: StringName, button: int) -> void:
	if not InputMap.has_action(action):
		return
	for ev in InputMap.action_get_events(action):
		if ev is InputEventJoypadButton and ev.button_index == button:
			return
	var e := InputEventJoypadButton.new()
	e.button_index = button
	InputMap.action_add_event(action, e)


# Sniff raw input to keep current_device in sync with whatever the player touched
# last. We never consume the event here — gameplay still handles it normally.
func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		_set_device(Device.KEYBOARD)
	elif event is InputEventJoypadButton:
		if (event as InputEventJoypadButton).pressed:
			_set_device(Device.GAMEPAD)
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) >= JOY_MOTION_THRESHOLD:
			_set_device(Device.GAMEPAD)


func _set_device(device: int) -> void:
	if device == current_device:
		return
	current_device = device
	device_changed.emit(current_device)


## Returns a short, human-readable label for the FIRST binding of `action_name`
## that matches the active device — e.g. "E" / "LMB" on keyboard, "X" / "RT" on a
## gamepad. If the active device has no binding, falls back to the other device's
## label so callers always get something to show. Returns "?" if the action has no
## events at all (or the action does not exist).
func action_glyph(action_name: StringName) -> String:
	if not InputMap.has_action(action_name):
		return "?"
	var events: Array = InputMap.action_get_events(action_name)
	if events.is_empty():
		return "?"

	var preferred_gamepad: bool = current_device == Device.GAMEPAD
	var primary: String = ""
	var fallback: String = ""

	for event in events:
		var is_pad: bool = _event_is_gamepad(event)
		var glyph: String = _glyph_for_event(event)
		if glyph == "":
			continue
		if is_pad == preferred_gamepad:
			if primary == "":
				primary = glyph
		elif fallback == "":
			fallback = glyph

	if primary != "":
		return primary
	if fallback != "":
		return fallback
	return "?"


## Convenience: a bracketed prompt line like "[E] Talk" / "[X] Talk", using the
## active device's glyph for `action_name`.
func prompt_text(action_name: StringName, label: String) -> String:
	return "[%s] %s" % [action_glyph(action_name), label]


func _event_is_gamepad(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


# Maps a single InputEvent to a short label. Returns "" when we can't name it, so
# action_glyph() can skip it and try the next binding.
func _glyph_for_event(event: InputEvent) -> String:
	if event is InputEventKey:
		var key_event: InputEventKey = event
		var code: int = key_event.physical_keycode
		if code == 0:
			code = key_event.keycode
		var label: String = OS.get_keycode_string(code)
		return label if label != "" else "Key"
	if event is InputEventMouseButton:
		return _mouse_button_name((event as InputEventMouseButton).button_index)
	if event is InputEventJoypadButton:
		var btn: int = (event as InputEventJoypadButton).button_index
		var name_btn = JOY_BUTTON_NAMES.get(btn, "")
		return str(name_btn) if name_btn != "" else "Btn%d" % btn
	if event is InputEventJoypadMotion:
		var axis: int = (event as InputEventJoypadMotion).axis
		var name_axis = JOY_AXIS_NAMES.get(axis, "")
		return str(name_axis) if name_axis != "" else "Axis%d" % axis
	return ""


func _mouse_button_name(button_index: int) -> String:
	match button_index:
		1:
			return "LMB"
		2:
			return "RMB"
		3:
			return "MMB"
		4:
			return "MWheelUp"
		5:
			return "MWheelDown"
		_:
			return "Mouse%d" % button_index
