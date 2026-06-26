# npc_state.gd
# Base class for one behaviour an NPC can be in (idle, walking somewhere, sleeping,
# working, talking...). States are plain objects (RefCounted), NOT nodes, so an NPC
# can own a whole set of them cheaply without cluttering its scene tree.
#
# The NPCStateMachine calls enter() when this state becomes active, physics_update()
# every physics frame while it's active, and exit() when leaving. Each state reads
# and drives its NPC through the helper methods on npc.gd (set_destination, nav_step,
# stop, play_anim, face_toward, resolve_location) — it never pokes the body directly,
# so all the movement/animation plumbing stays in one place.
#
# To add a new behaviour: write a script extending NPCState, override the hooks you
# need, and register it in NPC._register_states() (or a subclass). See
# docs/adding_content.md.

class_name NPCState
extends RefCounted

## The NPC node this state drives. Set by the state machine via setup().
var npc: NPC
## The machine that owns this state, used to request transitions.
var machine: NPCStateMachine

# Wire up the back-references. Called once when the state is registered.
func setup(owner_npc: NPC, owner_machine: NPCStateMachine) -> void:
	npc = owner_npc
	machine = owner_machine

# Called when this state becomes active. `msg` carries optional parameters from the
# caller (e.g. a movement target, the activity to switch to on arrival).
func enter(_msg: Dictionary = {}) -> void:
	pass

# Called when leaving this state, just before the next one's enter().
func exit() -> void:
	pass

# Called every physics frame while active. Set npc.velocity.x/.z here; the NPC adds
# gravity and calls move_and_slide() centrally after this runs.
func physics_update(_delta: float) -> void:
	pass
