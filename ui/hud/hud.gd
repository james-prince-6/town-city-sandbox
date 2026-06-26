# hud.gd
# Autoload singleton (registered as "HUD", pointing at hud.tscn).
#
# The always-on heads-up display. Like InventoryUI it owns NO game state of its
# own — it is a pure VIEW. It listens to the gameplay autoloads (PlayerStats,
# GameState, Clock, Hotbar, Inventory) and redraws whatever they tell it. If you
# want to change a value, change it on those systems; the HUD will follow.
#
# It sits on CanvasLayer layer 5, deliberately BELOW the bag (InventoryUI, layer
# 10) and dialogue, so a full-screen menu draws over it. process_mode = ALWAYS so
# the bars/clock stay readable even while the game is paused by a menu.
#
# Layout: health/stamina/money pinned to the top-left, the day + time clock to the
# top-right, and a centred strip of hotbar slots along the bottom.

extends CanvasLayer

# --- Scene node references -------------------------------------------------
# These come from hud.tscn. The hotbar slot widgets themselves are NOT in the
# scene — we build them in code (one per Hotbar.SLOT_COUNT) and parent them to
# this container, so the slot count can change without editing the scene.
@onready var health_bar: ProgressBar = $TopLeft/HealthBar
@onready var stamina_bar: ProgressBar = $TopLeft/StaminaBar
@onready var mana_bar: ProgressBar = $TopLeft/ManaBar
@onready var money_label: Label = $TopLeft/MoneyLabel
@onready var clock_label: Label = $TopRight/ClockLabel
@onready var hotbar_strip: HBoxContainer = $BottomCenter/HotbarStrip

# Combat feedback overlays (added to hud.tscn). The crosshair is static; the flash
# and vignette are driven by health_changed below.
@onready var damage_flash: ColorRect = $DamageFlash
@onready var low_health_vignette: ColorRect = $LowHealthVignette

# Built once in _ready: one PanelContainer per hotbar slot. Index lines up with
# Hotbar.slots, so _refresh_slot(i) knows exactly which widget to redraw.
var _slot_widgets: Array[PanelContainer] = []

# --- Combat-feedback tuning ------------------------------------------------

## Below this fraction of max health the low-health vignette starts to show; it
## ramps from invisible at the threshold to full at 0 health.
const LOW_HEALTH_FRACTION: float = 0.25
## How red the vignette gets at zero health (shader `intensity`, 0..1).
const VIGNETTE_MAX_INTENSITY: float = 0.9
## Peak alpha of the red damage flash when a hit lands.
const DAMAGE_FLASH_ALPHA: float = 0.45

# Last health value we saw, so we can tell a hit (drop) apart from healing/respawn.
# -1 means "no reading yet" — the first health_changed just records the baseline.
var _last_health: float = -1.0
# Active flash tween, kept so a fresh hit can cancel the previous fade.
var _flash_tween: Tween = null

# --- Block feedback --------------------------------------------------------
# While the player blocks, the stamina bar tints (and pulses) so it's clear the drain
# is from guarding — blue normally, red when nearly out (about to guard-break).
const BLOCK_BAR_COLOR: Color = Color(0.45, 0.75, 1.0)
const BLOCK_BAR_LOW_COLOR: Color = Color(1.0, 0.4, 0.3)
## Below this stamina fraction the blocking tint turns to the red "about to break" warning.
const BLOCK_LOW_FRACTION: float = 0.25
# Cached player so we don't search the tree every frame.
var _player_ref: Node = null

func _ready() -> void:
	# Draw above the world but below the bag/dialogue, and keep ticking while a
	# menu pauses the rest of the tree.
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_hotbar_slots()
	_connect_signals()
	_pull_initial_values()

# --- Setup -----------------------------------------------------------------

# Creates the fixed set of empty hotbar slot widgets once. Their contents are
# filled in later by _refresh_slot().
func _build_hotbar_slots() -> void:
	for i in Hotbar.SLOT_COUNT:
		var slot := _make_empty_slot(i)
		hotbar_strip.add_child(slot)
		_slot_widgets.append(slot)

