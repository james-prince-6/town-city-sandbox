# player.gd
# Updated to use the new InteractionUI script for dynamic prompts.
extends CharacterBody3D

## Emitted right after the selected hotbar item is used (left-click). The held-item
## viewmodel listens to this to play a swing/recoil so attacks read on screen.
signal item_used(item)

@export_group("Movement")
@export var speed: float = 5.0
@export var sprint_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export_group("Look")
@export var mouse_sensitivity: float = 0.25
## Right-stick free-look speed, in degrees per second at full deflection.
@export var joystick_look_sensitivity: float = 220.0
## Ignore right-stick noise below this magnitude (radial deadzone).
const JOY_LOOK_DEADZONE: float = 0.15

# --- Node References ---
@onready var head = $Head
@onready var interaction_raycast = $Head/Camera3D/InteractionRayCast
@onready var interaction_ui = InteractionUI # The InteractionUI autoload (a top-level CanvasLayer).
# NOTE: the old $InteractionUI CHILD was a plain Control parented under the player, which lives
# inside the world SubViewport (the pixel-art render layer) — its prompt rendered off-screen there.
# The autoload draws at full screen, so the prompt is actually visible.

# --- State Variables ---
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity")
var is_in_dialogue = false
var is_menu_open = false

# Where the player started this scene. Recorded once in _ready and handed to the
# DeathScreen as the respawn FALLBACK when the scene has no "respawn_point" nodes.
var spawn_transform: Transform3D

# --- Tuning for the new player systems ---
# How much stamina sprinting burns per second of running. PlayerStats clamps to
# 0, so when it runs dry we simply fall back to normal speed.
@export var sprint_stamina_per_second: float = 20.0

# How fast a knockback impulse bleeds off, in metres/second per second. A higher value
# makes a shove snappier (shorter slide); lower makes it carry farther.
@export var knockback_decay: float = 25.0

# Active horizontal knockback impulse (world space). Set by apply_knockback() when an
# attack lands, added on top of movement each frame, and damped back toward zero.
var _knockback_velocity: Vector3 = Vector3.ZERO

# --- Defensive moves -------------------------------------------------------
# Dodge (the PRIMARY defence): a quick stamina-gated dash with invincibility frames —
# time it right and you take the hit's nothing. Block (secondary) is handled in _on_hurt.
@export_group("Dodge")
## Dash speed during a dodge (m/s). Tuned up for a snappy, committed lunge (~3.6 m).
@export var dodge_speed: float = 18.0
## How long the dash lasts (seconds).
@export var dodge_duration: float = 0.2
## Invincibility window (seconds); a touch longer than the dash so the entry/exit are safe.
@export var dodge_iframes: float = 0.28
## Stamina spent per dodge — cheap enough to lean on dodging as the main defence.
@export var dodge_stamina_cost: float = 18.0
## Minimum gap between dodges (seconds) on top of the dash duration.
@export var dodge_cooldown: float = 0.35

## Camera-feel during a dodge: roll (lean) into the dash, a quick FOV kick for speed,
## and a small downward dip — sells the move in first person without an avatar.
@export var dodge_lean_degrees: float = 9.0
@export var dodge_fov_kick: float = 10.0
@export var dodge_dip: float = 0.12

## Extra camera-feel for traversal & stance. All of these ride on the SAME camera-feel
## lerp targets as the dodge kick (summed, not overwritten) so they compose cleanly.
@export_group("Camera Feel")
## Extra FOV added while sprinting at full speed, for a sense of pace. Eases in/out via the lerp.
@export var sprint_fov_kick: float = 6.0
## Grace window (seconds) after walking off a ledge during which a jump still fires. Pure help.
@export var coyote_time: float = 0.1
## Downward camera dip (metres) on a hard landing, scaled by fall time. Snaps down then eases back.
@export var landing_dip_amount: float = 0.08
## FOV change while blocking (negative = narrower, a defensive squint that pops back on release).
@export var block_fov_shift: float = -4.0
## Camera drop (metres) while blocking, to sell a defensive crouch.
@export var block_height_shift: float = 0.08

