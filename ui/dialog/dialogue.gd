# dialogue.gd
# Autoload singleton (registered as "Dialogue"). The game-facing front door to the
# conversation system. The heavy lifting — parsing .dialogue files, branching,
# conditions, mutations — is done by Nathan Hoad's Dialogue Manager addon (registered
# as the "DialogueManager" autoload). THIS wrapper adds the game-specific polish that
# the raw addon doesn't know about:
#
#   - The "cinematic-lite" camera: when a conversation has a speaker Node3D, the view
#     eases from the player's camera to an over-the-shoulder framing of the NPC and
#     pushes in, then eases back when the talk ends.
#   - Per-line speaker gestures: each line can carry a [#gesture=...] tag; the speaker
#     plays that animation as the line shows (defaults to "interact").
#   - The compatibility signals the rest of the game already listens to —
#     dialogue_started / dialogue_ended (no args) — plus an is_active flag other UIs
#     check before opening (pause menu, inventory, skill tree, the player, the clock).
#
# Anything that talks calls:
#     Dialogue.start_dialogue(some_dialogue_resource, speaker_node, "start")
# `speaker` is optional — pass the talking NPC (a Node3D, ideally with play_anim()) to
# get the camera framing + gestures. Signs / machines can omit it and just get the panel.
# `title` is the starting cue in the .dialogue file (defaults to the file's first cue).

extends Node

## Emitted once when a conversation opens. Player disables move/look, clock pauses, etc.
signal dialogue_started
## Emitted once when the whole conversation closes.
signal dialogue_ended

## True for the whole duration of a conversation. Other UIs check this before opening.
var is_active: bool = false

# --- Speaker / cinematic camera --------------------------------------------
var _speaker: Node = null
var _player_cam: Camera3D = null
var _dialogue_cam: Camera3D = null
var _cam_tween: Tween = null
const DEFAULT_TALK_ANIM: StringName = &"interact"

# The balloon scene that renders the conversation (built in code, styled to match the
# rest of the game's UI). Instanced fresh per conversation and freed when it ends.
const BALLOON_SCENE: PackedScene = preload("res://ui/dialog/dialogue_balloon.tscn")
var _balloon: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# React to the addon's runtime. got_dialogue fires per line (drive gestures);
	# dialogue_ended fires when a conversation reaches its end (clean up + notify game).
	DialogueManager.got_dialogue.connect(_on_addon_got_dialogue)
	DialogueManager.dialogue_ended.connect(_on_addon_dialogue_ended)


# --- Public API ------------------------------------------------------------

## Open a conversation from a compiled .dialogue resource. `speaker` (optional) gets the
## camera framing + per-line gestures. `title` is the starting cue (blank = file's first).
func start_dialogue(resource: DialogueResource, speaker: Node = null, title: String = "") -> void:
	if resource == null:
		push_warning("Dialogue: start_dialogue called with a null resource.")
		return
	if is_active:
		# A conversation is already open; ignore re-entry (branching happens inside the
		# .dialogue file now, so this only guards against double-talk bugs).
		return

	is_active = true
	_speaker = speaker
	dialogue_started.emit()
	_begin_cinematic()

	# Build our balloon and run the conversation through it. The NPC is passed in as a
	# named game state so dialogue expressions can reference it (e.g. `do speaker.play_anim(...)`).
	_balloon = BALLOON_SCENE.instantiate()
	add_child(_balloon)
	_balloon.start(resource, title, [{ "speaker": speaker }])


## Force-close any open conversation (e.g. on scene change). Safe to call when idle.
func end_dialogue() -> void:
	if not is_active:
		return
	if is_instance_valid(_balloon):
		_balloon.queue_free()
	_balloon = null
	_finish()


# --- Addon signal handlers -------------------------------------------------

# The addon reached the end of the conversation graph.
func _on_addon_dialogue_ended(_resource: DialogueResource) -> void:
	if not is_active:
		return
	# The balloon frees itself on end; just drop our reference and wrap up.
	_balloon = null
	_finish()


