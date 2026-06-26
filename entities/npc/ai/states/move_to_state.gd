# move_to_state.gd
# Walk to a target position using navigation, then hand off to a follow-up state.
# Schedules use this to send an NPC to a location ("go home") and then start the
# activity there ("sleep"). Recognised msg keys:
#   target      : Vector3    – where to walk to (required; missing = skip straight to on_arrive)
#   on_arrive   : StringName – state to switch to on arrival (default &"Idle")
#   arrive_msg  : Dictionary – msg passed to that state (default {})

class_name NPCMoveToState
extends NPCState

var _on_arrive: StringName = &"Idle"
var _arrive_msg: Dictionary = {}

func enter(msg: Dictionary = {}) -> void:
	_on_arrive = msg.get("on_arrive", &"Idle")
	_arrive_msg = msg.get("arrive_msg", {})
	var target = msg.get("target", null)
	if target == null:
		# Nowhere to walk; just do the activity right here.
		machine.transition_to(_on_arrive, _arrive_msg)
		return
	npc.set_destination(target)
	npc.play_anim(&"walk")

func physics_update(delta: float) -> void:
	if npc.nav_step(delta, npc.walk_speed):
		machine.transition_to(_on_arrive, _arrive_msg)
