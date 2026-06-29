# hud.gd
# Autoload singleton (registered as "HUD", pointing at hud.tscn).
#
# The always-on heads-up display in the Town City sticker style. Like InventoryUI it
# owns NO game state of its own — it is a pure VIEW. It listens to the gameplay
# autoloads (PlayerStats, GameState, Clock, Hotbar, Inventory) and redraws whatever
# they tell it. To change a value, change it on those systems; the HUD follows.
#
# Layout (see hud.tscn):
#   - top-left info strip: clock + day + money
#   - three stat bars (HP red / SP green / MP purple), each with an ink icon well
#   - one unified hotbar pinned bottom-centre; the selected cell brightens
#   - a centre crosshair, plus damage-flash + low-stat vignette overlays
#
# It sits on CanvasLayer layer 5, deliberately BELOW the bag (PlayerMenu) and dialogue,
# so a full-screen menu draws over it. process_mode = ALWAYS so the bars/clock stay
# readable even while the game is paused by a menu.

extends CanvasLayer

# --- Scene node references (unique names in hud.tscn) ----------------------
@onready var health_bar: ProgressBar = %HealthBar
@onready var stamina_bar: ProgressBar = %StaminaBar
@onready var mana_bar: ProgressBar = %ManaBar
@onready var money_label: Label = %Money
@onready var clock_label: Label = %Clock
@onready var day_label: Label = %Day
# The whole unified hotbar bar (toggled for the suppression feature); cells live in the strip.
@onready var hotbar_panel: PanelContainer = %Hotbar
@onready var hotbar_strip: HBoxContainer = %HotbarStrip

# Combat feedback overlays. The crosshair dot is flashed on a confirmed hit; the flash
# and vignettes are driven by the stat signals below.
@onready var damage_flash: ColorRect = $DamageFlash
@onready var low_health_vignette: ColorRect = $LowHealthVignette
@onready var stamina_warning_vignette: ColorRect = get_node_or_null("StaminaWarningVignette")
@onready var crosshair_dot: ColorRect = get_node_or_null("Crosshair/Dot")

# Built once in _ready: one cell Button per hotbar slot. Index lines up with Hotbar.slots,
# so _refresh_slot(i) knows exactly which widget to redraw.
var _slot_widgets: Array[Button] = []

# Size of a single hotbar cell (matches the locked design).
const CELL_SIZE: Vector2 = Vector2(56, 52)
# Pixel size of the item thumbnail inside a cell.
const CELL_ICON: float = 38.0

# --- Combat-feedback tuning ------------------------------------------------
const LOW_HEALTH_FRACTION: float = 0.25
const VIGNETTE_MAX_INTENSITY: float = 0.9
const DAMAGE_FLASH_ALPHA: float = 0.45
const DAMAGE_FLASH_COLOR: Color = Color(0.8, 0.0, 0.0)
const LOW_STAMINA_FRACTION: float = 0.25
const STAMINA_VIGNETTE_MAX_INTENSITY: float = 0.6

# Last health value we saw, so we can tell a hit (drop) from healing/respawn.
var _last_health: float = -1.0
var _flash_tween: Tween = null
var _crosshair_tween: Tween = null

# --- Block feedback --------------------------------------------------------
const BLOCK_BAR_COLOR: Color = Color(0.45, 0.75, 1.0)
const BLOCK_BAR_LOW_COLOR: Color = Color(1.0, 0.4, 0.3)
const BLOCK_LOW_FRACTION: float = 0.25
var _player_ref: Node = null

# --- Hotbar visibility (jobs / minigames can hide the bottom bar) ----------
# shown = (NOT suppressed) OR the menu is open.
var _hotbar_suppressed: bool = false
var _menu_open: bool = false


func _ready() -> void:
	# Draw above the world but below the bag/dialogue, and keep ticking while a menu pauses.
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_hotbar_slots()
	_connect_signals()
	_pull_initial_values()
	# PlayerMenu loads AFTER the HUD, so wire its open/close on the next idle frame.
	_connect_player_menu.call_deferred()
	_update_hotbar_visibility()


# --- Setup -----------------------------------------------------------------

func _build_hotbar_slots() -> void:
	for c in hotbar_strip.get_children():
		c.queue_free()
	_slot_widgets.clear()
	for i in Hotbar.SLOT_COUNT:
		var cell := _make_cell(i)
		hotbar_strip.add_child(cell)
		_slot_widgets.append(cell)

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

func _on_stamina_changed(current: float, maximum: float) -> void:
	stamina_bar.max_value = maximum
	stamina_bar.value = current

func _on_mana_changed(current: float, maximum: float) -> void:
	mana_bar.max_value = maximum
	mana_bar.value = current


