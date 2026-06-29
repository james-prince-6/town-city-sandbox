# dialogue_balloon.gd
# The visible conversation panel for Nathan Hoad's Dialogue Manager. Instanced by the
# "Dialogue" autoload for the lifetime of one conversation, then freed.
#
# Like the rest of this game's UI, the whole layout is built in CODE (no .tscn layout to
# keep in sync — the scene is just a bare CanvasLayer + this script). This is the
# high-fidelity "Town City" dialog: a bottom cream box, a bobbing speaker portrait that
# sits above it, a dark name plate, a footer "advance" affordance, and a rigid, numbered
# reply list with caret + selection highlight. All StyleBoxes/colors are built INLINE.
#
# It still reuses the addon's DialogueLabel for the actual text so we get its typewriter,
# inline [speed=…] / [wait=…] pacing, pause-on-punctuation and skip-to-end for free, plus
# a soft per-character typewriter blip.
#
# Contract with the addon: it calls start(resource, cue, extra_game_states); we drive the
# conversation ONLY through resource.get_next_dialogue_line(next_id, states), which makes
# the addon emit got_dialogue per line and dialogue_ended when we run off the end. The
# wrapper (dialogue.gd) reaches our `_name_label` to tint it per reputation tier — that
# field name is load-bearing, do not rename it.

extends CanvasLayer

# --- Typewriter feel -------------------------------------------------------
## Base seconds per character (~55 cps). Inline [speed=…] scales this per-line.
const SECONDS_PER_STEP: float = 0.018
## Per-character blip — UI click at low volume + jittered pitch, every other character.
const BLIP_STREAM: AudioStream = preload("res://assets/audio/ui/click_a.ogg")
const BLIP_VOLUME_DB: float = -22.0

# --- Input -----------------------------------------------------------------
const NEXT_ACTION: StringName = &"ui_accept"

# --- Fonts -----------------------------------------------------------------
const CHAKRA_FONT: Font = preload("res://ui/fonts/ChakraPetch-SemiBold.ttf")
const SPACE_FONT: Font = preload("res://ui/fonts/SpaceGrotesk-Bold.ttf")
## OpenType 'wght' axis tag as a 32-bit int (Space Grotesk ships as a variable font).
const WGHT_TAG: int = 2003265652

## The static bottom legend (the new global hint).
const LEGEND: String = "Space / E  —  continue   ·   1–4  —  pick reply   ·   Esc  —  end conversation"

# --- Palette (locked design tokens, built inline) --------------------------
var C_INK := Color8(14, 13, 18)            # #0e0d12
var C_TEXT := Color8(34, 31, 26)           # #221f1a
var C_DIM := Color8(106, 101, 92)          # #6a655c
var C_CREAM := Color8(231, 225, 212)       # #e7e1d4
var C_DARKCHIP := Color8(58, 50, 38)       # #3a3226
var C_TRACK := Color8(202, 191, 172)       # #cabfac
var C_GOLD := Color8(200, 148, 30)         # #c8941e
var C_GREEN := Color8(91, 163, 106)        # #5ba36a
var C_BLUE := Color8(79, 158, 214)         # #4f9ed6
var C_NAMEROLE := Color8(205, 185, 138)    # #cdb98a
var C_CHOICE_MUTED := Color8(74, 70, 63)   # #4a463f
var C_PORTRAIT_LETTER := Color8(231, 217, 168)  # #e7d9a8
var C_BOTTOM_HINT := Color8(205, 199, 186) # #cdc7ba
var C_TAG_INK := Color8(26, 20, 7)         # #1a1407
var C_BOX_BG := Color8(231, 225, 212, 242) # cream @0.95
var C_SEL_BG := Color8(200, 148, 30, 36)   # gold @0.14
var C_CLEAR := Color(0, 0, 0, 0)

# Space Grotesk pinned to a given weight (the raw variable TTF imports light/thin).
var _space500: FontVariation
var _space600: FontVariation
var _space700: FontVariation

# --- UI (built in code) ----------------------------------------------------
var _panel: PanelContainer
var _portrait_holder: Control
var _portrait_frame: PanelContainer
var _portrait_rect: TextureRect
var _portrait_initial: Label
var _nameplate: PanelContainer
var _name_label: Label
var _role_label: Label
var _text_label: DialogueLabel
var _speech_footer: HBoxContainer
var _progress_label: Label
var _advance_label: Label
var _advance_key_label: Label
var _choices_view: VBoxContainer
var _choices_box: VBoxContainer
var _hint_label: Label
var _blip_player: AudioStreamPlayer

