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
@onready var interaction_ui = $InteractionUI # This node now has the interaction_ui.gd script

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

var _dodge_time_left: float = 0.0
var _iframe_time_left: float = 0.0
var _dodge_cooldown_left: float = 0.0
var _dodge_dir: Vector3 = Vector3.ZERO

# Camera-feel state (captured in _ready; restored continuously by _update_camera_feel).
var _cam_base_fov: float = 75.0
var _cam_base_y: float = 0.0
var _lean_target_deg: float = 0.0

## True while holding block AND the held item can block (block_modifier > 0). Read in
## _on_hurt to soak front hits for stamina.
var is_blocking: bool = false

# Footstep bookkeeping: metres travelled on the ground since the last step sound.
var _step_accum: float = 0.0
const STEP_DISTANCE: float = 2.2

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
	$Head/Camera3D.add_child(load("res://entities/player/held_item_display.gd").new())
	# Remember the camera's resting FOV / height so the dodge feel can return to them.
	var cam := get_camera()
	_cam_base_fov = cam.fov
	_cam_base_y = cam.position.y

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
			var max_blockable: float = PlayerStats.stamina / mod
			var blocked: float = min(amount, max_blockable)
			if blocked > 0.0:
				PlayerStats.use_stamina(blocked * mod)
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
	if not is_on_floor():
		velocity.y -= gravity * delta
	# Dodge dash overrides steering for its brief window (gravity still applies). The
	# i-frames that make it a defence are handled in _on_hurt.
	if _dodge_time_left > 0.0:
		velocity.x = _dodge_dir.x * dodge_speed
		velocity.z = _dodge_dir.z * dodge_speed
		move_and_slide()
		return
	if Input.is_action_just_pressed("jump") and is_on_floor() and _suppress_action_frames == 0:
		velocity.y = jump_velocity
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
	if not is_on_floor() or _dodge_time_left > 0.0:
		_step_accum = 0.0
		return
	var hspeed: float = Vector2(velocity.x, velocity.z).length()
	if hspeed < 0.5:
		_step_accum = 0.0
		return
	_step_accum += hspeed * delta
	if _step_accum >= STEP_DISTANCE:
		_step_accum = 0.0
		CombatFeel.play_footstep()

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
	var w: float = clampf(delta * 14.0, 0.0, 1.0)  # smoothing weight
	cam.fov = lerpf(cam.fov, _cam_base_fov + dodge_fov_kick * f, w)
	cam.position.y = lerpf(cam.position.y, _cam_base_y - dodge_dip * f, w)
	# Roll (lean): ease toward the target, and bleed the target back to upright.
	_lean_target_deg = move_toward(_lean_target_deg, 0.0, dodge_lean_degrees * 5.0 * delta)
	cam.rotation.z = lerp_angle(cam.rotation.z, deg_to_rad(_lean_target_deg), w)

# The respawn FALLBACK location: where the player stood when the scene loaded.
# DeathScreen calls this only when the scene has no "respawn_point" markers.
func get_spawn_transform() -> Transform3D:
	return spawn_transform
