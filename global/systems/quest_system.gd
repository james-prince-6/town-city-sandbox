# quest_system.gd
# Autoload singleton (registered as "QuestSystem").
#
# The brain that tracks quests at RUNTIME. The Quest / QuestObjective resources
# are pure templates (no progress stored on them); everything mutable — which
# quests are active, how far along each objective is, which are finished — lives
# here so the .tres files stay shareable and save-friendly.
#
# Design notes (mirrors inventory.gd):
# - Quest definitions are auto-loaded by scanning a folder of .tres files at
#   startup into `database` ({ id -> Quest }). Drop a new Quest .tres in and it
#   "just works" — no code edits.
# - COLLECT_ITEM objectives update themselves: we listen to Inventory.item_changed
#   and re-evaluate every active quest whenever the bag changes.
# - REACH_FLAG objectives are completed "manually" via complete_objective(), called
#   e.g. from a dialogue `do QuestSystem.complete_objective(...)`.
# - When all objectives of an active quest are done, the quest auto-completes and
#   its rewards (GameEffects) are applied.

extends Node

## Folder scanned for Quest (.tres) resources at startup. Every Quest found is
## registered into `database` under its `id`.
const QUEST_DB_PATH := "res://global/quests/resources/"

## A quest's lifecycle, from the player's point of view.
enum State { NOT_STARTED, ACTIVE, COMPLETED }

## Emitted when a quest first becomes active.
signal quest_started(id: StringName)
## Emitted whenever an active quest's objective progress changes.
signal quest_updated(id: StringName)
## Emitted when every objective is satisfied and the quest finishes.
signal quest_completed(id: StringName)

## id (StringName) -> Quest resource. Lookup table for every quest definition.
var database: Dictionary = {}

## id (StringName) -> Array[int] of per-objective progress. Only active quests
## have an entry here. Index matches the Quest's `objectives` array.
var _active: Dictionary = {}

## id (StringName) -> true for quests that have been completed.
var _completed: Dictionary = {}

func _ready() -> void:
	_load_database()
	# Re-check COLLECT_ITEM objectives every time the bag changes.
	Inventory.item_changed.connect(_on_inventory_changed)

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

# --- Starting quests -------------------------------------------------------

func start_quest(id: StringName) -> void:
	if not database.has(id):
		push_warning("QuestSystem.start_quest: unknown quest id '%s'" % id)
		return
	# Don't restart something already running or finished.
	if is_active(id) or is_completed(id):
		return
	var quest: Quest = database[id]
	# Seed one progress slot per objective, then evaluate COLLECT objectives so a
	# quest you already have the items for starts partly (or fully) done.
	var progress: Array[int] = []
	progress.resize(quest.objectives.size())
	progress.fill(0)
	_active[id] = progress
	_reevaluate_collect(id)
	quest_started.emit(id)
	quest_updated.emit(id)
	# Starting may already satisfy everything (had all items in the bag).
	_check_completion(id)

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

## Per-objective progress for an active quest (a duplicate so callers can't mutate
## our state). Empty array if the quest isn't active.
func get_objective_progress(id: StringName) -> Array[int]:
	if not _active.has(id):
		return [] as Array[int]
	return (_active[id] as Array[int]).duplicate()

## Every Quest that is currently active, as resources (for the quest log UI).
func get_active_quests() -> Array[Quest]:
	var result: Array[Quest] = []
	for id in _active:
		var quest: Quest = database.get(id)
		if quest != null:
			result.append(quest)
	return result

# --- Progress updates ------------------------------------------------------

## Re-checks every COLLECT_ITEM objective of an active quest against the bag,
## clamping progress to required_count. Returns true if anything changed.
func _reevaluate_collect(id: StringName) -> bool:
	var quest: Quest = database.get(id)
	if quest == null:
		return false
	var progress: Array[int] = _active[id]
	var changed := false
	for i in quest.objectives.size():
		var objective: QuestObjective = quest.objectives[i]
		if objective.kind == QuestObjective.Kind.COLLECT_ITEM:
			var have := mini(Inventory.count_of(objective.target), objective.required_count)
			if progress[i] != have:
				progress[i] = have
				changed = true
	return changed

## When items change, refresh every active quest's COLLECT objectives. Emit a
## quest_updated for any that moved, and auto-complete any that are now done.
func _on_inventory_changed(_id: StringName, _new_count: int) -> void:
	# Copy the keys first: _check_completion can mutate _active mid-loop.
	for quest_id in _active.keys():
		if not _active.has(quest_id):
			continue
		if _reevaluate_collect(quest_id):
			quest_updated.emit(quest_id)
		_check_completion(quest_id)

## Marks a REACH_FLAG objective done (sets its progress to required). Called e.g. from a
## dialogue `do QuestSystem.complete_objective(...)`. `index` is the objective's position.
func complete_objective(id: StringName, index: int) -> void:
	if not _active.has(id):
		push_warning("QuestSystem.complete_objective: quest '%s' is not active" % id)
		return
	var quest: Quest = database.get(id)
	if quest == null:
		return
	if index < 0 or index >= quest.objectives.size():
		push_warning("QuestSystem.complete_objective: bad index %d for quest '%s'" % [index, id])
		return
	var progress: Array[int] = _active[id]
	var required: int = maxi(quest.objectives[index].required_count, 1)
	if progress[index] != required:
		progress[index] = required
		quest_updated.emit(id)
	_check_completion(id)

## Internal: if every objective of an active quest is satisfied, finish it.
func _check_completion(id: StringName) -> void:
	if not _active.has(id):
		return
	var quest: Quest = database.get(id)
	if quest == null:
		return
	var progress: Array[int] = _active[id]
	for i in quest.objectives.size():
		var required: int = maxi(quest.objectives[i].required_count, 1)
		if progress[i] < required:
			return  # at least one objective unfinished
	complete_quest(id)

# --- Completion ------------------------------------------------------------

## Finishes an active quest: moves it to _completed, hands out its rewards, and
## announces it. Safe to call directly (e.g. from a COMPLETE_QUEST effect).
func complete_quest(id: StringName) -> void:
	if not _active.has(id):
		push_warning("QuestSystem.complete_quest: quest '%s' is not active" % id)
		return
	_active.erase(id)
	_completed[id] = true
	var quest: Quest = database.get(id)
	if quest != null:
		for reward in quest.rewards:
			if reward != null:
				reward.apply()
	quest_completed.emit(id)

# --- Save / load -----------------------------------------------------------

func capture_state() -> Dictionary:
	# Duplicate the per-objective progress arrays so the snapshot is independent.
	var active_copy: Dictionary = {}
	for id in _active:
		active_copy[id] = (_active[id] as Array[int]).duplicate()
	return {
		"active": active_copy,
		"completed": _completed.duplicate(),
	}

func restore_state(data: Dictionary) -> void:
	_active = {}
	var saved_active: Dictionary = data.get("active", {})
	for id in saved_active:
		var progress: Array[int] = []
		for value in saved_active[id]:
			progress.append(int(value))
		_active[id] = progress
	_completed = data.get("completed", {}).duplicate()
	# Let any listening UI rebuild from the restored state.
	for id in _active:
		quest_updated.emit(id)
