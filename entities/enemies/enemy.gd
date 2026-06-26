# enemy.gd
# The "body + brain" shared by every hostile monster. A CharacterBody3D that reads a
# swappable EnemyStats data sheet (strength / weaknesses / attack / loot) and runs a
# tiny three-state brain over it: stand around, chase the player in a straight line,
# and attack when in range. One script + one scene + a different .tres = a different
# monster.
#
# It plugs into the shared combat backbone (see docs/combat.md):
# - A Health child holds the HP and the per-element multipliers (from stats), so the
#   player's typed weapons scale by this monster's weaknesses.
# - A HurtBox child (team = ENEMY) is wired so its `hit` -> health.apply_damage,
#   meaning player HitBoxes (target_team = ENEMY) damage this monster automatically.
# - When attacking, the enemy SPAWNS its own offence: a brief melee HitBox in front
#   of it, or a projectile scene — both target_team = PLAYER, source = self. Damage
#   never crosses entities by calling take_damage directly; it always flows
#   HitBox -> HurtBox -> Health/PlayerStats.
# - On Health.died it drops loot via WorldItem.spawn and frees itself.
#
# The FSM is written inline (a small enum + match) rather than the NPC's RefCounted
# state objects: there are only three states and they share a lot of context (the
# player ref, ranges, the cooldown timer), so a compact inline machine reads more
# directly here. The movement/gravity/turn style still mirrors npc.gd.

class_name Enemy
extends CharacterBody3D

## The data sheet that defines THIS monster (strength, weaknesses, attack, loot).
## Assigned per-scene in the Inspector; a different .tres makes a different creature.
@export var stats: EnemyStats

## The melee swing's HitBox stays alive this long (seconds) — a brief active window
## that sweeps the space in front of the monster, then auto-frees. Only used by
## MELEE-style stats.
@export var melee_hitbox_lifetime: float = 0.2

## How far in front of the body (m) a melee HitBox is spawned.
@export var melee_reach: float = 1.2

## Projectile scene a RANGED monster spits. Each ranged monster type assigns its own
## here (it carries a one_shot HitBox aimed at the player). Ignored for MELEE.
@export var projectile_scene: PackedScene

## How fast the body swivels to face its heading (deg/sec). Mirrors npc.gd so turns
## read as a visible pivot rather than an instant snap.
@export var turn_speed_degrees: float = 540.0

# --- The brain's states ----------------------------------------------------
# IDLE    : stand still until the player wanders within stats.detect_range.
# CHASE   : drive straight toward the player (with gravity); no navmesh needed.
# ATTACK  : in range -> fire the moveset (once per attack_cooldown), then keep chasing.
# WINDUP  : committed to a telegraphed special — plant + pulse a warning tell, then
#           fire the special when the wind-up timer elapses (player's window to dodge).
# STAGGER : briefly interrupted by a hit (no advancing / attacking) before recovering.
# (New values appended at the END so existing saved State ints, if any, keep meaning.)
enum State { IDLE, CHASE, ATTACK, WINDUP, STAGGER }

# --- Node refs -------------------------------------------------------------
@onready var health: Node = $Health
@onready var _hurt_box: HurtBox = $HurtBox
# Optional rigged body. Without it the enemy keeps its placeholder capsule and every
# animation call is a harmless no-op, so a scene with no Animator still works.
@onready var _animator: EnemyAnimator = get_node_or_null("Animator")

# --- Runtime ---------------------------------------------------------------
var _state: State = State.IDLE
# Gravity from project settings so the monster falls/stays grounded like everything else.
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
# The player we hunt, resolved lazily (the player may spawn after us).
var _player: Node3D = null
# Wall-clock (ms) of the last attack, so attack_cooldown gates the next one. Using
# Time.get_ticks_msec keeps cooldowns frame-rate independent.
var _last_attack_ms: int = -100000
# Desired body yaw; _apply_turn rotates toward it each frame (smooth facing).
var _target_yaw: float = 0.0
var _has_target_yaw: bool = false
# Guard so death loot/cleanup only ever runs once.
var _dead: bool = false
# Floating health bar above the head (built in _ready).
var _health_bar: HealthBar3D = null

