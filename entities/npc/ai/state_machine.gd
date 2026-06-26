# state_machine.gd
# A tiny finite state machine that owns an NPC's behaviour states and drives the
# active one. It's a plain object (RefCounted) created by npc.gd in code, so NPCs
# don't need any extra nodes in their scene — yet behaviours stay fully modular.
#
# Usage (from npc.gd):
#   _machine = NPCStateMachine.new(self)
#   _machine.add_state(&"Idle", NPCIdleState.new())
#   ...
#   _machine.transition_to(&"Idle")
# and each physics frame:
#   _machine.physics_update(delta)

class_name NPCStateMachine
extends RefCounted

## The NPC all states drive.
var npc: NPC
## Name of the active state (e.g. &"Idle"). Empty before the first transition.
var current_name: StringName = &""
## The active state object, or null before the first transition.
var current: NPCState

var _states: Dictionary = {}  # StringName -> NPCState

func _init(owner_npc: NPC) -> void:
	npc = owner_npc

## Register a state under a name. The same name passed to transition_to() activates it.
func add_state(state_name: StringName, state: NPCState) -> void:
	state.setup(npc, self)
	_states[state_name] = state

## True if a state with this name has been registered.
func has_state(state_name: StringName) -> bool:
	return _states.has(state_name)

## Switch to another state, running the old one's exit() then the new one's enter(msg).
## Unknown names warn and are ignored, so a typo in a schedule can't crash the NPC.
func transition_to(state_name: StringName, msg: Dictionary = {}) -> void:
	if not _states.has(state_name):
		push_warning("NPCStateMachine: no state named '%s'" % state_name)
		return
	if current:
		current.exit()
	current = _states[state_name]
	current_name = state_name
	current.enter(msg)

## Drive the active state. Called once per physics frame by the NPC.
func physics_update(delta: float) -> void:
	if current:
		current.physics_update(delta)
