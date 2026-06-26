# harvestable.gd
# A thing in the world you work at with a tool until it gives up its loot: a rock
# you mine, a plant you pick, a lava pool you ladle from. This is the BASE scene
# for the "hybrid" entity pattern — concrete kinds (rock, plant, lava_pool) are
# Godot INHERITED scenes that just duplicate this one and tweak the exported
# values + swap the MeshInstance3D in the Inspector. No code per variant.
#
# How the player works it (duck-typed, no special-casing in player.gd):
# - The player's interaction RayCast3D hits this StaticBody3D and calls
#   get_interaction_prompt() to show "[E] Mine Rock", then interact(player) on E.
# - interact() checks the equipped Hotbar tool, spends stamina, and chips away at
#   `durability`. When durability runs out it awards the drops and either frees
#   itself or hides + respawns after a delay.
#
# Tool gating:
# - If required_tool_type is NONE, anything works (hand-picked plants). Otherwise
#   the equipped item must be a ToolItem whose tool_type matches AND whose power
#   is at least required_power. A bare hand or wrong/weak tool does nothing.

extends StaticBody3D

# --- Tool requirement ------------------------------------------------------

## What kind of tool is needed to work this. NONE = hand-pickable (no tool needed).
## Uses the same enum the ToolItem resource defines so they compare directly.
@export var required_tool_type: ToolItem.ToolType = ToolItem.ToolType.NONE

## Minimum tool power required. The equipped tool's `power` must be >= this. Lets
## tougher nodes demand a better pickaxe even when the tool TYPE already matches.
@export var required_power: int = 1

## How many successful harvests this node takes before it's depleted. Each valid
## interact() that spends stamina knocks one off.
@export var durability: int = 3

# --- Loot ------------------------------------------------------------------

## Item id awarded when this node is fully harvested. Must exist in the Inventory
## database (e.g. &"iron_ore", &"plant_fiber").
@export var drop_item_id: StringName = &""

## How many of `drop_item_id` to award.
@export var drop_amount: int = 1

## true  -> spawn physical WorldItem pickups near the node (player grabs them).
## false -> add straight to the Inventory (e.g. hand-picked plants you pocket).
@export var drop_as_world_item: bool = true

# --- Presentation / lifecycle ---------------------------------------------

## Verb used in the prompt, combined with the node name: "Mine" -> "Mine Rock".
@export var prompt_verb: String = "Harvest"

## If > 0, the node hides itself when depleted and reappears (refilled) after this
## many seconds instead of being removed. 0 = just queue_free() when depleted.
@export var respawn_seconds: float = 0.0

# --- Internal state --------------------------------------------------------

## Remaining harvests this run. Reset back to `durability` on respawn.
var _remaining: int = 0

## Default stamina cost used when the node needs no tool (NONE) but we still want
## working it to cost a little effort.
const HAND_STAMINA_COST: float = 5.0

func _ready() -> void:
	_remaining = durability

# --- Interaction (duck-typed by the player's RayCast3D) --------------------

## Text shown in the player's prompt while they look at this node, e.g. "Mine Rock".
func get_interaction_prompt() -> String:
	return "%s %s" % [prompt_verb, name]

## Called when the player presses interact while aiming at this node. Validates the
## equipped tool, spends stamina, and advances the harvest. Bails out quietly (with
## a push_warning hint) when the player can't make progress.
func interact(_player: Node) -> void:
	# The equipped item from the hotbar. May be null (empty hand) or a plain Item.
	var selected: Item = Hotbar.get_selected_item()
	# It only counts as a usable tool if it's actually a ToolItem.
	var tool: ToolItem = selected as ToolItem

	# --- Tool gating: does the equipped thing satisfy our requirement? ---
	if required_tool_type != ToolItem.ToolType.NONE:
		if tool == null:
			push_warning("Harvestable '%s' needs a tool but none is equipped." % name)
			return
		if tool.tool_type != required_tool_type:
			push_warning("Harvestable '%s' needs tool type %d, got %d." % [name, required_tool_type, tool.tool_type])
			return
		if tool.power < required_power:
			push_warning("Harvestable '%s' needs power %d, equipped tool has %d." % [name, required_power, tool.power])
			return

	# --- Stamina: a swing costs effort. Abort if the player is too tired. ---
	# Use the tool's cost when we have one, otherwise the flat hand cost.
	var cost: float = tool.stamina_cost if tool != null else HAND_STAMINA_COST
	if not PlayerStats.use_stamina(cost):
		push_warning("Harvestable '%s': not enough stamina to work it." % name)
		return

	# --- Progress: chip away one harvest. ---
	_remaining -= 1
	if _remaining > 0:
		# Still more to go; nothing else to do this swing.
		return

	# --- Depleted: hand out the loot and end this node's life. ---
	_award_drops()
	if respawn_seconds > 0.0:
		_begin_respawn()
	else:
		queue_free()

# --- Loot + lifecycle helpers ---------------------------------------------

## Gives the player the configured drop, either as physical pickups or straight
## into the bag. Does nothing (with a warning) if no drop id was set.
func _award_drops() -> void:
	if drop_item_id == &"":
		push_warning("Harvestable '%s' depleted but has no drop_item_id set." % name)
		return

	if drop_as_world_item:
		# Scatter one physical pickup per unit, fanned out deterministically by index
		# (WorldItem.spawn varies the impulse by index, no randomness). Spawn a little
		# above the node's origin so they pop up rather than out of the floor.
		var spawn_pos: Vector3 = global_position + Vector3(0.0, 0.6, 0.0)
		for i in drop_amount:
			WorldItem.spawn(drop_item_id, 1, get_parent(), spawn_pos, i)
	else:
		# Hand-picked: straight into the inventory, no physical pickup.
		Inventory.add(drop_item_id, drop_amount)

## Hides + disables the node, then schedules it to come back refilled. Used when
## respawn_seconds > 0 (e.g. a lava pool that refills over time).
func _begin_respawn() -> void:
	_set_active(false)
	# A one-shot timer so we don't keep a node around just to count down.
	var timer: SceneTreeTimer = get_tree().create_timer(respawn_seconds)
	timer.timeout.connect(_on_respawn_timeout)

## Timer callback: refill durability and switch the node back on.
func _on_respawn_timeout() -> void:
	_remaining = durability
	_set_active(true)

## Toggles whether the node is visible AND interactable. While inactive the
## collision is off so the player's raycast passes through it and shows no prompt.
func _set_active(active: bool) -> void:
	visible = active
	# StaticBody3D inherits CollisionObject3D — flip its collision layers off so the
	# interaction raycast (and physics) ignore us while we're "gone".
	set_collision_layer(1 if active else 0)
	set_collision_mask(1 if active else 0)
