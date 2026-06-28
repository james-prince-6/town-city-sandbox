# quest_system.gd
# Autoload singleton (registered as "QuestSystem").
#
# The brain that tracks quests at RUNTIME. The Quest / QuestStage / QuestObjective
# resources are pure templates (no progress stored on them); everything mutable —
# which quests are active, how far along each objective is, which stage you're on,
# task deadlines, which are finished — lives here so the .tres files stay
# shareable and save-friendly.
#
# v2 capabilities (backward compatible):
# - TIERS: each Quest has a tier (MAIN / SIDE / TASK). TASK-tier quests can be
#   timed, repeatable, and handed out by task-giver NPCs.
# - MULTI-STAGE: a Quest may define `stages` (an ordered list of QuestStage). The
#   player works through them one at a time; each stage's `on_complete` effects
#   fire as it finishes, then the next stage begins. A Quest with empty `stages`
#   behaves exactly like before — its flat `objectives` are one implicit stage.
# - TIMED TASKS: a TASK with time_limit_minutes > 0 expires that many in-GAME
#   minutes after it starts (driven off Clock.time_changed), firing quest_failed.
#
# Per-active-quest runtime state is a Dictionary:
#   { "stage": int, "progress": Array[int] (current stage objectives), "deadline": int }
# deadline is an absolute game-minute (now_minutes()) deadline, or -1 if untimed.
#
# Auto-tracking:
# - COLLECT_ITEM objectives self-update: we listen to Inventory.item_changed and
#   re-evaluate the CURRENT stage's COLLECT objectives of every active quest.
# - REACH_FLAG objectives complete when mark_flag(flag) is called (areas/dungeons
#   call it) or when the GameState flag is already set as the stage begins.

extends Node

## Folder scanned for Quest (.tres) resources at startup. Every Quest found is
## registered into `database` under its `id`.
const QUEST_DB_PATH := "res://global/quests/resources/"

## A quest's lifecycle, from the player's point of view.
enum State { NOT_STARTED, ACTIVE, COMPLETED }

## Emitted when a quest first becomes active.
signal quest_started(id: StringName)
## Emitted whenever an active quest's objective/stage progress changes.
signal quest_updated(id: StringName)
## Emitted when every objective (final stage) is satisfied and the quest finishes.
signal quest_completed(id: StringName)
## Emitted when a multi-stage quest moves on to a new stage. stage_index is the
## NEW (now-current) stage's index.
signal quest_stage_advanced(id: StringName, stage_index: int)
## Emitted when a task is handed out by a giver NPC via the task-offering API.
signal task_offered(id: StringName, npc_id: StringName)
## Emitted when a timed TASK runs out of time before being completed.
signal task_expired(id: StringName)
## Emitted when an active quest fails (currently: a timed task expiring). No
## rewards are granted. Pairs with task_expired for tasks.
signal quest_failed(id: StringName)

## id (StringName) -> Quest resource. Lookup table for every quest definition.
var database: Dictionary = {}

## id (StringName) -> { "stage": int, "progress": Array[int], "deadline": int }.
## Only active quests have an entry here.
var _active: Dictionary = {}

## id (StringName) -> true for quests that have been completed (non-repeatable).
var _completed: Dictionary = {}

## id (StringName) -> game-minute until which a repeatable task is unavailable.
var _cooldowns: Dictionary = {}

## npc_id (StringName) -> Array[StringName] of task quest ids that giver offers.
var _task_givers: Dictionary = {}

func _ready() -> void:
	_load_database()
	# Re-check COLLECT_ITEM objectives every time the bag changes.
	Inventory.item_changed.connect(_on_inventory_changed)
	# Drive timed-task expiry + cooldown clearing off the game clock.
	Clock.time_changed.connect(_on_clock_tick)

# --- Database --------------------------------------------------------------

func _load_database() -> void:
	var dir := DirAccess.open(QUEST_DB_PATH)
	if dir == null:
		push_warning("QuestSystem: quest folder not found at %s" % QUEST_DB_PATH)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		# In exported builds Godot renames .tres -> .tres.remap; strip that so
		# the load() path stays valid in both the editor and exports.
		if file_name.ends_with(".tres") or file_name.ends_with(".tres.remap"):
			var clean := file_name.trim_suffix(".remap")
			var res := load(QUEST_DB_PATH + clean)
			if res is Quest:
				if res.id == &"":
					push_warning("QuestSystem: %s has an empty id, skipping." % clean)
				else:
					database[res.id] = res
		file_name = dir.get_next()
	dir.list_dir_end()

