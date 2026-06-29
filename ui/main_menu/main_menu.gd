# main_menu.gd
# Autoload singleton (register as "MainMenu"). The full-screen title menu shown at
# launch before any gameplay scene exists, and re-openable later (e.g. from the pause
# menu's future "Main Menu" button).
#
# Built entirely in code (no .tscn), mirroring pause_menu.gd / death_screen.gd so there
# is no layout resource to maintain. It is a CanvasLayer that processes ALWAYS, so it
# keeps working even if it is ever shown while the tree is paused.
#
# Boot flow: stages/boot.gd no longer jumps straight into the town. Instead it calls
# MainMenu.open(), and THIS menu is what eventually calls SceneManager.change_scene()
# (New Game) or SaveManager.load_game() (Continue) to enter the world. Because the
# world renders inside SceneManager's pixel-art SubViewport, all world entry MUST go
# through SceneManager / SaveManager — never get_tree().change_scene_*.
#
# Buttons:
#   New Game  -> fresh run: SceneManager.change_scene(FIRST_SCENE). Does NOT load a save.
#   Continue  -> SaveManager.load_game(DEFAULT_SLOT). Hidden/disabled when no save exists.
#   Load Game -> opens SaveSlotMenu in LOAD mode (an overlay above this menu).
#   Quit      -> get_tree().quit().
#
# Controller etiquette: on open we grab focus on the first button so A works without a
# mouse. ui_cancel deliberately does NOTHING here — this is the root menu, there is
# nowhere to back out to.
#
# VISUAL NOTE: this title screen deliberately BREAKS from the muted in-game cream theme
# into a bright cartoon look (gold sky, ink outlines, hard offset shadows, goo blobs).
# Everything is drawn with explicit colors / StyleBoxFlat rather than the project theme.
# The whole picture is composed on a fixed 1200x675 "design" canvas which is scaled
# uniformly to fit the viewport and centered (letterbox filled with the base gold).
#
# NOTE: intentionally NO class_name. The autoload is registered under the name
# "MainMenu"; giving the script the same class_name would collide with that global.

extends CanvasLayer

## The first real gameplay scene a New Game drops you into. Mirrors the constant that
## used to live in stages/boot.gd so the title screen owns "where a fresh run starts".
const FIRST_SCENE: String = "res://stages/overworld/town_template.tscn"

## Which save slot the "Continue" shortcut loads. Matches SaveManager's quicksave slot
## (F5/F9 both use slot 0), so Continue resumes the most recent quicksave.
const DEFAULT_SLOT: int = 0

## Keyboard fallback glyphs for the first-run controls toast, used only when InputDevice
## (the live device-aware glyph source) isn't available. Keep in sync with the bindings.
const CONTROLS_FALLBACK_GLYPHS: Dictionary = {
	&"interact": "E",
	&"inventory": "I",
	&"quest_log": "J",
	&"pause": "Esc",
	&"jump": "Space",
	&"sprint": "Shift",
}

# --- Cartoon palette (all explicit; the in-game theme is NOT used here) -----
const INK: Color = Color("221f1a")            # borders / text / shadows
const BASE_GOLD: Color = Color("ffd54a")      # base fill + letterbox
const SKY_TOP: Color = Color("5fc3e4")
const SKY_MID: Color = Color("7fd0e8")
const SKY_HORIZON: Color = Color("ffe08a")
const SUN_FILL: Color = Color("ffec9e")
const CLOUD_FILL: Color = Color("ffffff")
const HILL_L_FILL: Color = Color("5ba36a")
const HILL_R_FILL: Color = Color("69b478")
const GOO_PURPLE: Color = Color("8b6fc4")
const GOO_RED: Color = Color("ef5340")
const GOO_BLUE: Color = Color("4a86a4")
const TITLE_FILL: Color = Color("fbf8f0")
const TITLE_SHADOW: Color = Color("c8941e")
const CREAM: Color = Color("fbf8f0")
const WHITE: Color = Color("ffffff")
const HINT_GREY: Color = Color("6a655c")
const ACCENT_GREEN: Color = Color("5ba36a")
const ACCENT_BLUE: Color = Color("4a86a4")
const ACCENT_GOLD: Color = Color("c8941e")
const ACCENT_RED: Color = Color("ef5340")