@export_group("Block")
## Fraction of the normal stamina cost a blocked hit charges (0.5 = half cost). Lowering it
## lets a raised guard soak more damage per point of stamina, so blocking is an active payoff
## rather than a pure stopgap. The blocked hit also shoves the attacker back (see
## HurtBox.block_shove_force on the player's hurtbox).
@export_range(0.05, 1.0) var block_stamina_cost_mult: float = 0.5

var _dodge_time_left: float = 0.0
var _iframe_time_left: float = 0.0
var _dodge_cooldown_left: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO

# Camera-feel state (captured in _ready; restored continuously by _update_camera_feel).
var _cam_base_fov: float = 75.0
var _cam_base_y: float = 0.0
var _cam_base_x: float = 0.0
var _lean_target_deg: float = 0.0
# View-bob state: a phase advanced by ground speed, plus an amplitude eased in/out so the bob
# ramps up as you walk/sprint and fades smoothly when you stop or a menu opens.
var _bob_phase: float = 0.0
var _bob_amp: float = 0.0
# The first-person held-item viewmodel (created in _ready); we push it the walk bob each frame
# for a weightier hand sway on top of the camera bob it already inherits.
var _held_display: Node3D = null
## Radians of bob phase advanced per metre travelled (tunes how fast the bob cycles).
const BOB_FREQ: float = 1.6
## Camera bob magnitudes (metres) — kept slight so it reads as life, not seasickness.
const BOB_CAM_VERTICAL: float = 0.035
const BOB_CAM_HORIZONTAL: float = 0.022

## True while holding block AND the held item can block (block_modifier > 0). Read in
## _on_hurt to soak front hits for stamina.
var is_blocking: bool = false

# Footstep bookkeeping: metres travelled on the ground since the last step sound.
var _step_accum: float = 0.0
const STEP_DISTANCE: float = 2.2
# For the landing thud: track ground contact and how long we've been airborne, so a real fall
# lands with a step but a tiny hop/step-down doesn't.
var _was_on_floor: bool = true
var _air_time: float = 0.0
const LAND_AIR_TIME: float = 0.2
## Air-time (seconds) at which a landing reads as FULL intensity (max hitstop/shake/thud). A
## drop this long or longer hits hardest; shorter falls scale down toward LAND_AIR_TIME.
const LANDING_FULL_AIR_TIME: float = 0.9

@export_group("Footsteps")
## How far (m) to probe straight down for the surface under the player before a footstep, so
## the step can be pitched/volumed to what we're walking on. Falls back to the plain step on a miss.
@export var footstep_ray_length: float = 1.5
## Per-surface footstep modifiers: surface key (StringName) -> Vector2(pitch_center, volume_db
## offset). The surface is read from the collider under the player — its "surface_type" meta if
## present, else the first of these keys it is in the group of. Unknown/undetected surfaces use
## the plain footstep, so this is purely additive: populate it as world colliders get tagged.
@export var footstep_surface_mods: Dictionary = {
	&"grass": Vector2(1.05, -3.0),
	&"stone": Vector2(0.92, 1.0),
	&"rock": Vector2(0.90, 1.0),
	&"wood": Vector2(1.00, 0.0),
	&"metal": Vector2(0.85, 2.0),
	&"sand": Vector2(1.15, -5.0),
	&"snow": Vector2(1.20, -6.0),
	&"water": Vector2(1.25, -4.0),
}

# Stamina-dry warning: remember last frame's stamina so we can fire a one-shot cue the moment
# it transitions from >0 to empty during active use (sprint/dodge/block). Seeded in _ready.
var _prev_stamina: float = 1.0

# Coyote time: seconds of grace left after leaving the ground during which a jump still registers.
# A time-left counter (NOT a cooldown), so it starts at 0 — refilled to coyote_time while grounded.
var _coyote_time_left: float = 0.0
# Landing dip: current downward camera offset (metres) from the last hard landing, eased back to 0.
var _landing_dip: float = 0.0
## Seconds for the landing dip to ease back up to rest.
const LANDING_DIP_TIME: float = 0.15

