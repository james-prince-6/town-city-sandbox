# thrown_grenade.gd
# The smoke grenade in flight. A RigidBody3D that arcs out of the player's hand and,
# on the first of impact-or-fuse, spawns a SmokeCloud at its resting position and
# frees itself. It deals no damage — the only payload is the visual cloud.
#
# SmokeGrenadeItem sets `duration` after instancing; we forward it to the cloud.

extends RigidBody3D

## How long the spawned smoke cloud lives (seconds). Set by SmokeGrenadeItem.
@export var duration: float = 5.0

## Short fuse so the cloud appears soon even if the grenade lands somewhere it
## never registers a contact.
@export var fuse_time: float = 1.0

## The cloud scene to spawn where the grenade comes to rest.
@export var cloud_scene: PackedScene = preload("res://entities/items/consumables/smoke_cloud.tscn")

# Guard against fuse + impact both firing.
var _popped: bool = false

func _ready() -> void:
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)

	var fuse: SceneTreeTimer = get_tree().create_timer(fuse_time)
	fuse.timeout.connect(_pop)

## Called once by the thrower to launch the grenade.
func launch(velocity: Vector3, _source: Node) -> void:
	linear_velocity = velocity
	angular_velocity = Vector3(4.0, 3.0, 0.0)

func _on_body_entered(_body: Node) -> void:
	_pop()

# Spawn the cloud at our position and disappear.
func _pop() -> void:
	if _popped:
		return
	_popped = true

	var world: Node = SceneManager.current_world()
	if world == null:
		queue_free()
		return

	if cloud_scene != null:
		var cloud: Node3D = cloud_scene.instantiate() as Node3D
		if cloud != null:
			world.add_child(cloud)
			cloud.global_position = global_position
			# Hand the lifetime to the cloud so the .tres's duration controls it.
			if "duration" in cloud:
				cloud.set("duration", duration)

	queue_free()
