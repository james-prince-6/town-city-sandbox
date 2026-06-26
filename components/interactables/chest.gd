# chest.gd
# A one-shot lootable container. Drop this script on a StaticBody3D with a chest
# model child ("Model"). The first time the player interacts, it grants a
# LootTable's contents (added to the Inventory and/or spilled as WorldItems), plays
# a quick "lid lift" tween, then becomes inert — the prompt changes to "Opened" and
# further interactions do nothing.
#
# Persistence: each chest carries an exported `chest_id`. On open we set the
# GameState flag "chest_opened/<chest_id>". On _ready we read that flag back, so a
# chest the player already looted stays open (and gives nothing) on a return visit.
# Give every placed chest a UNIQUE chest_id or they'll share open-state.
#
# Duck-typed interaction: implements get_interaction_prompt()/interact(player) just
# like WorldItem/NPCs, so the player's raycast picks it up with no special-casing.

class_name Chest
extends StaticBody3D

## Unique id used to remember this specific chest's opened state across scene
## reloads (stored as the GameState flag below). MUST be unique per placed chest.
@export var chest_id: StringName = &"chest_unset"

## What spills out. Authored as a LootTable resource in the Inspector. May be left
## null for a purely decorative / empty chest (it still opens, just gives nothing).
@export var loot: LootTable

## Add rolled loot straight to the player's Inventory (the convenient path).
@export var grant_to_inventory: bool = true

## Also spawn the rolled loot as physical WorldItems that pop out of the chest, so
## opening feels tactile. If grant_to_inventory is also true the player effectively
## gets the loot twice — usually pick ONE. Defaults to inventory-only.
@export var spill_world_items: bool = false

## Prompt shown while still closed / already opened.
@export var closed_prompt: String = "Open chest"
@export var opened_prompt: String = "Opened"

## The child node lifted/rotated by the open tween. Defaults to "Model" (the chest
## mesh). If your model has a separate lid node, point this at it for a nicer hinge.
@export var lid_path: NodePath = ^"Model"

## How far (radians) the lid tilts back when opening, and how long the tween runs.
@export var lid_open_angle: float = -1.2
@export var open_tween_time: float = 0.4

# True once this chest has been opened (this session or a prior one).
var _opened: bool = false

func _ready() -> void:
	# Restore opened-state from a previous visit so loot isn't handed out twice.
	if GameState.get_flag(_flag_name(), false):
		_opened = true
		_snap_lid_open()

func _flag_name() -> StringName:
	return StringName("chest_opened/%s" % chest_id)

# --- Interaction (duck-typed by the player's RayCast3D) --------------------

func get_interaction_prompt() -> String:
	return opened_prompt if _opened else closed_prompt

func interact(player: Node) -> void:
	if _opened:
		return
	_opened = true
	GameState.set_flag(_flag_name(), true)
	_give_loot(player)
	_play_open_tween()

# --- Loot ------------------------------------------------------------------

func _give_loot(_player: Node) -> void:
	if loot == null:
		return
	var rolled: Dictionary = loot.roll()
	for id: StringName in rolled.keys():
		var amount: int = rolled[id]
		if amount <= 0:
			continue
		if grant_to_inventory:
			Inventory.add(id, amount)
		if spill_world_items:
			_spill(id, amount)

# Running counter so successive spills from this chest fan out instead of stacking.
var _spill_index: int = 0

# Pop loot out of the top of the chest as physical pickups. Each id gets one
# WorldItem carrying the whole stack; the index fans the impulses apart.
func _spill(id: StringName, amount: int) -> void:
	var origin: Vector3 = global_position + Vector3.UP * 0.6
	WorldItem.spawn(id, amount, SceneManager.current_world(), origin, _spill_index)
	_spill_index += 1

# --- Open animation --------------------------------------------------------

func _play_open_tween() -> void:
	var lid := get_node_or_null(lid_path) as Node3D
	if lid == null:
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(lid, "rotation:x", lid_open_angle, open_tween_time)

# For chests opened on a previous visit, jump straight to the open pose (no tween).
func _snap_lid_open() -> void:
	var lid := get_node_or_null(lid_path) as Node3D
	if lid == null:
		return
	lid.rotation.x = lid_open_angle