# When a menu/dialogue closes, the same button that closed it (e.g. B = ui_cancel AND
# dodge, A = ui_accept AND jump) is still "just pressed" this frame. Polled gameplay
# actions ignore set_input_as_handled, so we suppress them for a few frames after any
# UI un-blocks to stop the close press from leaking into a dodge/jump.
var _suppress_action_frames: int = 0
# Status effects on the player (burn/chill/poison); chill slows movement. Untyped + instanced
# via load() so this script never depends on the StatusReceiver global class being registered.
var _status = null
var _was_ui_blocking: bool = false

# True whenever any blocking UI (dialogue or an open menu) has control. Movement,
# camera look, and world interaction all pause while this is true.
func _is_ui_blocking() -> bool:
	return is_in_dialogue or is_menu_open

# Captures the mouse for gameplay, or frees it when a UI needs the cursor.
func _refresh_mouse_mode() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE if _is_ui_blocking() else Input.MOUSE_MODE_CAPTURED)

func _ready():
	# Join the "player" group so global systems (e.g. SceneManager) can locate
	# the player without hard-coded node paths.
	add_to_group("player")
	# Remember where we spawned so DeathScreen can drop us back here on respawn
	# when the current scene defines no "respawn_point" markers.
	spawn_transform = global_transform
	# Route incoming combat damage (enemy attacks hit this HurtBox) to PlayerStats.
	var hurtbox := get_node_or_null("HurtBox")
	if hurtbox:
		hurtbox.hit.connect(_on_hurt)
	# Status effects (burn/chill/poison). Named "StatusReceiver" so an attacker's HitBox finds it
	# next to our HurtBox; it ticks DoT into PlayerStats and slows us while chilled.
	_status = load("res://components/status_receiver.gd").new()
	_status.name = "StatusReceiver"
	add_child(_status)
	# The global Dialogue autoload owns the conversation UI. We just react to it
	# starting/ending so we can stop moving and free the mouse.
	Dialogue.dialogue_started.connect(_on_dialogue_started)
	Dialogue.dialogue_ended.connect(_on_dialogue_ended)
	# Same idea for the inventory bag.
	InventoryUI.opened.connect(_on_menu_opened)
	InventoryUI.closed.connect(_on_menu_closed)
	# The brewing menu is another blocking UI; treat it exactly like the inventory
	# so it stops movement and frees the mouse while it's open.
	BrewingUI.opened.connect(_on_menu_opened)
	BrewingUI.closed.connect(_on_menu_closed)
	# The shop menu is the same kind of blocking UI; connect it too so trading
	# stops movement and frees the mouse just like the inventory and brewing menus.
	ShopUI.opened.connect(_on_menu_opened)
	ShopUI.closed.connect(_on_menu_closed)
	# The house upgrade menu (opened at the home upgrade station) is the same kind of
	# blocking UI; connect it too so improving your home stops movement and frees the
	# mouse just like the shop and brewing menus.
	UpgradeUI.opened.connect(_on_menu_opened)
	UpgradeUI.closed.connect(_on_menu_closed)
	# The skill tree overlay is another blocking UI; treat it exactly like the others so
	# opening it stops movement and frees the mouse (and recaptures on close).
	SkillTreeUI.opened.connect(_on_menu_opened)
	SkillTreeUI.closed.connect(_on_menu_closed)
	# The crafting station menu (smelter/workbench/cooking/bar) is a blocking menu too.
	CraftingUI.opened.connect(_on_menu_opened)
	CraftingUI.closed.connect(_on_menu_closed)
	# The unified tabbed Player Menu (inventory / skills / crafting / map).
	PlayerMenu.opened.connect(_on_menu_opened)
	PlayerMenu.closed.connect(_on_menu_closed)
	# Death handling lives in the DeathScreen autoload now (it connects to
	# PlayerStats.died, shows the "You Died" overlay, and owns respawn). The player
	# only needs to expose where it started via get_spawn_transform(), so we do NOT
	# connect to PlayerStats.died here — that would double-handle the death.
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	interaction_ui.hide_prompt()
	# Spawn the first-person held-item viewmodel under the camera. It watches the
	# Hotbar and shows the selected item's 3D model in hand.
	_held_display = load("res://entities/player/held_item_display.gd").new()
	$Head/Camera3D.add_child(_held_display)
	# Remember the camera's resting FOV / height / x so the dodge feel + view bob return to them.
	var cam := get_camera()
	_cam_base_fov = cam.fov
	_cam_base_y = cam.position.y
	_cam_base_x = cam.position.x
	# Seed the stamina-warning tracker to the current pool so we don't fire a spurious cue on
	# the very first frame.
	_prev_stamina = PlayerStats.stamina