# --- Navigation ------------------------------------------------------------
# A NavigationAgent3D (created in _ready) lets the monster path AROUND walls when the scene
# has a baked navmesh (e.g. the procedural dungeons). When there's NO navmesh on the world
# map (the arena, most overworld combat), _nav_available stays false and the brain falls back
# to the original straight-line chase — so nothing regresses in nav-less scenes.
var _nav_agent: NavigationAgent3D = null
var _nav_available: bool = false
# Status effects (burn/chill/poison) applied to this enemy; chill slows movement. Untyped +
# instanced via load() so this script never depends on the StatusReceiver global class being in
# the script-class cache (avoids headless/stale-cache "class not found" at load time).
var _status = null
# Re-check navmesh availability on a slow cadence (the map syncs a frame or two after load).
var _nav_check_accum: float = 0.0
const NAV_CHECK_INTERVAL: float = 0.5

# --- Knockback -------------------------------------------------------------
# A decaying horizontal impulse layered on top of the brain's velocity each frame, so
# a hit shoves the body without fighting gravity. Set by apply_knockback(), bled off by
# KNOCKBACK_DECAY (m/s per second) in _physics_process.
var _knockback_velocity: Vector3 = Vector3.ZERO
const KNOCKBACK_DECAY: float = 28.0

# --- Stagger / flinch ------------------------------------------------------
# Wall-clock (ms) until which the monster is staggered (interrupted). While _state ==
# STAGGER and now < this, the brain stands down; once past it, it recovers to CHASE.
var _stagger_until_ms: int = 0

# --- Telegraphed special ---------------------------------------------------
# Wall-clock (ms) of the last special, gated by stats.special_cooldown.
var _last_special_ms: int = -100000
# While _state == WINDUP, the special fires once now >= this (the visible tell window).
var _windup_until_ms: int = 0
# Which SpecialStyle the in-progress wind-up will resolve to (chosen at _begin_special,
# so a subclass can vary it per cast without the brain re-deciding mid-tell).
var _pending_special: EnemyStats.SpecialStyle = EnemyStats.SpecialStyle.SLAM
# Per-mesh bookkeeping for the wind-up emissive "tell" so it can be cleanly restored:
# each entry is { "mesh": MeshInstance3D, "base": Material, "tween": Tween }.
var _tell_data: Array = []
# Counts up once per barrage cast (RING/SPIRAL). SPIRAL multiplies this by a fixed step to
# rotate the whole ring a little further each cast, producing the spinning spiral; RING
# ignores it. Plain int so successive casts deterministically advance the offset.
var _barrage_cast_index: int = 0


func _ready() -> void:
	add_to_group("enemy")

	# Apply the data sheet onto the body + components before the brain starts.
	_apply_stats()

	# If a rigged model was built, hide the placeholder capsule mesh (mirrors npc.gd).
	if _animator and _animator.has_model():
		var capsule := get_node_or_null("MeshInstance3D")
		if capsule:
			capsule.visible = false

	# Player weapons (HitBox target_team = ENEMY) overlap our HurtBox; route that into
	# our Health so we actually lose HP scaled by our weaknesses.
	if _hurt_box:
		_hurt_box.team = HurtBox.Team.ENEMY
		_hurt_box.hit.connect(_on_hurt)

	# Drop loot + clean up when the Health child says we've died.
	if health:
		health.died.connect(_on_died)

	# A small floating health bar above the head that follows the camera.
	_spawn_health_bar()

	# Pathfinding agent (used only when a navmesh exists; see _chase_dir). Created in code so
	# every enemy scene gets it without editing each .tscn.
	_nav_agent = NavigationAgent3D.new()
	_nav_agent.path_desired_distance = 0.6
	_nav_agent.target_desired_distance = 0.8
	_nav_agent.radius = 0.45
	_nav_agent.height = 1.6
	_nav_agent.avoidance_enabled = false
	add_child(_nav_agent)

	# Status effects (burn/chill/poison). Created in code so every enemy scene gets one; it
	# damages our Health over time and its speed_multiplier() slows us while chilled.
	_status = load("res://components/status_receiver.gd").new()
	_status.name = "StatusReceiver"
	add_child(_status)


# Build the floating health bar and park it above the body, scaled to the model's
# height so it clears the head of a small Husk and a tall Brute alike.
func _spawn_health_bar() -> void:
	if health == null:
		return
	_health_bar = HealthBar3D.new()
	add_child(_health_bar)
	var top: float = 1.9
	if _animator and _animator.has_model():
		top = _animator.target_height + 0.45
	_health_bar.position = Vector3(0.0, top, 0.0)
	_health_bar.setup(health)


# Copy the EnemyStats numbers onto the body and its Health component. Without stats we
# warn and fall back to whatever the scene's Health defaults are (so a half-configured
# monster still runs instead of crashing).
func _apply_stats() -> void:
	if stats == null:
		push_warning("Enemy '%s' has no EnemyStats assigned; using scene defaults." % name)
		return
	if health:
		health.max_health = stats.max_health
		# Re-seed current HP to the stats max (Health._ready may have run with the old
		# default before we got here).
		health.current = stats.max_health
		health.damage_multipliers = stats.damage_multipliers.duplicate()


