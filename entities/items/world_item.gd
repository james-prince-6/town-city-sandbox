# world_item.gd
# A physical, pick-up-able item lying in the world (a RigidBody3D so it tumbles
# and settles on the ground). Think of dropped loot: a rock breaks and spits out
# a chunk of stone, a critter dies and drops meat. Each WorldItem represents a
# little pile of one item type that the player can walk up to and grab.
#
# How the player picks it up (the default):
# - The player aims at the item and presses E, exactly like NPCs, chests, and
#   harvestables. The player's interaction RayCast3D duck-types whatever body it
#   hits: any body that answers get_interaction_prompt() shows a "[E] ..." prompt,
#   and pressing E calls interact(player). We implement both, so no special-casing
#   is needed in the player code — it "just works" like every other interactable.
#   (For this to work the body must sit on a collision layer the player's
#   interaction ray scans; see world_item.tscn — both default to layer 1.)
#
# - There is NO automatic walk-over vacuum by default anymore. The old "grab loot
#   just by walking near it" behavior still exists behind `auto_pickup`, but it's
#   opt-in (off by default) — see auto_pickup below.
#
# How loot spawns these:
# - Harvestables and critters call the static helper WorldItem.spawn(...). That
#   instances the scene, fills in the item id + amount, drops it into the world,
#   and gives it a little upward pop so it doesn't appear buried in the ground.

class_name WorldItem
extends RigidBody3D

## Which item this pickup grants. Should match an id in the Inventory database
## (e.g. &"stone", &"driftwood"). Set per-instance in the Inspector or via spawn().
@export var item_id: StringName = &""

## How many of `item_id` the player receives when picking this up.
@export var amount: int = 1

## Target size (largest dimension, in metres) the dropped model is scaled to fit.
## Kenney models ship at wildly different native scales — a banana and a bookcase
## would otherwise drop at completely different sizes. Normalizing to one target
## makes every pickup read as a consistent, grabbable little object on the ground.
@export var pickup_size: float = 0.35

## Opt-in legacy walk-over pickup. When true, the player collects this just by
## walking near it (no aiming needed). This is OFF by default: floor loot is now
## grabbed like every other interactable — look at it and press E. Leave this
## false unless you specifically want the old "walk-over vacuum" behavior for a
## particular item. Dropped loot sits low, so the player looks down to aim at it.
@export var auto_pickup: bool = false

## How close (metres) the player must get for walk-over pickup to trigger.
@export var pickup_radius: float = 1.3

# Guards against double-collecting (e.g. the walk-over area and an E press both firing).
var _collected: bool = false

func _ready() -> void:
	_show_item_model()
	_setup_pickup_area()

# Wire up the walk-over pickup: when the player's body enters the PickupArea, collect.
# The area sizes itself to `pickup_radius` (duplicating the shape so each instance is
# independent). Disabled cleanly when auto_pickup is off.
func _setup_pickup_area() -> void:
	var area := get_node_or_null("PickupArea") as Area3D
	if area == null:
		return
	if not auto_pickup:
		area.monitoring = false
		return
	var col := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col and col.shape is SphereShape3D:
		col.shape = col.shape.duplicate()  # don't mutate the shape shared across instances
		(col.shape as SphereShape3D).radius = pickup_radius
	area.body_entered.connect(_on_pickup_body_entered)

func _on_pickup_body_entered(body: Node) -> void:
	# Only the player vacuums loot — not other items, critters, or NPCs.
	if body.is_in_group("player"):
		_collect(body)

# If this item type defines a 3D world_model, instance it (scaled and centered to
# a consistent pickup size) and hide the default placeholder cube. Falls back to
# the cube when no model is set. item_id is filled in before the node enters the
# tree (see spawn / the Inspector), so it's ready here.
func _show_item_model() -> void:
	var item: Item = Inventory.get_item(item_id)
	if item == null or item.world_model == null:
		return

	var model := item.world_model.instantiate() as Node3D
	if model == null:
		return
	add_child(model)

	# Hide the placeholder cube only once we actually have a real model to show.
	var placeholder := get_node_or_null("MeshInstance3D")
	if placeholder:
		placeholder.visible = false

	_normalize_model(model)

