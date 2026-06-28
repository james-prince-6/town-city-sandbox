# clock.gd
# Autoload singleton (registered in Project Settings -> Autoload as "Clock").
#
# Drives the in-game time of day. Like GameState and Inventory, it lives outside
# the swappable scene tree so the clock keeps ticking as the player walks from
# room to room. It does NOT store the day count itself — that lives in
# GameState.day so there is a single source of truth. When midnight rolls over
# we just ask GameState to advance the day.
#
# Real seconds map to game minutes via `seconds_per_game_day`: that many real
# seconds equals one full 24-hour in-game day. NPC schedules, shop hours, and
# brewing timers will hang off the signals below instead of polling every frame.
#
# Access from anywhere: Clock.hour, Clock.get_time_string(), Clock.set_time(...).

extends Node

# --- Tuning knobs (edit these in the Inspector or here) --------------------

## How many REAL seconds make up one full in-game day (24 hours). At 1200 a day
## lasts 20 real minutes, so one in-game minute is 1200 / 1440 ≈ 0.833 seconds.
@export var seconds_per_game_day: float = 1200.0

## What hour the clock starts at when the game (or a fresh save) begins. 7 = 7 AM.
@export var start_hour: int = 7

## While true, time stops advancing. We auto-pause when a blocking UI is open
## (inventory, dialogue) so the world doesn't move on while the player is busy.
var paused: bool = false

## How many blocking menus currently want time stopped. Multiple menus can be
## open at once (e.g. PlayerMenu over a station), so we refcount instead of a
## bare bool: pause on the FIRST opener, resume only when the LAST one closes.
## This avoids a "close one menu while another is still open" wrongly resuming
## time. Bookkeeping only — not serialized (paused itself is captured).
var _pause_holders: int = 0

# --- Signals ---------------------------------------------------------------

## Emitted on every in-game minute tick. A HUD clock label listens to this.
signal time_changed(hour: int, minute: int)

## Emitted only when the hour rolls over. Cheaper for systems that only care
## about the hour (e.g. "is the shop open?") and don't need minute updates.
signal hour_changed(hour: int)

## Emitted right after midnight rollover, once GameState.day has advanced. NPC
## daily schedules and "new day" logic listen here. Carries the new day number.
signal day_started(day: int)

# --- Core time state -------------------------------------------------------

## Current hour, 0-23. Use set_time() / advance_minutes() to change it so the
## right signals fire — don't poke these directly.
var hour: int = 7

## Current minute, 0-59.
var minute: int = 0

## Real-time accumulator. We add `delta` here each frame and peel off whole
## in-game minutes as enough real time builds up. Keeping the leftover fraction
## here means we never lose or gain time to rounding.
var _seconds_accumulator: float = 0.0

func _ready() -> void:
	# ALWAYS so the clock can still process while the SceneTree is paused (we
	# manage our own `paused` flag for stopping time; we don't want an unrelated
	# tree pause to also freeze our auto-pause bookkeeping).
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Start at the configured opening time, e.g. 7:00 AM.
	set_time(start_hour, 0)

	# Auto-pause when a blocking UI is up, resume when it closes. We connect
	# defensively in case these autoloads load after us — they are siblings in
	# the autoload list, so they exist by the time _ready runs, but guarding
	# keeps the clock robust if one is ever removed.
	if Dialogue:
		Dialogue.dialogue_started.connect(_on_ui_blocked)
		Dialogue.dialogue_ended.connect(_on_ui_unblocked)
	if InventoryUI:
		InventoryUI.opened.connect(_on_ui_blocked)
		InventoryUI.closed.connect(_on_ui_unblocked)

	# The original wiring above only covered dialogue + the now-RETIRED bag UI, so
	# in-game time kept ticking (draining timed-task deadlines) while the player
	# sat in the active PlayerMenu, a shop, a crafting/brewing station, or the
	# house upgrade menu. Additively wire those CURRENTLY-USED blocking menus to
	# the same refcounted pause/resume handlers. Each is an OPTIONAL autoload, so
	# fetch via get_node_or_null and only connect if it actually exposes the
	# opened/closed signals — a missing or signal-less node is a silent no-op.
	for menu_path in [
		"/root/PlayerMenu",
		"/root/ShopUI",
		"/root/BrewingUI",
		"/root/CraftingUI",
		"/root/UpgradeUI",
	]:
		var menu = get_node_or_null(menu_path)
		if menu and menu.has_signal("opened") and menu.has_signal("closed"):
			menu.opened.connect(_on_ui_blocked)
			menu.closed.connect(_on_ui_unblocked)

func _process(delta: float) -> void:
	if paused:
		return

	# How many real seconds equal one in-game minute. There are 1440 minutes in
	# a day (24 * 60), so divide the day length by that.
	var seconds_per_game_minute: float = seconds_per_game_day / 1440.0
	if seconds_per_game_minute <= 0.0:
		# Misconfigured (zero/negative day length); avoid a divide-by-zero loop.
		return

	_seconds_accumulator += delta

	# Peel off as many whole in-game minutes as we've banked. A loop (not an if)
	# handles slow frames / fast clocks where several minutes pass at once.
	while _seconds_accumulator >= seconds_per_game_minute:
		_seconds_accumulator -= seconds_per_game_minute
		advance_minutes(1)

# --- Public controls -------------------------------------------------------

## Stop time. Safe to call repeatedly.
func pause() -> void:
	paused = true

## Resume time. Safe to call repeatedly.
func resume() -> void:
	paused = false

