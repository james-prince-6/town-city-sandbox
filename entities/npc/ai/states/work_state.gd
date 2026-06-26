# work_state.gd
# Busy doing an activity at a spot (tending a stall, sweeping, brewing). Plays the
# looping "interact" animation in place. A schedule sends the NPC here after walking
# to a work location.

class_name NPCWorkState
extends NPCState

func enter(_msg: Dictionary = {}) -> void:
	npc.stop()
	npc.play_anim(&"interact")

func physics_update(_delta: float) -> void:
	npc.stop()