## Look up the full Quest definition for an id (or null if unknown).
func get_quest(id: StringName) -> Quest:
	return database.get(id)

# --- Time helper -----------------------------------------------------------

## The current game time expressed as a single absolute minute count, so we can
## compare deadlines/cooldowns with one integer. day*1440 + hour*60 + minute.
func now_minutes() -> int:
	return GameState.day * 1440 + Clock.hour * 60 + Clock.minute

# --- Stage helpers ---------------------------------------------------------

## The QuestObjectives for a given stage. When the quest has no `stages`, the
## legacy flat `objectives` array is treated as the single (stage 0) list.
func _stage_objectives(id: StringName, stage_index: int) -> Array[QuestObjective]:
	var quest: Quest = database.get(id)
	if quest == null:
		return [] as Array[QuestObjective]
	if quest.stages.is_empty():
		return quest.objectives
	if stage_index < 0 or stage_index >= quest.stages.size():
		return [] as Array[QuestObjective]
	var stage: QuestStage = quest.stages[stage_index]
	if stage == null:
		return [] as Array[QuestObjective]
	return stage.objectives

## How many stages a quest has (legacy single-objective quests count as 1).
func _stage_count(id: StringName) -> int:
	var quest: Quest = database.get(id)
	if quest == null:
		return 1
	return maxi(quest.stages.size(), 1)

# --- Starting quests -------------------------------------------------------

func start_quest(id: StringName) -> void:
	if not database.has(id):
		push_warning("QuestSystem.start_quest: unknown quest id '%s'" % id)
		return
	# Don't restart something already running or permanently finished.
	if is_active(id) or is_completed(id):
		return
	var quest: Quest = database[id]
	# A repeatable task still on cooldown can't be (re)started yet.
	if _cooldowns.has(id) and now_minutes() < int(_cooldowns[id]):
		return
	# Gating: refuse to start out of order. A prerequisite quest must be COMPLETED first,
	# and a main-gated quest waits until the story (any MAIN-tier quest) is underway. Both
	# default to ungated, so quests without these set behave exactly as before.
	if quest.prerequisite_quest_id != &"" and not is_completed(quest.prerequisite_quest_id):
		return
	if quest.gate_on_main_quest_start and not _any_main_quest_started():
		return
	# Seed stage 0, one progress slot per current-stage objective.
	var objectives: Array[QuestObjective] = _stage_objectives(id, 0)
	var progress: Array[int] = []
	progress.resize(objectives.size())
	progress.fill(0)
	var deadline: int = -1
	if int(quest.tier) == Quest.Tier.TASK and quest.time_limit_minutes > 0:
		deadline = now_minutes() + quest.time_limit_minutes
	_active[id] = {"stage": 0, "progress": progress, "deadline": deadline}
	# Pre-fill from current inventory + already-set flags so a quest you already
	# satisfied starts partly (or fully) done.
	_reevaluate_stage_start(id)
	quest_started.emit(id)
	quest_updated.emit(id)
	# Starting may already satisfy the whole (first) stage.
	_check_stage(id)

## True once at least one MAIN-tier quest has been started (is active OR already
## completed) — i.e. the main story is underway. Backs the gate_on_main_quest_start gate.
func _any_main_quest_started() -> bool:
	for active_id in _active:
		var q: Quest = database.get(active_id)
		if q != null and int(q.tier) == Quest.Tier.MAIN:
			return true
	for done_id in _completed:
		var q2: Quest = database.get(done_id)
		if q2 != null and int(q2.tier) == Quest.Tier.MAIN:
			return true
	return false

# --- Queries ---------------------------------------------------------------

func get_state(id: StringName) -> State:
	if _completed.has(id):
		return State.COMPLETED
	if _active.has(id):
		return State.ACTIVE
	return State.NOT_STARTED

func is_active(id: StringName) -> bool:
	return _active.has(id)

func is_completed(id: StringName) -> bool:
	return _completed.has(id)

