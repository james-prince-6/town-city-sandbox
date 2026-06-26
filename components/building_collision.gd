# building_collision.gd
# Attach this to a container Node3D (e.g. the "Buildings" node in a level). At runtime it
# gives EVERY model placed under it solid, mesh-accurate collision automatically — so you
# can drop raw building scenes (.fbx/.gltf instances) straight in and they become walls
# you can't walk through, with zero per-building setup.
#
# How: it walks all descendant MeshInstance3D nodes and calls create_trimesh_collision(),
# which builds a precise (concave, mesh-shaped) StaticBody collider under each mesh. This
# is done at runtime only, so colliders aren't serialized into the .tscn — the scene stays
# light in the editor and you never hand-place collision boxes. Buildings are low-poly, so
# trimesh collision is cheap here.
#
# Notes:
# - Re-entrant safe: a mesh that already has a StaticBody child is skipped.
# - Only affects descendants of this node, so put your buildings under it (decorative
#   props that should NOT block the player can live elsewhere).
extends Node3D

func _ready() -> void:
	_build_colliders()

## Generate trimesh static colliders for every descendant mesh that doesn't already have
## one. Public so it can be re-run after spawning more buildings at runtime.
func _build_colliders() -> void:
	for node in find_children("", "MeshInstance3D", true, false):
		var mesh_inst := node as MeshInstance3D
		if mesh_inst == null or mesh_inst.mesh == null:
			continue
		if _has_static_body(mesh_inst):
			continue
		mesh_inst.create_trimesh_collision()

func _has_static_body(mesh_inst: MeshInstance3D) -> bool:
	for c in mesh_inst.get_children():
		if c is StaticBody3D:
			return true
	return false
