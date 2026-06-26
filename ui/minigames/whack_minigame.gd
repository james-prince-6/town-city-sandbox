# whack_minigame.gd
# "Whack-a-Light" reaction game. A 3x3 grid of buttons; one lights up at a time.
# Click the lit one before it expires to score. Clicking a dark cell is a miss
# (small penalty). Lights get faster the longer you survive, so the score curve
# rewards staying sharp. Runs for ROUND_SECONDS, then auto-finishes.
#
# Reward: ceil(score * REWARD_PER_POINT), so a good run pays out more money.
#
# All UI is built in code (no .tscn, no art). Extends Minigame, so it's a
# CanvasLayer with PROCESS_MODE_ALWAYS and plays while the world is paused.

extends Minigame

const GRID := 3                    # 3x3 board.
const ROUND_SECONDS := 20.0        # Total play time.
const HIT_POINTS := 10             # Score per successful hit.
const MISS_PENALTY := 5            # Score lost for clicking a dark cell.
const REWARD_PER_POINT := 0.5      # Money per point (see _current_reward()).

# Lights start slow and speed up as the round progresses.
const LIT_TIME_START := 1.1        # Seconds a light stays up at the start.
const LIT_TIME_END := 0.55         # ...and near the end.

var _score: int = 0
var _time_left: float = ROUND_SECONDS
var _active_index: int = -1        # Which cell is currently lit (-1 = none).

var _buttons: Array[Button] = []
var _score_label: Label
var _time_label: Label
var _light_timer: Timer

func _ready() -> void:
	title = "Whack-a-Light"
	super._ready()
	_build_ui()
	# Drive the light cycle with a paused-safe timer.
	_light_timer = _make_timer(LIT_TIME_START, true)
	_light_timer.timeout.connect(_on_light_expired)
	_light_next()

func _process(delta: float) -> void:
	# Manager pauses the tree, but this layer is ALWAYS — so _process still runs.
	if _closed:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		_time_left = 0.0
		_finish()
		return
	_time_label.text = "Time: %0.1f" % _time_left

# --- UI --------------------------------------------------------------------

func _build_ui() -> void:
	var dim := _make_backdrop()
	var vbox := _make_column(dim)

	var hud := HBoxContainer.new()
	hud.alignment = BoxContainer.ALIGNMENT_CENTER
	hud.add_theme_constant_override("separation", 40)
	vbox.add_child(hud)

	_score_label = Label.new()
	_score_label.add_theme_font_size_override("font_size", 24)
	_score_label.text = "Score: 0"
	hud.add_child(_score_label)

	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", 24)
	_time_label.text = "Time: %0.1f" % _time_left
	hud.add_child(_time_label)

	var grid := GridContainer.new()
	grid.columns = GRID
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)

	for i in GRID * GRID:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(110, 110)
		btn.toggle_mode = false
		# Bind the cell index so one handler serves the whole board.
		btn.pressed.connect(_on_cell_pressed.bind(i))
		grid.add_child(btn)
		_buttons.append(btn)
		_set_cell_lit(i, false)

	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(0, 44)
	done.pressed.connect(_finish)
	vbox.add_child(done)

# Paint a cell as lit (bright) or dark.
func _set_cell_lit(index: int, lit: bool) -> void:
	var btn := _buttons[index]
	var col := Color(1.0, 0.85, 0.2) if lit else Color(0.18, 0.18, 0.22)
	btn.add_theme_color_override("font_color", Color.BLACK)
	# Drive the visual through bg modulate via a StyleBoxFlat per state.
	var box := StyleBoxFlat.new()
	box.bg_color = col
	box.corner_radius_top_left = 8
	box.corner_radius_top_right = 8
	box.corner_radius_bottom_left = 8
	box.corner_radius_bottom_right = 8
	btn.add_theme_stylebox_override("normal", box)
	btn.add_theme_stylebox_override("hover", box)
	btn.add_theme_stylebox_override("pressed", box)

# --- Light cycle -----------------------------------------------------------

# Light a random cell (different from the current one) and arm the expiry timer
# with a time that shrinks as the round goes on.
func _light_next() -> void:
	if _active_index != -1:
		_set_cell_lit(_active_index, false)

	var next_index: int = randi() % (GRID * GRID)
	if GRID * GRID > 1:
		while next_index == _active_index:
			next_index = randi() % (GRID * GRID)
	_active_index = next_index
	_set_cell_lit(_active_index, true)

	# Interpolate lit time from START to END based on elapsed fraction.
	var elapsed_frac: float = clampf(1.0 - (_time_left / ROUND_SECONDS), 0.0, 1.0)
	var lit_time: float = lerpf(LIT_TIME_START, LIT_TIME_END, elapsed_frac)
	_light_timer.start(lit_time)

func _on_light_expired() -> void:
	# Missed it entirely — just move on (no penalty for letting it lapse).
	if _closed:
		return
	_light_next()

func _on_cell_pressed(index: int) -> void:
	if _closed:
		return
	if index == _active_index:
		_score += HIT_POINTS
		_set_cell_lit(_active_index, false)
		_active_index = -1
		_light_timer.stop()
		_light_next()
	else:
		# Clicked a dark cell — small penalty, score never goes negative.
		_score = max(_score - MISS_PENALTY, 0)
	_score_label.text = "Score: %d" % _score

# --- Finish ----------------------------------------------------------------

func _finish() -> void:
	_close(_current_score(), _current_reward())

func _current_score() -> int:
	return _score

func _current_reward() -> int:
	return int(ceil(_score * REWARD_PER_POINT))