# The design is authored at this fixed reference resolution and scaled to fit.
const DESIGN_SIZE: Vector2 = Vector2(1200, 675)

## True while the title screen is visible. Mirrors the is_open flag the other menus use
## (MenuManager reads it to decide whether an exclusive menu is currently up).
var is_open: bool = false

var _root: Control
# First button ("New Game") — grabbed on open so a controller has a selection.
var _first_button: Button = null
# Kept so we can enable/disable it each time we open, depending on whether a save exists.
var _continue_button: Button = null

# --- Cartoon-screen internals ----------------------------------------------
# The 1200x675 design canvas, uniformly scaled + centered inside the viewport.
var _design: Control = null
# The rotating sunburst behind the sun (spun in _process).
var _spinner: Node2D = null
# Continue's "Slot 0 · ..." hint label, refreshed whenever the button is shown.
var _continue_hint_label: Label = null
# Cartoon display fonts (loaded if present; size-only fallback otherwise).
var _font_display: Font = null   # Chakra Petch (title / buttons / chips)
var _font_body: Font = null      # Space Grotesk (tagline / hints)

func _ready() -> void:
	# High layer so the title sits above the HUD and any gameplay UI. Above the pause
	# menu (20) and death screen (21) too, since the title is a top-level state.
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Deliberately NOT joined to "exclusive_menu": this menu acts as the PARENT of the
	# SaveSlotMenu (Load Game opens that overlay on top), and a member of the exclusive
	# group would get auto-closed the moment the slot menu opens. We still politely close
	# OTHER exclusive menus ourselves via MenuManager.opening() in open().
	_build_ui()
	hide()

func _process(delta: float) -> void:
	# Spin the sunburst a full turn every 60s (matches the design's dcSpin animation).
	# Only bother while the title is actually on screen.
	if is_open and _spinner != null:
		_spinner.rotation += delta * TAU / 60.0

func _unhandled_input(event: InputEvent) -> void:
	# ui_cancel (Esc / B) is swallowed while the title is up so it can't accidentally
	# fall through to gameplay or the pause menu; there is nothing to "back out" to here.
	if is_open and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()

# --- Public API ------------------------------------------------------------

## Show the title screen and free the mouse. Safe to call at launch (from boot.gd) or
## again later (e.g. a pause-menu "Main Menu" button). show_menu() is an alias.
func open() -> void:
	if is_open:
		# Already up — just make sure focus is sane (e.g. re-opened over itself).
		focus_first()
		return
	is_open = true
	# Close any OTHER exclusive menu that happens to be open (inventory, shop, etc.) so
	# we don't draw the title over a half-open gameplay menu. MainMenu itself is not in
	# the group, so this never closes us.
	if _has_menu_manager():
		MenuManager.opening(self)
	# Refresh Continue's availability every time we open — a save may have appeared since.
	_refresh_continue()
	show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	focus_first()

## Alias kept because the brief mentions both names; some callers may prefer show_menu().
func show_menu() -> void:
	open()

## Hide the title screen. Does NOT change mouse mode on its own — the action that leaves
## the menu (New Game / Continue) decides whether to recapture the mouse for gameplay.
func close() -> void:
	if not is_open:
		return
	is_open = false
	hide()

## Put controller focus back on the first button. Exposed so SaveSlotMenu can hand focus
## back to us when its overlay closes and we are still visible underneath.
func focus_first() -> void:
	if _first_button != null:
		_first_button.grab_focus.call_deferred()

# --- Button handlers -------------------------------------------------------

