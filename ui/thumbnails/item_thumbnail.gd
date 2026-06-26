# item_thumbnail.gd
# Autoload singleton (register as "ItemThumbnail"). Turns an item's 3D world_model
# into a small 2D Texture2D so inventory/hotbar slots can show a real picture of the
# item instead of just its name.
#
# How it works: a single hidden SubViewport (with its own isolated World3D, a camera
# and two lights) renders ONE model at a time to a 128x128 transparent image, which is
# copied into a stable ImageTexture and cached by item id. Renders are queued and run
# sequentially, one model per couple of frames, so a full bag rebuild never stalls.
#
# Because render-to-texture has a one-frame delay, get_texture() returns null the first
# time an id is requested (and kicks off the render); callers either listen to
# thumbnail_ready or, more simply, use make_visual()/apply_to() which patch the texture
# in automatically once it's ready.
#
# NOTE: this script must NOT declare `class_name ItemThumbnail` — that name is the
# autoload singleton, and a matching class_name would collide with it.

extends Node

## Emitted once a model has finished rendering to a texture. Carries the item id and
## the finished texture. Mostly used internally (see _deliver); external listeners may
## use it too.
signal thumbnail_ready(id: StringName, texture: Texture2D)

## Square pixel size of every rendered thumbnail.
const RENDER_SIZE := Vector2i(128, 128)

# Finished textures, keyed by item id. Never re-rendered once cached.
var _cache: Dictionary = {}        # StringName -> ImageTexture
# Ids currently queued or mid-render, so we never enqueue the same one twice.
var _pending: Dictionary = {}      # StringName -> true
# FIFO of ids waiting to render.
var _queue: Array[StringName] = []
# True while a render await is in flight (keeps the queue strictly sequential).
var _busy: bool = false
# TextureRects waiting for a given id's render to finish, keyed by id.
var _waiting: Dictionary = {}      # StringName -> Array[TextureRect]

var _viewport: SubViewport
var _camera: Camera3D
var _model_holder: Node3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_viewport()

# Build the offscreen render rig once: a SubViewport with its own World3D so nothing
# from the live game scene leaks in, a perspective camera, and key+fill lights.
func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = RENDER_SIZE
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true   # isolated world so the live scene never leaks in
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_viewport)

	_camera = Camera3D.new()
	_camera.current = true
	_camera.near = 0.01
	_viewport.add_child(_camera)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	key.light_energy = 1.2
	_viewport.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, 140.0, 0.0)
	fill.light_energy = 0.5
	_viewport.add_child(fill)

	_model_holder = Node3D.new()
	_viewport.add_child(_model_holder)

# --- Public API ------------------------------------------------------------

## Returns the cached thumbnail for `id`, or null if it isn't rendered yet. A null
## return also kicks off the render in the background; listen to thumbnail_ready (or
## use make_visual/apply_to) to get the texture once it's ready.
func get_texture(id: StringName) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	_request(id)
	return null

## Builds a ready-to-add slot visual for an item id: a TextureRect showing the 3D
## thumbnail (falling back to the 2D icon, then updating to the thumbnail once it
## renders), or a wrapped-text Label when the item has no art at all. Used by the
## inventory grid, the hotbar drop row, the HUD, and drag previews.
func make_visual(id: StringName, px: float) -> Control:
	var item: Item = Inventory.get_item(id)
	if item != null and (item.world_model != null or item.icon != null):
		var tr := TextureRect.new()
		tr.custom_minimum_size = Vector2(px, px)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		apply_to(tr, id)
		return tr
	var lbl := Label.new()
	lbl.text = item.display_name if item != null else String(id)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl

## Points an existing TextureRect at an item's thumbnail. Uses the cached texture if
## ready; otherwise shows the 2D icon (if any) as a placeholder and swaps in the 3D
## thumbnail the moment it finishes rendering.
func apply_to(rect: TextureRect, id: StringName) -> void:
	var item: Item = Inventory.get_item(id)
	if item == null:
		return
	if item.world_model != null:
		var tex: Texture2D = get_texture(id)
		if tex != null:
			rect.texture = tex
		else:
			if item.icon != null:
				rect.texture = item.icon
			_register_waiting(rect, id)
	elif item.icon != null:
		rect.texture = item.icon