# --- Conversation state ----------------------------------------------------
var _resource: DialogueResource
var _states: Array = []
var _line: DialogueLine = null
var _waiting_for_input: bool = false
var _blip_toggle: bool = false
var _choice_index: int = 0
var _ending: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 11
	_build_ui()
	_text_label.spoke.connect(_on_spoke)
	_start_bob()
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
	_choice_index = 0

	# Name plate: hidden entirely when the line has no speaker (signs / narration).
	var has_name: bool = not _line.character.is_empty()
	_nameplate.visible = has_name
	_name_label.text = _line.character
	# Reset any prior reputation tint so it doesn't bleed across speakers; dialogue.gd
	# re-tints via got_dialogue for NPCs that have an npc_id.
	_name_label.add_theme_color_override("font_color", C_CREAM)
	_set_portrait(null, _line.character)

	# Speech layout while the line types out (footer/choices hidden until it settles).
	_enter_speech_state()
	_text_label.dialogue_line = _line
	_text_label.type_out()
	await _text_label.finished_typing

	if _line.responses.size() > 0:
		_enter_choice_state()
		_show_choices()
	else:
		_waiting_for_input = true
		_update_advance_affordance()
		_speech_footer.visible = true


func _advance(next_id: String) -> void:
	_set_line(await _resource.get_next_dialogue_line(next_id, _states))


# Speech vs. choice are two layout states of the same box; the line text stays visible in
# both (it's the speaker's words / the prompt above the replies).
func _enter_speech_state() -> void:
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_choices_view.visible = false
	_speech_footer.visible = false


func _enter_choice_state() -> void:
	_text_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_speech_footer.visible = false
	_choices_view.visible = true


# Footer label: "Continue" mid-node, "End" on a terminal line. (We never reach the "Reply"
# case at runtime because a line that carries responses shows the choice list immediately.)
func _update_advance_affordance() -> void:
	var nid: String = _line.next_id
	var at_end: bool = nid == "" or nid == "end" or nid == "end!"
	_advance_label.text = "End" if at_end else "Continue"
	_advance_key_label.text = "␣"
	# No reliable per-node line index/total from the addon, so progress is omitted.
	_progress_label.text = ""


# --- Choices ---------------------------------------------------------------

func _show_choices() -> void:
	var shown: int = 0
	for response in _line.responses:
		if not response.is_allowed:
			continue
		var idx: int = shown
		shown += 1
		var row: Button = _make_choice_row(shown, response)
		row.mouse_entered.connect(_select_choice.bind(idx))
		row.pressed.connect(_on_choice_selected.bind(response))
		_choices_box.add_child(row)
	if _choices_box.get_child_count() > 0:
		_choice_index = 0
		_select_choice(0)
		(_choices_box.get_child(0) as Button).grab_focus.call_deferred()


func _on_choice_selected(response) -> void:
	_advance(response.next_id)


func _clear_choices() -> void:
	for child in _choices_box.get_children():
		child.queue_free()


# Move the highlighted reply and restyle every row to match.
func _select_choice(idx: int) -> void:
	var count: int = _choices_box.get_child_count()
	if count == 0:
		return
	_choice_index = clampi(idx, 0, count - 1)
	for i in range(count):
		var btn := _choices_box.get_child(i) as Button
		if btn != null:
			_restyle_row(btn, i == _choice_index)
	var sel := _choices_box.get_child(_choice_index) as Button
	if sel != null and not sel.has_focus():
		sel.grab_focus()


# Repurposed: now sets the STATIC bottom legend ("" hides it).
func _set_hint(text: String) -> void:
	if _hint_label == null:
		return
	_hint_label.text = text
	_hint_label.visible = text != ""


# --- Input -----------------------------------------------------------------