func _unhandled_input(event):
	# A blocking UI (dialogue / inventory) swallows all gameplay input.
	if _is_ui_blocking():
		return

	if event is InputEventMouseMotion:
		rotate_y(deg_to_rad(-event.relative.x * mouse_sensitivity))
		head.rotate_x(deg_to_rad(-event.relative.y * mouse_sensitivity))
		head.rotation.x = clamp(head.rotation.x, deg_to_rad(-90), deg_to_rad(90))
		return

	_handle_hotbar_input(event)
	_handle_use_item(event)

# Number keys 1-8 pick a hotbar slot directly; the mouse wheel steps through
# slots. Hotbar wraps the index, so we don't have to bounds-check here.
func _handle_hotbar_input(event: InputEvent) -> void:
	# hotbar_1 maps to slot index 0, hotbar_2 to 1, and so on.
	for i in range(Hotbar.SLOT_COUNT):
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			Hotbar.select(i)
			return
	if event.is_action_pressed("hotbar_next"):
		Hotbar.select_next()
	elif event.is_action_pressed("hotbar_prev"):
		Hotbar.select_prev()

# Left mouse (use_item) "uses" the selected hotbar item. Behaviour is polymorphic:
# each Item subclass implements use(player) — a weapon swings/fires, a consumable
# applies or throws its effect, a plain item does nothing. This keeps all combat
# behaviour in the item classes (entities/items/...) instead of here.
func _handle_use_item(event: InputEvent) -> void:
	if not event.is_action_pressed("use_item"):
		return
	var item: Item = Hotbar.get_selected_item()
	if item == null:
		return
	item.use(self)
	# Tell the viewmodel to animate the swing/recoil for this use.
	item_used.emit(item)

## The first-person camera. Combat items use this to aim (raycast origin/direction
## or a projectile spawn point).
func get_camera() -> Camera3D:
	return $Head/Camera3D

# Incoming damage from enemy attacks: the player's HurtBox forwards a DamageInfo
# here, and we spend it against PlayerStats' health pool.
func _on_hurt(info: DamageInfo) -> void:
	# Dodge i-frames: a well-timed dodge negates the hit entirely (no damage, no shove).
	if _iframe_time_left > 0.0:
		return

	var amount: float = info.amount

	# BLOCK (secondary defence): soak front hits by paying stamina proportional to the
	# damage, scaled by the held item's block_modifier. You only block what your stamina
	# can pay for — when it runs out mid-hit, the rest gets through (a guard break). This
	# keeps blocking a costly stopgap, not a wall; dodging is the real answer.
	if is_blocking and _hit_from_front(info):
		var item: Item = Hotbar.get_selected_item()
		var mod: float = item.block_modifier if item != null else 0.0
		if mod > 0.0:
			# Block payoff: charge only block_stamina_cost_mult of the raw stamina, so the same
			# stamina pool now soaks proportionally MORE damage (e.g. ~2x at the 0.5 default).
			var cost_mult: float = maxf(block_stamina_cost_mult, 0.01)
			var max_blockable: float = PlayerStats.stamina / (mod * cost_mult)
			var blocked: float = min(amount, max_blockable)
			if blocked > 0.0:
				PlayerStats.use_stamina(blocked * mod * cost_mult)
				amount -= blocked
				CombatFeel.play_block()
				# A blocked blow barely budges you.
				apply_knockback(info.hit_direction, info.knockback * 0.25)
				if amount <= 0.0:
					return

	# Thick Skin (survival tree): ignore a fraction of whatever still lands.
	amount = amount * (1.0 - Progression.damage_reduction())
	# Second Wind's clutch save is handled inside PlayerStats.take_damage.
	PlayerStats.take_damage(amount)
	# Shove the player along the hit direction (full knockback for unblocked hits).
	apply_knockback(info.hit_direction, info.knockback)

