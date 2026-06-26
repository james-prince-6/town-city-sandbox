# talk_state.gd
# The NPC is in a conversation with the player: frozen in place, playing idle. The
# NPC enters this from interact() and leaves it (back to its schedule) when the
# dialogue ends — that wiring lives in npc.gd (_on_dialogue_ended).

class_name NPCTalkState
extends NPCState

func enter(_msg: Dictionary = {}) -> void:
	npc.stop()
	npc.play_anim(&"idle")

func physics_update(_delta: float) -> void:
	npc.stop()
