# furniture_dresser.gd
# A tiny "interior decorator" helper. Building interiors (see RoomInterior) need to
# drop a lot of furniture models — beds, cabinets, sofas, rugs — each instanced from a
# Kenney furniture .fbx, positioned/rotated/scaled, and (usually) wrapped in a fitted
# box collider so the player bumps into it. Doing that by hand for every piece is noise;
# this helper collapses it to a single `place(...)` call.
#
# Usage from a RoomInterior subclass:
#     var d := FurnitureDresser.new()
#     add_child(d)                       # parent it into the world first
#     d.place("res://assets/models/furniture/furniture-kit/bedSingle.fbx",
#             Vector3(-5, 0, -5), 90.0)  # model, local pos, yaw degrees
#
# Anything placed becomes a child of the dresser, so the whole furnishing set can be
# cleared or transformed as one unit. Collision is auto-fitted from the model's combined
# visual AABB (the same recurse-VisualInstance3D trick prop.gd uses), so you never hand-
# author a CollisionShape3D per piece. Flat decor (rugs, doormats) can pass collision=false.

class_name FurnitureDresser
extends Node3D

## Instance a furniture model, parent it under this dresser, and place it.
##
## model_path   : res:// path to the .fbx (or any PackedScene) to instance.
## local_pos    : position in THIS dresser's local space (dresser usually sits at the
##                world origin, so this is effectively world space for room interiors).
## yaw_degrees  : rotation about Y (how the piece faces).
## scale        : uniform scale multiplier. The Kenney furniture-kit is scaled to real-world
##                metres via nodes/root_scale=0.2 in each .fbx.import (the raw FBX is ~5x too
##                large), so the imported base is already correct and scale=1.0 is true size.
## collision    : when true, wrap the model in a StaticBody3D with a box collider fitted
##                to its visual bounds. Turn off for walk-through flat decor.
##
## Returns the top node added for the piece (the StaticBody3D when collision is on,
## otherwise the model instance itself) so callers can tweak it further if needed.
func place(model_path: String, local_pos: Vector3, yaw_degrees: float = 0.0, scale: float = 1.0, collision: bool = true) -> Node3D:
	var packed := load(model_path) as PackedScene
	if packed == null:
		push_warning("FurnitureDresser: could not load model '%s'." % model_path)
		return null
	var model: Node3D = packed.instantiate()
	model.scale = Vector3(scale, scale, scale)

	if not collision:
		add_child(model)
		model.position = local_pos
		model.rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
		return model

	# Wrap in a StaticBody so the player collides with it. The model parents UNDER the
	# body at the origin; the body carries the placement transform.
	var body := StaticBody3D.new()
	body.add_child(model)
	add_child(body)
	body.position = local_pos
	body.rotation_degrees = Vector3(0.0, yaw_degrees, 0.0)
	_fit_box_collider(body, model)
	return body

# --- Collision fitting (mirrors prop.gd) -----------------------------------

# Build one BoxShape3D collider on `body`, sized to the union of every mesh under
# `model`, expressed in `body`'s local space.
func _fit_box_collider(body: StaticBody3D, model: Node3D) -> void:
	var aabb := _combined_visual_aabb(body, model)
	if aabb.size == Vector3.ZERO:
		push_warning("FurnitureDresser: no visible mesh under '%s' to size collision from." % model.name)
		return
	var shape := BoxShape3D.new()
	shape.size = aabb.size
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = aabb.position + aabb.size * 0.5
	body.add_child(col)

# Union of every descendant mesh's bounds, expressed in `body`'s local space.
func _combined_visual_aabb(body: Node3D, model: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for vi in _find_visuals(model):
		var local_to_body := body.global_transform.affine_inverse() * vi.global_transform
		var box := local_to_body * vi.get_aabb()
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
	for child in node.get_children():
		out.append_array(_find_visuals(child))
	return out
