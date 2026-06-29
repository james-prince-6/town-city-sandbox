# animal.gd
# A data-driven wild ANIMAL used to populate the wild areas with wildlife — both
# peaceful (deer, rabbit, cow…) and hostile (boar, mountain lion, bear…). One script
# drives every species; the per-species differences (model, size, hit points, speed,
# whether it bites you) are all @export fields, so each variant scene only fills those
# in (see deer.tscn / boar.tscn / etc).
#
# WHY this composes components instead of hand-rolling combat:
# - It raises a reusable Health child (components/health.gd) for hit points and a
#   HurtBox child (components/hurt_box.gd, team = ENEMY) so the player's weapons hit it
#   exactly like they hit enemies — the player swing spawns a HitBox (target_team =
#   ENEMY) which overlaps our HurtBox, the HurtBox emits `hit`, and we forward that to
#   Health.apply_damage. No special-casing in the player code.
# - Hostile animals ATTACK by spawning their own HitBox (target_team = PLAYER) in front
#   of the body for a fraction of a second — the same mechanism every enemy uses.
#
# WHY load components by PATH (load("res://…").new()): new class_name symbols may not be
# resolved in a headless/first-import pass, and this node is instanced at runtime by the
# AnimalSpawner. Loading by path sidesteps the "class not found yet" race.
#
# The brain is deliberately tiny and readable (no pathfinding):
# - peaceful: gentle idle/wander (mirrors entities/critters/critter.gd) but FLEES
#   directly away from the nearest player when it gets too close.
# - hostile : idle until a player enters detect_range, then chase in a straight line
#   (gravity-aware, smoothly turning to face the heading) and bite when in range.

class_name Animal
extends CharacterBody3D

# --- Appearance ------------------------------------------------------------

## The cube-pet model (an .fbx PackedScene from res://assets/models/critters/cube-pets/)
## shown for this animal. Instanced as a child and uniformly scaled so its visual height
## matches `target_height`, with its feet resting on the body origin. Null is tolerated
## (an invisible placeholder is used) so the animal still works headless / mis-configured.
@export var model_scene: PackedScene

## Human-readable species name (for prompts / debugging). Not required by the brain.
@export var display_name: String = "Animal"

## Visual height in metres the model is uniformly scaled to. Keeps a chick and a bear at
## believable relative sizes regardless of each fbx's native export scale.
@export var target_height: float = 1.0

# --- Vitality / movement ---------------------------------------------------

## Starting (and maximum) hit points, fed into the Health child.
@export var max_health: float = 30.0

## Chase / flee speed in metres/second (the "I mean it" speed).
@export var move_speed: float = 3.0

## Multiplier applied to a HOSTILE animal's chase speed only (peaceful flee speed is
## untouched). Lets an area or a global tuning pass "shave" predator pace without editing
## every predator scene: a gather zone can drop this just below 1.0 so its big cats stay
## faster than a walk yet slow enough that a SPRINTING player can break away — turning a
## guaranteed kill into a kiteable threat. 1.0 = native move_speed (no change). Read live
## each physics frame, so it can be set safely after the animal has spawned.
@export var hostile_speed_scale: float = 1.0

## Gentle ambling speed while idly wandering (peaceful animals at rest).
@export var wander_speed: float = 1.4

# --- Combat behaviour ------------------------------------------------------

## If true this animal is hostile: it hunts the player. If false it is peaceful and flees.
@export var hostile: bool = false

## Damage dealt per bite (hostile only), applied through a spawned HitBox.
@export var contact_damage: float = 6.0

## Element of the bite (see DamageInfo.DamageType: PHYSICAL=0, FIRE=1, …).
@export var damage_type: int = 0

## How close (metres) a player must be for a hostile animal to notice and start chasing.
@export var detect_range: float = 12.0

## How close (metres) a hostile animal must be to bite.
@export var attack_range: float = 1.8

## Minimum seconds between bites.
@export var attack_cooldown: float = 1.4

