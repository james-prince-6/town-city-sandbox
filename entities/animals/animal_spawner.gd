# animal_spawner.gd
# Drops a node of this script into a wild-area scene to procedurally SCATTER wildlife
# across a disc around it. Mirrors entities/props/nature_scatter.gd, but for live Animal
# bodies instead of static decoration: each placed point ground-aligns by a downward
# raycast and instances a random pick from `variants` (deer / boar / cow / …).
#
# Deterministic per `rng_seed` so a wild area populates the same way every run (no save
# needed for the initial layout; killed animals simply don't respawn unless you reseed).
#
# Usage in the editor: add an AnimalSpawner, fill `variants` with the variant scenes
# (deer.tscn, boar.tscn, …), set count / area_radius. In code (the wild areas reference
# this by PATH): set the fields then add it to the tree. If `variants` is empty it no-ops.
#
# It defers + awaits a physics frame before scattering so the scene's ground colliders
# exist for the alignment raycast (same reasoning as nature_scatter).

class_name AnimalSpawner
extends Node3D

## The Animal variant scenes to randomly choose from for each spawn (e.g. deer.tscn,
## boar.tscn). Empty = nothing is spawned. Each instance is a random pick from this list.
@export var variants: Array[PackedScene] = []

## How many animals to place.
@export var count: int = 8

## Scatter within a disc of this radius (metres) on the XZ plane around this node.
@export var area_radius: float = 25.0

## Seed for the deterministic layout. Change it for a different arrangement.
@export var rng_seed: int = 1

## Keep this inner radius clear (e.g. so nothing spawns on the player's entry marker).
@export var clear_radius: float = 0.0

## Physics layers the ground-alignment raycast checks (world geometry is layer 1).
@export_flags_3d_physics var ground_mask: int = 1

func _ready() -> void:
	# Defer so the scene's ground colliders exist before we raycast onto them.
	call_deferred("_scatter")

func _scatter() -> void:
	if variants.is_empty() or count <= 0:
		return
	# One physics frame so freshly-added ground colliders are live for the ray queries.
	await get_tree().physics_frame

	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = global_position

	for i in range(count):
		var ps: PackedScene = variants[rng.randi() % variants.size()]
		if ps == null:
			continue

		# Uniform random point in the disc (sqrt keeps it even, not centre-biased).
		var ang: float = rng.randf() * TAU
		var dist: float = sqrt(rng.randf()) * area_radius
		if clear_radius > 0.0 and dist < clear_radius:
			dist = clear_radius + rng.randf() * maxf(0.01, area_radius - clear_radius)
		var pos: Vector3 = origin + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)

		# Ground-align: drop the animal onto whatever surface is below the chosen point.
		var params := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 60.0, pos + Vector3.DOWN * 60.0)
		params.collision_mask = ground_mask
		var hit: Dictionary = space.intersect_ray(params)
		if hit.is_empty():
			continue  # nothing to stand on here — skip
		var hit_pos: Vector3 = hit["position"]
		pos = hit_pos

		var animal: Node3D = ps.instantiate() as Node3D
		if animal == null:
			continue
		add_child(animal)
		# Lift a touch so the body's capsule starts above the ground and settles via gravity.
		animal.global_position = pos + Vector3.UP * 0.2
