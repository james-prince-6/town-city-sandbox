# held_item_display.gd
# A simple first-person "held item" viewmodel. It lives under the player's camera
# and shows the 3D model of whatever item is currently selected in the Hotbar —
# so the sword you have equipped actually appears in your hand.
#
# It does three things beyond just showing the model:
#   - NORMALIZES size: kit models import at wildly different scales, so we scale each
#     so its longest dimension is held_size. Without this a model can be metres-huge
#     (clipping the whole screen) or invisibly tiny.
#   - PLACEHOLDER fallback: an item with no world_model (e.g. the bow, which has no
#     model in the kit) still shows a small block so your hand isn't empty.
#   - SWING/RECOIL: when the player uses the item it plays a quick chop (melee) or
#     pullback (ranged) so attacks read on screen.
#
# This is intentionally rough: a plain child of the camera with no separate viewmodel
# camera/layer, so a held model can clip into nearby geometry up close. Graft on a
# dedicated viewmodel camera later for polish.

class_name HeldItemDisplay
extends Node3D

## Resting offset from the camera: +x right, -y down, -z forward. Lower-right hand.
@export var held_position: Vector3 = Vector3(0.32, -0.28, -0.55)
## The held model is scaled so its LONGEST dimension equals this (metres).
@export var held_size: float = 0.45
## Orientation tweak so models face the player sensibly.
@export var held_rotation_degrees: Vector3 = Vector3(0.0, 180.0, 0.0)

var _current: Node3D
var _swing_tween: Tween

func _ready() -> void:
	# Re-show whenever the selection, the hotbar contents, or the held stack changes.
	Hotbar.selection_changed.connect(func(_index): _refresh())
	Hotbar.slots_changed.connect(_refresh)
	Inventory.item_changed.connect(func(_id, _count): _refresh())
	# Animate the viewmodel whenever the player uses the held item.
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_signal("item_used"):
		player.item_used.connect(_on_item_used)
	_refresh()

func _refresh() -> void:
	if is_instance_valid(_current):
		_current.queue_free()
	_current = null

	var item: Item = Hotbar.get_selected_item()
	if item == null:
		return
	# Don't show anything for an item you no longer actually hold.
	if Inventory.count_of(Hotbar.get_selected_id()) <= 0:
		return

	# Use the item's 3D model, or a small placeholder block when it has none (so the
	# hand still shows something — e.g. the bow, which has no model in the asset kit).
	var model: Node3D
	if item.world_model != null:
		model = item.world_model.instantiate()
	else:
		model = _make_placeholder()

	add_child(model)
	_normalize(model)
	model.position = held_position
	model.rotation_degrees = held_rotation_degrees
	_current = model

# Build a small neutral block to stand in for an item with no world_model.
func _make_placeholder() -> Node3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.4, 0.08)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.4, 0.25)
	mi.material_override = mat
	return mi

# Scale the model so its longest dimension equals held_size, so any kit model shows at
# a sane, consistent size in hand regardless of how it was authored/imported.
func _normalize(model: Node3D) -> void:
	var aabb := _aabb(model)
	var longest: float = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
	if longest > 0.0:
		model.scale = Vector3.ONE * (held_size / longest)

# Play a quick swing (melee) or recoil (ranged) on the current model. Other item
# kinds (consumables, tools) don't animate.
func _on_item_used(item) -> void:
	if not is_instance_valid(_current):
		return
	var is_melee := item is MeleeWeaponItem
	var is_ranged := item is RangedWeaponItem
	if not (is_melee or is_ranged):
		return

	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	# Snap back to rest first so rapid clicks each start from the same pose.
	_current.position = held_position
	_current.rotation_degrees = held_rotation_degrees

	_swing_tween = create_tween()
	if is_ranged:
		# Short recoil toward the camera, then settle.
		_swing_tween.tween_property(_current, "position", held_position + Vector3(0.0, 0.02, 0.12), 0.05)
		_swing_tween.tween_property(_current, "position", held_position, 0.12)
	else:
		# A proper slash: a quick wind-up up-and-back, then a diagonal strike down across
		# the body, then ease back to rest. The wind-up is what makes it read as a forward
		# swing rather than looking like it plays in reverse.
		var windup_rot := held_rotation_degrees + Vector3(28.0, 0.0, 35.0)
		var windup_pos := held_position + Vector3(0.07, 0.06, 0.07)
		var strike_rot := held_rotation_degrees + Vector3(-45.0, 0.0, -55.0)
		var strike_pos := held_position + Vector3(-0.09, -0.07, -0.2)
		_swing_tween.tween_property(_current, "rotation_degrees", windup_rot, 0.06)
		_swing_tween.parallel().tween_property(_current, "position", windup_pos, 0.06)
		_swing_tween.tween_property(_current, "rotation_degrees", strike_rot, 0.07)
		_swing_tween.parallel().tween_property(_current, "position", strike_pos, 0.07)
		_swing_tween.tween_property(_current, "rotation_degrees", held_rotation_degrees, 0.16)
		_swing_tween.parallel().tween_property(_current, "position", held_position, 0.16)

# --- geometry helpers (mirror enemy_animator.gd) ---------------------------

func _aabb(root: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for vi in _find_meshes(root):
		var local := root.global_transform.affine_inverse() * vi.global_transform
		var box := local * vi.get_aabb()
		if not found:
			result = box
			found = true
		else:
			result = result.merge(box)
	return result

func _find_meshes(node: Node) -> Array[VisualInstance3D]:
	var out: Array[VisualInstance3D] = []
	if node is VisualInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_meshes(c))
	return out