# Subscribe to every system the HUD mirrors. We never poll in _process; each
# system pushes us a signal when its value changes.
func _connect_signals() -> void:
	PlayerStats.health_changed.connect(_on_health_changed)
	PlayerStats.stamina_changed.connect(_on_stamina_changed)
	PlayerStats.mana_changed.connect(_on_mana_changed)
	GameState.money_changed.connect(_on_money_changed)
	GameState.day_changed.connect(_on_day_changed)
	Clock.time_changed.connect(_on_time_changed)
	Hotbar.slots_changed.connect(_on_slots_changed)
	Hotbar.selection_changed.connect(_on_selection_changed)
	Inventory.item_changed.connect(_on_item_changed)

# These autoloads almost certainly emitted their "changed" signals during their
# own _ready, BEFORE this HUD existed to hear them. So we read the current value
# of each one directly to start fully in sync.
func _pull_initial_values() -> void:
	_on_health_changed(PlayerStats.health, PlayerStats.max_health)
	_on_stamina_changed(PlayerStats.stamina, PlayerStats.max_stamina)
	_on_mana_changed(PlayerStats.mana, PlayerStats.max_mana)
	_on_money_changed(GameState.money)
	_refresh_clock_label()
	_refresh_all_slots()
	_refresh_selection()

# --- Stat bars -------------------------------------------------------------

func _on_health_changed(current: float, maximum: float) -> void:
	health_bar.max_value = maximum
	health_bar.value = current
	_update_combat_feedback(current, maximum)

# --- Combat feedback (crosshair / damage flash / low-health vignette) -------

# Reacts to every health change: pulses a red flash on a DROP (a hit), and keeps
# the edge vignette's strength in sync with how low health currently is.
func _update_combat_feedback(current: float, maximum: float) -> void:
	# A drop versus our last reading means the player took damage — flash. The very
	# first call (baseline) and any heal/respawn (rise) must NOT flash.
	if _last_health >= 0.0 and current < _last_health:
		_play_damage_flash()
	_last_health = current

	_update_low_health_vignette(current, maximum)

# Fades a full-screen red overlay in fast, then back out, so a hit reads as a
# brief pulse. A new hit restarts the pulse from the top.
func _play_damage_flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	damage_flash.color.a = DAMAGE_FLASH_ALPHA
	# Tween must keep running while the tree is paused (e.g. dying mid-pause), and
	# use real time so the pulse length is independent of Engine.time_scale.
	_flash_tween = create_tween()
	_flash_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_flash_tween.tween_property(damage_flash, "color:a", 0.0, 0.35)

# Drives the vignette shader: clear until health drops below LOW_HEALTH_FRACTION
# of max, then ramps up to VIGNETTE_MAX_INTENSITY as health approaches zero.
func _update_low_health_vignette(current: float, maximum: float) -> void:
	var mat := low_health_vignette.material as ShaderMaterial
	if mat == null:
		return
	var fraction: float = current / maximum if maximum > 0.0 else 0.0
	var intensity: float = 0.0
	if fraction < LOW_HEALTH_FRACTION:
		# 0 at the threshold, 1 at empty.
		var t: float = 1.0 - (fraction / LOW_HEALTH_FRACTION)
		intensity = clampf(t, 0.0, 1.0) * VIGNETTE_MAX_INTENSITY
	mat.set_shader_parameter("intensity", intensity)

func _on_stamina_changed(current: float, maximum: float) -> void:
	stamina_bar.max_value = maximum
	stamina_bar.value = current

func _on_mana_changed(current: float, maximum: float) -> void:
	mana_bar.max_value = maximum
	mana_bar.value = current

# Per-frame: tint/pulse the stamina bar while the player is blocking so it reads as a
# guard drain. Returns to plain white the moment blocking stops.
func _process(_delta: float) -> void:
	if not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group("player")
	var blocking: bool = is_instance_valid(_player_ref) and ("is_blocking" in _player_ref) and _player_ref.is_blocking
	if not blocking:
		stamina_bar.modulate = Color(1, 1, 1, 1)
		return
	var frac: float = stamina_bar.value / stamina_bar.max_value if stamina_bar.max_value > 0.0 else 0.0
	var base: Color = BLOCK_BAR_LOW_COLOR if frac < BLOCK_LOW_FRACTION else BLOCK_BAR_COLOR
	# Gentle pulse so it draws the eye while guarding.
	var pulse: float = 0.78 + 0.22 * sin(Time.get_ticks_msec() * 0.012)
	stamina_bar.modulate = Color(base.r * pulse, base.g * pulse, base.b * pulse, 1.0)

