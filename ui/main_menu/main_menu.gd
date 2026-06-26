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
# NOTE: intentionally NO class_name. The autoload is registered under the name
# "MainMenu"; giving the script the same class_name would collide with that global.

extends CanvasLayer

## The first real gameplay scene a New Game drops you into. Mirrors the constant that
## used to live in stages/boot.gd so the title screen owns "where a fresh run starts".
const FIRST_SCENE: String = "res://stages/overworld/town_template.tscn"

## Which save slot the "Continue" shortcut loads. Matches SaveManager's quicksave slot
## (F5/F9 both use slot 0), so Continue resumes the most recent quicksave.
const DEFAULT_SLOT: int = 0

## True while the title screen is visible. Mirrors the is_open flag the other menus use
## (MenuManager reads it to decide whether an exclusive menu is currently up).
var is_open: bool = false

var _root: Control
# First button ("New Game") — grabbed on open so a controller has a selection.
var _first_button: Button = null
# Kept so we can enable/disable it each time we open, depending on whether a save exists.
var _continue_button: Button = null

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
	_enter_world()
	SceneManager.change_scene(FIRST_SCENE)

func _on_continue() -> void:
	# Resume the default slot. load_game() restores every system AND the saved scene/
	# location via SceneManager, so we just need to dismiss the menu and recapture input.
	if not SaveManager.has_save(DEFAULT_SLOT):
		return # Shouldn't happen (button is disabled), but guard anyway.
	_enter_world()
	SaveManager.load_game(DEFAULT_SLOT)

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

func _has_menu_manager() -> bool:
	return get_node_or_null("/root/MenuManager") != null

# --- UI construction (all in code) -----------------------------------------

func _build_ui() -> void:
	# Opaque backdrop (this is a full title screen, not a translucent overlay) that also
	# eats any stray clicks.
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.05, 0.08, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	_root = bg

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(300, 0)
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "Town City"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	vbox.add_child(title)

	# A little breathing room between the title and the buttons.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 24)
	vbox.add_child(spacer)

	_first_button = _add_button(vbox, "New Game", Callable(self, "_on_new_game"))
	_continue_button = _add_button(vbox, "Continue", Callable(self, "_on_continue"))
	_add_button(vbox, "Load Game", Callable(self, "_on_load_game"))
	_add_button(vbox, "Quit", Callable(self, "_on_quit"))

# Build one menu Button, wire its handler, and return it. UISound auto-hooks every
# BaseButton's `pressed` signal, so we don't play click sounds by hand here.
func _add_button(parent: Node, text: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 48)
	btn.focus_mode = Control.FOCUS_ALL
	btn.pressed.connect(handler)
	parent.add_child(btn)
	return btn