func _physics_process(delta: float) -> void:
	# Gravity first so the monster sticks to the floor; the states own horizontal vel.
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	# Make sure we have a live player reference (it may have spawned after us, or a
	# previous one may have been freed).
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as Node3D

	# Periodically re-check whether this world has a baked navmesh (it syncs a frame or two
	# after the scene loads), so chase movement can switch to pathing when one appears.
	_nav_check_accum -= delta
	if _nav_check_accum <= 0.0:
		_nav_check_accum = NAV_CHECK_INTERVAL
		_update_nav_availability()

	if stats != null and _player != null:
		_run_brain(delta)
	else:
		# No stats or no player yet: stand still (gravity still applies above).
		_stop_horizontal()

	_apply_turn(delta)

	# Drive the legs from how fast we're actually trying to move, so the walk cycle
	# matches real movement and runs INDEPENDENTLY of the attack layer (legs keep
	# stepping while the arms swing). Read intent BEFORE knockback is layered in, so a
	# shove doesn't read as "running".
	if _animator:
		var move_max: float = stats.move_speed if stats != null else 3.0
		var hspeed: float = Vector2(velocity.x, velocity.z).length()
		_animator.set_locomotion(clampf(hspeed / maxf(move_max, 0.1), 0.0, 1.0))

	# Layer the decaying knockback impulse on top of the brain's horizontal velocity, so
	# a hit visibly shoves the body. Y is untouched, so it never fights gravity.
	if _knockback_velocity.length_squared() > 0.0001:
		velocity.x += _knockback_velocity.x
		velocity.z += _knockback_velocity.z
		_knockback_velocity = _knockback_velocity.move_toward(Vector3.ZERO, KNOCKBACK_DECAY * delta)
	else:
		_knockback_velocity = Vector3.ZERO

	move_and_slide()


# --- The three-state brain -------------------------------------------------

# One frame of behaviour. Distances are measured flat (XZ) so a tall monster on a
# step doesn't think it's out of range. Two top-level states: stand around until the
# player is noticed, then engage. Engagement differs by attack style — a melee monster
# presses in and swings, a ranged one holds at range and kites if crowded — and in both
# cases the attack is layered over movement, so the legs keep going while it strikes.
func _run_brain(_delta: float) -> void:
	var dist: float = _flat_distance_to_player()

	match _state:
		State.IDLE:
			_stop_horizontal()
			# Player came close enough to notice -> give chase.
			if dist <= stats.detect_range:
				_state = State.CHASE

		State.CHASE:
			# Lost interest if the player got far away (a little hysteresis past
			# detect_range so we don't flicker right at the edge).
			if dist > stats.detect_range * 1.3:
				_state = State.IDLE
				_stop_horizontal()
				return
			if stats.attack_style == EnemyStats.AttackStyle.RANGED:
				_ranged_behavior(dist)
			else:
				_melee_behavior(dist)

		State.WINDUP:
			_update_windup()

		State.STAGGER:
			_update_stagger()


# Melee: always face the player; close the gap; once at arm's reach keep pressing in
# slowly (so the legs still step) and swing on cooldown; hug-close, plant and swing.
func _melee_behavior(dist: float) -> void:
	_face_toward(_player.global_position)
	if dist > stats.attack_range:
		_move_toward_player(stats.move_speed)
	elif dist > stats.attack_range * 0.6:
		_move_toward_player(stats.move_speed * 0.35)
		_engage(dist)
	else:
		_stop_horizontal()
		_engage(dist)


# Ranged: hold around attack_range. Too far -> advance; too close -> back off (kite);
# in the band -> plant. Fire whenever roughly in band, even while repositioning.
func _ranged_behavior(dist: float) -> void:
	_face_toward(_player.global_position)
	var ideal: float = stats.attack_range
	if dist > ideal * 1.1:
		_move_toward_player(stats.move_speed)
	elif dist < ideal * 0.6:
		_move_away_from_player(stats.move_speed)
	else:
		_stop_horizontal()
	if dist <= ideal * 1.15 and dist >= ideal * 0.45:
		_engage(dist)


# Decide what to do when in striking position. Gated by the normal attack rhythm
# (_can_attack), so a special is rolled for at most once per attack_cooldown rather than
# every frame. When the dice (and range + special cooldown) line up, commit to the
# telegraphed special; otherwise throw the normal attack.
func _engage(dist: float) -> void:
	# Already mid-tell or staggered: don't stack another action on top.
	if _state == State.WINDUP or _state == State.STAGGER:
		return
	if not _can_attack():
		return
	if stats.has_special and _can_special() and dist <= stats.special_range and randf() < stats.special_chance:
		_begin_special()
		return
	_perform_attack()


