# npc.gd
# Reusable base for the town's characters. A CharacterBody3D that can stand, walk
# the navmesh, follow a daily schedule, animate a rigged body, and talk to the
# player. The *behaviour* lives in small swappable states (see entities/npc/ai/);
# this script is the "body + services" those states drive, plus the glue to the
# Clock (schedule), the player (interaction), and the animator.
#
# To make a specific character: instance npc.tscn, set npc_name / npc_id, drag in a
# DialogueResource, and optionally an NPCSchedule. For a custom brain, extend this
# script and override _register_states() to add your own NPCState classes.
#
# Robustness: the NavigationAgent3D ($NavAgent) and the Animator (NPCAnimator) are
# both OPTIONAL. Without a nav agent (or a baked navmesh) the NPC walks in a straight
# line; without an animator it keeps its placeholder capsule. So subclass scenes that
# don't include those nodes (e.g. shopkeeper.tscn) still work unchanged.

class_name NPC
extends CharacterBody3D

## OPTIONAL one-stop authoring resource. Assign an NPCDefinition .tres and this
## NPC self-configures on _ready: identity, animated body (model/skin/height),
## speeds, schedule/behaviour, starting mood, and which conversation it opens with
## (branching by mood / time / quest / reputation). Leave it null and the manual
## @export fields below drive the NPC exactly as before — fully back-compatible.
## See global/npc/npc_definition.gd for the "how to make a new NPC" guide.
@export var definition: NPCDefinition

## Shown in the interaction prompt and used as a fallback speaker name.
@export var npc_name: String = "Villager"

## Stable id used as this NPC's Reputation key (e.g. &"marlo").
@export var npc_id: StringName = &""

## The conversation that plays when the player talks to this NPC: a compiled .dialogue
## file. Used directly when this NPC has no `definition`; otherwise the definition's
## dialogue wins. Branching (mood/time/quest/rep) lives inside the .dialogue file.
@export var dialogue: DialogueResource
## Which cue in `dialogue` to open on (blank uses the file's first cue).
@export var dialogue_title: String = "start"

## Optional daily routine. With one set, the NPC walks to scheduled locations and
## switches activities by the in-game Clock. Without one, it idles (or wanders).
@export var schedule: NPCSchedule

@export_group("Movement")
## Walking speed when following the schedule (m/s).
@export var walk_speed: float = 2.2
## Speed used by the free-roam Wander state (m/s).
@export var wander_speed: float = 1.4
## How close (m) counts as "arrived" at a destination.
@export var arrive_distance: float = 0.6

@export_group("Idle behaviour")
## When the NPC has nothing scheduled, wander near its spawn instead of standing.
@export var wander_when_idle: bool = false
## Radius (m) around the spawn point the Wander state roams within.
@export var wander_radius: float = 5.0
## Seconds the Wander state pauses on arrival before roaming again.
@export var wander_pause: float = 2.0

@export_group("Facing")
## If true, the NPC swivels to face the player when spoken to (yaw only).
@export var turn_to_face_player: bool = true
## How fast the body rotates toward its target heading (degrees/second). The body
## turns smoothly instead of snapping, so you actually see it pivot. The Kenney rig
## has no dedicated turn clip, so this rotation IS the turn (idle/walk plays during it).
@export var turn_speed_degrees: float = 480.0

# --- Node refs (both optional — see header) --------------------------------
@onready var _nav: NavigationAgent3D = get_node_or_null("NavAgent")
@onready var _animator: NPCAnimator = get_node_or_null("Animator")

# --- Runtime ---------------------------------------------------------------
var _machine: NPCStateMachine
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
## Spawn position; the Wander state roams around this anchor.
var home_position: Vector3
# Final navigation goal, kept so we can fall back to straight-line movement when a
# scene has no baked navmesh (the agent then reports "finished" with no path).
var _nav_target: Vector3
var _has_nav_target: bool = false
# Desired body heading (yaw, radians). The body rotates toward this each frame so
# turns are smooth/visible rather than an instant snap. Unset until something aims it.
var _target_yaw: float = 0.0
var _has_target_yaw: bool = false
# The schedule entry currently being acted on, so we only react when it changes.
var _active_entry: ScheduleEntry
# True while a conversation with the player is open (suspends schedule reactions).
var _talking: bool = false
# Optional floating quest marker ("!"/"?"/"T") above the head, built in _ready for
# NPCs that have a real id. Null for anonymous NPCs (and in scenes without one).
var _quest_marker: Node3D = null