# Start a knockback impulse: a horizontal shove of `force` m/s along `direction`. It is
# integrated into movement in handle_movement() and damped by knockback_decay each frame.
# This is the body side of the shared knockback contract (HitBox -> DamageInfo -> here).
func apply_knockback(direction: Vector3, force: float) -> void:
	if force <= 0.0:
		return
	var dir: Vector3 = direction
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	_knockback_velocity = dir.normalized() * force

func _physics_process(delta):
	_tick_defensive_timers(delta)
	_check_stamina_warning()
	# When a menu/dialogue just closed, suppress polled actions for a few frames so the
	# closing press (B = cancel + dodge, A = accept + jump) doesn't leak into gameplay.
	var blocking := _is_ui_blocking()
	if _was_ui_blocking and not blocking:
		_suppress_action_frames = 3
	_was_ui_blocking = blocking
	if _suppress_action_frames > 0:
		_suppress_action_frames -= 1
	if not blocking:
		_update_block()
		_try_dodge()
		handle_movement(delta)
		_update_footsteps(delta)

	_update_camera_feel(delta)
	_handle_joystick_look(delta)
	handle_interaction()

func handle_movement(delta):
	# Coyote time: keep a small grace window after walking off a ledge during which a jump
	# still fires. Refilled while grounded, drained in the air.
	if is_on_floor():
		_coyote_time_left = coyote_time
	else:
		_coyote_time_left = maxf(_coyote_time_left - delta, 0.0)
		velocity.y -= gravity * delta
	# Dodge dash overrides steering for its brief window (gravity still applies). The
	# i-frames that make it a defence are handled in _on_hurt.
	if _dodge_time_left > 0.0:
		velocity.x = _dodge_dir.x * dodge_speed
		velocity.z = _dodge_dir.z * dodge_speed
		move_and_slide()
		return
	if Input.is_action_just_pressed("jump") and _coyote_time_left > 0.0 and _suppress_action_frames == 0:
		velocity.y = jump_velocity
		_coyote_time_left = 0.0  # consume the grace so one press = one jump
	var input_dir = Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var direction = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	# Sprinting only counts when we're actually moving, and it costs stamina.
	# use_stamina returns false (and spends nothing) once we're empty, so the
	# player smoothly drops back to normal speed instead of sprinting for free.
	# Raising a block slows you down and rules out sprinting.
	var current_speed := speed
	if is_blocking:
		current_speed = speed * 0.45
	elif Input.is_action_pressed("sprint") and direction != Vector3.ZERO:
		if PlayerStats.use_stamina(sprint_stamina_per_second * delta):
			current_speed = sprint_speed
	# A chill status slows the player too.
	if _status != null:
		current_speed *= _status.speed_multiplier()
	if direction:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed)
		velocity.z = move_toward(velocity.z, 0, speed)
	# Layer any active knockback impulse on top of intended movement so a shove carries the
	# player even while they steer, then let move_and_slide resolve it against the world.
	velocity.x += _knockback_velocity.x
	velocity.z += _knockback_velocity.z
	move_and_slide()
	# Bleed the impulse off so the shove is a brief lurch, not permanent drift.
	_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, knockback_decay * delta)