# Drive toward the player at the given speed. Uses the navmesh (pathing around walls) when
# one is available, otherwise a straight line — see _chase_dir.
func _move_toward_player(speed: float) -> void:
	var dir: Vector3 = _chase_dir(_player.global_position)
	if dir == Vector3.ZERO:
		_stop_horizontal()
		return
	var s: float = speed * _speed_mult()
	velocity.x = dir.x * s
	velocity.z = dir.z * s


# Movement multiplier from status effects (chill slows us). 1.0 when unaffected.
func _speed_mult() -> float:
	if _status != null:
		return _status.speed_multiplier()
	return 1.0


# Horizontal unit direction to move toward `target_pos`. When the world has a baked navmesh,
# query the agent for the next point along a path that routes around walls; otherwise (and if
# the path is degenerate) fall back to a straight bee-line. Returns ZERO when already there.
func _chase_dir(target_pos: Vector3) -> Vector3:
	if _nav_available and _nav_agent != null:
		_nav_agent.target_position = target_pos
		var next: Vector3 = _nav_agent.get_next_path_position()
		var nav_d: Vector3 = next - global_position
		nav_d.y = 0.0
		if nav_d.length() > 0.05:
			return nav_d.normalized()
	var to_target: Vector3 = target_pos - global_position
	to_target.y = 0.0
	if to_target.length() < 0.05:
		return Vector3.ZERO
	return to_target.normalized()


# Refresh whether the current world has any navigation regions (i.e. a baked navmesh). Cheap
# but not free, so it's called on a slow cadence from _physics_process.
func _update_nav_availability() -> void:
	var world := get_world_3d()
	if world == null:
		_nav_available = false
		return
	var map: RID = world.navigation_map
	_nav_available = NavigationServer3D.map_get_regions(map).size() > 0


# Back away from the player (ranged kiting) at the given speed.
func _move_away_from_player(speed: float) -> void:
	var away: Vector3 = global_position - _player.global_position
	away.y = 0.0
	if away.length() < 0.05:
		_stop_horizontal()
		return
	var dir: Vector3 = away.normalized()
	var s: float = speed * _speed_mult()
	velocity.x = dir.x * s
	velocity.z = dir.z * s


# True once enough real time has passed since the last attack.
func _can_attack() -> bool:
	var elapsed_ms: int = Time.get_ticks_msec() - _last_attack_ms
	return float(elapsed_ms) >= stats.attack_cooldown * 1000.0


# Launch the monster's offence according to its style, and start the cooldown.
func _perform_attack() -> void:
	_last_attack_ms = Time.get_ticks_msec()
	# Visible swing — melee enemies alternate between two swings so attacks don't look canned;
	# ranged enemies use the single cast/swing.
	if _animator:
		if stats.attack_style == EnemyStats.AttackStyle.MELEE:
			_animator.play_oneshot(&"attack" if randf() < 0.5 else &"attack2")
		else:
			_animator.play_oneshot(&"attack")
	match stats.attack_style:
		EnemyStats.AttackStyle.MELEE:
			_spawn_melee_hitbox()
		EnemyStats.AttackStyle.RANGED:
			_spawn_projectile()


# --- Telegraphed special ---------------------------------------------------

# True once enough real time has passed since the last special (separate cooldown).
func _can_special() -> bool:
	var elapsed_ms: int = Time.get_ticks_msec() - _last_special_ms
	return float(elapsed_ms) >= stats.special_cooldown * 1000.0


# Commit to a special: plant, start the visible wind-up tell, and schedule the payload
# for special_windup seconds from now. Also bumps the normal-attack clock so a regular
# swing doesn't fire the instant the special resolves. Subclasses pick the flavour via
# _choose_special_style().
func _begin_special() -> void:
	_last_attack_ms = Time.get_ticks_msec()
	_pending_special = _choose_special_style()
	_state = State.WINDUP
	_windup_until_ms = Time.get_ticks_msec() + int(stats.special_windup * 1000.0)
	_stop_horizontal()
	_start_windup_tell()


# Which special flavour THIS cast uses. Base monsters just use their stat; the boss
# overrides this to alternate styles across its phases.
func _choose_special_style() -> EnemyStats.SpecialStyle:
	return stats.special_style