func _ready() -> void:
	add_to_group("npc")
	home_position = global_position

	# Apply the authoring resource (if any) BEFORE we read schedule / animator
	# state below, so everything downstream sees the configured values.
	if definition:
		_apply_definition()

	# If a rigged model was built, hide the placeholder capsule mesh.
	if _animator and _animator.has_model():
		var capsule := get_node_or_null("MeshInstance3D")
		if capsule:
			capsule.visible = false

	# Build the behaviour state machine and register the default states.
	_machine = NPCStateMachine.new(self)
	_register_states()

	# Pick a starting behaviour from the schedule (or idle / wander).
	_reevaluate(true)

	# Follow the in-game clock for schedule changes.
	if schedule and Clock:
		Clock.time_changed.connect(_on_time_changed)

	# Float a quest marker over identified NPCs (anonymous "Villager" NPCs get none).
	_spawn_quest_marker()

# Build the floating "!"/"?"/"T" quest marker above the head for NPCs with a real id.
# The script is loaded BY PATH (not by symbol) so a cold class-cache never trips us up.
func _spawn_quest_marker() -> void:
	if npc_id == &"":
		return
	var marker_script: Script = load("res://entities/npc/quest_marker.gd")
	if marker_script == null:
		return
	var marker = marker_script.new()
	# Position BEFORE add_child so the marker captures the right resting height in
	# its _ready (the bob oscillates around it). Height scales with the body.
	var head_height: float = definition.target_height if definition != null else 1.8
	marker.position = Vector3(0.0, head_height + 0.45, 0.0)
	add_child(marker)
	_quest_marker = marker

## Configure this NPC from its NPCDefinition. Only fills in things the definition
## specifies; runs before the state machine is built so schedule/behaviour are set.
func _apply_definition() -> void:
	if definition.display_name != "":
		npc_name = definition.display_name
	if definition.id != &"":
		npc_id = definition.id

	# Visuals: push the look into the animator and rebuild its body. The animator
	# already _ready()'d (children first), so this swaps it to the def's model.
	if _animator:
		_animator.apply_definition(definition.model_scene, definition.skin_texture, definition.target_height)

	# Movement tuning.
	walk_speed = definition.move_speed
	wander_speed = definition.move_speed
	turn_speed_degrees = definition.turn_speed_degrees

	# Behaviour: only run a schedule in SCHEDULE mode; otherwise idle or wander.
	match definition.default_behavior:
		NPCDefinition.Behavior.SCHEDULE:
			schedule = definition.schedule
		NPCDefinition.Behavior.WANDER:
			schedule = null
			wander_when_idle = true
		_:  # IDLE
			schedule = null
			wander_when_idle = false

	# Anchor wandering at the home WorldLocation if one is named and present.
	if definition.home_location_id != &"":
		var home = resolve_location(definition.home_location_id)
		if home != null:
			home_position = home

	# Seed this NPC's starting mood (without clobbering a saved/in-progress one).
	if definition.id != &"":
		NPCMoods.ensure_default(definition.id, definition.default_mood)

	# Register any TASK-tier quests this NPC offers so QuestSystem.has_task_available /
	# request_task know its pool. The OFFER itself is authored in the .dialogue via
	# `do QuestSystem.request_task("<id>")`; here we only declare what's available.
	# Reached defensively via the autoload so NPCs work in scenes/tests without it.
	if definition.id != &"" and not definition.task_pool.is_empty():
		var quests := get_node_or_null("/root/QuestSystem")
		if quests != null and quests.has_method("register_task_giver"):
			quests.register_task_giver(definition.id, definition.task_pool)

## Register the standard behaviour states. Override in a subclass to add more
## (call super() first to keep the defaults).
func _register_states() -> void:
	_machine.add_state(&"Idle", NPCIdleState.new())
	_machine.add_state(&"Wander", NPCWanderState.new())
	_machine.add_state(&"MoveTo", NPCMoveToState.new())
	_machine.add_state(&"Sleep", NPCSleepState.new())
	_machine.add_state(&"Work", NPCWorkState.new())
	_machine.add_state(&"Talk", NPCTalkState.new())

func _physics_process(delta: float) -> void:
	# Gravity keeps the NPC grounded; states own horizontal velocity.
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0.0
	if _machine:
		_machine.physics_update(delta)
	_apply_turn(delta)
	move_and_slide()

# Rotate the body's yaw toward the last-aimed heading at turn_speed_degrees/sec, so
# direction changes read as a visible pivot instead of an instant snap.
func _apply_turn(delta: float) -> void:
	if not _has_target_yaw:
		return
	var max_step := deg_to_rad(turn_speed_degrees) * delta
	var diff := wrapf(_target_yaw - rotation.y, -PI, PI)
	if absf(diff) <= max_step:
		rotation.y = _target_yaw
	else:
		rotation.y += signf(diff) * max_step

## Name of the active behaviour state (e.g. &"Idle"). Useful for tests/debugging.
func current_state() -> StringName:
	return _machine.current_name if _machine else &""

# --- Schedule --------------------------------------------------------------

