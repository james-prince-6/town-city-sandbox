# minigame.gd
# Base class for every arcade minigame. A Minigame is a self-contained,
# code-built CanvasLayer UI: MinigameManager instances it as a child of itself,
# the game plays out while the rest of the world is paused, and when it's over
# the game emits `finished(score, reward)`. The manager listens for that, grants
# the reward, and frees the game.
#
# Why CanvasLayer + PROCESS_MODE_ALWAYS: the manager pauses the SceneTree
# (get_tree().paused = true) so the world freezes behind the cabinet. A minigame
# obviously still needs to run, so it (and everything it spawns that needs to
# tick — timers, _process) must use PROCESS_MODE_ALWAYS. _ready() sets that on
# the layer; subclasses that add their own Timers should set the same mode on
# them (see _make_timer()).
#
# To make a new game: extend Minigame, set `title`, build your UI in _ready()
# (call super._ready() first), and call _close(score, reward) when done. Escape
# always closes early with whatever score has accumulated so far.

class_name Minigame
extends CanvasLayer

const Glass = preload("res://ui/glass_style.gd")

## Emitted exactly once when the game ends — either naturally ("Done"/timeout)
## or early via Escape. `reward` is the money the manager should grant.
signal finished(score: int, reward: int)

## Shown in the game's header. Subclasses set this before/in _ready().
@export var title: String = "Minigame"

# Guard so a double-trigger (timeout racing with a Done click, or Escape during
# the closing frame) can't emit `finished` twice or grant a reward twice.
var _closed: bool = false

func _ready() -> void:
	# High layer so we sit above the world HUD; the manager also puts its own
	# layer high, this keeps the game above any dim it might add.
	layer = 16
	# Run while the tree is paused (the world is frozen behind us).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Games are mouse-driven; make sure the cursor is free. (The manager also
	# frees it, but a game can be reused/tested standalone.)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _unhandled_input(event: InputEvent) -> void:
	# Escape bails out early, keeping whatever score/reward accrued so far.
	if event.is_action_pressed("ui_cancel"):
		_close(_current_score(), _current_reward())
		get_viewport().set_input_as_handled()

# --- Helpers for subclasses ------------------------------------------------

## End the game. Safe to call more than once; only the first call counts.
func _close(score: int, reward: int) -> void:
	if _closed:
		return
	_closed = true
	finished.emit(score, reward)

## A Timer that ticks while the tree is paused. Use this instead of `Timer.new()`
## directly so your timers don't silently freeze with the world.
func _make_timer(wait_time: float, one_shot: bool = false) -> Timer:
	var t := Timer.new()
	t.wait_time = wait_time
	t.one_shot = one_shot
	t.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(t)
	return t

## Overridden by subclasses so Escape can report the in-progress score. Default
## is 0 (a game that hasn't tracked anything yet).
func _current_score() -> int:
	return 0

## Overridden by subclasses so Escape grants a fair partial reward. Default 0.
func _current_reward() -> int:
	return 0

# --- Shared UI scaffolding -------------------------------------------------

## Builds a full-rect dim backdrop that eats clicks behind the game, and returns
## it so subclasses can parent their content onto it. Call once from _ready().
func _make_backdrop() -> Control:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	Glass.frost(dim)
	return dim

## Standard centered column with the title at the top. Returns the VBox so the
## subclass can append its own controls. `parent` is usually _make_backdrop().
func _make_column(parent: Control) -> VBoxContainer:
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(center)

	var panel := PanelContainer.new()
	Glass.apply(panel, 18, 22)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(420, 0)
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)

	var title_label := Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 38)
	vbox.add_child(title_label)

	return vbox