# One frame of the wind-up: keep facing the player (so the slam/volley lands where they
# are when it fires) and hold position. When the tell window elapses, fire and recover.
# Guarded so a vanished player can't strand us here.
func _update_windup() -> void:
	if _player == null or not is_instance_valid(_player):
		_clear_windup_tell()
		_state = State.CHASE
		return
	_face_toward(_player.global_position)
	_stop_horizontal()
	if Time.get_ticks_msec() >= _windup_until_ms:
		_execute_special()
		_state = State.CHASE


# Resolve the telegraphed special now that the tell has played out: clear the warning,
# play the swing, start the special cooldown, and spawn the chosen payload.
func _execute_special() -> void:
	_clear_windup_tell()
	_last_special_ms = Time.get_ticks_msec()
	_last_attack_ms = Time.get_ticks_msec()
	if _animator:
		_animator.play_oneshot(&"attack")
	match _pending_special:
		EnemyStats.SpecialStyle.VOLLEY:
			_spawn_volley()
		EnemyStats.SpecialStyle.RING:
			# A full 360° ring with no rotation between casts.
			_spawn_barrage(0.0)
		EnemyStats.SpecialStyle.SPIRAL:
			# Same ring, but rotate the whole pattern a bit further every cast so
			# successive barrages spin (the classic bullet-hell spiral). A ~17° step is
			# coprime-ish with typical ring counts, so casts don't immediately realign.
			_spawn_barrage(deg_to_rad(17.0) * float(_barrage_cast_index))
			_barrage_cast_index += 1
		_:
			_spawn_slam()


# SLAM: a big AoE HitBox centered on the body (a ground pound). Heavy damage + large
# knockback, brief active window so it sweeps anyone standing in the blast.
func _spawn_slam() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var hb := HitBox.new()
	hb.amount = stats.special_damage
	hb.damage_type = stats.special_damage_type
	hb.target_team = HurtBox.Team.PLAYER
	hb.one_shot = false
	hb.lifetime = maxf(melee_hitbox_lifetime, 0.18)
	hb.source = self
	hb.knockback = stats.special_knockback

	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = maxf(stats.special_radius, 0.5)
	shape.shape = sphere
	hb.add_child(shape)

	parent.add_child(hb)
	hb.global_position = global_position + Vector3.UP * 0.8


# VOLLEY: fan special_projectile_count projectiles toward the player across
# special_spread_degrees. Falls back to the slam if no projectile scene is wired.
func _spawn_volley() -> void:
	if projectile_scene == null:
		_spawn_slam()
		return
	var n: int = maxi(stats.special_projectile_count, 1)
	var spawn_pos: Vector3 = global_position + Vector3.UP * 1.0
	var target: Vector3 = _player.global_position + Vector3.UP * 1.0
	var base_dir: Vector3 = target - spawn_pos
	if base_dir.length() < 0.05:
		base_dir = -global_transform.basis.z
	base_dir = base_dir.normalized()
	var spread: float = deg_to_rad(stats.special_spread_degrees)
	for i in range(n):
		# Evenly distribute angles across [-spread/2, +spread/2]; single shot = straight.
		var t: float = 0.5 if n == 1 else float(i) / float(n - 1)
		var ang: float = lerpf(-spread * 0.5, spread * 0.5, t)
		var dir: Vector3 = base_dir.rotated(Vector3.UP, ang)
		_spawn_one_projectile(spawn_pos, dir, stats.special_damage, stats.special_damage_type, stats.special_knockback)


# RING / SPIRAL: a bullet-hell barrage — fire special_ring_count projectiles spaced evenly
# around the full 360° circle on the horizontal plane, IGNORING where the player stands
# (so it reads as an expanding ring of shots the player has to weave out of). `angle_offset`
# (radians) rotates the entire ring; RING passes 0, SPIRAL passes a per-cast offset so
# successive barrages spin. Reuses _spawn_one_projectile so it shares the projectile path
# with the normal attack and the volley. Falls back to the slam if no projectile is wired.
func _spawn_barrage(angle_offset: float) -> void:
	if projectile_scene == null:
		_spawn_slam()
		return
	var n: int = maxi(stats.special_ring_count, 1)
	var spawn_pos: Vector3 = global_position + Vector3.UP * 1.0
	# Start from world -Z (the body's forward at yaw 0) and step a full turn around it.
	var base_dir: Vector3 = Vector3.FORWARD
	var step: float = TAU / float(n)
	for i in range(n):
		var ang: float = angle_offset + step * float(i)
		var dir: Vector3 = base_dir.rotated(Vector3.UP, ang)
		_spawn_one_projectile(spawn_pos, dir, stats.special_damage, stats.special_damage_type, stats.special_knockback)