# Handled in _input (not _unhandled_input) so a click that lands ON the dialogue box
# advances too. We only consume events we actually act on, so the reply buttons still
# receive their own clicks/keys normally.
func _input(event: InputEvent) -> void:
	if _line == null:
		return

	# Esc ends the whole conversation from any state.
	if event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		_end_conversation()
		return

	# 1) Typing -> skip to the end of the current line.
	if _text_label.is_typing:
		var clicked: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
		if clicked or event.is_action_pressed(NEXT_ACTION):
			_text_label.skip_typing()
			get_viewport().set_input_as_handled()
		return

	# 2) Choices shown -> cursor move / confirm / number quick-select.
	if _choices_box.get_child_count() > 0:
		_handle_choices_input(event)
		return

	# 3) Plain line + waiting -> advance on accept / left click.
	if not _waiting_for_input:
		return
	var advance: bool = event.is_action_pressed(NEXT_ACTION)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		advance = true
	if advance:
		get_viewport().set_input_as_handled()
		_advance(_line.next_id)


func _handle_choices_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_up"):
		_select_choice(_choice_index - 1)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"ui_down"):
		_select_choice(_choice_index + 1)
		get_viewport().set_input_as_handled()
		return
	# Accept confirms the highlighted reply.
	if event.is_action_pressed(NEXT_ACTION):
		var btn := _choices_box.get_child(_choice_index) as Button
		if btn != null and not btn.disabled:
			btn.pressed.emit()
			get_viewport().set_input_as_handled()
		return
	# 1..9 quick-select. Mouse clicks fall through here untouched so the buttons get them.
	_handle_choice_hotkeys(event)


# 1..9 quick-select a visible reply button.
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


# End the conversation cleanly. The Dialogue autoload owns is_active + camera teardown, so
# defer to it; fall back to freeing ourselves if it's somehow absent.
func _end_conversation() -> void:
	if _ending:
		return
	_ending = true
	var d := get_node_or_null(^"/root/Dialogue")
	if d != null and d.has_method("end_dialogue"):
		d.end_dialogue()
	else:
		queue_free()


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
	_space500 = _space(500.0)
	_space600 = _space(600.0)
	_space700 = _space(700.0)

	# Full-screen positioning layer; ignores the mouse so only the real surfaces catch it.
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_FULL_RECT)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(anchor)

	_build_box(anchor)
	_build_portrait(anchor)
	_build_nameplate(anchor)
	_build_bottom_hint(anchor)

	_blip_player = AudioStreamPlayer.new()
	_blip_player.stream = BLIP_STREAM
	_blip_player.volume_db = BLIP_VOLUME_DB
	_blip_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_blip_player)


# The cream dialog box: anchored bottom, inset 46 left/right, 30 from the bottom, fixed
# 190 tall. Padding 20 (top/bottom) x 24 (left/right). Vertical flex inside.
func _build_box(anchor: Control) -> void:
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_panel.offset_left = 46.0
	_panel.offset_right = -46.0
	_panel.offset_bottom = -30.0
	_panel.offset_top = -(30.0 + 190.0)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH

	var box_sb := StyleBoxFlat.new()
	box_sb.bg_color = C_BOX_BG
	box_sb.set_border_width_all(3)
	box_sb.border_color = C_INK
	box_sb.set_corner_radius_all(8)
	box_sb.content_margin_left = 24.0
	box_sb.content_margin_right = 24.0
	box_sb.content_margin_top = 20.0
	box_sb.content_margin_bottom = 20.0
	_panel.add_theme_stylebox_override("panel", box_sb)
	anchor.add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	_panel.add_child(vbox)

	# --- Line text (visible in both speech + choice states) ---
	_text_label = DialogueLabel.new()
	_text_label.fit_content = true
	_text_label.bbcode_enabled = true
	_text_label.scroll_active = false
	_text_label.seconds_per_step = SECONDS_PER_STEP
	_text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_text_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text_label.add_theme_font_override("normal_font", _space500)
	_text_label.add_theme_font_size_override("normal_font_size", 21)
	_text_label.add_theme_color_override("default_color", C_TEXT)
	_text_label.add_theme_constant_override("line_separation", 8)
	vbox.add_child(_text_label)

	# --- Speech footer (progress · advance affordance) ---
	_speech_footer = HBoxContainer.new()
	_speech_footer.add_theme_constant_override("separation", 8)
	vbox.add_child(_speech_footer)

	_progress_label = Label.new()
	_progress_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	_progress_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_override("font", CHAKRA_FONT)
	_progress_label.add_theme_font_size_override("font_size", 12)
	_progress_label.add_theme_color_override("font_color", C_DIM)
	_speech_footer.add_child(_progress_label)

	var advance_group := HBoxContainer.new()
	advance_group.add_theme_constant_override("separation", 8)
	advance_group.size_flags_horizontal = Control.SIZE_SHRINK_END
	advance_group.alignment = BoxContainer.ALIGNMENT_END
	_speech_footer.add_child(advance_group)

	_advance_label = Label.new()
	_advance_label.text = "Continue"
	_advance_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_advance_label.add_theme_font_override("font", CHAKRA_FONT)
	_advance_label.add_theme_font_size_override("font_size", 14)
	_advance_label.add_theme_color_override("font_color", C_TEXT)
	advance_group.add_child(_advance_label)

	var key_chip := PanelContainer.new()
	key_chip.custom_minimum_size = Vector2(26, 26)
	key_chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var key_sb := StyleBoxFlat.new()
	key_sb.bg_color = C_TEXT
	key_sb.set_corner_radius_all(5)
	key_sb.content_margin_left = 8.0
	key_sb.content_margin_right = 8.0
	key_sb.content_margin_top = 0.0
	key_sb.content_margin_bottom = 0.0
	key_chip.add_theme_stylebox_override("panel", key_sb)
	advance_group.add_child(key_chip)

	_advance_key_label = Label.new()
	_advance_key_label.text = "␣"
	_advance_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_advance_key_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_advance_key_label.add_theme_font_override("font", CHAKRA_FONT)
	_advance_key_label.add_theme_font_size_override("font_size", 12)
	_advance_key_label.add_theme_color_override("font_color", C_CREAM)
	key_chip.add_child(_advance_key_label)

	# --- Choice list (border-top divider + rigid numbered rows) ---
	_choices_view = VBoxContainer.new()
	_choices_view.add_theme_constant_override("separation", 0)
	_choices_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_choices_view)

	var top_border := ColorRect.new()
	top_border.color = C_TRACK
	top_border.custom_minimum_size = Vector2(0, 2)
	top_border.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices_view.add_child(top_border)

	_choices_box = VBoxContainer.new()
	_choices_box.add_theme_constant_override("separation", 0)
	_choices_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choices_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_choices_view.add_child(_choices_box)

	_speech_footer.visible = false
	_choices_view.visible = false