func _on_new_game() -> void:
	# Fresh run: jump straight into the world WITHOUT touching any save. Autoloads keep
	# their launch defaults, so this is a clean game.
	_maybe_show_controls_hint()
	_grant_starting_tools()
	# Give the player an obvious first objective. start_quest no-ops if it's already
	# active/completed, and this only runs on New Game — the Continue/Load path restores
	# QuestSystem from the save, so we never auto-start there.
	if QuestSystem != null:
		QuestSystem.start_quest(&"getting_started")
	_enter_world()
	SceneManager.change_scene(FIRST_SCENE)

# New-game-only grant of the four basic tools. Guarded by a dedicated GameState flag so it
# never re-grants on a subsequent New Game within the same process, and so it stays distinct
# from the dungeon direct-play kit's &"starter_kit_granted" latch. Adds the items to the bag
# AND lays them out on the first four hotbar slots so the player starts ready to mine/chop/fight.
func _grant_starting_tools() -> void:
	if GameState.get_flag(&"starting_tools_granted"):
		return
	GameState.set_flag(&"starting_tools_granted", true)
	Inventory.add(&"pickaxe", 1)
	Inventory.add(&"hatchet", 1)
	Inventory.add(&"iron_sword", 1)
	Inventory.add(&"bow", 1)
	Hotbar.set_slot(0, &"pickaxe")
	Hotbar.set_slot(1, &"hatchet")
	Hotbar.set_slot(2, &"iron_sword")
	Hotbar.set_slot(3, &"bow")
	Hotbar.select(0)

# First-run onboarding: on a genuinely fresh start (no loadable save anywhere) pop a few
# toasts listing the core bindings so new players aren't stranded. Fully guarded — if the
# feed autoload is missing we silently skip it, and it never touches the continue/save
# flow. Glyphs are device-aware (controller labels on a pad) via InputDevice when present.
func _maybe_show_controls_hint() -> void:
	if SaveManager != null and SaveManager.has_loadable_save(DEFAULT_SLOT):
		return # Returning player resuming a save; don't nag with the controls primer.
	var feed := get_node_or_null("/root/NotificationFeed")
	if feed == null or not feed.has_method("notify"):
		return
	for line in _controls_hint_lines():
		feed.notify(line)

# Builds the 2-3 device-aware controls lines. Reads InputDevice (guarded) so the glyphs
# match the player's current device; falls back to keyboard literals when it's absent.
func _controls_hint_lines() -> Array[String]:
	var devices := get_node_or_null("/root/InputDevice")
	var on_pad: bool = devices != null and ("current_device" in devices) and int(devices.current_device) == 1
	# Movement / camera line: the analog vs. WASD distinction has no single InputMap glyph,
	# so it adapts off the device family directly.
	var move_line: String
	if on_pad:
		move_line = "L-Stick Move   R-Stick Look   %s Sprint" % _controls_glyph(devices, &"sprint", "L3")
	else:
		move_line = "WASD Move   Mouse Look   %s Sprint" % _controls_glyph(devices, &"sprint", "Shift")
	var action_line: String = "%s   %s   %s" % [
		_controls_prompt(devices, &"interact", "Interact"),
		_controls_prompt(devices, &"inventory", "Inventory"),
		_controls_prompt(devices, &"quest_log", "Quests"),
	]
	var system_line: String = "%s   %s" % [
		_controls_prompt(devices, &"jump", "Jump"),
		_controls_prompt(devices, &"pause", "Pause"),
	]
	return [move_line, action_line, system_line]

# "[glyph] Label" for an action, device-aware via InputDevice; literal fallback otherwise.
func _controls_prompt(devices: Node, action: StringName, label: String) -> String:
	if devices != null and devices.has_method("prompt_text"):
		return String(devices.prompt_text(action, label))
	return "[%s] %s" % [String(CONTROLS_FALLBACK_GLYPHS.get(action, "?")), label]

# Bare glyph for an action (no label), device-aware; `fallback` used if unresolved.
func _controls_glyph(devices: Node, action: StringName, fallback: String) -> String:
	if devices != null and devices.has_method("action_glyph"):
		var g: String = String(devices.action_glyph(action))
		if g != "" and g != "?":
			return g
	return fallback

