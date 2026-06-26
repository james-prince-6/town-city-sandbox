# sleep_state.gd
# Rest at a bed/home. The Kenney rig ships no lie-down clip, so for now this just
# stands idle at the spot (play_anim(&"sleep") falls back to idle). Swap in a custom
# sleeping animation later by registering a "sleep" clip on the NPCAnimator.

class_name NPCSleepState
extends NPCState

func enter(_msg: Dictionary = {}) -> void:
	npc.stop()
	npc.play_anim(&"sleep")

func physics_update(_delta: float) -> void:
	npc.stop()