## How close (metres) a player must be for a PEACEFUL animal to bolt away. Hostile ignores.
@export var flee_range: float = 6.0

# --- Loot ------------------------------------------------------------------

## Item dropped on death (e.g. &"raw_meat"). Empty = drops nothing.
@export var loot_item_id: StringName = &""

## How many of `loot_item_id` to drop.
@export var loot_amount: int = 1

# --- Wander pacing (peaceful) ---------------------------------------------

## Rough seconds spent ambling toward a goal before resting, and resting before moving.
## Randomised +/-50% so a herd doesn't move in lockstep.
@export var move_duration: float = 2.0
@export var rest_duration: float = 1.5

# --- Node references (built in _ready) -------------------------------------

# Reusable hit-point pool. Created in code so the thin .tscn carries no component wiring.
var health: Node = null
# The "you can hit me here" volume (team = ENEMY) so player weapons damage us.
var _hurt_box: Area3D = null
# The instanced visual (or an invisible placeholder when model_scene is null).
var _model: Node3D = null

# --- Internal state --------------------------------------------------------

# Gravity from project settings, so the animal stays grounded like the player.
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# Peaceful wander phase state (mirrors critter.gd).
var _is_wandering: bool = false
var _phase_timer: float = 0.0
var _wander_direction: Vector3 = Vector3.ZERO

# Last time (ms) a hostile animal bit, seeded hugely negative so the FIRST bite isn't
# wrongly blocked by the cooldown (Time.get_ticks_msec starts near 0).
var _last_attack_ms: int = -100000


func _ready() -> void:
	# Discoverable by spawners / combat / quests under both names the codebase uses.
	add_to_group("critter")
	add_to_group("animal")

	_build_health()
	_build_hurt_box()
	_build_model()
	_build_collider()

	# Peaceful animals start at rest; the physics step alternates rest/wander on its own.
	if not hostile:
		_start_resting()


# --- Construction helpers --------------------------------------------------

# Create the Health child (loaded by path — see file header on why) and listen for death.
func _build_health() -> void:
	health = load("res://components/health.gd").new()
	health.name = "Health"
	health.set("max_health", max_health)
	add_child(health)
	# String-form connect: `health` is statically typed Node (the Health is loaded by path),
	# so address its `died` signal by name to avoid an unsafe-access warning.
	health.connect("died", _on_health_died)


# Create the HurtBox child (team = ENEMY) with a sphere shape and forward hits to Health.
func _build_hurt_box() -> void:
	_hurt_box = load("res://components/hurt_box.gd").new()
	_hurt_box.name = "HurtBox"
	# HurtBox.Team.ENEMY == 1.
	_hurt_box.set("team", 1)
	var shape := SphereShape3D.new()
	# Sized to roughly cover the body so weapons connect comfortably.
	shape.radius = maxf(0.5, target_height * 0.5)
	var col := CollisionShape3D.new()
	col.shape = shape
	# Raise it to the middle of the body so it overlaps a chest-height swing.
	col.position = Vector3(0.0, maxf(0.5, target_height * 0.5), 0.0)
	_hurt_box.add_child(col)
	add_child(_hurt_box)
	# String-form connect: _hurt_box is statically typed Area3D (the HurtBox is loaded by
	# path), so address its custom `hit` signal by name to avoid an unsafe-access warning.
	_hurt_box.connect("hit", _on_hurt_box_hit)


