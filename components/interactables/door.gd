# door.gd
# An openable door. Drop this on a StaticBody3D whose child "Pivot" holds the door
# leaf model; opening rotates the pivot (a swing) or, if `slide_open` is on, slides
# the pivot sideways. Either way the door's collider is disabled while open so the
# player can walk through.
#
# Locking: set `required_key` to an item id (e.g. &"copper_ore" used as a stand-in
# key) and the door stays locked until the player has one. Interacting while locked
# shows "Locked — needs X". The first successful open CONSUMES one key from the
# Inventory (set consume_key = false for a reusable key). Set required_key empty for
# a free door.
#
# Remote control: a Lever/Button calls open() directly. open() ignores the lock (a
# lever is its own "key"), so puzzle doors can be wired to switches. close()/toggle()
# are provided too for switches that latch.
#
# Duck-typed interaction: implements get_interaction_prompt()/interact(player).

class_name Door
extends StaticBody3D

## Item id required to unlock (and, if consume_key, spent on first open). Empty =
## unlocked. Reuse an existing Inventory id; the dungeons use &"copper_ore".
@export var required_key: StringName = &""

## Spend one `required_key` from the Inventory the first time the door is opened.
@export var consume_key: bool = true

## Swing (rotate the pivot) by default; flip this to slide it sideways instead.
@export var slide_open: bool = false

## Swing target angle in radians (used when slide_open is false).
@export var open_angle: float = 1.4
## Slide offset in metres along the pivot's local X (used when slide_open is true).
@export var slide_offset: float = 2.2
## How long the open/close tween runs.
@export var move_time: float = 0.5

## The child node that actually moves. Defaults to "Pivot".
@export var pivot_path: NodePath = ^"Pivot"
## The door's blocking collider, disabled while open. Defaults to "CollisionShape3D".
@export var collider_path: NodePath = ^"CollisionShape3D"

@export var open_prompt: String = "Open door"
@export var close_prompt: String = "Close door"

var _open: bool = false
# Remembered so swing/slide can return exactly to the shut pose.
var _closed_rotation: float = 0.0
var _closed_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	var pivot := _pivot()
	if pivot != null:
		_closed_rotation = pivot.rotation.y
		_closed_position = pivot.position

func _pivot() -> Node3D:
	return get_node_or_null(pivot_path) as Node3D

# --- Interaction (duck-typed by the player's RayCast3D) --------------------

func get_interaction_prompt() -> String:
	if _open:
		return close_prompt
	if _is_locked():
		return "Locked — needs %s" % _key_label()
	return open_prompt

func interact(_player: Node) -> void:
	if _open:
		close()
		return
	if _is_locked():
		# No key yet — refuse, leave it shut. The prompt already told the player why.
		return
	# Spend the key on the first open only (door is now permanently unlocked-feeling).
	if required_key != &"" and consume_key:
		Inventory.remove(required_key, 1)
	open()

# --- Lock helpers ----------------------------------------------------------

func _is_locked() -> bool:
	return required_key != &"" and not Inventory.has(required_key, 1)

# Prefer the item's display name for the prompt; fall back to the raw id.
func _key_label() -> String:
	var item: Item = Inventory.get_item(required_key)
	return item.display_name if item != null else String(required_key)

# --- Open / close (also called by levers) ----------------------------------

## Open the door. Safe to call repeatedly and from a Lever — it bypasses the lock,
## so wire puzzle doors to a switch and let the switch be the "key".
func open() -> void:
	if _open:
		return
	_open = true
	_set_collider_disabled(true)
	_animate_to_open()

## Shut the door again (used by latching switches / the close prompt).
func close() -> void:
	if not _open:
		return
	_open = false
	_animate_to_closed()
	# Re-enable the collider only once it's actually shut, so the player isn't
	# caught inside it mid-swing.
	await get_tree().create_timer(move_time).timeout
	_set_collider_disabled(false)

## Flip whichever way the door currently is. Handy default for levers.
func toggle() -> void:
	if _open:
		close()
	else:
		open()

func _animate_to_open() -> void:
	var pivot := _pivot()
	if pivot == null:
		return
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if slide_open:
		tween.tween_property(pivot, "position", _closed_position + Vector3(slide_offset, 0.0, 0.0), move_time)
	else:
		tween.tween_property(pivot, "rotation:y", _closed_rotation + open_angle, move_time)

func _animate_to_closed() -> void:
	var pivot := _pivot()
	if pivot == null:
		return
	var tween := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	if slide_open:
		tween.tween_property(pivot, "position", _closed_position, move_time)
	else:
		tween.tween_property(pivot, "rotation:y", _closed_rotation, move_time)

func _set_collider_disabled(disabled: bool) -> void:
	var col := get_node_or_null(collider_path) as CollisionShape3D
	if col != null:
		# set_deferred: never toggle physics state mid-callback.
		col.set_deferred("disabled", disabled)