func handle_interaction():
	# No prompts or interactions while a conversation or menu is open.
	if _is_ui_blocking():
		interaction_ui.hide_prompt()
		return

	# is_colliding() can be true while get_collider() is null for a frame (e.g. the
	# target was freed this frame), so always null-check the collider before use.
	var collider = interaction_raycast.get_collider() if interaction_raycast.is_colliding() else null
	if collider != null and collider.has_method("get_interaction_prompt"):
		# InteractionUI now prepends the device-aware button glyph itself (E / X).
		interaction_ui.show_prompt(collider.get_interaction_prompt())
	else:
		interaction_ui.hide_prompt()

	if Input.is_action_just_pressed("interact") and collider != null and collider.has_method("interact"):
		collider.interact(self)

func _on_dialogue_started():
	is_in_dialogue = true
	interaction_ui.hide_prompt()
	_refresh_mouse_mode()

func _on_dialogue_ended():
	is_in_dialogue = false
	_refresh_mouse_mode()

func _on_menu_opened():
	is_menu_open = true
	interaction_ui.hide_prompt()
	_refresh_mouse_mode()

func _on_menu_closed():
	is_menu_open = false
	_refresh_mouse_mode()

# Right-stick free-look, mirroring the mouse look in _unhandled_input. Respects the
# same UI-blocking guard so the camera holds still while a menu/dialogue is open.
func _handle_joystick_look(delta: float) -> void:
	if _is_ui_blocking():
		return
	var look := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	)
	if look.length() < JOY_LOOK_DEADZONE:
		return
	rotate_y(deg_to_rad(-look.x * joystick_look_sensitivity * delta))
	head.rotate_x(deg_to_rad(-look.y * joystick_look_sensitivity * delta))
	head.rotation.x = clamp(head.rotation.x, deg_to_rad(-90), deg_to_rad(90))

# --- Defensive moves -------------------------------------------------------

# Count down the dodge / i-frame / cooldown timers each physics frame.
func _tick_defensive_timers(delta: float) -> void:
	if _dodge_time_left > 0.0:
		_dodge_time_left -= delta
	if _iframe_time_left > 0.0:
		_iframe_time_left -= delta
	if _dodge_cooldown_left > 0.0:
		_dodge_cooldown_left -= delta

# Blocking is active only while the button is held AND the held item can block.
func _update_block() -> void:
	var item: Item = Hotbar.get_selected_item()
	is_blocking = Input.is_action_pressed("block") and item != null and item.block_modifier > 0.0

# Start a dodge dash if requested, grounded, off cooldown, and we can afford the stamina.
# Dashes in the movement-input direction, or backward if there's no input.
func _try_dodge() -> void:
	if not Input.is_action_just_pressed("dodge"):
		return
	if _suppress_action_frames > 0:
		return  # a menu just closed with B; don't dodge from that same press
	if _dodge_time_left > 0.0 or _dodge_cooldown_left > 0.0 or not is_on_floor():
		return
	if not PlayerStats.use_stamina(dodge_stamina_cost):
		return
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_backward")
	var dir: Vector3 = transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)
	dir.y = 0.0
	if dir.length() < 0.1:
		dir = transform.basis * Vector3(0.0, 0.0, 1.0)  # no input -> dodge straight back
	_dodge_dir = dir.normalized()
	_dodge_time_left = dodge_duration
	_iframe_time_left = dodge_iframes
	_dodge_cooldown_left = dodge_duration + dodge_cooldown
	# Lean the camera into the dash: roll toward the lateral component of the dodge.
	var lateral: float = _dodge_dir.dot(transform.basis.x)
	_lean_target_deg = -lateral * dodge_lean_degrees
	CombatFeel.play_swing()  # a quick whoosh

# True if the incoming hit comes from roughly in front of the player (so a block can
# catch it). hit_direction points from attacker toward us, so the attacker is the
# other way; we block when we're facing them.
func _hit_from_front(info: DamageInfo) -> bool:
	if info.hit_direction.length() < 0.01:
		return true  # unknown direction -> give the benefit of the doubt
	var to_attacker: Vector3 = -info.hit_direction
	to_attacker.y = 0.0
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	if to_attacker.length() < 0.01 or forward.length() < 0.01:
		return true
	return forward.normalized().dot(to_attacker.normalized()) > 0.35  # ~110 deg front cone

