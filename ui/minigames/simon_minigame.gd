# simon_minigame.gd
# "Simon Says" memory game. Four coloured pads. Each round the game flashes a
# growing sequence; the player must repeat it by clicking the pads in order. Get
# it right and the sequence grows by one (and you score). One mistake ends the
# game. The longer the sequence you reach, the bigger the reward.
#
# Reward: score = highest sequence length completed; reward = score * REWARD_PER_
# ROUND money.
#
# All UI is built in code (no .tscn, no art). Extends Minigame, so it's a
# CanvasLayer with PROCESS_MODE_ALWAYS and plays while the world is paused.

extends Minigame

const PAD_COUNT := 4
const REWARD_PER_ROUND := 8        # Money per completed round.
const FLASH_ON := 0.45             # How long each pad stays lit while showing.
const FLASH_GAP := 0.2             # Dark gap between flashes.

# Base (dim) and lit colours for each pad, by index.
const PAD_DIM := [
	Color(0.20, 0.05, 0.05), Color(0.05, 0.20, 0.05),
	Color(0.05, 0.05, 0.22), Color(0.22, 0.20, 0.05),
]
const PAD_LIT := [
	Color(1.0, 0.25, 0.25), Color(0.30, 1.0, 0.35),
	Color(0.35, 0.45, 1.0), Color(1.0, 0.90, 0.30),
]

# State machine: SHOWING = replaying the sequence to the player (input locked);
# INPUT = waiting for the player's taps; OVER = finished.
enum State { SHOWING, INPUT, OVER }

var _sequence: Array[int] = []
var _input_pos: int = 0            # How far through their replay the player is.
var _score: int = 0                # Rounds completed (== best sequence length).
var _state: int = State.SHOWING

var _pads: Array[Button] = []
var _status_label: Label
var _score_label: Label
var _flash_timer: Timer
var _flash_queue: Array[int] = []  # Pending pad indices to flash during SHOWING.

func _ready() -> void:
	title = "Simon Says"
	super._ready()
	_build_ui()
	_flash_timer = _make_timer(FLASH_ON, true)
	_flash_timer.timeout.connect(_on_flash_step)
	_next_round()

# --- UI --------------------------------------------------------------------

func _build_ui() -> void:
	var dim := _make_backdrop()
	var vbox := _make_column(dim)

	_score_label = Label.new()
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 24)
	_score_label.text = "Round: 0"
	vbox.add_child(_score_label)

	_status_label = Label.new()
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", 22)
	_status_label.text = "Watch..."
	vbox.add_child(_status_label)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	vbox.add_child(grid)

	for i in PAD_COUNT:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(150, 150)
		btn.pressed.connect(_on_pad_pressed.bind(i))
		grid.add_child(btn)
		_pads.append(btn)
		_set_pad_lit(i, false)

	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(0, 44)
	done.pressed.connect(_finish)
	vbox.add_child(done)

func _set_pad_lit(index: int, lit: bool) -> void:
	var col: Color = PAD_LIT[index] if lit else PAD_DIM[index]
	var box := StyleBoxFlat.new()
	box.bg_color = col
	box.corner_radius_top_left = 12
	box.corner_radius_top_right = 12
	box.corner_radius_bottom_left = 12
	box.corner_radius_bottom_right = 12
	var btn := _pads[index]
	btn.add_theme_stylebox_override("normal", box)
	btn.add_theme_stylebox_override("hover", box)
	btn.add_theme_stylebox_override("pressed", box)

# --- Round flow ------------------------------------------------------------

# Append a random pad to the sequence and replay the whole thing for the player.
func _next_round() -> void:
	_sequence.append(randi() % PAD_COUNT)
	_input_pos = 0
	_state = State.SHOWING
	_status_label.text = "Watch..."
	_score_label.text = "Round: %d" % _sequence.size()
	# Queue each step (lit pad) to flash one at a time via the timer.
	_flash_queue = _sequence.duplicate()
	_flash_timer.start(FLASH_GAP)  # short lead-in before the first flash

# Drives the showing animation: alternates "light a pad" and "go dark" states.
func _on_flash_step() -> void:
	if _closed:
		return
	# If a pad is currently lit, darken it and pause briefly before the next one.
	var lit_index := _currently_lit_pad()
	if lit_index != -1:
		_set_pad_lit(lit_index, false)
		if _flash_queue.is_empty():
			# Done replaying — hand control to the player.
			_state = State.INPUT
			_status_label.text = "Your turn!"
			return
		_flash_timer.start(FLASH_GAP)
		return
	# Otherwise light the next queued pad.
	if _flash_queue.is_empty():
		_state = State.INPUT
		_status_label.text = "Your turn!"
		return
	var next_pad: int = _flash_queue.pop_front()
	_set_pad_lit(next_pad, true)
	_flash_timer.start(FLASH_ON)

func _currently_lit_pad() -> int:
	for i in PAD_COUNT:
		var box := _pads[i].get_theme_stylebox("normal")
		if box is StyleBoxFlat and (box as StyleBoxFlat).bg_color == PAD_LIT[i]:
			return i
	return -1

func _on_pad_pressed(index: int) -> void:
	if _state != State.INPUT or _closed:
		return
	# Brief visual feedback on the tapped pad.
	_set_pad_lit(index, true)
	var blip := _make_timer(0.15, true)
	blip.timeout.connect(func() -> void:
		if not _closed:
			_set_pad_lit(index, false)
		blip.queue_free())
	blip.start()

	if index == _sequence[_input_pos]:
		_input_pos += 1
		if _input_pos >= _sequence.size():
			# Completed the round.
			_state = State.SHOWING   # lock input during the post-round gap
			_score = _sequence.size()
			_score_label.text = "Round: %d" % _score
			_status_label.text = "Nice!"
			var gap := _make_timer(0.6, true)
			gap.timeout.connect(func() -> void:
				gap.queue_free()
				if not _closed:
					_next_round())
			gap.start()
	else:
		# Wrong pad — game over, finish with the best score reached.
		_state = State.OVER
		_status_label.text = "Wrong! Game over."
		_finish()

# --- Finish ----------------------------------------------------------------

func _finish() -> void:
	_close(_current_score(), _current_reward())

func _current_score() -> int:
	return _score

func _current_reward() -> int:
	return _score * REWARD_PER_ROUND
