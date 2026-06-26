# interaction_prompt.gd
# Autoload "InteractionUI" (a CanvasLayer). The corner pop-up that tells the
# player what they can do right now — e.g. "[E] Talk" on keyboard, "[X] Talk" on
# a gamepad.
#
# Two ways to drive it:
#   - show_prompt(text) / hide_prompt()  — the simple single-action path the player
#     uses every frame for whatever its interaction raycast is pointing at. The
#     glyph (the "[E]") is resolved live from the active input device, so it is no
#     longer hard-coded.
#   - set_actions(actions)               — an optional multi-action path: pass an
#     Array of { "action": StringName, "text": String } and it renders one line
#     per action (e.g. "[E] Talk" / "[F] Loot"). Empty array hides the panel.
#
# Device awareness: we listen to InputDevice.device_changed and re-render the last
# shown content, so swapping keyboard<->controller updates the glyphs instantly.
# Everything is null-safe: if the InputDevice autoload is somehow missing we fall
# back to sensible keyboard labels so a prompt is never blank.

extends CanvasLayer

const Glass = preload("res://ui/glass_style.gd")

# The VBox that holds one Label per visible action line. Built in the .tscn.
@onready var panel_container: PanelContainer = $PanelContainer
@onready var lines_box: VBoxContainer = $PanelContainer/Margin/Lines

# The action lines currently being shown. Each entry is a Dictionary:
#   { "action": StringName, "text": String }
# Kept so we can re-render (same content, fresh glyphs) when the device changes.
var _current_lines: Array = []

# Cached reference to the InputDevice autoload (may be null if not registered).
var _input_device: Node = null


func _ready() -> void:
	# Resolve the device tracker by path so a missing autoload degrades gracefully
	# instead of throwing a parse/lookup error.
	_input_device = get_node_or_null("/root/InputDevice")
	if _input_device != null and _input_device.has_signal("device_changed"):
		_input_device.device_changed.connect(_on_device_changed)
	# Frosted-glass backing instead of a flat dark panel.
	Glass.apply(panel_container, 12, 14)
	# Hidden until something asks to be shown.
	hide_prompt()


## Shows a single interaction line for the "interact" action — the API the player
## relies on. `text` is the action label only (e.g. "Talk"); the glyph is added
## for you based on the active input device.
func show_prompt(text: String) -> void:
	set_actions([{ "action": &"interact", "text": text }])


## Hides the prompt entirely.
func hide_prompt() -> void:
	_current_lines = []
	if panel_container != null:
		panel_container.hide()


## Optional multi-action API. `actions` is an Array of Dictionaries, each
## { "action": StringName, "text": String }. Renders one line per action like
## "[E] Talk" / "[X] Open". An empty array hides the panel.
func set_actions(actions: Array) -> void:
	_current_lines = actions
	_render()


# Rebuilds the visible labels from _current_lines using the active device's glyphs.
func _render() -> void:
	if lines_box == null or panel_container == null:
		return

	if _current_lines.is_empty():
		panel_container.hide()
		return

	# Reuse existing Labels where we can, add/remove to match the line count. This
	# avoids churning nodes every frame when the player holds on one interactable.
	var needed: int = _current_lines.size()
	while lines_box.get_child_count() < needed:
		lines_box.add_child(_make_line_label())
	while lines_box.get_child_count() > needed:
		var extra: Node = lines_box.get_child(lines_box.get_child_count() - 1)
		lines_box.remove_child(extra)
		extra.queue_free()

	for i in range(needed):
		var entry = _current_lines[i]
		var action_name: StringName = entry.get("action", &"")
		var label_text: String = String(entry.get("text", ""))
		var line_label: Label = lines_box.get_child(i) as Label
		if line_label != null:
			line_label.text = "[%s] %s" % [_glyph_for(action_name), label_text]

	panel_container.show()


func _make_line_label() -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label


# Resolves the short button glyph for an action via InputDevice, with a safe
# keyboard fallback if the autoload is missing.
func _glyph_for(action_name: StringName) -> String:
	if _input_device != null and _input_device.has_method("action_glyph"):
		return _input_device.action_glyph(action_name)
	# Fallback when the device tracker is unavailable: name the most common action,
	# otherwise show "?".
	if action_name == &"interact":
		return "E"
	return "?"


# Re-render with the same content so glyphs update when the player swaps device.
func _on_device_changed(_device: int) -> void:
	if not _current_lines.is_empty():
		_render()