## Jump straight to a specific time. Emits time_changed always, and
## hour_changed if the hour actually changed. Does NOT roll the day over —
## use this for "go to sleep" / scripted time skips that set the destination.
func set_time(new_hour: int, new_minute: int) -> void:
	var old_hour: int = hour
	hour = clampi(new_hour, 0, 23)
	minute = clampi(new_minute, 0, 59)
	# Setting an explicit time shouldn't leave a leftover fraction that nudges
	# us into the next minute almost immediately.
	_seconds_accumulator = 0.0
	time_changed.emit(hour, minute)
	if hour != old_hour:
		hour_changed.emit(hour)

## Advance the clock by `n` in-game minutes, firing the right signals along the
## way and handling hour and midnight rollovers. `_process` calls this one
## minute at a time; gameplay can call it with a big number to skip time.
func advance_minutes(n: int) -> void:
	if n <= 0:
		if n < 0:
			push_warning("Clock.advance_minutes: ignoring negative amount %d" % n)
		return

	# Collapse the whole advance into one running total of minutes-since-midnight
	# so we can detect day rollovers cleanly, then unpack it back into hh:mm.
	var total_minutes: int = hour * 60 + minute + n
	var minutes_in_day: int = 24 * 60

	# Each full day's worth of minutes that ticked past is one new day.
	var days_passed: int = total_minutes / minutes_in_day
	total_minutes = total_minutes % minutes_in_day

	var old_hour: int = hour
	hour = total_minutes / 60
	minute = total_minutes % 60

	time_changed.emit(hour, minute)
	if hour != old_hour:
		hour_changed.emit(hour)

	# Roll the day (or days, if a huge skip crossed several midnights). GameState
	# owns the day count; we just notify after each rollover.
	for _i in range(days_passed):
		GameState.advance_day()
		day_started.emit(GameState.day)

# --- Formatting ------------------------------------------------------------

## Human-friendly 12-hour clock string, e.g. "7:30 AM" or "12:05 PM". Minutes are
## zero-padded; the hour is not. Handy for a HUD label.
func get_time_string() -> String:
	var suffix: String = "AM" if hour < 12 else "PM"
	# Convert 0-23 to a 12-hour face: 0 -> 12, 13 -> 1, etc.
	var display_hour: int = hour % 12
	if display_hour == 0:
		display_hour = 12
	return "%d:%02d %s" % [display_hour, minute, suffix]

# --- Atmosphere helpers ----------------------------------------------------
# Pure getters so world/atmosphere code can interpolate by time of day WITHOUT
# duplicating the hour/minute math (or having to listen to time_changed just to
# read the clock). Additive only — no state, signals or serialization touched.

## The current time of day as a 0..1 fraction of a full 24h day. 0.0 = midnight
## (00:00), 0.5 = noon (12:00), ~0.9999 just before the next midnight. Atmosphere
## code can multiply this by TAU for a sun angle, or feed it to lookup tables.
func get_time_fraction() -> float:
	return (float(hour) * 60.0 + float(minute)) / 1440.0

## A smooth 0..1 "daylight" factor: 0 = deep night, 1 = full daytime, with soft
## dawn/dusk ramps via smoothstep so tints glide rather than snap at fixed hours.
## Dawn ramps up ~5-8h, dusk ramps down ~17-20h. Handy for lerping sky/lamp tone.
func get_day_factor() -> float:
	var h: float = float(hour) + float(minute) / 60.0
	# Night before dawn and after dusk -> 0; full day between ~8 and ~17.
	var dawn: float = smoothstep(5.0, 8.0, h)
	var dusk: float = 1.0 - smoothstep(17.0, 20.0, h)
	return clampf(minf(dawn, dusk), 0.0, 1.0)

# --- Auto-pause wiring -----------------------------------------------------
# These are called by the UI signals connected in _ready. We pause on open and
# resume on close. Keeping them as named methods (rather than lambdas) makes the
# connections easy to read and disconnect later if needed.

func _on_ui_blocked() -> void:
	# Refcounted: only the FIRST opener actually stops time.
	_pause_holders += 1
	if _pause_holders == 1:
		pause()

func _on_ui_unblocked() -> void:
	# Refcounted: only the LAST closer resumes, so closing one menu while another
	# is still open keeps time stopped. clampi guards against any spurious extra
	# close signal driving the count negative (which would never resume).
	_pause_holders = maxi(_pause_holders - 1, 0)
	if _pause_holders == 0:
		resume()

# --- Save / load -----------------------------------------------------------
# A single dictionary snapshot, mirroring the other systems. The save system
# gathers one of these from each autoload and writes them out together. We don't
# store the day here — that comes from GameState's own capture_state().

func capture_state() -> Dictionary:
	return {
		"hour": hour,
		"minute": minute,
		"paused": paused,
	}

func restore_state(data: Dictionary) -> void:
	# Route through set_time so signals fire and listeners refresh on load.
	set_time(data.get("hour", start_hour), data.get("minute", 0))
	# Pause is purely a function of which blocking UI is OPEN, tracked by the
	# refcount _pause_holders — which is NOT serialized, so it is always 0 right
	# after a load. Saving is normally done from the pause menu (which calls
	# Clock.pause()), so the snapshot's `paused` is almost always true; restoring
	# that true with zero holders would freeze time FOREVER (nothing is left open
	# to drive a resume). So reset to running on load and let whatever menu is/gets
	# opened re-pause through the normal refcounted path.
	_pause_holders = 0
	paused = false
