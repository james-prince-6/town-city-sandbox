# ui_sound.gd
# Autoload singleton (register as "UISound"). Gives the WHOLE UI a click sound with
# zero per-button wiring: it watches the scene tree and connects every BaseButton's
# `pressed` signal to a click, so any menu button — now or added later — plays a sound
# when pressed. Runs always (works while the game is paused, e.g. the pause menu).
#
# Beyond button clicks it also provides a little "audio body" to common UI/feel events,
# all wired ADDITIVELY and GUARDED so a missing autoload/signal simply means no cue:
#   * Inventory.item_gained  -> a satisfying pickup blip while foraging/looting/trading.
#   * Inventory/Dialogue UI opened/closed -> brief open/close cues.
# Every cue reuses the existing click samples (no new assets) at its own volume, so the
# whole game gets consistent, low-cost audio feedback.
extends Node

const VOLUME_DB: float = -6.0
## Pickup feedback sits a touch louder than a click so loot reads through the mix.
const PICKUP_VOLUME_DB: float = -5.0
## Menu open/close cues are intentionally quiet so they punctuate rather than nag.
const MENU_CUE_VOLUME_DB: float = -12.0

# --- Deep-polish feedback cue volumes (per-category, all tunable) -----------
## Hotbar swap chirp — a touch quieter than a button click so it reads as a light
## "tick" distinct from committing to a menu choice.
const HOTBAR_VOLUME_DB: float = -8.0
## Drinking/throwing a consumable. Its own knob so foley can be balanced apart.
const CONSUMABLE_VOLUME_DB: float = -6.0
## A finished brew/craft is a small reward moment, so it sits a bit forward.
const CRAFT_DONE_VOLUME_DB: float = -4.0
## Spending a skill point is a progression beat — bright and clearly audible.
const SKILL_VOLUME_DB: float = -4.0
## Reputation shifts (either direction) share one moderate level.
const REP_VOLUME_DB: float = -6.0
## Interaction acquire/lost are ambient awareness pips — very quiet on purpose so
## they never nag while the player sweeps the camera across many interactables.
const INTERACTION_VOLUME_DB: float = -14.0

## CraftingSystem.Status.DONE as a literal so we don't have to import the enum
## across the autoload boundary. Status values are append-only (see project
## gotchas), so DONE == 2 is stable.
const CRAFT_STATUS_DONE: int = 2

var click_sounds: Array[AudioStream] = [
	preload("res://assets/audio/ui/click_a.ogg"),
	preload("res://assets/audio/ui/click_b.ogg"),
]

## Pickup samples. Reuses the click bank for now (no dedicated foley yet); swapping in
## real pickup .oggs later is a one-line change with no other code touched.
var pickup_sounds: Array[AudioStream] = [
	preload("res://assets/audio/ui/click_a.ogg"),
	preload("res://assets/audio/ui/click_b.ogg"),
]

# --- Deep-polish cue banks -------------------------------------------------
# Each new event gets its own sample bank. Where a bank is LEFT EMPTY, the
# procedural synth fallback (_play_synth_tone) covers it so the cue is audible
# even before any dedicated .ogg lands — drop files into a bank later and they
# take over automatically with no other code change.

## Hotbar selection chirp — two variants reused from the click bank so swapping
## slots feels tactile and distinct from a menu button press.
var hotbar_sounds: Array[AudioStream] = [
	preload("res://assets/audio/ui/click_a.ogg"),
	preload("res://assets/audio/ui/click_b.ogg"),
]
## Consumable use, craft-complete, skill spend, reputation up/down, and the two
## interaction pips have no bespoke foley yet, so they ride the synth fallback.
var consumable_sounds: Array[AudioStream] = []
var craft_done_sounds: Array[AudioStream] = []
var skill_sounds: Array[AudioStream] = []
var rep_up_sounds: Array[AudioStream] = []
var rep_down_sounds: Array[AudioStream] = []
var interaction_acquire_sounds: Array[AudioStream] = []
var interaction_lost_sounds: Array[AudioStream] = []

# --- Procedural synth fallback tuning (frequencies in Hz, durations in s) ---
# Pure-code sine pips synthesised on demand when a bank above is empty. All
# tunable; values chosen so each event has a recognisable pitch contour.
@export var synth_enabled: bool = true
## Sample rate of the generated tone. 22050 is plenty for a short pip and keeps
## the per-cue buffer tiny.
@export var synth_mix_rate: float = 22050.0
## Peak amplitude (0..1) before the per-cue volume_db is applied.
@export var synth_amplitude: float = 0.35
## Fade-in time so the tone never starts on a click/pop.
@export var synth_attack: float = 0.005
## Exponential decay rate; higher = shorter, pluckier tail.
@export var synth_decay: float = 12.0