func _on_time_changed(hour: int, minute: int) -> void:
	if _talking:
		return
	_apply_schedule(hour, minute)

# Look up the entry in effect now; if it changed, act on it.
func _apply_schedule(hour: int, minute: int) -> void:
	if schedule == null:
		return
	var entry := schedule.get_current_entry(hour, minute)
	if entry == null or entry == _active_entry:
		return
	_active_entry = entry
	_go_to_entry(entry)

# Walk to the entry's location (if any and resolvable) then do its activity.
func _go_to_entry(entry: ScheduleEntry) -> void:
	var pos = resolve_location(entry.location_id)
	if pos == null:
		_machine.transition_to(entry.activity)
	else:
		_machine.transition_to(&"MoveTo", {
			"target": pos,
			"on_arrive": entry.activity,
		})

# Choose a behaviour when not driven by a fresh schedule tick: follow the current
# schedule entry, else wander or idle. `force` re-applies even if the entry is the same.
func _reevaluate(force: bool = false) -> void:
	if schedule:
		if force:
			_active_entry = null
		_apply_schedule(Clock.hour, Clock.minute)
		return
	if wander_when_idle:
		_machine.transition_to(&"Wander")
	else:
		_machine.transition_to(&"Idle")

# --- Movement services (called by states) ----------------------------------

## Set the navigation goal for nav_step() to walk toward.
func set_destination(pos: Vector3) -> void:
	_nav_target = pos
	_has_nav_target = true
	if _nav:
		_nav.target_position = pos

## Step one frame toward the current destination at `speed`. Returns true once the
## NPC has arrived (or has no destination). Uses the navmesh when present, and falls
## back to a straight line when a scene has no baked navigation so NPCs still move.
func nav_step(delta: float, speed: float) -> bool:
	if not _has_nav_target:
		stop()
		return true
	var to_target := _nav_target - global_position
	to_target.y = 0.0
	if to_target.length() <= arrive_distance:
		stop()
		_has_nav_target = false
		return true

	var dir: Vector3
	if _nav:
		var next := _nav.get_next_path_position()
		dir = next - global_position
		dir.y = 0.0
		# No usable path (no navmesh baked) -> head straight for the goal.
		if _nav.is_navigation_finished() or dir.length() < 0.05:
			dir = to_target
	else:
		dir = to_target

	dir = dir.normalized()
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	_face_direction(dir)
	return false

## Stop horizontal movement (gravity still applies).
func stop() -> void:
	velocity.x = 0.0
	velocity.z = 0.0

## Play an animation clip on the rigged body, if there is one.
func play_anim(anim_name: StringName) -> void:
	if _animator:
		_animator.play(anim_name)

## Resolve a WorldLocation id to a global position, or null if not found in this
## scene. Lets schedules turn &"market" into a place to walk to.
func resolve_location(location_id: StringName):
	if location_id == &"":
		return null
	for node in get_tree().get_nodes_in_group("world_location"):
		if node is WorldLocation and node.location_id == location_id:
			return node.global_position
	return null

# --- Interaction (duck-typed by the player's RayCast3D) --------------------

func get_interaction_prompt() -> String:
	var base := "Talk to %s" % npc_name
	# Append a hand-in hint when an active quest tied to this NPC is fully satisfied.
	# Heuristic + fully guarded: a miss simply leaves the plain "Talk to X" (never a
	# false positive).
	var quests: Node = get_node_or_null("/root/QuestSystem")
	if quests != null and _has_turn_in_quest(quests):
		return base + " (ready to turn in)"
	return base

func interact(player) -> void:
	if turn_to_face_player and player is Node3D:
		_face_toward(player.global_position)

	# Pick the opening conversation: the definition's .dialogue when one is set, else the
	# manual field. Branching (mood / time / quest / reputation) lives inside the file.
	var opening: DialogueResource = dialogue
	var title: String = dialogue_title
	if definition and definition.dialogue:
		opening = definition.dialogue
		title = definition.dialogue_title

	if opening == null:
		push_warning("NPC '%s' has no dialogue assigned." % npc_name)
		return
	_talking = true
	# Tuck the floating marker away while we're mid-conversation.
	if _quest_marker != null and _quest_marker.has_method("set_dialogue_active"):
		_quest_marker.set_dialogue_active(true)
	if _machine:
		_machine.transition_to(&"Talk")
	# Pass ourselves as the speaker so the dialogue system can frame the camera on us and play
	# our gesture animations per line (cinematic-lite conversations).
	Dialogue.start_dialogue(opening, self, title)
	# Resume the schedule once this conversation closes (one-shot so it self-cleans).
	Dialogue.dialogue_ended.connect(_on_dialogue_ended, CONNECT_ONE_SHOT)

