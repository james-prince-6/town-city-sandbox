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
## Orientation tweak so models face the player sensibly. Used as the BASE pose for items that
## opt out of auto-orient (auto_orient_held = false) — bows, shields, chunky tools.
@export var held_rotation_degrees: Vector3 = Vector3(0.0, 180.0, 0.0)
## Auto-orient aim: the direction (in this node's local frame, -Z forward / +Y up) that an
## auto-oriented weapon's business end points toward. Up-and-forward reads as "held ready".
## This is the SINGLE knob to retune the look of every auto-oriented weapon at once.
const HELD_AIM: Vector3 = Vector3(0.0, 0.6, -0.8)
## A model only auto-orients when its longest axis is at least this many times its average
## cross-section — i.e. it's clearly a long thin blade/shaft, not a chunky block (pickaxe head,
## lantern, shield). Below this the long axis is ambiguous, so we keep the manual base pose.
const AUTO_MIN_ELONG: float = 2.2

var _current: Node3D
var _swing_tween: Tween
# The current item's resting pose (base pose + the item's per-item offsets), so the swing
# animation returns to the right spot for each weapon.
var _rest_position: Vector3
var _rest_rotation: Vector3

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
	# Kill any in-flight swing tween before freeing the model it animates, so it doesn't step
	# on a freed node when the selection changes mid-swing.
	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
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
	_apply_held_transform(model, item)
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

# Size, orient and place the model in the hand. Two paths:
#   AUTO  (default, for clearly elongated weapons) — derive orientation from the geometry: point
#         the long axis (blade/shaft) up-and-forward (HELD_AIM) with the grip resting in the hand,
#         so a weapon looks right with NO per-item rotation tuning. held_rotation_offset is then a
#         small local-space nudge (normally zero).
#   MANUAL (auto_orient_held = false, or a model too chunky to have an obvious long axis) — the
#         classic fixed base pose (held_rotation_degrees) plus the item's held_rotation_offset.
# Both paths normalise size to held_size * held_scale and record _rest_position/_rest_rotation so
# the swing animation returns to the right pose.
func _apply_held_transform(model: Node3D, item: Item) -> void:
	# Measure at unit scale first so axis sign / elongation are scale-independent.
	var aabb := _aabb(model)
	var sz := aabb.size
	var longest: float = max(sz.x, max(sz.y, sz.z))
	var scale_factor: float = item.held_scale
	if longest > 0.0:
		scale_factor = (held_size / longest) * item.held_scale
	# Never allow a zero/negative scale: in the auto path it makes a singular basis whose
	# decomposed euler is NaN, which then poisons _rest_rotation and the swing tween.
	scale_factor = maxf(scale_factor, 0.0001)

	# Primary (longest) axis index and how elongated the model is along it.
	var i := 0
	if sz.y >= sz.x and sz.y >= sz.z:
		i = 1
	elif sz.z >= sz.x and sz.z >= sz.y:
		i = 2
	var perp: float = (sz[(i + 1) % 3] + sz[(i + 2) % 3]) * 0.5
	var elong: float = longest / max(0.0001, perp)

	var use_auto: bool = item.auto_orient_held and elong >= AUTO_MIN_ELONG and longest > 0.0
	if use_auto:
		var mn: float = aabb.position[i]
		var mx: float = aabb.position[i] + sz[i]
		# Business end = the end FARTHER from the model origin (kits author the grip at/near the
		# origin). Aim grip->head along HELD_AIM.
		var axis := Vector3.ZERO
		axis[i] = 1.0
		var grip_to_head: Vector3 = axis if absf(mx) >= absf(mn) else -axis
		var q := _from_to_quat(grip_to_head, HELD_AIM)
		# Optional local-space fine-tune nudge (usually zero for auto items).
		if item.held_rotation_offset != Vector3.ZERO:
			var o := item.held_rotation_offset
			q = q * Quaternion.from_euler(Vector3(deg_to_rad(o.x), deg_to_rad(o.y), deg_to_rad(o.z)))
		# Rotate about the model origin (≈ the grip), so the grip stays in the hand.
		var basis := Basis(q).scaled(Vector3.ONE * scale_factor)
		model.transform = Transform3D(basis, held_position + item.held_position_offset)
		_rest_position = model.position
		_rest_rotation = model.rotation_degrees
	else:
		model.scale = Vector3.ONE * scale_factor
		_rest_position = held_position + item.held_position_offset
		_rest_rotation = held_rotation_degrees + item.held_rotation_offset
		model.position = _rest_position
		model.rotation_degrees = _rest_rotation

# Shortest-arc rotation that turns unit vector `from` onto unit vector `to`.
func _from_to_quat(from: Vector3, to: Vector3) -> Quaternion:
	var a := from.normalized()
	var b := to.normalized()
	var d: float = a.dot(b)
	if d > 0.99999:
		return Quaternion.IDENTITY
	if d < -0.99999:
		# Antiparallel: rotate 180° about any axis perpendicular to `a`.
		var perp_axis := a.cross(Vector3.UP)
		if perp_axis.length() < 0.0001:
			perp_axis = a.cross(Vector3.RIGHT)
		return Quaternion(perp_axis.normalized(), PI)
	var axis := a.cross(b).normalized()
	var angle: float = acos(clampf(d, -1.0, 1.0))
	return Quaternion(axis, angle)

# Play a quick swing (melee) or recoil (ranged) on the current model. Other item
# kinds (consumables, tools) don't animate.
func _on_item_used(item) -> void:
	if not is_instance_valid(_current):
		return
	# Melee = a MeleeWeaponItem OR a ToolItem whose job is WEAPON (swords/axes/clubs are tools).
	var is_melee: bool = item is MeleeWeaponItem or (item is ToolItem and (item as ToolItem).tool_type == ToolItem.ToolType.WEAPON)
	var is_ranged: bool = item is RangedWeaponItem
	if not (is_melee or is_ranged):
		return

	if _swing_tween and _swing_tween.is_valid():
		_swing_tween.kill()
	# Snap back to rest first so rapid clicks each start from the same pose.
	_current.position = _rest_position
	_current.rotation_degrees = _rest_rotation

	_swing_tween = create_tween()
	if is_ranged:
		# Short recoil toward the camera, then settle.
		_swing_tween.tween_property(_current, "position", _rest_position + Vector3(0.0, 0.02, 0.12), 0.05)
		_swing_tween.tween_property(_current, "position", _rest_position, 0.12)
	else:
		# A proper slash: a quick wind-up up-and-back, then a diagonal strike down across
		# the body, then ease back to rest. The wind-up is what makes it read as a forward
		# swing rather than looking like it plays in reverse.
		var windup_rot := _rest_rotation + Vector3(28.0, 0.0, 35.0)
		var windup_pos := _rest_position + Vector3(0.07, 0.06, 0.07)
		var strike_rot := _rest_rotation + Vector3(-45.0, 0.0, -55.0)
		var strike_pos := _rest_position + Vector3(-0.09, -0.07, -0.2)
		_swing_tween.tween_property(_current, "rotation_degrees", windup_rot, 0.06)
		_swing_tween.parallel().tween_property(_current, "position", windup_pos, 0.06)
		_swing_tween.tween_property(_current, "rotation_degrees", strike_rot, 0.07)
		_swing_tween.parallel().tween_property(_current, "position", strike_pos, 0.07)
		_swing_tween.tween_property(_current, "rotation_degrees", _rest_rotation, 0.16)
		_swing_tween.parallel().tween_property(_current, "position", _rest_position, 0.16)

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
