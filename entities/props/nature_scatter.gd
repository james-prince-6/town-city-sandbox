# nature_scatter.gd
# Drops a node of this script into a scene to procedurally SCATTER decorative models
# (trees, rocks, plants, mushrooms, clutter) across a disc around it. Deterministic per
# `rng_seed`, so a scene dresses the same way every run (and doesn't need saving). Each
# instance gets a random pick from `models`, a random yaw + scale, and is dropped onto the
# ground with a downward raycast (so it sits on terrain / dungeon floors regardless of the
# node's own height). Runs at runtime only (not in the editor), so the .tscn stays light.
#
# Usage in the editor: add a NatureScatter node, fill `models` with PackedScenes (e.g. the
# Stylized Nature MegaKit glTFs), set count/area_radius. In code: set the fields then add it
# to the tree. Set `make_collision` for trees/boulders the player should bump into; leave it
# off for grass/flowers/small clutter you walk through.
class_name NatureScatter
extends Node3D

## Models to randomly choose from for each scattered instance. Leave empty and set
## `models_dir` instead to pull every imported model from a folder (easier than listing 68).
@export var models: Array[PackedScene] = []
## If `models` is empty, every PackedScene (.gltf/.glb/.fbx) in this folder is used. Lets you
## point at e.g. res://assets/models/nature/stylized-megakit/ without authoring a big array.
@export_dir var models_dir: String = ""
## Optional case-insensitive name substrings to keep when scanning `models_dir` (e.g.
## ["Tree","Pine"] for just trees, ["Rock","Pebble"] for rocks). Empty = keep everything.
@export var name_filter: PackedStringArray = []
## How many instances to place.
@export var count: int = 30
## Scatter within a disc of this radius (metres) on the XZ plane around this node.
@export var area_radius: float = 20.0
## Keep this inner radius clear (e.g. so nothing spawns on the player start / a building).
@export var clear_radius: float = 0.0
## Seed for the deterministic layout. Change it for a different arrangement.
@export var rng_seed: int = 1
@export var min_scale: float = 0.8
@export var max_scale: float = 1.3
## Random heading per instance (most natural for foliage/rocks).
@export var random_yaw: bool = true
## Raycast down to sit each instance on the ground. Needs the ground to have collision.
@export var ground_align: bool = true
## Physics layers the ground raycast checks (world geometry is layer 1).
@export_flags_3d_physics var ground_mask: int = 1
## Wrap each instance in a StaticBody3D with a box collider (use for trees/boulders).
@export var make_collision: bool = false
## Vertical sink so a model whose origin isn't exactly at its base doesn't float (metres).
@export var ground_offset: float = 0.0

func _ready() -> void:
	# Defer so the scene's colliders (terrain / dungeon floor) exist before we raycast.
	call_deferred("_scatter")

func _scatter() -> void:
	var pool: Array[PackedScene] = _resolve_models()
	if pool.is_empty() or count <= 0:
		return
	await get_tree().physics_frame
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = global_position
	# Colliders of props we've already placed (when make_collision). Excluded from the ground
	# ray so a later instance doesn't land on an earlier prop's box and stack into a tower.
	var placed_rids: Array[RID] = []
	for i in range(count):
		var ps: PackedScene = pool[rng.randi() % pool.size()]
		if ps == null:
			continue
		# Uniform random point in the disc (sqrt keeps it even, not centre-biased).
		var ang: float = rng.randf() * TAU
		var dist: float = sqrt(rng.randf()) * area_radius
		if clear_radius > 0.0 and dist < clear_radius:
			dist = clear_radius + rng.randf() * maxf(0.01, area_radius - clear_radius)
		var pos: Vector3 = origin + Vector3(cos(ang) * dist, 0.0, sin(ang) * dist)

		if ground_align:
			var params := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 60.0, pos + Vector3.DOWN * 60.0)
			params.collision_mask = ground_mask
			params.exclude = placed_rids
			var hit: Dictionary = space.intersect_ray(params)
			if hit.is_empty():
				continue  # nothing to stand on here — skip
			var hit_pos: Vector3 = hit["position"]
			pos = hit_pos

		var model: Node3D = ps.instantiate() as Node3D
		if model == null:
			continue
		var holder: Node3D = model
		if make_collision:
			holder = StaticBody3D.new()
			holder.add_child(model)
		add_child(holder)
		holder.global_position = pos - Vector3.UP * ground_offset
		if random_yaw:
			holder.rotation.y = rng.randf() * TAU
		holder.scale = Vector3.ONE * rng.randf_range(min_scale, max_scale)
		if make_collision:
			_add_box_collider(holder as StaticBody3D, model)
			placed_rids.append((holder as StaticBody3D).get_rid())

# The set of models to scatter: the explicit `models` list if given, else every imported
# scene in `models_dir` that passes `name_filter`.
func _resolve_models() -> Array[PackedScene]:
	if not models.is_empty():
		return models
	var out: Array[PackedScene] = []
	if models_dir == "":
		return out
	var dir := DirAccess.open(models_dir)
	if dir == null:
		return out
	for file_name in dir.get_files():
		# In exported builds source files become X.gltf.remap; strip that. The X.gltf.import
		# sidecars stay as-is and fail the extension check below, so no duplicates.
		var fn: String = file_name.trim_suffix(".remap")
		var lower: String = fn.to_lower()
		if not (lower.ends_with(".gltf") or lower.ends_with(".glb") or lower.ends_with(".fbx")):
			continue
		if not _passes_filter(fn):
			continue
		var res: Resource = load(models_dir.path_join(fn))
		if res is PackedScene:
			out.append(res)
	return out

func _passes_filter(file_name: String) -> bool:
	if name_filter.is_empty():
		return true
	var lower: String = file_name.to_lower()
	for sub in name_filter:
		if lower.contains(String(sub).to_lower()):
			return true
	return false

# Build one box collider sized to the model's visual bounds (mirrors prop.gd).
func _add_box_collider(body: StaticBody3D, model: Node3D) -> void:
	var aabb := _visual_aabb(model)
	if aabb.size == Vector3.ZERO:
		return
	var shape := BoxShape3D.new()
	shape.size = aabb.size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = aabb.position + aabb.size * 0.5
	body.add_child(col)

func _visual_aabb(root: Node3D) -> AABB:
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
