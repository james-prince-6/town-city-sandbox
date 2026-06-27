# auto_world_colliders.gd
# Drop ONE of these (a plain Node) into a level to give SOLID placed models collision without
# hand-building shapes or reparenting them. On _ready it walks the whole current scene and, for
# every node whose NAME contains one of `solid_name_filters`, builds trimesh static colliders on
# that node's descendant meshes — so buildings, trees, the fountain, etc. become things you can't
# walk through. Decorative props (flowers, grass, pebbles, plants) are simply not listed, so they
# stay walk-through.
#
# Why name-based (vs. trimeshing everything like building_collision.gd): placed model instances
# are named meaningfully ("building-d", "CommonTree_12", "fountain-round"), but their internal
# mesh nodes aren't — so matching on the instance name lets us collide ONLY the things that should
# block the player, scattered under any parent (the terrain, a "Roads" node, the scene root),
# without colliding flat roads, grass, or decorative clutter.
#
# Safe to combine with building_collision.gd: a mesh that already has a StaticBody child is skipped,
# so the two never double up.
extends Node

## Case-insensitive name substrings of placed instances that should be SOLID. A node whose name
## contains any of these gets trimesh colliders on its descendant meshes. Leave decorative props
## (Flower/Pebble/Plant/Grass) off the list to keep them walk-through.
@export var solid_name_filters: PackedStringArray = ["building", "tree", "fountain", "planter", "rock", "boulder", "barrel", "crate", "statue", "pillar"]

func _ready() -> void:
	# Defer one frame so sibling scripts (e.g. building_collision) and instanced scenes are fully
	# in the tree before we scan.
	call_deferred("_bake")

func _bake() -> void:
	var root: Node = get_tree().current_scene
	if root == null:
		root = get_parent()
	if root != null:
		_scan(root)

# Walk the tree: a node whose name matches gets its meshes collided (and we don't descend into it
# again — _add_colliders already covers all its meshes). Non-matching nodes are recursed so solids
# nested under plain containers (Roads, the terrain) are still found.
func _scan(node: Node) -> void:
	for child in node.get_children():
		if _matches(child.name):
			_add_colliders(child)
		else:
			_scan(child)

func _matches(node_name: String) -> bool:
	var lower: String = node_name.to_lower()
	for f in solid_name_filters:
		if lower.contains(String(f).to_lower()):
			return true
	return false

# Give every descendant MeshInstance3D of `node` a trimesh StaticBody collider, unless it already
# has one (so re-runs and overlap with building_collision.gd are no-ops).
func _add_colliders(node: Node) -> void:
	for m in node.find_children("", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		if _has_static_body(mi):
			continue
		mi.create_trimesh_collision()

func _has_static_body(mesh_inst: MeshInstance3D) -> bool:
	for c in mesh_inst.get_children():
		if c is StaticBody3D:
			return true
	return false