func _on_dialogue_ended() -> void:
	_talking = false
	# Re-show + re-evaluate the marker — the chat may have started/finished a quest.
	if _quest_marker != null and _quest_marker.has_method("set_dialogue_active"):
		_quest_marker.set_dialogue_active(false)
	_reevaluate(true)

# --- Quest discoverability helpers -----------------------------------------
# These power the floating quest marker (quest_marker.gd) and the "ready to turn in"
# suffix on the talk prompt. All are HEURISTIC and defensively guarded: with no
# QuestSystem, or when a link to this NPC can't be proven, they return false/"" so
# we show nothing rather than a wrong marker.

# Reputation effect index in GameEffect.EffectType. The enums in this project are
# append-only, so this int is stable; we compare against it without importing the
# symbol (keeps this hot-path file free of an extra class dependency).
const _ADD_REPUTATION_EFFECT: int = 4

## Best-guess glyph to float over this NPC: "?" ready to turn in, "!" a new quest to
## pick up, "T" a repeatable task is available, "" nothing. Called by quest_marker.gd.
func get_quest_marker_glyph() -> String:
	if npc_id == &"":
		return ""
	var quests: Node = get_node_or_null("/root/QuestSystem")
	if quests == null:
		return ""
	# Priority: finishing work you have > picking up a new quest > a repeatable task.
	if _has_turn_in_quest(quests):
		return "?"
	if _has_available_quest(quests):
		return "!"
	if quests.has_method("has_task_available") and quests.has_task_available(npc_id):
		return "T"
	return ""

# True if some ACTIVE quest tied to this NPC has every current-stage objective met
# (so it's waiting to be handed in here).
func _has_turn_in_quest(quests: Node) -> bool:
	if not quests.has_method("get_active_quests"):
		return false
	for quest in quests.get_active_quests():
		if quest == null or not _quest_tied_to_me(quest):
			continue
		if _quest_objectives_satisfied(quests, quest.id):
			return true
	return false

# True if a not-yet-started, non-task quest tied to this NPC exists (a "!" to offer).
# Conservative: tasks are reported via has_task_available ("T"); active/completed
# quests never count. This is the fuzzy signal — it may light up slightly early for a
# gated follow-up quest, but it never overrides the precise "?"/"T" states above.
func _has_available_quest(quests: Node) -> bool:
	if not quests.has_method("get_state") or not ("database" in quests):
		return false
	for id in quests.database.keys():
		var quest = quests.database[id]
		if quest == null:
			continue
		if int(quest.tier) == 2:  # Quest.Tier.TASK -> handled by has_task_available
			continue
		if not _quest_tied_to_me(quest):
			continue
		if quests.get_state(quest.id) == 0:  # QuestSystem.State.NOT_STARTED
			return true
	return false

# Heuristic link between a quest and this NPC: an explicit giver, an id naming
# convention ("<npc>_..." / "task_<npc>_..."), or a reputation reward aimed at us.
func _quest_tied_to_me(quest) -> bool:
	var key := String(npc_id)
	if key == "":
		return false
	if "giver_npc_id" in quest and quest.giver_npc_id == npc_id:
		return true
	var qid := String(quest.id)
	if qid.begins_with(key + "_") or qid.begins_with("task_" + key + "_"):
		return true
	if "rewards" in quest and quest.rewards != null:
		for reward in quest.rewards:
			if reward == null:
				continue
			if ("type" in reward) and ("target" in reward):
				if int(reward.type) == _ADD_REPUTATION_EFFECT and reward.target == npc_id:
					return true
	return false

# True if every current-stage objective of an active quest is satisfied. Empty/unknown
# objective lists return false (so we never claim an objective-less quest is "done").
func _quest_objectives_satisfied(quests: Node, id) -> bool:
	if not quests.has_method("get_current_objectives"):
		return false
	var objectives = quests.get_current_objectives(id)
	if objectives == null or objectives.is_empty():
		return false
	var progress = quests.get_objective_progress(id)
	for i in objectives.size():
		var required: int = maxi(int(objectives[i].required_count), 1)
		var current: int = int(progress[i]) if i < progress.size() else 0
		if current < required:
			return false
	return true

# --- Facing ----------------------------------------------------------------

# Aim at a world point (used when turning to face the player on interact).
func _face_toward(target_position: Vector3) -> void:
	_aim_heading(target_position - global_position)

# Aim along a movement direction (used while walking). Kept separate so walking
# never aims with a near-zero vector.
func _face_direction(dir: Vector3) -> void:
	_aim_heading(dir)

# Set the desired yaw from a horizontal direction. _apply_turn() then rotates toward
# it smoothly. The body's forward is -Z (matching the old look_at), so the yaw that
# points -Z along (dx,dz) is atan2(-dx, -dz).
func _aim_heading(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length() < 0.05:
		return
	_target_yaw = atan2(-flat.x, -flat.z)
	_has_target_yaw = true