# Play a footstep every STEP_DISTANCE metres of ground travel (auto-faster when sprinting
# since it's distance-based). Silent while airborne, dodging, or basically still.
func _update_footsteps(delta: float) -> void:
	var on_floor: bool = is_on_floor()
	# Landing thud: a step the instant we touch down after a real fall (not a micro-hop).
	if on_floor and not _was_on_floor and _air_time > LAND_AIR_TIME:
		# Scale the impact (hitstop/shake/pitch) by air-time so a long drop lands heavier than a
		# short hop. report_landing owns the thud now; degrade to a plain step if it's missing.
		var land_intensity: float = clampf(_air_time / LANDING_FULL_AIR_TIME, 0.0, 1.0)
		if CombatFeel.has_method("report_landing"):
			CombatFeel.report_landing(land_intensity)
		else:
			CombatFeel.play_footstep()
		_step_accum = 0.0
		# Camera impact dip, scaled by how long we were falling (a longer drop hits harder).
		_landing_dip = clampf(landing_dip_amount * (_air_time / LAND_AIR_TIME), 0.05, 0.15)
	_was_on_floor = on_floor
	_air_time = 0.0 if on_floor else _air_time + delta
	if not on_floor or _dodge_time_left > 0.0:
		_step_accum = 0.0
		return
	var hspeed: float = Vector2(velocity.x, velocity.z).length()
	if hspeed < 0.5:
		_step_accum = 0.0
		return
	_step_accum += hspeed * delta
	if _step_accum >= STEP_DISTANCE:
		_step_accum = 0.0
		_emit_footstep()

# Play a footstep, varied by the surface underfoot. Raycast straight down; if it hits a
# collider tagged with a known surface (a "surface_type" meta or a matching group), play the
# step with that surface's pitch/volume modifiers, otherwise the plain footstep.
func _emit_footstep() -> void:
	var surf := _detect_surface()
	if surf != &"" and footstep_surface_mods.has(surf) and CombatFeel.has_method("play_footstep_modulated"):
		var mod: Vector2 = footstep_surface_mods[surf]
		CombatFeel.play_footstep_modulated(mod.x, mod.y)
		return
	CombatFeel.play_footstep()

# Identify the surface under the player for footstep variation. Returns the surface key
# (StringName) or &"" when nothing usable is underfoot. Cheap: one short downward ray, run only
# on a step (every STEP_DISTANCE metres), never per frame.
func _detect_surface() -> StringName:
	var world := get_world_3d()
	if world == null:
		return &""
	var space := world.direct_space_state
	if space == null:
		return &""
	var from: Vector3 = global_position
	var to: Vector3 = from + Vector3.DOWN * footstep_ray_length
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var excludes: Array[RID] = [get_rid()]
	query.exclude = excludes
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return &""
	var collider = hit.get("collider")
	if collider == null or not (collider is Node):
		return &""
	# An explicit tag wins, so a designer can label a surface directly on its collider.
	if collider.has_meta(&"surface_type"):
		return StringName(str(collider.get_meta(&"surface_type")))
	# Otherwise match the collider's groups against the known surface keys.
	for key in footstep_surface_mods:
		if collider.is_in_group(StringName(key)):
			return StringName(key)
	return &""

# Fire a one-shot warning the moment stamina runs dry mid-use (sprint/dodge/block draining it
# from >0 to empty). Regen back above 0 re-arms it. The cue itself is owned by CombatFeel and
# no-ops gracefully while its sound pool is empty (assets pending).
func _check_stamina_warning() -> void:
	var s: float = PlayerStats.stamina
	if _prev_stamina > 0.0 and s <= 0.0 and CombatFeel.has_method("play_stamina_warning"):
		CombatFeel.play_stamina_warning()
	_prev_stamina = s

