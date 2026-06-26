# dialogue_balloon.gd
# The visible conversation panel for Nathan Hoad's Dialogue Manager. Instanced by the
# "Dialogue" autoload for the lifetime of one conversation, then freed.
#
# Like the rest of this game's UI, the whole layout is built in CODE (mirrors the old
# dialogue panel / pause_menu) so there's no .tscn layout to keep in sync — the scene is
# just a bare CanvasLayer + this script.
#
# It reuses the addon's DialogueLabel for the actual text so we get its typewriter,
# inline [speed=…] / [wait=…] pacing, pause-on-punctuation and skip-to-end for free.
# On top of that this balloon adds:
#   - A portrait (texture, or a tinted initial fallback) + speaker name, matching the
#     old look.
#   - Numbered response buttons with 1–9 hotkeys (the addon's stock menu has neither).
#   - Typewriter SFX: a soft blip per character as the line types out (the new
#     "expanded capability" requested for the overhaul).
#
# Contract with the addon: it calls start(resource, cue, extra_game_states); we drive
# the conversation with resource.get_next_dialogue_line(next_id, states), which makes
# the addon emit dialogue_ended when we run off the end.

extends CanvasLayer

# --- Typewriter feel -------------------------------------------------------
## Base seconds per character (~55 cps, matching the old panel). Inline [speed=…] in the
## dialogue text scales this per-line.
const SECONDS_PER_STEP: float = 0.018
## Per-character blip. Reuses the UI click at low volume + jittered pitch so it reads as
## a typewriter tick rather than a click. Every other character plays, to avoid a rattle.
const BLIP_STREAM: AudioStream = preload("res://assets/audio/ui/click_a.ogg")
const BLIP_VOLUME_DB: float = -22.0

# --- Input actions ---------------------------------------------------------
const NEXT_ACTION: StringName = &"ui_accept"

# --- UI (built in code) ----------------------------------------------------
var _panel: PanelContainer
var _portrait_rect: TextureRect
var _portrait_initial: Label
var _name_label: Label
var _text_label: DialogueLabel
var _choices_box: VBoxContainer
var _hint_label: Label
var _blip_player: AudioStreamPlayer

# --- Conversation state ----------------------------------------------------
var _resource: DialogueResource
var _states: Array = []
var _line: DialogueLine = null
var _waiting_for_input: bool = false
var _blip_toggle: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 11
	_build_ui()
	_text_label.spoke.connect(_on_spoke)
	hide()


# --- Public entry (called by the addon / Dialogue autoload) -----------------

## Begin the conversation. `extra_game_states` carries the speaker etc. for expressions.
func start(resource: DialogueResource, cue: String = "", extra_game_states: Array = []) -> void:
	_resource = resource
	# `self` first so the balloon's own locals are reachable, then the caller's states.
	_states = [self] + extra_game_states
	_set_line(await _resource.get_next_dialogue_line(cue, _states))
	show()


# --- Line flow -------------------------------------------------------------

# Apply a freshly fetched line, or close the balloon when the conversation ends (null).
func _set_line(next_line: DialogueLine) -> void:
	_line = next_line
	if _line == null:
		# Conversation finished — the addon has already emitted dialogue_ended.
		queue_free()
		return
	await _apply_line()


func _apply_line() -> void:
	_waiting_for_input = false
	_clear_choices()

	_name_label.visible = not _line.character.is_empty()
	_name_label.text = _line.character
	_set_portrait(null, _line.character)

	# Type the line out (DialogueLabel handles speed/wait/skip + inline mutations).
	_set_hint("► Space / Click to skip")
	_text_label.dialogue_line = _line
	_text_label.type_out()
	await _text_label.finished_typing

	if _line.responses.size() > 0:
		_set_hint("")
		_show_choices()
	else:
		_waiting_for_input = true
		_set_hint("▼  Space / Click to continue")


func _advance(next_id: String) -> void:
	_set_line(await _resource.get_next_dialogue_line(next_id, _states))


# --- Choices ---------------------------------------------------------------

func _show_choices() -> void:
	var shown: int = 0
	var first_button: Button = null
	for response in _line.responses:
		if not response.is_allowed:
			continue
		shown += 1
		var button := Button.new()
		button.text = "%d.  %s" % [shown, response.text]
		button.focus_mode = Control.FOCUS_ALL
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_on_choice_selected.bind(response))
		_choices_box.add_child(button)
		if first_button == null:
			first_button = button
	if first_button != null:
		first_button.grab_focus.call_deferred()


func _on_choice_selected(response) -> void:
	_advance(response.next_id)


func _clear_choices() -> void:
	for child in _choices_box.get_children():
		child.queue_free()


# Update the little skip/continue affordance at the corner of the panel ("" hides it).
func _set_hint(text: String) -> void:
	if _hint_label == null:
		return
	_hint_label.text = text
	_hint_label.visible = text != ""


