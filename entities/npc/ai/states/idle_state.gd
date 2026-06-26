# idle_state.gd
# Stand still, but feel ALIVE: play idle, occasionally break into a brief emote (look around,
# stretch, a little cheer), and WAVE when the player walks up. The default resting behaviour and
# the fallback an NPC drops back to when it has nothing scheduled to do.
#
# All of this is pure animation on the NPC's own body (npc.play_anim) — it never touches the
# dialogue/interaction path, so talking to the NPC still works exactly as before (pressing the
# interact key pulls the NPC into the Talk state, leaving this one).

class_name NPCIdleState
extends NPCState

# Ambient emotes the NPC drifts through while standing around. These are logical clip names the
# Mixamo NPC animator provides (see npc_animator.gd MIXAMO_SOURCES).
const AMBIENT_EMOTES: Array[StringName] = [&"look", &"talk", &"cheer", &"salute"]
# Roughly how long an emote plays before we settle back to idle (seconds).
const EMOTE_DURATION: float = 3.2
# How near (m) the player must be to earn a wave.
const GREET_RANGE: float = 3.0

# false = resting on idle and counting down to the next emote; true = mid-emote, counting it out.
var _emoting: bool = false
var _timer: float = 0.0
# Latches so we wave ONCE per approach (re-arms when the player walks away again).
var _greeted: bool = false


func enter(_msg: Dictionary = {}) -> void:
	npc.stop()
	npc.play_anim(&"idle")
	_emoting = false
	_greeted = false
	_timer = randf_range(5.0, 11.0)


func physics_update(delta: float) -> void:
	npc.stop()

	# Greet-on-approach takes priority: a one-shot wave the first time the player comes close.
	if _check_greet():
		return

	_timer -= delta
	if _timer > 0.0:
		return

	if _emoting:
		# Emote finished — settle back to idle and schedule the next one.
		_emoting = false
		npc.play_anim(&"idle")
		_timer = randf_range(6.0, 12.0)
	else:
		# Break into a random emote for a few seconds.
		_emoting = true
		_timer = EMOTE_DURATION
		npc.play_anim(AMBIENT_EMOTES[randi() % AMBIENT_EMOTES.size()])


# Wave once when the player enters GREET_RANGE; re-arm when they leave. Returns true on the frame
# it triggers a wave (so the normal emote timer doesn't fight it that frame).
func _check_greet() -> bool:
	var player := npc.get_tree().get_first_node_in_group("player")
	if player == null or not (player is Node3D):
		_greeted = false
		return false
	var near: bool = npc.global_position.distance_to((player as Node3D).global_position) <= GREET_RANGE
	if near and not _greeted:
		_greeted = true
		_emoting = true
		_timer = EMOTE_DURATION
		npc.play_anim(&"wave")
		return true
	if not near:
		_greeted = false
	return false
