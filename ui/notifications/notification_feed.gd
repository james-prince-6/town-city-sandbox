# notification_feed.gd
# Autoload singleton (registered as "NotificationFeed"). A small stack of transient
# "toast" messages in the top-right corner of the screen.
#
# Built entirely in code (no .tscn), mirroring main_menu.gd / death_screen.gd so there
# is no layout resource to maintain. It is a CanvasLayer that processes ALWAYS, so a
# toast still fades correctly even if one pops while the tree is paused (e.g. a level-up
# landing as a menu opens).
#
# What it shows:
#   - Inventory.item_gained -> "+N DisplayName" when the player picks up / crafts / buys.
#   - Progression.leveled_up -> "Level N!" in gold, a louder colour than item toasts.
#
# Toasts stack newest-on-top in a VBoxContainer. Each one fades itself out after a few
# seconds and frees, so the feed naturally trims back to empty when things go quiet. We
# never touch game state here — this is a pure VIEW that listens to the gameplay autoloads.
#
# NOTE: intentionally NO class_name. The autoload is registered under the name
# "NotificationFeed"; giving the script the same class_name would collide with that global.

extends CanvasLayer

## How long a toast stays fully visible before it begins to fade, in seconds.
const HOLD_SECONDS: float = 2.2
## How long the fade-out itself takes, in seconds. HOLD + FADE is the total lifetime.
const FADE_SECONDS: float = 0.8
## Cap on how many toasts are shown at once; the oldest is dropped past this so a flood
## of pickups can't run off the screen.
const MAX_TOASTS: int = 5
## Gold tint used for level-up toasts, to set them apart from plain white item toasts.
const LEVEL_UP_COLOR: Color = Color(1.0, 0.84, 0.2)

# The column the toasts live in, pinned to the top-right. Built once in _ready().
var _stack: VBoxContainer

func _ready() -> void:
	# Above the HUD (layer 5) so toasts read over the bars, but below full-screen menus
	# like the bag (10) / pause (20) which should cover everything. Always-process so a
	# toast's fade tween keeps running even while a menu pauses the rest of the tree.
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_connect_signals()

# --- Public API ------------------------------------------------------------

## Pop a toast reading `text` in `color`. The single entry point — both the signal
## handlers below and any future caller go through here. Auto-fades and frees itself.
func notify(text: String, color: Color = Color.WHITE) -> void:
	var toast := _make_toast(text, color)
	# Newest on top: insert at index 0 so the freshest message sits nearest the corner.
	_stack.add_child(toast)
	_stack.move_child(toast, 0)
	_trim_overflow()
	_animate(toast)

# --- Setup -----------------------------------------------------------------

func _connect_signals() -> void:
	# Inventory + Progression are registered ahead of this autoload, so they already
	# exist when we connect. Both signals are one-liners straight into notify().
	Inventory.item_gained.connect(_on_item_gained)
	Progression.leveled_up.connect(_on_leveled_up)

# --- Signal handlers -------------------------------------------------------

func _on_item_gained(id: StringName, amount: int) -> void:
	# Resolve a friendly name through the item database, falling back to the raw id for
	# anything not yet defined as an Item resource.
	var item := Inventory.get_item(id)
	var label_text: String = item.display_name if item else String(id)
	notify("+%d %s" % [amount, label_text])

func _on_leveled_up(level: int, _points_gained: int) -> void:
	notify("Level %d!" % level, LEVEL_UP_COLOR)

# --- Lifetime --------------------------------------------------------------

# Tween a toast: hold at full opacity, then fade out, then free it. Uses real time and
# survives a tree pause so it behaves the same whether or not the game is paused.
func _animate(toast: Control) -> void:
	# Bind the tween to the TOAST (not the feed). If _trim_overflow frees this toast early, a
	# feed-bound tween would step on the freed node next frame and spam errors; a toast-bound
	# tween is auto-killed when the toast is freed.
	var tween := toast.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(HOLD_SECONDS)
	tween.tween_property(toast, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(toast.queue_free)

# Drops the oldest toasts (those at the bottom of the stack) once we exceed MAX_TOASTS,
# so a burst of pickups can't grow the column past the cap.
func _trim_overflow() -> void:
	while _stack.get_child_count() > MAX_TOASTS:
		var oldest := _stack.get_child(_stack.get_child_count() - 1)
		oldest.queue_free()
		# queue_free() doesn't drop the node from the count until end of frame, so remove
		# it from the tree now to keep this loop honest.
		_stack.remove_child(oldest)

# --- UI construction (all in code) -----------------------------------------

func _build_ui() -> void:
	# Anchor a container to the top-right corner with a little margin, and let toasts
	# stack downward from there. MOUSE_FILTER_IGNORE so the feed never eats clicks.
	_stack = VBoxContainer.new()
	_stack.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	_stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stack.add_theme_constant_override("separation", 6)
	_stack.offset_left = -316
	_stack.offset_top = 16
	_stack.offset_right = -16
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)

# Builds one toast widget: a dark rounded panel with the message label inside. Right-
# aligned so toasts hug the corner regardless of how long the text is.
func _make_toast(text: String, color: Color) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END

	# Semi-transparent dark backing so light text stays readable over any scene.
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.05, 0.08, 0.82)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", 18)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return panel