func _on_continue() -> void:
	# Resume the default slot. load_game() restores every system AND the saved scene/
	# location via SceneManager, so we just need to dismiss the menu and recapture input.
	if not SaveManager.has_save(DEFAULT_SLOT):
		return # Shouldn't happen (button is disabled), but guard anyway.
	# Load FIRST; only dismiss the menu and capture the mouse if the load actually succeeded,
	# so a failed/corrupt load can't strand us with the menu gone and no world.
	if SaveManager.load_game(DEFAULT_SLOT):
		_enter_world()

func _on_load_game() -> void:
	# Open the slot browser in LOAD mode as an overlay on top of the title. We stay
	# visible underneath so cancelling the slot menu returns here. Untyped var so the
	# dynamic .Mode / .open access resolves at runtime (Node has neither statically).
	var slot_menu = get_node_or_null("/root/SaveSlotMenu")
	if slot_menu != null and slot_menu.has_method("open"):
		slot_menu.open(slot_menu.Mode.LOAD)

func _on_quit() -> void:
	get_tree().quit()

# Common teardown when leaving the title for actual gameplay: hide the menu, unpause in
# case we were opened over a paused game, and recapture the mouse for FPS controls.
func _enter_world() -> void:
	close()
	get_tree().paused = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# --- Helpers ---------------------------------------------------------------

# Enable + show Continue only when a save exists in the default slot; otherwise disable
# AND hide it so the title doesn't dangle a dead button on a brand-new install.
func _refresh_continue() -> void:
	if _continue_button == null:
		return
	# Gate on a VALID, loadable save (file exists AND parses AND has a compatible version),
	# not just a file on disk. A corrupt/old/incompatible save would otherwise dangle a
	# Continue button that loads into a blank screen.
	var have_save: bool = SaveManager.has_loadable_save(DEFAULT_SLOT)
	_continue_button.disabled = not have_save
	_continue_button.visible = have_save
	if have_save and _continue_hint_label != null:
		_continue_hint_label.text = _continue_hint()

# "Slot 0 · <when>" sub-label for the Continue button. SaveManager stores no playtime
# (its payload is just version/systems/location), so — mirroring SaveSlotMenu._slot_label —
# we surface the save file's last-modified timestamp as the most honest "where you left off"
# marker instead of a fabricated hours-played figure.
func _continue_hint() -> String:
	var path: String = SaveManager.slot_path(DEFAULT_SLOT)
	var mtime: int = FileAccess.get_modified_time(path)
	if mtime <= 0:
		return "Slot %d" % DEFAULT_SLOT
	# Trim the seconds for a compact "YYYY-MM-DD HH:MM" stamp.
	var when: String = Time.get_datetime_string_from_unix_time(mtime, true).replace("T", " ").substr(0, 16)
	return "Slot %d · %s" % [DEFAULT_SLOT, when]

func _has_menu_manager() -> bool:
	return get_node_or_null("/root/MenuManager") != null

# --- UI construction (all in code) -----------------------------------------

func _build_ui() -> void:
	_load_fonts()

	# Opaque base fill (#ffd54a). Doubles as the backdrop that eats stray clicks and as
	# the letterbox color around the scaled design canvas. This is `_root`.
	var bg := ColorRect.new()
	bg.color = BASE_GOLD
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	_root = bg

	# The 1200x675 design canvas. Scaled uniformly + centered by _layout_design().
	_design = Control.new()
	_design.size = DESIGN_SIZE
	_design.clip_contents = true            # match the design's overflow:hidden frame
	_design.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_design)

	_build_sky()
	_build_sunburst()
	_build_sun()
	_build_clouds()
	_build_hills()
	_build_goo()
	_build_title()
	_build_buttons()
	_build_footer()

	# Keep the canvas fitted to the window now and on every resize.
	get_viewport().size_changed.connect(_layout_design)
	_layout_design.call_deferred()