## Per-cue synth pitch/length. Ascending pitches read as "good/forward" and
## lower ones as "back/away", matching each event's meaning.
@export var hotbar_synth_freq: float = 660.0
@export var hotbar_synth_dur: float = 0.045
@export var consumable_synth_freq: float = 392.0
@export var consumable_synth_dur: float = 0.12
@export var craft_synth_freq: float = 784.0
@export var craft_synth_dur: float = 0.16
@export var skill_synth_freq: float = 880.0
@export var skill_synth_dur: float = 0.14
@export var rep_up_synth_freq: float = 740.0
@export var rep_down_synth_freq: float = 311.0
@export var rep_synth_dur: float = 0.13
@export var interact_acquire_freq: float = 880.0
@export var interact_lost_freq: float = 440.0
@export var interact_synth_dur: float = 0.04

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Hook up buttons that already exist, then everything added afterwards.
	get_tree().node_added.connect(_on_node_added)
	_connect_existing(get_tree().root)
	_connect_feedback_signals()

# Wire optional gameplay/UI signals for extra audio feedback. Every connection is
# guarded (autoload may be absent, signal may not exist), so this never hard-depends on
# another system — it just adds a cue when the source is present.
func _connect_feedback_signals() -> void:
	# Item pickup: constant satisfying feedback while looting/trading.
	var inv := get_node_or_null("/root/Inventory")
	if inv != null and inv.has_signal("item_gained"):
		if not inv.is_connected("item_gained", Callable(self, "_on_item_gained")):
			inv.connect("item_gained", Callable(self, "_on_item_gained"))

	# Inventory open/close cues.
	var inv_ui := get_node_or_null("/root/InventoryUI")
	_connect_open_close(inv_ui)

	# Dialogue start/end cues (signals are dialogue_started / dialogue_ended).
	var dlg := get_node_or_null("/root/Dialogue")
	if dlg != null:
		if dlg.has_signal("dialogue_started") and not dlg.is_connected("dialogue_started", Callable(self, "_on_menu_opened")):
			dlg.connect("dialogue_started", Callable(self, "_on_menu_opened"))
		if dlg.has_signal("dialogue_ended") and not dlg.is_connected("dialogue_ended", Callable(self, "_on_menu_closed")):
			dlg.connect("dialogue_ended", Callable(self, "_on_menu_closed"))

	# Hotbar slot swaps: a light chirp distinct from button clicks.
	var hb := get_node_or_null("/root/Hotbar")
	if hb != null and hb.has_signal("selection_changed"):
		if not hb.is_connected("selection_changed", Callable(self, "_on_hotbar_selection_changed")):
			hb.connect("selection_changed", Callable(self, "_on_hotbar_selection_changed"))

	# Crafting machines: we listen to the single state-change signal and only
	# chime when the change lands on DONE (a finished brew waiting to collect).
	var cs := get_node_or_null("/root/CraftingSystem")
	if cs != null and cs.has_signal("machine_changed"):
		if not cs.is_connected("machine_changed", Callable(self, "_on_machine_changed")):
			cs.connect("machine_changed", Callable(self, "_on_machine_changed"))

	# Skill allocation: a bright ascending chime when a point is spent. We connect
	# here rather than editing Progression, keeping that autoload untouched.
	var prog := get_node_or_null("/root/Progression")
	if prog != null and prog.has_signal("skills_changed"):
		if not prog.is_connected("skills_changed", Callable(self, "_on_skills_changed")):
			prog.connect("skills_changed", Callable(self, "_on_skills_changed"))

	# Reputation shifts: pool/pitch chosen by the sign of the (already-thresholded)
	# delta, so a clear rise vs. fall is audible.
	var rep := get_node_or_null("/root/Reputation")
	if rep != null and rep.has_signal("reputation_shifted"):
		if not rep.is_connected("reputation_shifted", Callable(self, "_on_reputation_shifted")):
			rep.connect("reputation_shifted", Callable(self, "_on_reputation_shifted"))

	# Interaction prompt acquire/lost awareness pips. NOTE: the *live* InteractionUI
	# autoload (interaction_prompt.gd) does not yet emit these; this connect is
	# guarded so it simply no-ops there. See integrator notes for activation.
	var iui := get_node_or_null("/root/InteractionUI")
	if iui != null:
		if iui.has_signal("target_acquired") and not iui.is_connected("target_acquired", Callable(self, "_on_target_acquired")):
			iui.connect("target_acquired", Callable(self, "_on_target_acquired"))
		if iui.has_signal("target_lost") and not iui.is_connected("target_lost", Callable(self, "_on_target_lost")):
			iui.connect("target_lost", Callable(self, "_on_target_lost"))

# Connect a node's "opened"/"closed" signals (if present) to the open/close cues.
func _connect_open_close(node: Node) -> void:
	if node == null:
		return
	if node.has_signal("opened") and not node.is_connected("opened", Callable(self, "_on_menu_opened")):
		node.connect("opened", Callable(self, "_on_menu_opened"))
	if node.has_signal("closed") and not node.is_connected("closed", Callable(self, "_on_menu_closed")):
		node.connect("closed", Callable(self, "_on_menu_closed"))

func _connect_existing(node: Node) -> void:
	if node is BaseButton:
		_hook(node)
	for c in node.get_children():
		_connect_existing(c)

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_hook(node)

func _hook(button: BaseButton) -> void:
	if not button.pressed.is_connected(_play_click):
		button.pressed.connect(_play_click)