# Instance and normalise the visual. Scales uniformly so the model's visual height equals
# target_height, and offsets it so its feet rest on the body origin (mirrors world_item /
# nature_scatter AABB normalisation). Falls back to a tiny invisible placeholder if null.
func _build_model() -> void:
	if model_scene != null:
		_model = model_scene.instantiate() as Node3D
	if _model == null:
		# Robust fallback: an invisible placeholder so the animal still functions.
		var ph := MeshInstance3D.new()
		ph.mesh = BoxMesh.new()
		ph.visible = false
		_model = ph
		add_child(_model)
		return

	add_child(_model)
	var aabb := _combined_visual_aabb(_model)
	if aabb.size.y <= 0.0:
		return
	var s: float = target_height / aabb.size.y
	_model.scale = Vector3.ONE * s
	# Centre on X/Z, rest the model's BOTTOM on the body origin so its feet sit at y=0.
	var center_x: float = aabb.position.x + aabb.size.x * 0.5
	var center_z: float = aabb.position.z + aabb.size.z * 0.5
	_model.position = Vector3(-center_x * s, -aabb.position.y * s, -center_z * s)


# Resize and re-seat the movement capsule so its BOTTOM sits at the body origin (y=0),
# where _build_model() pins the model's feet. The thin .tscn carries a fixed capsule that
# is CENTRED on the origin (its bottom 0.5 m below), so every species otherwise rests with
# its feet floating half the capsule height above the terrain. Sizing the capsule to
# target_height here also keeps the collider proportional to each species' visual.
func _build_collider() -> void:
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null:
		return
	var cap := CapsuleShape3D.new()
	cap.height = maxf(0.4, target_height)
	cap.radius = clampf(target_height * 0.25, 0.2, cap.height * 0.5)
	col.shape = cap
	# Lift the capsule so its BOTTOM sits at the body origin (y=0), matching the model's feet.
	col.position = Vector3(0.0, cap.height * 0.5, 0.0)


# --- Physics / brain -------------------------------------------------------

func _physics_process(delta: float) -> void:
	# Gravity always, so the animal settles onto and sticks to the floor.
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0

	if hostile:
		_hostile_brain(delta)
	else:
		_peaceful_brain(delta)

	move_and_slide()


# Peaceful: amble idly, but bolt straight away from the nearest player when it's close.
func _peaceful_brain(delta: float) -> void:
	var player: Node3D = _get_player()
	if player != null:
		var to_self: Vector3 = global_position - player.global_position
		to_self.y = 0.0
		var dist: float = to_self.length()
		if dist < flee_range and dist > 0.001:
			# Flee directly away at the urgent (move_speed) pace and face that way.
			var flee_dir: Vector3 = to_self / dist
			velocity.x = flee_dir.x * move_speed
			velocity.z = flee_dir.z * move_speed
			_face_heading(flee_dir, delta)
			return

	# Not fleeing — run the gentle wander phase machine.
	_phase_timer -= delta
	if _phase_timer <= 0.0:
		if _is_wandering:
			_start_resting()
		else:
			_start_wandering()

	if _is_wandering:
		velocity.x = _wander_direction.x * wander_speed
		velocity.z = _wander_direction.z * wander_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, wander_speed)
		velocity.z = move_toward(velocity.z, 0.0, wander_speed)


# Hostile: idle until a player is within detect_range, then chase and bite.
func _hostile_brain(delta: float) -> void:
	# Effective chase speed = native move_speed shaved by hostile_speed_scale (clamped
	# non-negative). Computed once per step and used for both closing AND the decel
	# move_toward steps so the predator's whole motion respects the area's danger dial.
	var spd: float = move_speed * maxf(0.0, hostile_speed_scale)
	var player: Node3D = _get_player()
	if player == null:
		velocity.x = move_toward(velocity.x, 0.0, spd)
		velocity.z = move_toward(velocity.z, 0.0, spd)
		return

	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist: float = to_player.length()

	if dist > detect_range:
		# Hasn't noticed the player yet — stand down.
		velocity.x = move_toward(velocity.x, 0.0, spd)
		velocity.z = move_toward(velocity.z, 0.0, spd)
		return

	var heading: Vector3 = to_player / dist if dist > 0.001 else Vector3.ZERO
	if heading != Vector3.ZERO:
		_face_heading(heading, delta)

	if dist <= attack_range:
		# In bite range — stop closing and try to bite (cooldown-gated).
		velocity.x = move_toward(velocity.x, 0.0, spd)
		velocity.z = move_toward(velocity.z, 0.0, spd)
		_try_attack()
	else:
		# Chase in a straight line.
		velocity.x = heading.x * spd
		velocity.z = heading.z * spd