# --- Money -----------------------------------------------------------------

func _on_money_changed(new_amount: int) -> void:
	money_label.text = "$%d" % new_amount

# --- Clock (day + time) ----------------------------------------------------
# Both the day and the time live on this one label, so either signal just
# rebuilds the whole string from the current GameState.day and Clock time.

func _on_time_changed(_hour: int, _minute: int) -> void:
	_refresh_clock_label()

func _on_day_changed(_new_day: int) -> void:
	_refresh_clock_label()

func _refresh_clock_label() -> void:
	clock_label.text = "Day %d  %s" % [GameState.day, Clock.get_time_string()]

# --- Hotbar ----------------------------------------------------------------

# A hotbar slot's item id changed: redraw every slot (cheap, only 8) so a moved
# item leaves its old slot and appears in its new one.
func _on_slots_changed() -> void:
	_refresh_all_slots()

# The highlighted slot moved.
func _on_selection_changed(_index: int) -> void:
	_refresh_selection()

# An item count changed in the bag. If that item sits in a hotbar slot, its "xN"
# count needs updating.
func _on_item_changed(id: StringName, _new_count: int) -> void:
	for i in _slot_widgets.size():
		if Hotbar.slots[i] == id:
			_refresh_slot(i)

func _refresh_all_slots() -> void:
	for i in _slot_widgets.size():
		_refresh_slot(i)

# Rebuilds the contents of a single slot widget: icon-or-name plus count, or
# empty if the slot holds no id.
func _refresh_slot(index: int) -> void:
	var slot := _slot_widgets[index]
	# Clear out whatever the slot showed before.
	for child in slot.get_children():
		child.queue_free()

	var id: StringName = Hotbar.slots[index]
	if id == &"":
		return # Empty slot: leave it blank.

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(box)

	var item := Inventory.get_item(id)

	# Most items have no art yet, so fall back to the display name as text — the
	# same trick the bag UI uses.
	if item and item.icon:
		var icon := TextureRect.new()
		icon.texture = item.icon
		icon.custom_minimum_size = Vector2(40, 40)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		box.add_child(icon)
	else:
		var name_label := Label.new()
		name_label.text = item.display_name if item else String(id)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		name_label.add_theme_font_size_override("font_size", 11)
		box.add_child(name_label)

	# How many of this item the player is actually carrying.
	var count_label := Label.new()
	count_label.text = "x%d" % Inventory.count_of(id)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_font_size_override("font_size", 11)
	box.add_child(count_label)

# Highlights the currently selected slot and un-highlights the rest. We do this
# by toggling each slot's modulate so it works without a custom theme/StyleBox.
func _refresh_selection() -> void:
	for i in _slot_widgets.size():
		var selected := (i == Hotbar.selected_index)
		# Selected slot is bright and slightly enlarged; others are dimmed.
		_slot_widgets[i].modulate = Color(1, 1, 1, 1) if selected else Color(0.6, 0.6, 0.6, 1)
		_slot_widgets[i].scale = Vector2(1.1, 1.1) if selected else Vector2(1, 1)

# --- Slot widget factory ---------------------------------------------------

# Builds one empty hotbar slot frame. The slot number (1..8) is shown faintly in
# the corner so the player learns the number-key bindings.
func _make_empty_slot(index: int) -> PanelContainer:
	var slot := PanelContainer.new()
	slot.custom_minimum_size = Vector2(64, 64)
	# Pivot in the centre so the "selected" scale grows evenly from the middle.
	slot.pivot_offset = slot.custom_minimum_size * 0.5
	slot.tooltip_text = "Slot %d" % (index + 1)
	return slot