# --- Stagger / flinch ------------------------------------------------------

# One frame of being staggered: stand down until the interrupt window expires, then
# recover straight into the chase (the brain re-evaluates from there). Always exits, so
# a stagger can never soft-lock the monster.
func _update_stagger() -> void:
	_stop_horizontal()
	if Time.get_ticks_msec() >= _stagger_until_ms:
		_state = State.CHASE


# Decide whether an incoming hit interrupts us and, if so, enter the STAGGER state. A
# crit always staggers; otherwise the post-resistance damage must clear poise_threshold
# (so armored/heavy enemies shrug off chip damage). Cancels any in-progress wind-up.
func _maybe_stagger(info: DamageInfo, damage_dealt: float) -> void:
	if _dead or stats == null:
		return
	if stats.stagger_duration <= 0.0:
		return
	var crit: bool = info != null and info.is_crit
	if not crit and damage_dealt < stats.poise_threshold:
		return
	# Drop any telegraphed special: getting hit hard interrupts the wind-up.
	if _state == State.WINDUP:
		_clear_windup_tell()
	_state = State.STAGGER
	_stagger_until_ms = Time.get_ticks_msec() + int(stats.stagger_duration * 1000.0)
	# Visible hit reaction layered over the body.
	if _animator:
		_animator.play_oneshot(&"flinch")


# --- Knockback -------------------------------------------------------------

## Shove the body along `direction` with `force`, scaled down by knockback_resistance
## (1 = immovable). Implemented as a decaying horizontal impulse integrated in
## _physics_process, so it never fights gravity. Part of the shared combat contract:
## _on_hurt calls this with the DamageInfo's hit_direction + knockback.
func apply_knockback(direction: Vector3, force: float) -> void:
	if _dead or force <= 0.0:
		return
	var flat: Vector3 = direction
	flat.y = 0.0
	if flat.length() < 0.01:
		return
	var resist: float = 0.3
	if stats != null:
		resist = clampf(stats.knockback_resistance, 0.0, 1.0)
	_knockback_velocity = flat.normalized() * force * (1.0 - resist)


# --- Attacks (always via a HitBox targeting the PLAYER) --------------------

# Briefly spawn a HitBox a short way in front of the body. It lives for
# melee_hitbox_lifetime seconds, hits the player's HurtBox (team PLAYER) once, then
# auto-frees. source = self for kill credit.
func _spawn_melee_hitbox() -> void:
	var hb := HitBox.new()
	hb.amount = stats.damage
	hb.damage_type = stats.damage_type
	hb.target_team = HurtBox.Team.PLAYER
	hb.one_shot = false           # a swing can graze; lifetime ends it, not one hit
	hb.lifetime = melee_hitbox_lifetime
	hb.source = self
	# A normal swing nudges the player a little; the slam special does the big shove.
	hb.knockback = stats.attack_knockback

	# Give the area a shape so it can actually overlap things.
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.8
	shape.shape = sphere
	hb.add_child(shape)

	# Add to the world (our parent), then place it in front of where we're facing.
	# Forward is -Z to match npc.gd's facing convention.
	var parent := get_parent()
	if parent == null:
		hb.queue_free()
		return
	parent.add_child(hb)
	var forward: Vector3 = -global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.05:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	hb.global_position = global_position + forward * melee_reach + Vector3.UP * 0.8


# Spit a projectile scene toward the player. The projectile carries its own one_shot
# HitBox (target_team PLAYER) and frees on hit/lifetime — see *_projectile.gd.
#
# Normally a single shot flies straight at the player, but stats.projectiles_per_shot lets
# a monster fire a small SPREAD (a light shotgun burst) fanned across shot_spread_degrees.
# At the defaults (projectiles_per_shot = 1, shot_spread_degrees = 0) this is exactly the
# old single straight shot — byte-for-behavior unchanged.
func _spawn_projectile() -> void:
	if projectile_scene == null:
		push_warning("Enemy '%s' is RANGED but has no projectile_scene." % name)
		return
	# Spawn from roughly the monster's "mouth" height; aim at the player's torso so shots
	# don't sail over their head.
	var spawn_pos: Vector3 = global_position + Vector3.UP * 1.0
	var target: Vector3 = _player.global_position + Vector3.UP * 1.0
	var base_dir: Vector3 = (target - spawn_pos).normalized()
	var n: int = maxi(stats.projectiles_per_shot, 1)
	# Fast path / unchanged behavior: a single shot just flies straight at the player.
	if n <= 1:
		_spawn_one_projectile(spawn_pos, base_dir, stats.damage, stats.damage_type, stats.attack_knockback)
		return
	# Burst: fan n projectiles evenly across [-spread/2, +spread/2] (same math as the
	# volley special), all carrying the normal attack's damage/knockback.
	var spread: float = deg_to_rad(stats.shot_spread_degrees)
	for i in range(n):
		var t: float = 0.5 if n == 1 else float(i) / float(n - 1)
		var ang: float = lerpf(-spread * 0.5, spread * 0.5, t)
		var dir: Vector3 = base_dir.rotated(Vector3.UP, ang)
		_spawn_one_projectile(spawn_pos, dir, stats.damage, stats.damage_type, stats.attack_knockback)