# First-person "dodge animation": roll the camera into the dash, kick the FOV, and dip
# the view, all eased back to rest. Driven by the dodge timer so it self-returns; the
# roll target decays independently. Runs every frame so it always settles to neutral.
func _update_camera_feel(delta: float) -> void:
	var cam := get_camera()
	if cam == null:
		return
	# 1.0 at the start of a dodge, falling to 0 as the dash ends (0 when not dodging).
	var f: float = 0.0
	if dodge_duration > 0.0 and _dodge_time_left > 0.0:
		f = clampf(_dodge_time_left / dodge_duration, 0.0, 1.0)
	# Walk bob: a slight camera sway synced to footstep cadence, folded into the same lerp
	# targets so it composes with the dodge dip instead of fighting it.
	_update_bob(delta)
	var bob_y: float = sin(_bob_phase * 2.0) * _bob_amp * BOB_CAM_VERTICAL
	var bob_x: float = cos(_bob_phase) * _bob_amp * BOB_CAM_HORIZONTAL
	var w: float = clampf(delta * 14.0, 0.0, 1.0)  # smoothing weight
	# Compose the camera-feel offsets ADDITIVELY so sprint / landing / block stack with the
	# dodge kick instead of overwriting it; the shared lerp eases every one of them in/out.
	# Sprint: a small FOV push while actually moving at full sprint speed on the ground.
	var hspeed: float = Vector2(velocity.x, velocity.z).length()
	var sprinting: bool = Input.is_action_pressed("sprint") and is_on_floor() and hspeed >= sprint_speed * 0.95 and not is_blocking
	var sprint_fov: float = sprint_fov_kick if sprinting else 0.0
	# Block stance: narrow the FOV and drop the view to read as a defensive crouch.
	var block_fov: float = block_fov_shift if is_blocking else 0.0
	var block_y: float = block_height_shift if is_blocking else 0.0
	# Landing dip eases back up to rest over ~LANDING_DIP_TIME seconds after a hard landing.
	if _landing_dip > 0.0:
		_landing_dip = move_toward(_landing_dip, 0.0, (0.15 / LANDING_DIP_TIME) * delta)
	var fov_target: float = _cam_base_fov + dodge_fov_kick * f + sprint_fov + block_fov
	var y_target: float = _cam_base_y - dodge_dip * f + bob_y - _landing_dip - block_y
	cam.fov = lerpf(cam.fov, fov_target, w)
	cam.position.y = lerpf(cam.position.y, y_target, w)
	cam.position.x = lerpf(cam.position.x, _cam_base_x + bob_x, w)
	# Roll (lean): ease toward the target, and bleed the target back to upright.
	_lean_target_deg = move_toward(_lean_target_deg, 0.0, dodge_lean_degrees * 5.0 * delta)
	cam.rotation.z = lerp_angle(cam.rotation.z, deg_to_rad(_lean_target_deg), w)
	# Push a stronger bob to the held item so the weapon visibly sways in hand (it sits under the
	# camera, so this rides on top of the camera bob for a sense of weight).
	if is_instance_valid(_held_display) and _held_display.has_method("apply_walk_bob"):
		_held_display.apply_walk_bob(_bob_phase, _bob_amp)

# Advance the view-bob phase by ground speed and ease its amplitude in/out: the bob ramps up
# while walking/sprinting on the ground and fades when you stop, jump, or a menu opens.
func _update_bob(delta: float) -> void:
	var hspeed: float = Vector2(velocity.x, velocity.z).length()
	var moving: bool = is_on_floor() and hspeed > 0.5 and not _is_ui_blocking()
	var target_amp: float = 0.0
	if moving:
		# Grow the bob with speed (a floor so a slow creep still bobs a little), full at sprint.
		target_amp = clampf(hspeed / sprint_speed, 0.35, 1.0)
		_bob_phase += hspeed * delta * BOB_FREQ
		if _bob_phase > TAU * 1000.0:
			_bob_phase -= TAU * 1000.0
	_bob_amp = lerpf(_bob_amp, target_amp, clampf(delta * 8.0, 0.0, 1.0))

# The respawn FALLBACK location: where the player stood when the scene loaded.
# DeathScreen calls this only when the scene has no "respawn_point" markers.
func get_spawn_transform() -> Transform3D:
	return spawn_transform