# --- Combat feedback (crosshair / damage flash / low-stat vignettes) -------

func _update_combat_feedback(current: float, maximum: float) -> void:
	if _last_health >= 0.0 and current < _last_health:
		_play_damage_flash()
	_last_health = current
	_update_low_health_vignette(current, maximum)

func _play_damage_flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	damage_flash.color = Color(DAMAGE_FLASH_COLOR.r, DAMAGE_FLASH_COLOR.g, DAMAGE_FLASH_COLOR.b, DAMAGE_FLASH_ALPHA)
	_flash_tween = create_tween()
	_flash_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_flash_tween.tween_property(damage_flash, "color:a", 0.0, 0.35)

## Pops the crosshair dot to white + 1.3x scale, then settles back, as a hit-marker.
func _flash_crosshair() -> void:
	if not is_instance_valid(crosshair_dot):
		return
	if _crosshair_tween and _crosshair_tween.is_valid():
		_crosshair_tween.kill()
	crosshair_dot.pivot_offset = crosshair_dot.size * 0.5
	crosshair_dot.color = Color(1, 1, 1, 1)
	crosshair_dot.scale = Vector2(1.3, 1.3)
	_crosshair_tween = create_tween()
	_crosshair_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_crosshair_tween.set_parallel(true)
	_crosshair_tween.tween_property(crosshair_dot, "scale", Vector2(1, 1), 0.15)
	_crosshair_tween.tween_property(crosshair_dot, "color", Color(0.957, 0.945, 0.91, 0.9), 0.15)

## A short WHITE full-screen flash for a critical hit (reuses the damage flash rect/tween).
func show_crit_flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	damage_flash.color = Color(1, 1, 1, 0.25)
	_flash_tween = create_tween()
	_flash_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_flash_tween.tween_property(damage_flash, "color:a", 0.0, 0.1)

## A golden flash on a kill: fast in, slow out.
func show_kill_flash() -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	damage_flash.color = Color(1.0, 0.85, 0.1, 0.0)
	_flash_tween = create_tween()
	_flash_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_flash_tween.tween_property(damage_flash, "color:a", 0.3, 0.05)
	_flash_tween.tween_property(damage_flash, "color:a", 0.0, 0.25)

func _update_low_health_vignette(current: float, maximum: float) -> void:
	var mat := low_health_vignette.material as ShaderMaterial
	if mat == null:
		return
	var fraction: float = current / maximum if maximum > 0.0 else 0.0
	var intensity: float = 0.0
	if fraction < LOW_HEALTH_FRACTION:
		var t: float = 1.0 - (fraction / LOW_HEALTH_FRACTION)
		intensity = clampf(t, 0.0, 1.0) * VIGNETTE_MAX_INTENSITY
	mat.set_shader_parameter("intensity", intensity)


# Per-frame: stamina warning vignette + block tint on the stamina bar.
func _process(_delta: float) -> void:
	_update_stamina_vignette()
	if not is_instance_valid(_player_ref):
		_player_ref = get_tree().get_first_node_in_group("player")
	var blocking: bool = is_instance_valid(_player_ref) and ("is_blocking" in _player_ref) and _player_ref.is_blocking
	if not blocking:
		stamina_bar.modulate = Color(1, 1, 1, 1)
		return
	var frac: float = stamina_bar.value / stamina_bar.max_value if stamina_bar.max_value > 0.0 else 0.0
	var base: Color = BLOCK_BAR_LOW_COLOR if frac < BLOCK_LOW_FRACTION else BLOCK_BAR_COLOR
	var pulse: float = 0.78 + 0.22 * sin(Time.get_ticks_msec() * 0.012)
	stamina_bar.modulate = Color(base.r * pulse, base.g * pulse, base.b * pulse, 1.0)

func _update_stamina_vignette() -> void:
	if not is_instance_valid(stamina_warning_vignette):
		return
	var mat := stamina_warning_vignette.material as ShaderMaterial
	if mat == null:
		return
	var maximum: float = stamina_bar.max_value
	var fraction: float = stamina_bar.value / maximum if maximum > 0.0 else 0.0
	var intensity: float = 0.0
	if fraction < LOW_STAMINA_FRACTION:
		var t: float = 1.0 - (fraction / LOW_STAMINA_FRACTION)
		intensity = clampf(t, 0.0, 1.0) * STAMINA_VIGNETTE_MAX_INTENSITY
	mat.set_shader_parameter("intensity", intensity)


# --- Money -----------------------------------------------------------------

func _on_money_changed(new_amount: int) -> void:
	# The "$" sign is a static label in the info strip; this is just the number.
	money_label.text = str(new_amount)


# --- Clock (day + time) ----------------------------------------------------