## Raw runtime state dict for an active quest (a duplicate so callers can't
## mutate ours): { "stage", "progress" (dup), "deadline" }. Empty if not active.
func get_state_data(id: StringName) -> Dictionary:
	if not _active.has(id):
		return {}
	var state: Dictionary = _active[id]
	return {
		"stage": int(state["stage"]),
		"progress": (state["progress"] as Array[int]).duplicate(),
		"deadline": int(state["deadline"]),
	}

## Per-objective progress for the CURRENT stage of an active quest (a duplicate
## so callers can't mutate our state). Empty array if the quest isn't active.
func get_objective_progress(id: StringName) -> Array[int]:
	if not _active.has(id):
		return [] as Array[int]
	var state: Dictionary = _active[id]
	return (state["progress"] as Array[int]).duplicate()

## Every Quest that is currently active, as resources (for the quest log UI).
func get_active_quests() -> Array[Quest]:
	var result: Array[Quest] = []
	for id in _active:
		var quest: Quest = database.get(id)
		if quest != null:
			result.append(quest)
	return result

## The set of item ids the player is CURRENTLY collecting: every CURRENT-stage
## COLLECT_ITEM objective target of any active quest whose count isn't yet
## satisfied. The shop reads this to avoid selling items quests still need.
func get_active_quest_item_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id in _active:
		var state: Dictionary = _active[id]
		var stage_index: int = int(state["stage"])
		var progress: Array[int] = state["progress"]
		var objectives: Array[QuestObjective] = _stage_objectives(id, stage_index)
		for i in objectives.size():
			if i >= progress.size():
				break
			var objective: QuestObjective = objectives[i]
			if objective.kind != QuestObjective.Kind.COLLECT_ITEM:
				continue
			var required: int = maxi(objective.required_count, 1)
			if progress[i] >= required:
				continue  # already gathered enough of this one
			if objective.target != &"" and not ids.has(objective.target):
				ids.append(objective.target)
	return ids

## Active quests filtered to one tier (Quest.Tier.MAIN / SIDE / TASK).
func get_active_by_tier(tier: int) -> Array[Quest]:
	var result: Array[Quest] = []
	for id in _active:
		var quest: Quest = database.get(id)
		if quest != null and int(quest.tier) == tier:
			result.append(quest)
	return result

## The tier of a quest (defaults to SIDE for unknown ids).
func get_quest_tier(id: StringName) -> int:
	var quest: Quest = database.get(id)
	if quest == null:
		return Quest.Tier.SIDE
	return int(quest.tier)

## The current stage index of an active quest (0 if not active / legacy).
func get_current_stage_index(id: StringName) -> int:
	if not _active.has(id):
		return 0
	var state: Dictionary = _active[id]
	return int(state["stage"])

## The current QuestStage resource, or null for legacy (no `stages`) / inactive.
func get_current_stage(id: StringName) -> QuestStage:
	var quest: Quest = database.get(id)
	if quest == null or quest.stages.is_empty():
		return null
	var idx: int = get_current_stage_index(id)
	if idx < 0 or idx >= quest.stages.size():
		return null
	return quest.stages[idx]

## The objectives the player is currently working on (current stage, or the
## legacy flat list).
func get_current_objectives(id: StringName) -> Array[QuestObjective]:
	var idx: int = get_current_stage_index(id)
	return _stage_objectives(id, idx)

## How many stages this quest has (1 for legacy single-stage quests).
func get_stage_count(id: StringName) -> int:
	return _stage_count(id)

## Game-minutes left before a timed task expires, or -1 if the quest isn't an
## active timed task.
func get_task_minutes_remaining(id: StringName) -> int:
	if not _active.has(id):
		return -1
	var state: Dictionary = _active[id]
	var deadline: int = int(state["deadline"])
	if deadline < 0:
		return -1
	return maxi(0, deadline - now_minutes())

# --- Progress updates ------------------------------------------------------

## Re-checks the CURRENT stage's COLLECT_ITEM objectives against the bag,
## clamping progress to required_count. Returns true if anything changed.
func _reevaluate_collect(id: StringName) -> bool:
	if not _active.has(id):
		return false
	var state: Dictionary = _active[id]
	var stage_index: int = int(state["stage"])
	var progress: Array[int] = state["progress"]
	var objectives: Array[QuestObjective] = _stage_objectives(id, stage_index)
	var changed := false
	for i in objectives.size():
		if i >= progress.size():
			break
		var objective: QuestObjective = objectives[i]
		if objective.kind == QuestObjective.Kind.COLLECT_ITEM:
			var have := mini(Inventory.count_of(objective.target), maxi(objective.required_count, 1))
			if progress[i] != have:
				progress[i] = have
				changed = true
	return changed