# Spawn a brief HitBox in front of the body to bite the player, if off cooldown.
func _try_attack() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_attack_ms < int(attack_cooldown * 1000.0):
		return
	_last_attack_ms = now

	var hb: Area3D = load("res://components/hit_box.gd").new()
	hb.set("amount", contact_damage)
	hb.set("damage_type", damage_type)
	# HurtBox.Team.PLAYER == 0 — only the player is bitten.
	hb.set("target_team", 0)
	hb.set("one_shot", false)
	hb.set("lifetime", 0.2)
	hb.set("source", self)

	var shape := SphereShape3D.new()
	shape.radius = 0.6
	var col := CollisionShape3D.new()
	col.shape = shape
	hb.add_child(col)
	add_child(hb)
	# Place it just in front of the body at bite height. Local -Z is forward, and we
	# smooth-turn the whole body to face the player, so local forward points at them.
	hb.position = Vector3(0.0, maxf(0.5, target_height * 0.5), -maxf(0.6, attack_range * 0.6))


# --- Wander phase machine (peaceful, mirrors critter.gd) -------------------

func _start_resting() -> void:
	_is_wandering = false
	_wander_direction = Vector3.ZERO
	_phase_timer = rest_duration * randf_range(0.5, 1.5)


func _start_wandering() -> void:
	_is_wandering = true
	var angle: float = randf_range(0.0, TAU)
	_wander_direction = Vector3(cos(angle), 0.0, sin(angle)).normalized()
	_face_heading(_wander_direction, 1.0)
	_phase_timer = move_duration * randf_range(0.5, 1.5)


# Smoothly rotate the body's yaw toward a flat heading so it turns to walk, not snaps.
func _face_heading(heading: Vector3, delta: float) -> void:
	if heading.length() < 0.001:
		return
	var target_yaw: float = atan2(-heading.x, -heading.z)
	# lerp_angle takes the short way around; the 8*delta factor (clamped) is a snappy ease.
	var t: float = clampf(delta * 8.0, 0.0, 1.0)
	rotation.y = lerp_angle(rotation.y, target_yaw, t)


# --- Damage in / death -----------------------------------------------------

# HurtBox.hit handler: route the incoming damage into our Health pool.
func _on_hurt_box_hit(info: DamageInfo) -> void:
	if health != null:
		# call() by name: `health` is typed Node (the Health is loaded by path), so we
		# can't statically resolve apply_damage — invoke it dynamically.
		health.call("apply_damage", info)


# Health.died handler: drop loot into the world, then remove ourselves.
func _on_health_died() -> void:
	if loot_item_id != &"" and loot_amount > 0:
		var world: Node = get_parent()
		if world != null:
			WorldItem.spawn(loot_item_id, loot_amount, world, global_position)
	queue_free()


# --- Player lookup ---------------------------------------------------------

# Resolve the player lazily each frame — robust to the player being (re)spawned, freed,
# or absent (e.g. in a headless test). Returns null when there's no live player.
func _get_player() -> Node3D:
	var p: Node = get_tree().get_first_node_in_group("player")
	if p != null and is_instance_valid(p) and p is Node3D:
		return p as Node3D
	return null


# --- Visual AABB helpers (mirror world_item / nature_scatter) --------------

func _combined_visual_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for vi in _find_visuals(root):
		var local: Transform3D = root.global_transform.affine_inverse() * vi.global_transform
		var box: AABB = local * vi.get_aabb()
		if not found:
			result = box
			found = true
		else:
			result = result.merge(box)
	return result


func _find_visuals(node: Node) -> Array[VisualInstance3D]:
	var out: Array[VisualInstance3D] = []
	if node is VisualInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_visuals(c))
	return out