# Instance one projectile, place it, and hand it its payload via the duck-typed
# launch(). Shared by the normal ranged attack and the special volley.
func _spawn_one_projectile(spawn_pos: Vector3, dir: Vector3, amount: float, damage_type: DamageInfo.DamageType, knockback: float) -> void:
	if projectile_scene == null:
		return
	var proj := projectile_scene.instantiate()
	var parent := get_parent()
	if parent == null:
		proj.queue_free()
		return
	parent.add_child(proj)
	(proj as Node3D).global_position = spawn_pos
	# Every enemy projectile in this folder implements launch() (see header). The
	# trailing knockback arg is optional, so older projectiles still work.
	if proj.has_method("launch"):
		proj.launch(dir, amount, damage_type, self, knockback)


# --- Damage in / death -----------------------------------------------------

# Our HurtBox got hit by a player weapon: apply it to Health (which scales by our
# weaknesses/resistances and emits died at 0), then react — flash, maybe stagger, and
# take knockback per the shared combat contract.
func _on_hurt(info: DamageInfo) -> void:
	var dealt: float = 0.0
	if health:
		dealt = float(health.apply_damage(info))
	# Brief white flash on the rigged body so hits read clearly (no-op without a model).
	_flash_hurt()
	# Don't bother reacting if the hit just killed us — _on_died takes over.
	if _dead or (health and health.is_dead()):
		return
	# Flinch/stagger (poise-gated; crits always interrupt) and get shoved.
	_maybe_stagger(info, dealt)
	if info != null:
		apply_knockback(info.hit_direction, info.knockback)


# Health hit 0: scatter loot into the world, play the death clip, then remove ourselves
# once it finishes (or instantly if there's no model). Guarded so a double-hit in one
# frame can't drop loot or die twice.
func _on_died() -> void:
	if _dead:
		return
	_dead = true
	# Death thud.
	CombatFeel.play_death()
	# Cancel any in-progress wind-up tell so a corpse doesn't keep glowing.
	_clear_windup_tell()
	# Drop the health bar the moment we die.
	if is_instance_valid(_health_bar):
		_health_bar.queue_free()
		_health_bar = null
	if stats != null and stats.loot_item_id != &"" and stats.loot_amount > 0:
		WorldItem.spawn(stats.loot_item_id, stats.loot_amount, get_parent(), global_position)

	# Award combat XP for the kill. Granted once (guarded by _dead above) and only when a
	# data sheet is present; Progression handles the level-up/skill-point bookkeeping.
	if stats != null:
		Progression.add_xp(stats.xp)

	# Stop the brain/physics: zero velocity and let the death animation play out. We
	# don't want a corpse to keep chasing while it crumples.
	_state = State.IDLE
	_stop_horizontal()
	set_physics_process(false)
	if _hurt_box:
		_hurt_box.set_deferred("monitorable", false)

	# No rigged body (or no death clip) -> free immediately, as before.
	if _animator == null or not _animator.has_model():
		queue_free()
		return
	var death_len: float = _animator.death_length()
	if death_len <= 0.0:
		queue_free()
		return

	_animator.play_oneshot(&"death")
	# Free after the clip's duration. A timer (not the animation_finished signal) keeps
	# this robust to blend timing and missed signals; the corpse holds its last frame
	# (death is LOOP_NONE) until the timer fires.
	await get_tree().create_timer(death_len).timeout
	queue_free()


# --- Animation glue --------------------------------------------------------