## Pre-fills the CURRENT stage's progress from the world as the stage begins:
## COLLECT from the bag, REACH_FLAG from already-set GameState flags.
func _reevaluate_stage_start(id: StringName) -> void:
	if not _active.has(id):
		return
	var state: Dictionary = _active[id]
	var stage_index: int = int(state["stage"])
	var progress: Array[int] = state["progress"]
	var objectives: Array[QuestObjective] = _stage_objectives(id, stage_index)
	for i in objectives.size():
		if i >= progress.size():
			break
		var objective: QuestObjective = objectives[i]
		var required: int = maxi(objective.required_count, 1)
		if objective.kind == QuestObjective.Kind.COLLECT_ITEM:
			progress[i] = mini(Inventory.count_of(objective.target), required)
		elif objective.kind == QuestObjective.Kind.REACH_FLAG:
			if GameState.get_flag(objective.target, false):
				progress[i] = required

## When items change, refresh every active quest's CURRENT-stage COLLECT
## objectives. Emit quest_updated for any that moved, and advance/finish any
## stage that is now satisfied.
func _on_inventory_changed(_id: StringName, _new_count: int) -> void:
	# Copy keys first: _check_stage can mutate _active mid-loop.
	for quest_id in _active.keys():
		if not _active.has(quest_id):
			continue
		if _reevaluate_collect(quest_id):
			quest_updated.emit(quest_id)
		_check_stage(quest_id)

## Marks a CURRENT-stage objective done (sets its progress to required). Called
## e.g. from a dialogue `do QuestSystem.complete_objective(...)`. `index` is the
## objective's position within the current stage.
func complete_objective(id: StringName, index: int) -> void:
	if not _active.has(id):
		push_warning("QuestSystem.complete_objective: quest '%s' is not active" % id)
		return
	var state: Dictionary = _active[id]
	var stage_index: int = int(state["stage"])
	var progress: Array[int] = state["progress"]
	var objectives: Array[QuestObjective] = _stage_objectives(id, stage_index)
	if index < 0 or index >= objectives.size() or index >= progress.size():
		push_warning("QuestSystem.complete_objective: bad index %d for quest '%s'" % [index, id])
		return
	var required: int = maxi(objectives[index].required_count, 1)
	if progress[index] != required:
		progress[index] = required
		quest_updated.emit(id)
	_check_stage(id)

## Reports a world flag as reached. For every ACTIVE quest, any CURRENT-stage
## REACH_FLAG objective whose target == flag is marked done. Areas/dungeons call
## this (alongside GameState.set_flag) when the player clears/reaches something.
func mark_flag(flag: StringName) -> void:
	for quest_id in _active.keys():
		if not _active.has(quest_id):
			continue
		var state: Dictionary = _active[quest_id]
		var stage_index: int = int(state["stage"])
		var progress: Array[int] = state["progress"]
		var objectives: Array[QuestObjective] = _stage_objectives(quest_id, stage_index)
		var changed := false
		for i in objectives.size():
			if i >= progress.size():
				break
			var objective: QuestObjective = objectives[i]
			if objective.kind == QuestObjective.Kind.REACH_FLAG and objective.target == flag:
				var required: int = maxi(objective.required_count, 1)
				if progress[i] != required:
					progress[i] = required
					changed = true
		if changed:
			quest_updated.emit(quest_id)
		_check_stage(quest_id)