# --- Input -----------------------------------------------------------------

# Handled in _input (not _unhandled_input) so a click that lands ON the dialogue panel
# advances too — otherwise the PanelContainer swallows the click and nothing happens,
# which reads as "I can't skip the text". We only consume the events we actually act on,
# so the response buttons still receive their own clicks/keys normally.
func _input(event: InputEvent) -> void:
	if _line == null:
		return

	# Skip the typewriter to the end of the current line.
	if _text_label.is_typing:
		var clicked: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		if clicked or event.is_action_pressed(NEXT_ACTION):
			_text_label.skip_typing()
			get_viewport().set_input_as_handled()
		return

	# While choices are up, the focused button handles accept; 1–9 quick-select.
	if _choices_box.get_child_count() > 0:
		_handle_choice_hotkeys(event)
		return

	# Plain line: advance on accept / left click.
	if not _waiting_for_input:
		return
	var advance := event.is_action_pressed(NEXT_ACTION)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance = true
	if advance:
		get_viewport().set_input_as_handled()
		_advance(_line.next_id)


# 1..9 quick-select a visible choice button.
func _handle_choice_hotkeys(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := event as InputEventKey
	var n: int = key.keycode - KEY_1
	if n >= 0 and n < _choices_box.get_child_count():
		var btn := _choices_box.get_child(n) as Button
		if btn != null and not btn.disabled:
			btn.pressed.emit()
			get_viewport().set_input_as_handled()


# --- Typewriter SFX --------------------------------------------------------

func _on_spoke(letter: String, _index: int, _speed: float) -> void:
	# Don't tick on whitespace, and only every other character, for a softer cadence.
	if letter.strip_edges() == "":
		return
	_blip_toggle = not _blip_toggle
	if not _blip_toggle:
		return
	_blip_player.pitch_scale = randf_range(0.95, 1.15)
	_blip_player.play()


# --- UI construction (all in code) -----------------------------------------

func _build_ui() -> void:
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 40.0
	_panel.offset_right = -40.0
	# Taller than before so a long list of response options has room; anything past what
	# fits scrolls inside the choices ScrollContainer (built below).
	_panel.offset_top = -360.0
	_panel.offset_bottom = -24.0
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	anchor.add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_panel.add_child(margin)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	margin.add_child(hbox)

	# Portrait frame (texture, or a colored initial as a fallback).
	var portrait_frame := PanelContainer.new()
	portrait_frame.custom_minimum_size = Vector2(96, 96)
	portrait_frame.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hbox.add_child(portrait_frame)

	_portrait_rect = TextureRect.new()
	_portrait_rect.custom_minimum_size = Vector2(96, 96)
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait_frame.add_child(_portrait_rect)

	_portrait_initial = Label.new()
	_portrait_initial.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_portrait_initial.add_theme_font_size_override("font_size", 48)
	portrait_frame.add_child(_portrait_initial)

	# Text column: name, line, choices.
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	hbox.add_child(vbox)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	vbox.add_child(_name_label)

	_text_label = DialogueLabel.new()
	_text_label.fit_content = true
	_text_label.bbcode_enabled = true
	_text_label.scroll_active = false
	_text_label.seconds_per_step = SECONDS_PER_STEP
	_text_label.custom_minimum_size = Vector2(0, 64)
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(_text_label)

	# Choices live inside a ScrollContainer so a long option list (more than fits the panel)
	# stays fully reachable — it scrolls with the mouse wheel, and arrow-key / focus navigation
	# auto-scrolls the focused button into view. Fixes options running off the bottom of the
	# screen where they couldn't be seen or clicked.
	var choices_scroll := ScrollContainer.new()
	choices_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	choices_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	choices_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(choices_scroll)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 4)
	_choices_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices_scroll.add_child(_choices_box)

	# A small dim prompt so players know how to skip/advance (the missing affordance).
	_hint_label = Label.new()
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.add_theme_font_size_override("font_size", 13)
	_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.45))
	vbox.add_child(_hint_label)

	_blip_player = AudioStreamPlayer.new()
	_blip_player.stream = BLIP_STREAM
	_blip_player.volume_db = BLIP_VOLUME_DB
	_blip_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_blip_player)


# Show a portrait texture if given; otherwise draw the speaker's initial on a tinted
# square so every speaker still reads as "someone".
func _set_portrait(tex: Texture2D, speaker_name: String) -> void:
	if tex != null:
		_portrait_rect.texture = tex
		_portrait_rect.show()
		_portrait_initial.hide()
		return
	_portrait_rect.texture = null
	_portrait_rect.hide()
	_portrait_initial.show()
	_portrait_initial.text = speaker_name.substr(0, 1).to_upper() if speaker_name.length() > 0 else "?"
