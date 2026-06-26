# lever.gd
# A switch that drives another node — most commonly a Door. Interacting flips the
# lever, tilts its handle, and calls a method (default "toggle") on the node at
# `target_path`. So a Lever pointed at a Door, with target_method "open", opens that
# door from across the room; with "toggle" it works as an on/off latch.
#
# It's deliberately generic: target_method can be any zero-arg method the target
# exposes — Door.open()/close()/toggle(), or your own activate() on something else —
# so the same script doubles as a floor button, wall switch, or pull-chain.
#
# Duck-typed interaction: implements get_interaction_prompt()/interact(player).

class_name Lever
extends StaticBody3D

## The node this lever controls (e.g. a Door). Set in the Inspector.
@export var target_path: NodePath

## Method called on the target each activation. "toggle" flips a door; use "open"
## for a one-way switch, or "activate" for custom machines.
@export var target_method: StringName = &"toggle"

## When true the lever can only be thrown once (one-shot gate trigger); after that
## it's spent and the prompt goes inert. When false it latches both ways.
@export var one_shot: bool = false

## The handle node that tilts on use. Defaults to "Handle".
@export var handle_path: NodePath = ^"Handle"
## Handle tilt (radians) in the "on" position, and tween duration.
@export var on_angle: float = 0.9
@export var move_time: float = 0.25

@export var prompt: String = "Pull lever"
@export var spent_prompt: String = "Lever (spent)"

# Current latch state and whether a one-shot lever has been used up.
var _on: bool = false
var _spent: bool = false
var _rest_rotation: float = 0.0

func _ready() -> void:
	var handle := _handle()
	if handle != null:
		_rest_rotation = handle.rotation.z

func _handle() -> Node3D:
	return get_node_or_null(handle_path) as Node3D

# --- Interaction (duck-typed by the player's RayCast3D) --------------------

func get_interaction_prompt() -> String:
	return spent_prompt if _spent else prompt

func interact(_player: Node) -> void:
	if _spent:
		return
	_on = not _on
	_animate_handle()
	_drive_target()
	if one_shot:
		_spent = true

# --- Driving the target ----------------------------------------------------

func _drive_target() -> void:
	if target_path.is_empty():
		push_warning("Lever '%s': no target_path set." % name)
		return
	var target := get_node_or_null(target_path)
	if target == null:
		push_warning("Lever '%s': target_path points at nothing." % name)
		return
	if not target.has_method(target_method):
		push_warning("Lever '%s': target has no method '%s'." % [name, target_method])
		return
	target.call(target_method)

# --- Handle animation ------------------------------------------------------

func _animate_handle() -> void:
	var handle := _handle()
	if handle == null:
		return
	var target_rot: float = _rest_rotation + (on_angle if _on else 0.0)
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(handle, "rotation:z", target_rot, move_time)