# Uniformly scale the design canvas to fit the viewport, centered (letterbox = base gold).
func _layout_design() -> void:
	if _design == null:
		return
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var s: float = min(vp.x / DESIGN_SIZE.x, vp.y / DESIGN_SIZE.y)
	_design.scale = Vector2(s, s)
	_design.position = Vector2((vp.x - DESIGN_SIZE.x * s) * 0.5, (vp.y - DESIGN_SIZE.y * s) * 0.5)

# Layer 2: bright sky gradient with a HARD horizon stop at y = 0.42.
func _build_sky() -> void:
	var grad := Gradient.new()
	# Duplicate the 0.42 offset (split by a hair) to make the horizon a crisp hard edge.
	grad.offsets = PackedFloat32Array([0.0, 0.42, 0.4201, 1.0])
	grad.colors = PackedColorArray([SKY_TOP, SKY_MID, SKY_HORIZON, BASE_GOLD])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill_from = Vector2(0, 0)
	tex.fill_to = Vector2(0, 1)             # vertical
	tex.width = 4
	tex.height = 256
	var sky := TextureRect.new()
	sky.texture = tex
	sky.position = Vector2.ZERO
	sky.size = DESIGN_SIZE
	sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_design.add_child(sky)

# Layer 3: translucent 12-wedge sunburst behind the sun. 520x520 box at (-180,-180) so its
# center sits at (80,80), partly offscreen top-left. Spun in _process (full turn / 60s).
func _build_sunburst() -> void:
	_spinner = Node2D.new()
	_spinner.position = Vector2(80, 80)     # circle center
	_design.add_child(_spinner)
	var radius := 260.0                      # 520 / 2
	for i in 12:
		var a0 := deg_to_rad(float(i) * 30.0)
		var a1 := deg_to_rad(float(i) * 30.0 + 12.0)   # 12deg wedge per 30deg sector
		var pts := PackedVector2Array()
		pts.append(Vector2.ZERO)
		var steps := 4
		for s in steps + 1:
			var a: float = lerp(a0, a1, float(s) / float(steps))
			pts.append(Vector2(cos(a), sin(a)) * radius)
		var wedge := Polygon2D.new()
		wedge.polygon = pts
		wedge.color = Color(1, 1, 1, 0.34)
		_spinner.add_child(wedge)

# Layer 4: the sun. 128x128 circle at (18,18), 5px ink border. Static.
func _build_sun() -> void:
	_add_panel(Vector2(18, 18), Vector2(128, 128), _flat_box(SUN_FILL, 5, 64))

# Layer 5: two static white cloud pills with 4px ink borders.
func _build_clouds() -> void:
	_add_panel(Vector2(760, 70), Vector2(150, 42), _flat_box(CLOUD_FILL, 4, 999))
	_add_panel(Vector2(540, 140), Vector2(110, 34), _flat_box(CLOUD_FILL, 4, 999))

# Layer 6: two big rounded hill blobs clipped by the bottom edge, 5px ink borders.
func _build_hills() -> void:
	_add_panel(Vector2(-60, 495), Vector2(420, 300), _flat_box(HILL_L_FILL, 5, 999))
	_add_panel(Vector2(800, 505), Vector2(480, 320), _flat_box(HILL_R_FILL, 5, 999))

# Layer 7: three bobbing goo blobs (the mascot menace). Each holds a constant tilt and
# bobs its Y between 0 and -amp on an ease-in-out loop.
func _build_goo() -> void:
	_add_goo(GOO_PURPLE, Vector2(140, 430), 64, -8.0, 16.0, 4.5)
	_add_goo(GOO_RED, Vector2(852, 300), 48, 10.0, 22.0, 5.2)
	_add_goo(GOO_BLUE, Vector2(994, 449), 56, -4.0, 12.0, 4.0)