# Speaker portrait: a dark chip sitting ABOVE the box, left edge at 46px, bobbing gently.
func _build_portrait(anchor: Control) -> void:
	_portrait_holder = Control.new()
	# Pin to the bottom-left corner of the screen, 108x108, ending 228px up.
	_portrait_holder.anchor_left = 0.0
	_portrait_holder.anchor_right = 0.0
	_portrait_holder.anchor_top = 1.0
	_portrait_holder.anchor_bottom = 1.0
	_portrait_holder.offset_left = 46.0
	_portrait_holder.offset_right = 46.0 + 108.0
	_portrait_holder.offset_bottom = -228.0
	_portrait_holder.offset_top = -(228.0 + 108.0)
	_portrait_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(_portrait_holder)

	# Bob target — a free child (the holder is a plain Control, so this isn't relaid out).
	_portrait_frame = PanelContainer.new()
	_portrait_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var p_sb := StyleBoxFlat.new()
	p_sb.bg_color = C_DARKCHIP
	p_sb.set_border_width_all(4)
	p_sb.border_color = C_INK
	p_sb.set_corner_radius_all(8)
	_portrait_frame.add_theme_stylebox_override("panel", p_sb)
	_portrait_holder.add_child(_portrait_frame)

	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_frame.add_child(content)

	_portrait_rect = TextureRect.new()
	_portrait_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_portrait_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_portrait_rect)

	_portrait_initial = Label.new()
	_portrait_initial.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_portrait_initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_portrait_initial.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_initial.add_theme_font_override("font", CHAKRA_FONT)
	_portrait_initial.add_theme_font_size_override("font_size", 24)
	_portrait_initial.add_theme_color_override("font_color", C_PORTRAIT_LETTER)
	content.add_child(_portrait_initial)