func _finish() -> void:
	is_active = false
	_end_cinematic()
	dialogue_ended.emit()


# A new line is being shown — gesture the speaker to match it.
func _on_addon_got_dialogue(line: DialogueLine) -> void:
	if not is_active:
		return
	if _speaker == null or not is_instance_valid(_speaker):
		return
	if not _speaker.has_method("play_anim"):
		return
	var cue: String = line.get_tag_value("gesture")
	_speaker.play_anim(StringName(cue) if cue != "" else DEFAULT_TALK_ANIM)


# --- Cinematic-lite camera -------------------------------------------------
# Ease a dedicated dialogue camera from the player's current view to a framing of the
# speaker, with a gentle push-in. Falls back gracefully (no camera change) whenever
# anything's missing — so sign/machine dialogue and headless tests are unaffected.

func _begin_cinematic() -> void:
	if _speaker == null or not (_speaker is Node3D):
		return
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not player.has_method("get_camera"):
		return
	var cam: Camera3D = player.get_camera()
	if cam == null:
		return
	var world: Node = SceneManager.current_world() if SceneManager else null
	if world == null:
		return

	_player_cam = cam
	_dialogue_cam = Camera3D.new()
	world.add_child(_dialogue_cam)
	_dialogue_cam.global_transform = cam.global_transform
	_dialogue_cam.fov = cam.fov
	_dialogue_cam.make_current()

	var target: Transform3D = _frame_transform(player as Node3D, _speaker as Node3D)
	_kill_cam_tween()
	_cam_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_cam_tween.tween_property(_dialogue_cam, "global_transform", target, 0.6)
	_cam_tween.parallel().tween_property(_dialogue_cam, "fov", 55.0, 0.6)


# Ease back to the player's camera, then hand control back to it and free the dialogue camera.
func _end_cinematic() -> void:
	if _dialogue_cam == null or not is_instance_valid(_dialogue_cam):
		_speaker = null
		return
	var back_xform: Transform3D = _player_cam.global_transform if is_instance_valid(_player_cam) else _dialogue_cam.global_transform
	var back_fov: float = _player_cam.fov if is_instance_valid(_player_cam) else 75.0
	_kill_cam_tween()
	_cam_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_cam_tween.tween_property(_dialogue_cam, "global_transform", back_xform, 0.4)
	_cam_tween.parallel().tween_property(_dialogue_cam, "fov", back_fov, 0.4)
	_cam_tween.tween_callback(_restore_player_cam)
	_speaker = null


func _restore_player_cam() -> void:
	if is_instance_valid(_player_cam):
		_player_cam.make_current()
	if is_instance_valid(_dialogue_cam):
		_dialogue_cam.queue_free()
	_dialogue_cam = null
	_player_cam = null


func _kill_cam_tween() -> void:
	if _cam_tween != null and _cam_tween.is_valid():
		_cam_tween.kill()
	_cam_tween = null


# An over-the-shoulder framing: beside the player's head, aimed LOW on the NPC so the NPC sits
# in the upper part of the frame — clear of the dialogue box that fills the bottom of the screen.
func _frame_transform(player: Node3D, speaker: Node3D) -> Transform3D:
	var npc_head: Vector3 = speaker.global_position + Vector3.UP * 1.5
	var player_head: Vector3 = player.global_position + Vector3.UP * 1.6
	var to_npc: Vector3 = npc_head - player_head
	to_npc.y = 0.0
	if to_npc.length() < 0.1:
		to_npc = -player.global_transform.basis.z
	to_npc = to_npc.normalized()
	var right: Vector3 = to_npc.cross(Vector3.UP).normalized()
	# Sit a touch higher and look at the NPC's torso (not their head): the downward tilt pushes
	# the NPC up the screen so the bottom dialogue box no longer covers their face.
	var cam_pos: Vector3 = player_head - to_npc * 0.2 + right * 0.7 + Vector3.UP * 0.25
	var aim: Vector3 = speaker.global_position + Vector3.UP * 0.85
	var xform := Transform3D(Basis(), cam_pos)
	return xform.looking_at(aim, Vector3.UP)