func _add_goo(fill: Color, pos: Vector2, diameter: float, tilt_deg: float, amp: float, dur: float) -> void:
	var goo := _add_panel(pos, Vector2(diameter, diameter), _flat_box(fill, 5, diameter * 0.5))
	goo.pivot_offset = Vector2(diameter, diameter) * 0.5
	goo.rotation_degrees = tilt_deg
	# Bob: pos.y -> pos.y - amp -> pos.y, sine-eased, looping forever.
	var tw := create_tween().set_loops().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(goo, "position:y", pos.y - amp, dur * 0.5)
	tw.tween_property(goo, "position:y", pos.y, dur * 0.5)

# Layer 8/9: the title block ("Town" / "City") plus the tagline card beneath it.
func _build_title() -> void:
	var title := Label.new()
	title.text = "Town\nCity"
	title.position = Vector2(80, 150)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(title, _font_display, 120)
	title.add_theme_color_override("font_color", TITLE_FILL)
	# ~6px ink stroke -> Godot outline_size ~12 (outline radiates both ways).
	title.add_theme_color_override("font_outline_color", INK)
	title.add_theme_constant_override("outline_size", 12)
	# Hard gold drop shadow, offset (8,8), zero blur/outline.
	title.add_theme_color_override("font_shadow_color", TITLE_SHADOW)
	title.add_theme_constant_override("shadow_offset_x", 8)
	title.add_theme_constant_override("shadow_offset_y", 8)
	title.add_theme_constant_override("shadow_outline_size", 0)
	# Tighten toward the design's line-height 0.86 (best-effort via negative line spacing).
	title.add_theme_constant_override("line_spacing", -18)
	_design.add_child(title)

	# Tagline card below the title: white bg, 4px ink, radius 8, hard ink shadow (4,4).
	var tag_pos := Vector2(80, 384)
	var tag_size := Vector2(330, 34)
	_add_panel(tag_pos + Vector2(4, 4), tag_size, _flat_box_b(WHITE, INK, 0, 8))   # shadow
	var card := _add_panel(tag_pos, tag_size, _flat_box(WHITE, 4, 8))
	var tag := Label.new()
	tag.text = "A small town. Big problems. Mostly goo."
	tag.set_anchors_preset(Control.PRESET_FULL_RECT)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(tag, _font_body, 15)
	tag.add_theme_color_override("font_color", INK)
	card.add_child(tag)

# Layer 10: the menu button column at (768,250), width 360, gap 14.
func _build_buttons() -> void:
	var col := VBoxContainer.new()
	col.position = Vector2(768, 250)
	col.custom_minimum_size = Vector2(360, 0)
	col.add_theme_constant_override("separation", 14)
	_design.add_child(col)

	_first_button = _make_button(col, "New Game", "▶", ACCENT_GREEN, false, _on_new_game)
	_continue_button = _make_button(col, "Continue", "↻", ACCENT_BLUE, true, _on_continue)
	var load_btn := _make_button(col, "Load Game", "⊞", ACCENT_GOLD, false, _on_load_game)
	var quit_btn := _make_button(col, "Quit", "✕", ACCENT_RED, false, _on_quit)

	_continue_hint_label = _continue_button.get_meta("hint_label") as Label

	# Wrap selection at the ends. Default Godot focus nav handles the middle and skips the
	# hidden Continue row automatically, so we only need to close the loop top<->bottom.
	_first_button.focus_neighbor_top = _first_button.get_path_to(quit_btn)
	quit_btn.focus_neighbor_bottom = quit_btn.get_path_to(_first_button)