# Flash the model's meshes white for a moment to telegraph a hit, then restore. Uses a
# tween on each mesh's material so it self-cleans; a no-op when there's no model.
func _flash_hurt() -> void:
	if _dead or _animator == null or not _animator.has_model():
		return
	var meshes := _animator.find_children("", "MeshInstance3D", true, false)
	for m in meshes:
		var mesh := m as MeshInstance3D
		if mesh == null:
			continue
		# Clone the current override so we don't stomp the shared skin material, flash
		# its emission bright white, then fade back and restore the original.
		var base_mat := mesh.material_override
		var flash_mat := StandardMaterial3D.new()
		if base_mat is StandardMaterial3D:
			flash_mat = (base_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
		flash_mat.emission_enabled = true
		flash_mat.emission = Color(1, 1, 1)
		flash_mat.emission_energy_multiplier = 2.0
		mesh.material_override = flash_mat
		var ft := create_tween()
		ft.tween_property(flash_mat, "emission_energy_multiplier", 0.0, 0.18)
		ft.tween_callback(_restore_material.bind(mesh, base_mat))


# Restore a mesh's original material override after a hurt flash (deferred via tween).
func _restore_material(mesh: MeshInstance3D, base_mat: Material) -> void:
	if is_instance_valid(mesh):
		mesh.material_override = base_mat


# Start the telegraphed-special "tell": pulse every mesh's emission a warning orange so
# the player sees the heavy attack coming and can dodge. Each mesh gets its own looping
# tween + a remembered base material; _clear_windup_tell tears it all down. No-op
# without a rigged model (the brain still works, just without the visual cue).
func _start_windup_tell() -> void:
	_clear_windup_tell()
	if _dead or _animator == null or not _animator.has_model():
		return
	# Telegraph the big attack with a roar (on top of the emissive pulse below).
	_animator.play_oneshot(&"roar")
	var meshes := _animator.find_children("", "MeshInstance3D", true, false)
	for m in meshes:
		var mesh := m as MeshInstance3D
		if mesh == null:
			continue
		var base_mat := mesh.material_override
		var tell_mat := StandardMaterial3D.new()
		if base_mat is StandardMaterial3D:
			tell_mat = (base_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
		tell_mat.emission_enabled = true
		tell_mat.emission = Color(1.0, 0.25, 0.05)
		tell_mat.emission_energy_multiplier = 0.0
		mesh.material_override = tell_mat
		var tw := create_tween()
		tw.set_loops()
		tw.tween_property(tell_mat, "emission_energy_multiplier", 3.5, 0.16)
		tw.tween_property(tell_mat, "emission_energy_multiplier", 0.4, 0.16)
		var entry := {"mesh": mesh, "base": base_mat, "tween": tw}
		_tell_data.append(entry)


# Stop the wind-up tell: kill each pulse tween and restore the original material.
func _clear_windup_tell() -> void:
	for entry in _tell_data:
		var tw = entry.get("tween")
		if tw is Tween and (tw as Tween).is_valid():
			(tw as Tween).kill()
		var mesh = entry.get("mesh")
		if is_instance_valid(mesh):
			(mesh as MeshInstance3D).material_override = entry.get("base")
	_tell_data.clear()


# --- Facing / movement helpers (mirrors npc.gd) ----------------------------

# Stop horizontal motion (gravity still owns Y).
func _stop_horizontal() -> void:
	velocity.x = 0.0
	velocity.z = 0.0


# Flat (XZ) distance to the player; safe to call only when _player is valid.
func _flat_distance_to_player() -> float:
	var to_player: Vector3 = _player.global_position - global_position
	to_player.y = 0.0
	return to_player.length()


# Aim the desired heading at a world point. _apply_turn rotates toward it smoothly.
# Body forward is -Z (matching npc.gd / look_at), so the yaw pointing -Z along
# (dx,dz) is atan2(-dx, -dz).
func _face_toward(target_position: Vector3) -> void:
	var flat: Vector3 = target_position - global_position
	flat.y = 0.0
	if flat.length() < 0.05:
		return
	_target_yaw = atan2(-flat.x, -flat.z)
	_has_target_yaw = true


# Rotate the body's yaw toward the last-aimed heading at turn_speed_degrees/sec.
func _apply_turn(delta: float) -> void:
	if not _has_target_yaw:
		return
	var max_step: float = deg_to_rad(turn_speed_degrees) * delta
	var diff: float = wrapf(_target_yaw - rotation.y, -PI, PI)
	if absf(diff) <= max_step:
		rotation.y = _target_yaw
	else:
		rotation.y += signf(diff) * max_step


## Name of the active brain state as a StringName — handy for tests/debugging. Reports
## "Attack" when engaged and within striking range, else the top-level state.
func current_state() -> StringName:
	if _state == State.WINDUP:
		return &"Windup"
	if _state == State.STAGGER:
		return &"Stagger"
	if _state == State.IDLE:
		return &"Idle"
	if _player != null and is_instance_valid(_player) and _flat_distance_to_player() <= stats.attack_range * 1.2:
		return &"Attack"
	return &"Chase"