# Scale the freshly-instanced model down to `pickup_size`, re-center it on the
# body origin, and resize the collision box to match. The model enters at scale 1
# / position 0 / no rotation, so its visual bounds (computed below) are expressed
# directly in this body's local space — no rotation math needed.
func _normalize_model(model: Node3D) -> void:
	var aabb := _combined_visual_aabb(model)
	if aabb.size == Vector3.ZERO:
		return

	var largest: float = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
	var s: float = 1.0 if largest <= 0.0 else pickup_size / largest
	model.scale = Vector3.ONE * s

	# Centre the model on X/Z but rest its BOTTOM on the body origin, so the pickup sits ON
	# the ground while its (taller) collider rises up from there — see _fit_collision.
	var center_x: float = aabb.position.x + aabb.size.x * 0.5
	var center_z: float = aabb.position.z + aabb.size.z * 0.5
	model.position = Vector3(-center_x * s, -aabb.position.y * s, -center_z * s)

	_fit_collision(aabb.size * s)

# Build the body's collider. We deliberately make it a TALLER box than the (often tiny)
# loot model: floor loot scaled to `pickup_size` is a sub-10 cm target that the player's
# eye-level interaction ray sails clean over, making "look at it and press E" almost
# impossible. A minimum knee-high box (rising UP from the body origin, so the item still
# rests on the ground) gives a comfortable aim target without floating the item.
func _fit_collision(size: Vector3) -> void:
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col == null:
		return
	var box := BoxShape3D.new()
	box.size = Vector3(maxf(size.x, 0.35), maxf(size.y, 0.55), maxf(size.z, 0.35))
	col.shape = box
	# Bottom of the box at the body origin (where the model's feet sit) so it extends upward.
	col.position = Vector3(0.0, box.size.y * 0.5, 0.0)

# Union of every descendant mesh's bounds, expressed in `model`'s local space.
# (Mirrors the auto-fit pattern used by entities/props/prop.gd.)
func _combined_visual_aabb(model: Node3D) -> AABB:
	var result := AABB()
	var found := false
	for vi in _find_visuals(model):
		var local_to_model := model.global_transform.affine_inverse() * vi.global_transform
		var box := local_to_model * vi.get_aabb()
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

# --- Interaction (duck-typed by the player's RayCast3D) --------------------

## The text shown in the interaction prompt while the player is looking at this.
## Falls back to the raw id if the item isn't in the database yet.
func get_interaction_prompt() -> String:
	var item: Item = Inventory.get_item(item_id)
	var name_text: String = item.display_name if item != null else String(item_id)
	return "Pick up %s" % name_text

## Called when the player presses the interact key while looking at this item.
## This is the normal pickup path — aim at the loot on the floor and press E.
func interact(player: Node) -> void:
	_collect(player)

# The single pickup path, shared by walk-over and the E-press, guarded so the loot
# is only granted once. Adds it to the Inventory, then removes the body.
func _collect(_player: Node) -> void:
	if _collected:
		return
	if item_id == &"":
		push_warning("WorldItem: item_id is empty, nothing to pick up.")
		queue_free()
		return
	_collected = true
	Inventory.add(item_id, amount)
	queue_free()

# --- Spawning loot ---------------------------------------------------------

## Drops a fresh WorldItem into `world` at `global_pos` and returns it.
##
## Used by harvestables/critters to scatter loot. We give each spawned item a
## small upward (and slightly sideways) impulse so a burst of drops fans out
## instead of stacking in one spot. The spread is DETERMINISTIC — derived from
## `index` and the spawn position rather than a random number — so the same loot
## drop looks the same every time (handy for save/replay and easier to debug).
static func spawn(
		item_id: StringName,
		amount: int,
		world: Node,
		global_pos: Vector3,
		index: int = 0
	) -> WorldItem:
	# Load and instance the scene that pairs with this script.
	var scene: PackedScene = load("res://entities/items/world_item.tscn")
	if scene == null:
		push_warning("WorldItem.spawn: could not load world_item.tscn")
		return null

	var item: WorldItem = scene.instantiate() as WorldItem
	item.item_id = item_id
	item.amount = amount

	# Must be in the tree before we can set a global position safely.
	world.add_child(item)
	item.global_position = global_pos

	# Build a deterministic-but-varied impulse. We fan drops out in a circle using
	# the index as an angle, and nudge the strength using the spawn position so two
	# drops at different spots don't move identically. No Math.random involved.
	var angle: float = float(index) * 2.39996  # ~golden angle, spreads points evenly
	var horizontal_kick: float = 1.5
	var upward_kick: float = 3.0
	# Tiny positional jitter so co-located bursts still differ a little.
	var pos_jitter: float = fposmod(global_pos.x + global_pos.z, 1.0)

	var impulse := Vector3(
		cos(angle) * horizontal_kick,
		upward_kick + pos_jitter,
		sin(angle) * horizontal_kick
	)
	item.apply_central_impulse(impulse)

	return item