# Build one cartoon menu row. The row IS a focusable Button (so `pressed`, focus and the
# behavior contract all hold); its visible body + crisp offset shadow are child panels we
# slide/recolor on selection. Children are click-transparent so the Button gets the input.
func _make_button(parent: Node, label: String, icon: String, accent: Color, has_hint: bool, handler: Callable) -> Button:
	var row := Vector2(360, 64)

	var btn := Button.new()
	btn.text = ""
	btn.custom_minimum_size = row
	btn.focus_mode = Control.FOCUS_ALL
	# Strip the Button's own chrome — we draw the body ourselves with child panels.
	var empty_states := ["normal", "hover", "pressed", "focus", "disabled"]
	for st in empty_states:
		btn.add_theme_stylebox_override(st, StyleBoxEmpty.new())
	btn.pressed.connect(handler)
	parent.add_child(btn)

	# Crisp (zero-blur) drop shadow: a duplicate ink panel behind the body.
	var shadow := Panel.new()
	shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shadow.position = Vector2(4, 4)
	shadow.size = row
	shadow.add_theme_stylebox_override("panel", _flat_box_b(INK, INK, 0, 12))
	btn.add_child(shadow)

	# Body panel (recolored on selection).
	var body := Panel.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.position = Vector2.ZERO
	body.size = row
	var body_normal := _flat_box_b(CREAM, INK, 4, 12)
	var body_sel := _flat_box_b(accent, INK, 4, 12)
	body.add_theme_stylebox_override("panel", body_normal)
	btn.add_child(body)

	# Row content: [icon chip] [label .... ] [hint?]
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 18
	hb.offset_top = 15
	hb.offset_right = -18
	hb.offset_bottom = -15
	hb.add_theme_constant_override("separation", 14)
	body.add_child(hb)

	# Icon chip (34x34, radius 8, 3px ink). Accent bg / cream glyph; inverts on selection.
	var chip := Panel.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.custom_minimum_size = Vector2(34, 34)
	var chip_normal := _flat_box_b(accent, INK, 3, 8)
	var chip_sel := _flat_box_b(CREAM, INK, 3, 8)
	chip.add_theme_stylebox_override("panel", chip_normal)
	hb.add_child(chip)
	var icon_lbl := Label.new()
	icon_lbl.text = icon
	icon_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(icon_lbl, _font_display, 16)
	icon_lbl.add_theme_color_override("font_color", CREAM)
	chip.add_child(icon_lbl)

	# Label (flex 1).
	var title_lbl := Label.new()
	title_lbl.text = label
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(title_lbl, _font_display, 23)
	title_lbl.add_theme_color_override("font_color", INK)
	hb.add_child(title_lbl)

	# Optional hint chip (Continue's "Slot 0 · ...").
	var hint_lbl: Label = null
	if has_hint:
		hint_lbl = Label.new()
		hint_lbl.text = ""
		hint_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_apply_font(hint_lbl, _font_body, 11)
		hint_lbl.add_theme_color_override("font_color", HINT_GREY)
		hb.add_child(hint_lbl)

	# Stash references for the selection visual swap.
	btn.set_meta("accent", accent)
	btn.set_meta("shadow", shadow)
	btn.set_meta("body", body)
	btn.set_meta("body_normal", body_normal)
	btn.set_meta("body_sel", body_sel)
	btn.set_meta("chip", chip)
	btn.set_meta("chip_normal", chip_normal)
	btn.set_meta("chip_sel", chip_sel)
	btn.set_meta("title_label", title_lbl)
	btn.set_meta("icon_label", icon_lbl)
	btn.set_meta("hint_label", hint_lbl)

	# Focus drives the selected look; hovering grabs focus (so mouse == selection).
	btn.focus_entered.connect(_set_selected.bind(btn, true))
	btn.focus_exited.connect(_set_selected.bind(btn, false))
	btn.mouse_entered.connect(btn.grab_focus)
	return btn