## Internal: if every objective of the CURRENT stage is satisfied, finish the
## stage (apply its on_complete effects + advance) or, if it was the last/only
## stage, complete the whole quest. Chains: an advanced stage whose objectives
## are already met completes immediately too.
func _check_stage(id: StringName) -> void:
	if not _active.has(id):
		return
	var state: Dictionary = _active[id]
	var stage_index: int = int(state["stage"])
	var progress: Array[int] = state["progress"]
	var objectives: Array[QuestObjective] = _stage_objectives(id, stage_index)
	for i in objectives.size():
		var required: int = maxi(objectives[i].required_count, 1)
		if i >= progress.size() or progress[i] < required:
			return  # at least one current-stage objective unfinished
	var quest: Quest = database.get(id)
	if quest == null:
		return
	var uses_stages: bool = not quest.stages.is_empty()
	if uses_stages and stage_index >= 0 and stage_index < quest.stages.size():
		var stage: QuestStage = quest.stages[stage_index]
		if stage != null:
			for effect in stage.on_complete:
				if effect != null:
					effect.apply()
		# on_complete effects may have mutated our state (e.g. completed the
		# quest outright). Bail if this quest is no longer active.
		if not _active.has(id):
			return
	if stage_index + 1 < _stage_count(id):
		# A non-final stage just finished: hand out a small XP nudge for progress.
		_award_progression_xp(STAGE_ADVANCE_XP)
		# Advance to the next stage: reset progress, pre-fill, announce, re-check.
		state["stage"] = stage_index + 1
		var next_objectives: Array[QuestObjective] = _stage_objectives(id, stage_index + 1)
		var next_progress: Array[int] = []
		next_progress.resize(next_objectives.size())
		next_progress.fill(0)
		state["progress"] = next_progress
		_reevaluate_stage_start(id)
		quest_stage_advanced.emit(id, stage_index + 1)
		quest_updated.emit(id)
		_check_stage(id)
	else:
		complete_quest(id)

# --- Completion ------------------------------------------------------------

## Finishes an active quest: hands out its final rewards and announces it. A
## repeatable task goes on cooldown instead of being permanently completed, so
## it can be re-offered later. Safe to call directly (e.g. COMPLETE_QUEST effect).
func complete_quest(id: StringName) -> void:
	if not _active.has(id):
		push_warning("QuestSystem.complete_quest: quest '%s' is not active" % id)
		return
	var quest: Quest = database.get(id)
	_active.erase(id)
	var repeatable: bool = quest != null and quest.repeatable
	if repeatable:
		_cooldowns[id] = now_minutes() + maxi(quest.cooldown_minutes, 0)
	else:
		_completed[id] = true
	# Apply rewards after state is settled so anything they trigger sees a
	# consistent view.
	if quest != null:
		for reward in quest.rewards:
			if reward != null:
				reward.apply()
	# Reward progression XP, scaled by the quest's tier (main story > side > task).
	_award_progression_xp(_completion_xp_for_tier(get_quest_tier(id)))
	quest_completed.emit(id)

# --- Progression XP rewards -------------------------------------------------

## XP granted on completing a quest of each tier, indexed by Quest.Tier
## (MAIN=0, SIDE=1, TASK=2). Defaults to the TASK value for unknown tiers.
const COMPLETION_XP_MAIN: int = 150
const COMPLETION_XP_SIDE: int = 60
const COMPLETION_XP_TASK: int = 20

## XP granted each time a non-final stage of a multi-stage quest is finished.
const STAGE_ADVANCE_XP: int = 20

## The completion XP for a quest tier (Quest.Tier int).
func _completion_xp_for_tier(tier: int) -> int:
	if tier == Quest.Tier.MAIN:
		return COMPLETION_XP_MAIN
	if tier == Quest.Tier.SIDE:
		return COMPLETION_XP_SIDE
	return COMPLETION_XP_TASK

## Award progression XP through the optional Progression autoload, guarded so the
## quest system keeps working in scenes/tests where Progression isn't present.
func _award_progression_xp(amount: int) -> void:
	if amount <= 0:
		return
	var progression := get_node_or_null("/root/Progression")
	if progression != null and progression.has_method("add_xp"):
		progression.add_xp(amount)

# --- Timed tasks + cooldowns -----------------------------------------------

## Per game-minute tick: expire any timed task past its deadline and clear any
## cooldowns that have elapsed.
func _on_clock_tick(_hour: int, _minute: int) -> void:
	var now: int = now_minutes()
	for quest_id in _active.keys():
		if not _active.has(quest_id):
			continue
		var state: Dictionary = _active[quest_id]
		var deadline: int = int(state["deadline"])
		if deadline >= 0 and now > deadline:
			_expire_task(quest_id, now)
	for cd_id in _cooldowns.keys():
		if now >= int(_cooldowns[cd_id]):
			_cooldowns.erase(cd_id)