func _on_time_changed(_hour: int, _minute: int) -> void:
	_refresh_clock_label()

func _on_day_changed(_new_day: int) -> void:
	_refresh_clock_label()

func _refresh_clock_label() -> void:
	clock_label.text = "%s %s" % [_time_of_day_glyph(Clock.hour), Clock.get_time_string()]
	day_label.text = "DAY %d" % GameState.day

# A tiny ASCII time-of-day tag (the UI fonts have no emoji glyphs).
func _time_of_day_glyph(hour: int) -> String:
	if hour >= 5 and hour < 7:
		return "(*)"   # sunrise
	if hour >= 7 and hour < 17:
		return "(O)"   # day
	if hour >= 17 and hour < 19:
		return "(~)"   # dusk
	return "(C)"       # night


# --- Hotbar visibility -----------------------------------------------------

func set_hotbar_suppressed(suppressed: bool) -> void:
	_hotbar_suppressed = suppressed
	_update_hotbar_visibility()

func _update_hotbar_visibility() -> void:
	if hotbar_panel != null:
		hotbar_panel.visible = (not _hotbar_suppressed) or _menu_open

func _connect_player_menu() -> void:
	var pm: Node = get_node_or_null("/root/PlayerMenu")
	if pm == null:
		return
	if pm.has_signal("opened") and not pm.opened.is_connected(_on_menu_opened_hud):
		pm.opened.connect(_on_menu_opened_hud)
	if pm.has_signal("closed") and not pm.closed.is_connected(_on_menu_closed_hud):
		pm.closed.connect(_on_menu_closed_hud)

func _on_menu_opened_hud() -> void:
	_menu_open = true
	_update_hotbar_visibility()

func _on_menu_closed_hud() -> void:
	_menu_open = false
	_update_hotbar_visibility()


# --- Hotbar cells ----------------------------------------------------------

func _on_slots_changed() -> void:
	_refresh_all_slots()

func _on_selection_changed(_index: int) -> void:
	_refresh_selection()

func _on_item_changed(id: StringName, _new_count: int) -> void:
	for i in _slot_widgets.size():
		if Hotbar.slots[i] == id:
			_refresh_slot(i)

func _refresh_all_slots() -> void:
	for i in _slot_widgets.size():
		_refresh_slot(i)

# Rebuilds the contents of one cell: thumbnail + count, keeping the persistent slot number.
func _refresh_slot(index: int) -> void:
	var cell := _slot_widgets[index]
	for child in cell.get_children():
		if child.name == "SlotNumber":
			continue
		child.queue_free()

	var id: StringName = Hotbar.slots[index]
	if id == &"":
		return

	# Square content area so the thumbnail sits centred; count overlays the corner.
	var content := Control.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(content)

	var visual: Control = ItemThumbnail.make_visual(id, CELL_ICON)
	visual.position = (CELL_SIZE - Vector2(CELL_ICON, CELL_ICON)) * 0.5
	content.add_child(visual)

	var count_label := Label.new()
	count_label.theme_type_variation = &"Dim"
	count_label.text = "x%d" % Inventory.count_of(id)
	count_label.add_theme_font_size_override("font_size", 11)
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	count_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	count_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	count_label.offset_right = -2.0
	count_label.offset_bottom = -1.0
	content.add_child(count_label)

# Marks the selected cell: SlotButton's pressed style brightens it and adds the gold
# outline. No scaling — that overflowed the cell into the ink frame and read as broken.
func _refresh_selection() -> void:
	for i in _slot_widgets.size():
		var cell := _slot_widgets[i]
		cell.button_pressed = (i == Hotbar.selected_index)

# Builds one hotbar cell. SlotButton variation gives the cream/bright sticker look.
func _make_cell(index: int) -> Button:
	var cell := Button.new()
	cell.theme_type_variation = &"SlotButton"
	cell.toggle_mode = true
	cell.custom_minimum_size = CELL_SIZE
	# Selection is driven by the Hotbar autoload (number keys / scroll), not by focusing
	# the HUD — so cells don't take focus and steal it from gameplay.
	cell.focus_mode = Control.FOCUS_NONE
	cell.clip_contents = true
	cell.pivot_offset = CELL_SIZE * 0.5
	cell.tooltip_text = "Slot %d" % (index + 1)
	cell.pressed.connect(func() -> void: Hotbar.select(index))

	# Faint slot-number hint (1..8), top-left, kept across refreshes.
	var number_label := Label.new()
	number_label.name = "SlotNumber"
	number_label.theme_type_variation = &"Dim"
	number_label.text = str(index + 1)
	number_label.add_theme_font_size_override("font_size", 10)
	number_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	number_label.position = Vector2(5, 2)
	cell.add_child(number_label)
	return cell