# --- Render queue ----------------------------------------------------------

func _request(id: StringName) -> void:
	if _cache.has(id) or _pending.has(id):
		return
	var item: Item = Inventory.get_item(id)
	if item == null or item.world_model == null:
		return
	_pending[id] = true
	_queue.append(id)
	_process_queue()

func _process_queue() -> void:
	if _busy or _queue.is_empty():
		return
	_busy = true
	var id: StringName = _queue.pop_front()
	await _render(id)
	_busy = false
	_process_queue()

func _render(id: StringName) -> void:
	var item: Item = Inventory.get_item(id)
	if item == null or item.world_model == null:
		_fail_render(id, item)
		return

	for c in _model_holder.get_children():
		c.queue_free()

	var model: Node3D = item.world_model.instantiate() as Node3D
	if model == null:
		_fail_render(id, item)
		return
	_model_holder.add_child(model)

	# Let the freshly added model's transforms/bounds settle before we read its AABB.
	await get_tree().process_frame
	_frame_camera(model)

	# Render exactly one frame, then grab the pixels after the draw completes.
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	var img: Image = _viewport.get_texture().get_image()
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED

	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_cache[id] = tex
	_pending.erase(id)
	model.queue_free()

	_deliver(id, tex)
	thumbnail_ready.emit(id, tex)

# A render couldn't run (item/model failed to instance). Cache a fallback texture (the item's
# 2D icon if it has one, else a 1x1 transparent pixel) so the id is NEVER re-queued — otherwise
# get_texture() would re-request and re-fail on every redraw — and resolve any waiting rects so
# they stop sitting on a placeholder forever (and _waiting[id] doesn't leak).
func _fail_render(id: StringName, item: Item) -> void:
	var tex: Texture2D
	if item != null and item.icon != null:
		tex = item.icon
	else:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.set_pixel(0, 0, Color(0, 0, 0, 0))
		tex = ImageTexture.create_from_image(img)
	_cache[id] = tex
	_pending.erase(id)
	_deliver(id, tex)

# Position the camera so the whole model fits, viewed from a pleasant 3/4 angle.
func _frame_camera(model: Node3D) -> void:
	var aabb: AABB = _combined_visual_aabb(model)
	var center: Vector3 = aabb.position + aabb.size * 0.5
	var radius: float = maxf(aabb.size.length() * 0.5, 0.001)
	var fov: float = 30.0
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.fov = fov
	var dist: float = radius / sin(deg_to_rad(fov * 0.5)) * 1.1
	var dir: Vector3 = Vector3(1.0, 0.7, 1.0).normalized()
	_camera.position = center + dir * dist
	_camera.look_at(center, Vector3.UP)
	_camera.far = dist + radius * 2.0 + 10.0

# Union of every descendant mesh's bounds, in `model`'s local space. Mirrors the
# auto-fit pattern in entities/items/world_item.gd and entities/props/prop.gd.
func _combined_visual_aabb(model: Node3D) -> AABB:
	var result := AABB()
	var found: bool = false
	for vi in _find_visuals(model):
		var local_to_model: Transform3D = model.global_transform.affine_inverse() * vi.global_transform
		var box: AABB = local_to_model * vi.get_aabb()
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

# --- Deferred texture delivery --------------------------------------------

func _register_waiting(rect: TextureRect, id: StringName) -> void:
	if not _waiting.has(id):
		_waiting[id] = []
	(_waiting[id] as Array).append(rect)

func _deliver(id: StringName, tex: Texture2D) -> void:
	if not _waiting.has(id):
		return
	for r in _waiting[id]:
		if is_instance_valid(r):
			(r as TextureRect).texture = tex
	_waiting.erase(id)