# Dark name plate to the right of the portrait. The name Label is `_name_label` (the
# field dialogue.gd tints by reputation — do not rename).
func _build_nameplate(anchor: Control) -> void:
	_nameplate = PanelContainer.new()
	_nameplate.anchor_left = 0.0
	_nameplate.anchor_right = 0.0
	_nameplate.anchor_top = 1.0
	_nameplate.anchor_bottom = 1.0
	# Zero-size pinned corner; grows right + up to fit its content.
	_nameplate.offset_left = 166.0
	_nameplate.offset_right = 166.0
	_nameplate.offset_bottom = -236.0
	_nameplate.offset_top = -236.0
	_nameplate.grow_horizontal = Control.GROW_DIRECTION_END
	_nameplate.grow_vertical = Control.GROW_DIRECTION_BEGIN

	var n_sb := StyleBoxFlat.new()
	n_sb.bg_color = C_DARKCHIP
	n_sb.set_border_width_all(3)
	n_sb.border_color = C_INK
	n_sb.set_corner_radius_all(6)
	n_sb.content_margin_left = 14.0
	n_sb.content_margin_right = 14.0
	n_sb.content_margin_top = 6.0
	n_sb.content_margin_bottom = 6.0
	_nameplate.add_theme_stylebox_override("panel", n_sb)
	anchor.add_child(_nameplate)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 9)
	_nameplate.add_child(row)

	_name_label = Label.new()
	_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_override("font", CHAKRA_FONT)
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.add_theme_color_override("font_color", C_CREAM)
	row.add_child(_name_label)

	_role_label = Label.new()
	# No data source for a role line; left blank (hidden). Set _role_label.text to show one.
	_role_label.text = ""
	_role_label.visible = false
	_role_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_role_label.add_theme_font_override("font", CHAKRA_FONT)
	_role_label.add_theme_font_size_override("font_size", 11)
	_role_label.add_theme_color_override("font_color", C_NAMEROLE)
	row.add_child(_role_label)

	_nameplate.visible = false


# Global bottom legend (the static hint), right-aligned just below the box.
func _build_bottom_hint(anchor: Control) -> void:
	_hint_label = Label.new()
	_hint_label.anchor_left = 0.0
	_hint_label.anchor_right = 1.0
	_hint_label.anchor_top = 1.0
	_hint_label.anchor_bottom = 1.0
	_hint_label.offset_left = 46.0
	_hint_label.offset_right = -46.0
	_hint_label.offset_bottom = -8.0
	_hint_label.offset_top = -28.0
	_hint_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_label.add_theme_font_override("font", _space600)
	_hint_label.add_theme_font_size_override("font_size", 11)
	_hint_label.add_theme_color_override("font_color", C_BOTTOM_HINT)
	anchor.add_child(_hint_label)
	_set_hint(LEGEND)


# Build one numbered reply row as a Button (kept a Button so hotkeys / pressed.emit() /
# focus still work) with a custom caret · text · [tag] · number layout inside.
func _make_choice_row(number: int, response) -> Button:
	var btn := Button.new()
	btn.focus_mode = Control.FOCUS_ALL
	btn.custom_minimum_size = Vector2(0, 46)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.text = ""

	# Bottom divider (kept INSIDE the button so _choices_box children stay 1:1 with rows).
	var divider := ColorRect.new()
	divider.color = C_TRACK
	divider.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	divider.offset_top = -2.0
	divider.custom_minimum_size = Vector2(0, 2)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(divider)

	var mc := MarginContainer.new()
	mc.set_anchors_preset(Control.PRESET_FULL_RECT)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_theme_constant_override("margin_left", 14)
	mc.add_theme_constant_override("margin_right", 6)
	mc.add_theme_constant_override("margin_top", 11)
	mc.add_theme_constant_override("margin_bottom", 11)
	btn.add_child(mc)

	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.alignment = BoxContainer.ALIGNMENT_BEGIN
	hb.add_theme_constant_override("separation", 12)
	mc.add_child(hb)

	var caret := Label.new()
	caret.text = "▸"
	caret.custom_minimum_size = Vector2(14, 0)
	caret.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caret.add_theme_font_override("font", _space600)
	caret.add_theme_font_size_override("font_size", 15)
	hb.add_child(caret)

	var txt := Label.new()
	txt.text = response.text
	txt.clip_text = true
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	txt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	txt.add_theme_font_override("font", _space600)
	txt.add_theme_font_size_override("font_size", 17)
	hb.add_child(txt)

	# Optional colored tag (ACCEPT/SHOP/…), only when the author supplied a [#tag=…].
	var tag_text: String = _derive_tag(response)
	if tag_text != "":
		hb.add_child(_make_tag(tag_text))

	var num_panel := PanelContainer.new()
	num_panel.custom_minimum_size = Vector2(22, 22)
	num_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var num_lbl := Label.new()
	num_lbl.text = str(number)
	num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num_lbl.add_theme_font_override("font", CHAKRA_FONT)
	num_lbl.add_theme_font_size_override("font_size", 12)
	num_panel.add_child(num_lbl)
	hb.add_child(num_panel)

	btn.set_meta("caret", caret)
	btn.set_meta("txt", txt)
	btn.set_meta("num_panel", num_panel)
	btn.set_meta("num_lbl", num_lbl)
	_restyle_row(btn, false)
	return btn


