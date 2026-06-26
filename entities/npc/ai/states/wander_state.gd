# wander_state.gd
# Free-roam: pick a random reachable point near the NPC's home anchor, walk there,
# pause a beat, then pick another. Gives idle NPCs a bit of life when they have no
# schedule entry telling them where to be (enable via NPC.wander_when_idle).

class_name NPCWanderState
extends NPCState

var _pausing: bool = false
var _pause_left: float = 0.0

func enter(_msg: Dictionary = {}) -> void:
	_pick_new_target()

func physics_update(delta: float) -> void:
	if _pausing:
		npc.stop()
		_pause_left -= delta
		if _pause_left <= 0.0:
			_pick_new_target()
		return
	if npc.nav_step(delta, npc.wander_speed):
		# Arrived: rest a moment before roaming again.
		_pausing = true
		_pause_left = npc.wander_pause
		npc.play_anim(&"idle")

func _pick_new_target() -> void:
	_pausing = false
	var angle := randf_range(0.0, TAU)
	var dist := randf_range(1.0, npc.wander_radius)
	var target := npc.home_position + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
	npc.set_destination(target)
	npc.play_anim(&"walk")