# --- Feedback handlers -----------------------------------------------------

func _on_item_gained(_id: StringName, _amount: int) -> void:
	_play_random(pickup_sounds, PICKUP_VOLUME_DB)

func _on_menu_opened() -> void:
	_play_random(click_sounds, MENU_CUE_VOLUME_DB)

func _on_menu_closed() -> void:
	_play_random(click_sounds, MENU_CUE_VOLUME_DB)

# Hotbar slot changed — light tactile chirp.
func _on_hotbar_selection_changed(_index: int) -> void:
	_play_cue(hotbar_sounds, HOTBAR_VOLUME_DB, hotbar_synth_freq, hotbar_synth_dur)

## Public hook called (guarded) by ConsumableItem after a successful use. Exposed
## as a method because consumables are shared Resources we can't connect a signal
## to from here — they reach UISound by autoload path instead.
func play_consumable_use_cue() -> void:
	_play_cue(consumable_sounds, CONSUMABLE_VOLUME_DB, consumable_synth_freq, consumable_synth_dur)

# A crafting machine changed state — chime only when it just became DONE.
func _on_machine_changed(machine_id: StringName) -> void:
	var cs := get_node_or_null("/root/CraftingSystem")
	if cs == null or not cs.has_method("get_status"):
		return
	# Untyped: get_status() returns the Status enum across a duck-typed call, which
	# the parser sees as Variant (never infer a typed local from that — gotcha #1).
	var status = cs.get_status(machine_id)
	if int(status) == CRAFT_STATUS_DONE:
		_play_cue(craft_done_sounds, CRAFT_DONE_VOLUME_DB, craft_synth_freq, craft_synth_dur)

# A skill point was (re)allocated — bright progression chime.
func _on_skills_changed() -> void:
	_play_cue(skill_sounds, SKILL_VOLUME_DB, skill_synth_freq, skill_synth_dur)

# Reputation moved enough to surface — pitch up for gains, down for losses.
func _on_reputation_shifted(_npc_id: StringName, delta: int, _value: int) -> void:
	if delta >= 0:
		_play_cue(rep_up_sounds, REP_VOLUME_DB, rep_up_synth_freq, rep_synth_dur)
	else:
		_play_cue(rep_down_sounds, REP_VOLUME_DB, rep_down_synth_freq, rep_synth_dur)

# Began / stopped looking at an interactable — quiet ascending/descending pip.
func _on_target_acquired(_target = null) -> void:
	_play_cue(interaction_acquire_sounds, INTERACTION_VOLUME_DB, interact_acquire_freq, interact_synth_dur)

func _on_target_lost(_target = null) -> void:
	_play_cue(interaction_lost_sounds, INTERACTION_VOLUME_DB, interact_lost_freq, interact_synth_dur)

# --- Playback --------------------------------------------------------------

func _play_click() -> void:
	_play_random(click_sounds, VOLUME_DB)

# Play a cue from `sounds`, or — when that bank is empty — synthesise a fallback
# pip at `synth_freq`/`synth_dur` so the event is always audible. This is what lets
# every new feedback hook work today, before any dedicated .ogg exists.
func _play_cue(sounds: Array[AudioStream], db: float, synth_freq: float, synth_dur: float) -> void:
	if not sounds.is_empty():
		_play_random(sounds, db)
		return
	_play_synth_tone(synth_freq, synth_dur, db)

# Generate and play a short sine pip entirely in code (no asset needed). Used as
# the empty-bank fallback above. The tone gets a quick attack + exponential decay
# so it reads as a soft "blip" with no start/end clicks. Pure and side-effect free
# apart from the one-shot player it spawns; zero risk if synth_enabled is false.
func _play_synth_tone(freq: float, dur: float, db: float) -> void:
	if not synth_enabled or freq <= 0.0 or dur <= 0.0:
		return
	var rate: int = int(synth_mix_rate)
	if rate <= 0:
		return
	var count: int = int(dur * float(rate))
	if count <= 0:
		return
	var bytes := PackedByteArray()
	bytes.resize(count * 2)  # 16-bit mono => 2 bytes per sample
	var omega: float = TAU * freq
	for i in count:
		var t: float = float(i) / float(rate)
		# Linear attack ramp then exponential decay envelope.
		var attack: float = 1.0
		if synth_attack > 0.0:
			attack = minf(t / synth_attack, 1.0)
		var env: float = attack * exp(-t * synth_decay)
		var sample: float = sin(omega * t) * env * synth_amplitude
		var s16: int = int(clampf(sample, -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, s16)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	wav.data = bytes
	_play_stream(wav, db)

# Pick a random stream from `sounds` and play it at `volume_db`.
func _play_random(sounds: Array[AudioStream], volume_db: float = VOLUME_DB) -> void:
	if sounds.is_empty():
		return
	var stream: AudioStream = sounds[randi() % sounds.size()]
	_play_stream(stream, volume_db)

# Spawn a one-shot player that frees itself when finished. Routes to SFX when available.
func _play_stream(stream: AudioStream, volume_db: float) -> void:
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	if AudioServer.get_bus_index(&"SFX") != -1:
		p.bus = &"SFX"
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