## A timed task ran out: drop it (no rewards), put it on cooldown if repeatable,
## and announce the failure.
func _expire_task(id: StringName, now: int) -> void:
	if not _active.has(id):
		return
	var quest: Quest = database.get(id)
	_active.erase(id)
	if quest != null and quest.repeatable:
		_cooldowns[id] = now + maxi(quest.cooldown_minutes, 0)
	task_expired.emit(id)
	quest_failed.emit(id)

# --- Task offering API -----------------------------------------------------

## Registers the pool of task quest ids an NPC can hand out. npc.gd calls this on
## _ready from NPCDefinition.task_pool. `pool` is an Array of quest ids
## (StringName or String).
func register_task_giver(npc_id: StringName, pool: Array) -> void:
	var ids: Array[StringName] = []
	for entry in pool:
		ids.append(StringName(entry))
	_task_givers[npc_id] = ids

## True if a quest id is a TASK that can be offered right now: known, TASK-tier,
## not active, not (completed and non-repeatable), and not on cooldown.
func is_task_available(id: StringName) -> bool:
	var quest: Quest = database.get(id)
	if quest == null:
		return false
	if int(quest.tier) != Quest.Tier.TASK:
		return false
	if is_active(id):
		return false
	if is_completed(id) and not quest.repeatable:
		return false
	if _cooldowns.has(id) and now_minutes() < int(_cooldowns[id]):
		return false
	return true

## True if the given giver has at least one task available to hand out.
func has_task_available(npc_id: StringName) -> bool:
	if not _task_givers.has(npc_id):
		return false
	var pool: Array = _task_givers[npc_id]
	for tid in pool:
		if is_task_available(tid):
			return true
	return false

## Starts the first available task in the giver's pool, announces it, and returns
## its id (or &"" if the giver has nothing to offer).
func request_task(npc_id: StringName) -> StringName:
	if not _task_givers.has(npc_id):
		return &""
	var pool: Array = _task_givers[npc_id]
	for tid in pool:
		var task_id: StringName = tid
		if is_task_available(task_id):
			start_quest(task_id)
			task_offered.emit(task_id, npc_id)
			return task_id
	return &""

## Starts one specific available task. Returns false if it isn't currently
## offerable.
func give_task(id: StringName) -> bool:
	if not is_task_available(id):
		return false
	start_quest(id)
	return true

# --- Save / load -----------------------------------------------------------

func capture_state() -> Dictionary:
	# Duplicate per-quest state so the snapshot is independent.
	var active_copy: Dictionary = {}
	for id in _active:
		var state: Dictionary = _active[id]
		active_copy[id] = {
			"stage": int(state["stage"]),
			"progress": (state["progress"] as Array[int]).duplicate(),
			"deadline": int(state["deadline"]),
		}
	return {
		"active": active_copy,
		"completed": _completed.duplicate(),
		"cooldowns": _cooldowns.duplicate(),
	}

func restore_state(data: Dictionary) -> void:
	_active = {}
	_completed = {}
	_cooldowns = {}
	var saved_active: Dictionary = data.get("active", {})
	for id in saved_active:
		var entry = saved_active[id]
		var stage: int = 0
		var deadline: int = -1
		var progress: Array[int] = []
		if entry is Dictionary:
			# v2 format: { stage, progress, deadline }.
			var entry_dict: Dictionary = entry
			stage = int(entry_dict.get("stage", 0))
			deadline = int(entry_dict.get("deadline", -1))
			for value in entry_dict.get("progress", []):
				progress.append(int(value))
		elif entry is Array:
			# OLD format: active[id] was a bare Array[int]. Treat as stage 0,
			# untimed.
			for value in entry:
				progress.append(int(value))
		_active[id] = {"stage": stage, "progress": progress, "deadline": deadline}
	var saved_completed: Dictionary = data.get("completed", {})
	_completed = saved_completed.duplicate()
	var saved_cooldowns: Dictionary = data.get("cooldowns", {})
	for cd_id in saved_cooldowns:
		_cooldowns[cd_id] = int(saved_cooldowns[cd_id])
	# Let any listening UI rebuild from the restored state.
	for id in _active:
		quest_updated.emit(id)
