# critter.gd
# A simple wandering creature that the player can fight (LIGHT combat).
#
# This uses the project's "hybrid" pattern: the critter scene COMPOSES a small,
# reusable Health component (components/health.gd) as a CHILD node. This script
# owns only the body + the tiny brain (idle / gentle wander); the Health child
# owns the hit points. Keeping them separate means the same Health component also
# works on rocks and other critters without copy-pasting damage logic.
#
# Combat flow (the damage comes FROM the player, not from here):
# - The player swings a WEAPON tool, raycasts forward, finds this body, looks for
#   a Health child, and calls Health.take_damage(weapon.damage).
# - When Health fires `died`, our handler drops loot and removes the critter.
#
# The AI is deliberately tiny and readable: no pathfinding, no states machine —
# just "stand still for a bit, then amble in a random direction for a bit," with
# gravity so it stays on the ground.

extends CharacterBody3D

# --- Tunables (editable per-critter in the Inspector) ----------------------

## How fast the critter ambles while wandering (metres/second). Kept slow so it
## reads as a gentle creature, not something chasing the player.
@export var wander_speed: float = 1.5

## Roughly how long (seconds) the critter keeps moving before picking a new goal,
## and how long it rests between moves. We randomise around these so it doesn't
## look robotic.
@export var move_duration: float = 2.0
@export var rest_duration: float = 1.5

## Which item this critter drops when it dies, and how many. Defaults match the
## task spec; swap in the Inspector for different critters.
@export var loot_item_id: StringName = &"plant_fiber"
@export var loot_amount: int = 1

# --- Node references -------------------------------------------------------

# The reusable Health component dropped in as a child of the scene. We grab it in
# _ready and listen for its `died` signal.
@onready var health: Node = $Health

# --- Internal AI state -----------------------------------------------------

# Gravity pulled from project settings so the critter falls/stays grounded just
# like the player does.
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")

# True while ambling toward a goal; false while resting in place.
var _is_wandering: bool = false

# Seconds left in the current wander/rest phase. When it hits 0 we flip phases.
var _phase_timer: float = 0.0

# The flat (XZ) direction we're currently ambling in. Y stays 0 — gravity owns Y.
var _wander_direction: Vector3 = Vector3.ZERO


func _ready() -> void:
	# Join the "critter" group so other systems (spawners, combat, quests) can
	# find all critters without hard-coded node paths.
	add_to_group("critter")

	# When our Health child reports it has died, drop loot and clean up.
	health.died.connect(_on_health_died)

	# Start out resting, then the timer logic in _physics_process takes over and
	# alternates between resting and wandering on its own.
	_start_resting()


func _physics_process(delta: float) -> void:
	# Always apply gravity so the critter settles onto the floor and can't float.
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		# Pin Y to 0 while grounded so move_and_slide doesn't accumulate tiny
		# downward drift.
		velocity.y = 0.0

	# Count down the current phase; when it expires, swap between wander and rest.
	_phase_timer -= delta
	if _phase_timer <= 0.0:
		if _is_wandering:
			_start_resting()
		else:
			_start_wandering()

	# Drive horizontal movement from whatever phase we're in.
	if _is_wandering:
		velocity.x = _wander_direction.x * wander_speed
		velocity.z = _wander_direction.z * wander_speed
	else:
		# Resting: ease horizontal speed to a stop.
		velocity.x = move_toward(velocity.x, 0.0, wander_speed)
		velocity.z = move_toward(velocity.z, 0.0, wander_speed)

	move_and_slide()

# --- Tiny wander brain -----------------------------------------------------

## Begin a rest phase: stand still for a slightly-randomised stretch of time.
func _start_resting() -> void:
	_is_wandering = false
	_wander_direction = Vector3.ZERO
	# +/- 50% jitter so rests vary and critters don't all sync up.
	_phase_timer = rest_duration * randf_range(0.5, 1.5)

## Begin a wander phase: pick a fresh random flat direction and amble that way.
func _start_wandering() -> void:
	_is_wandering = true
	# Random heading on the XZ plane (Y = 0 so it never tries to walk uphill into
	# the air). normalized() keeps speed consistent regardless of the angle.
	var angle: float = randf_range(0.0, TAU)
	_wander_direction = Vector3(cos(angle), 0.0, sin(angle)).normalized()
	# Face roughly where we're heading so the placeholder mesh turns to walk.
	look_at(global_position + _wander_direction, Vector3.UP)
	_phase_timer = move_duration * randf_range(0.5, 1.5)

# --- Death / loot ----------------------------------------------------------

## Hooked to Health.died. Spits out the configured loot as a physical WorldItem,
## then removes the critter from the world.
func _on_health_died() -> void:
	# Drop loot into the same world the critter lives in (its parent node), at the
	# critter's feet. WorldItem.spawn gives it a small upward pop so it's grabbable.
	if loot_item_id != &"" and loot_amount > 0:
		WorldItem.spawn(loot_item_id, loot_amount, get_parent(), global_position)
	queue_free()
