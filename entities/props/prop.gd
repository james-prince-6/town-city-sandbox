# prop.gd
# A reusable "shell" for placeable static props — furniture, bar fixtures, road
# pieces, decorations. The pattern: make a scene with this script on a
# StaticBody3D root and drop a model (a Kenney .fbx, or any visual) under it as a
# child. At runtime it auto-fits a single box collider around the model's combined
# visual bounds, so you never have to hand-place a CollisionShape3D per prop.
#
# To make a new prop shell: duplicate prop.tscn, swap the "Model" child for the
# Kenney model you want, tweak exports. Appearance is just that child — swap it
# freely later without touching anything else.
#
# For a prop the player can interact with (a sign, a jukebox, a bar tap), set
# `interaction_prompt` and extend this script to override interact().

class_name Prop
extends StaticBody3D

## Build a box collider from the visual bounds on load. Turn off for purely
## decorative props you can walk through (e.g. flat rugs, hanging banners).
@export var auto_collision: bool = true

## If non-empty, the prop answers the player's interaction raycast with this
## prompt (e.g. "Read", "Use"). Leave blank for non-interactive scenery.
@export var interaction_prompt: String = ""

func _ready() -> void:
	if auto_collision and _find_collision_shape() == null:
		_build_collision_from_visual()

# --- Auto collision --------------------------------------------------------

func _build_collision_from_visual() -> void:
	var aabb := _combined_visual_aabb()
	if aabb.size == Vector3.ZERO:
		push_warning("Prop '%s': no visible mesh found to size collision from." % name)
		return
	var shape := BoxShape3D.new()
	shape.size = aabb.size
	var col := CollisionShape3D.new()
	col.shape = shape
	# AABB is in this body's local space; place the box at its centre.
	col.position = aabb.position + aabb.size * 0.5
	add_child(col)

# Union of every descendant mesh's bounds, expressed in this prop's local space.
func _combined_visual_aabb() -> AABB:
	var result := AABB()
	var found := false
	for vi in _find_visuals(self):
		var local_to_self := global_transform.affine_inverse() * vi.global_transform
		var box := local_to_self * vi.get_aabb()
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

func _find_collision_shape() -> CollisionShape3D:
	for child in get_children():
		if child is CollisionShape3D:
			return child
	return null

# --- Interaction (only active when interaction_prompt is set) --------------

func get_interaction_prompt() -> String:
	return interaction_prompt

# Override in a subclass for functional props (open a shop, play a sound, etc.).
func interact(_player) -> void:
	pass