# Swap a button between its normal and selected (focused) look, animating the lift + shadow.
func _set_selected(btn: Button, on: bool) -> void:
	if not is_instance_valid(btn):
		return
	var accent: Color = btn.get_meta("accent")
	var body: Panel = btn.get_meta("body")
	var shadow: Panel = btn.get_meta("shadow")
	var chip: Panel = btn.get_meta("chip")

	body.add_theme_stylebox_override("panel", btn.get_meta("body_sel") if on else btn.get_meta("body_normal"))
	chip.add_theme_stylebox_override("panel", btn.get_meta("chip_sel") if on else btn.get_meta("chip_normal"))

	var title_lbl: Label = btn.get_meta("title_label")
	title_lbl.add_theme_color_override("font_color", WHITE if on else INK)
	var icon_lbl: Label = btn.get_meta("icon_label")
	icon_lbl.add_theme_color_override("font_color", INK if on else CREAM)
	var hint_lbl = btn.get_meta("hint_label") if btn.has_meta("hint_label") else null
	if hint_lbl != null:
		(hint_lbl as Label).add_theme_color_override("font_color", WHITE if on else HINT_GREY)

	# Slide the body up-left to (-3,-3) and grow the shadow to (7,7) when selected.
	var prev = btn.get_meta("sel_tween") if btn.has_meta("sel_tween") else null
	if prev != null and (prev as Tween).is_valid():
		(prev as Tween).kill()
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(body, "position", Vector2(-3, -3) if on else Vector2.ZERO, 0.08)
	tw.tween_property(shadow, "position", Vector2(7, 7) if on else Vector2(4, 4), 0.08)
	btn.set_meta("sel_tween", tw)

# Layer 11: footer — version chip (left) + nav hint (right), pinned near the bottom.
func _build_footer() -> void:
	# Version chip: ink bg, gold text. Version number can come from ProjectSettings; the
	# build name is the design's literal.
	var ver := "0.4.1"
	if ProjectSettings.has_setting("application/config/version"):
		var v = ProjectSettings.get_setting("application/config/version")
		if typeof(v) == TYPE_STRING and String(v) != "":
			ver = String(v)
	var version_text := "v%s · build \"Sentient Goo\"" % ver

	var chip := _add_panel(Vector2(80, 628), Vector2(232, 27), _flat_box_b(INK, INK, 0, 6))
	var ver_lbl := Label.new()
	ver_lbl.text = version_text
	ver_lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	ver_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ver_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	ver_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(ver_lbl, _font_display, 12)
	ver_lbl.add_theme_color_override("font_color", BASE_GOLD)
	chip.add_child(ver_lbl)

	# Nav hint: right-aligned ink text.
	var nav := Label.new()
	nav.text = "↑↓ navigate  ·  Enter select"
	nav.position = Vector2(700, 631)
	nav.size = Vector2(428, 24)
	nav.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	nav.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nav.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_apply_font(nav, _font_body, 12)
	nav.add_theme_color_override("font_color", INK)
	_design.add_child(nav)

# --- Small construction helpers --------------------------------------------

# Load the cartoon display fonts if present; we degrade to the default font (size only)
# rather than hard-fail if the files ever move.
func _load_fonts() -> void:
	var chakra := "res://ui/fonts/ChakraPetch-SemiBold.ttf"
	var grotesk := "res://ui/fonts/SpaceGrotesk-Bold.ttf"
	if ResourceLoader.exists(chakra):
		_font_display = load(chakra)
	if ResourceLoader.exists(grotesk):
		_font_body = load(grotesk)

# Apply a font (if loaded) + size to a Label.
func _apply_font(lbl: Label, font: Font, size: int) -> void:
	if font != null:
		lbl.add_theme_font_override("font", font)
	lbl.add_theme_font_size_override("font_size", size)

# StyleBoxFlat with an INK border of the given width (the common case for this screen).
func _flat_box(bg: Color, border_w: int, radius: int) -> StyleBoxFlat:
	return _flat_box_b(bg, INK, border_w, radius)

# StyleBoxFlat with an explicit border color (used for the ink shadow panels: bg == border).
func _flat_box_b(bg: Color, border_col: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border_col
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.corner_detail = 12
	return sb

# Add a click-transparent Panel with the given stylebox to the design canvas.
func _add_panel(pos: Vector2, size: Vector2, stylebox: StyleBox) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", stylebox)
	_design.add_child(p)
	return p