func _restyle_row(btn: Button, selected: bool) -> void:
	var sb := _choice_stylebox(selected)
	for st in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(st, sb)
	var caret := btn.get_meta("caret") as Label
	if caret != null:
		caret.add_theme_color_override("font_color", C_GOLD if selected else C_CLEAR)
	var txt := btn.get_meta("txt") as Label
	if txt != null:
		txt.add_theme_color_override("font_color", C_TEXT if selected else C_CHOICE_MUTED)
	var num_panel := btn.get_meta("num_panel") as PanelContainer
	if num_panel != null:
		num_panel.add_theme_stylebox_override("panel", _num_chip_stylebox(selected))
	var num_lbl := btn.get_meta("num_lbl") as Label
	if num_lbl != null:
		num_lbl.add_theme_color_override("font_color", C_CREAM if selected else C_DIM)


# Row background + 4px left accent (gold when selected). The bottom divider is a separate
# ColorRect because StyleBoxFlat can't carry two different border colors.
func _choice_stylebox(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SEL_BG if selected else C_CLEAR
	sb.set_corner_radius_all(0)
	sb.border_width_left = 4
	sb.border_width_top = 0
	sb.border_width_right = 0
	sb.border_width_bottom = 0
	sb.border_color = C_GOLD if selected else C_CLEAR
	sb.content_margin_left = 0.0
	sb.content_margin_right = 0.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	return sb


func _num_chip_stylebox(selected: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(4)
	sb.set_border_width_all(2)
	if selected:
		sb.bg_color = C_TEXT
		sb.border_color = C_INK
	else:
		sb.bg_color = C_CLEAR
		sb.border_color = C_TRACK
	sb.content_margin_left = 0.0
	sb.content_margin_right = 0.0
	sb.content_margin_top = 0.0
	sb.content_margin_bottom = 0.0
	return sb


# Optional reply tag. Baseline: none. If the .dialogue author tags a response (e.g.
# [#tag=ACCEPT]) and the addon exposes it, we surface a colored pill.
func _derive_tag(response) -> String:
	if response != null and response.has_method("get_tag_value"):
		var t = response.get_tag_value("tag")
		if t != null and String(t) != "":
			return String(t).to_upper()
	return ""


func _make_tag(text: String) -> PanelContainer:
	var bg: Color = C_BLUE
	if text == "ACCEPT":
		bg = C_GREEN
	elif text == "SHOP":
		bg = C_GOLD
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 7.0
	sb.content_margin_right = 7.0
	sb.content_margin_top = 2.0
	sb.content_margin_bottom = 2.0
	panel.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", _space700)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", C_TAG_INK)
	panel.add_child(lbl)
	return panel


# Show a portrait texture if given; otherwise an NPC abbreviation glyph (first 3 letters).
func _set_portrait(tex: Texture2D, speaker_name: String) -> void:
	if tex != null:
		_portrait_rect.texture = tex
		_portrait_rect.show()
		_portrait_initial.hide()
		return
	_portrait_rect.texture = null
	_portrait_rect.hide()
	_portrait_initial.show()
	var s: String = speaker_name.strip_edges()
	_portrait_initial.text = s.substr(0, 3).to_upper() if s.length() > 0 else "?"


# --- Helpers ---------------------------------------------------------------

# Looping portrait bob — runs while the game is paused (this CanvasLayer is PROCESS_ALWAYS,
# and a node-bound tween inherits that, so it keeps ticking during the dialogue pause).
func _start_bob() -> void:
	var t := create_tween().set_loops()
	t.tween_property(_portrait_frame, "position:y", -3.0, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_portrait_frame, "position:y", 0.0, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


# Space Grotesk pinned to a weight via its OpenType 'wght' axis.
func _space(weight: float) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = SPACE_FONT
	fv.variation_opentype = {WGHT_TAG: weight}
	return fv
