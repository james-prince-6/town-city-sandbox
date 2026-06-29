# quest_tracker.gd
# Autoload singleton (registered as "QuestTracker", pointing at THIS .gd script).
#
# A tiny always-on "what am I doing / where" panel pinned top-left, just under the
# HUD stat bars. It shows the single most-important active quest in the Town City
# sticker style: a gold tier TAB ("MAIN QUEST" / "SIDE QUEST" / "TASK") sitting on a
# cream CARD with the quest title, optional stage line, and the first objective with a
# checkbox + LIVE collect count (e.g. "Gather lava ash (2/5)"). Hides when idle.
#
# WHY a standalone CanvasLayer autoload (not an edit to hud.gd): this keeps the
# quest-discoverability work completely OFF the Combat HUD so the two never collide.
# Like the HUD/QuestLog it owns NO state — it is a pure VIEW that reads QuestSystem
# and redraws on its signals (+ Inventory.item_changed for live collect counts).
#
# It sits on CanvasLayer layer 6 (with the quest log) and process_mode = ALWAYS so it
# stays readable while a menu pauses the tree. Styling comes from the project theme's
# QuestTab / QuestCard / Display / Dim variations (no per-node colours needed).

extends CanvasLayer

# Tier index -> tab label (mirrors Quest.Tier: MAIN=0, SIDE=1, TASK=2).
const TIER_NAMES: Array = ["MAIN QUEST", "SIDE QUEST", "TASK"]
## Dark ink the tab label uses so it reads on the gold tab.
const TAB_TEXT_COLOR: Color = Color(0.102, 0.078, 0.027)
## The objective checkbox: solid ink when done, faint when still to do.
const CHECK_DONE: Color = Color(0.055, 0.051, 0.071, 1.0)
const CHECK_TODO: Color = Color(0.055, 0.051, 0.071, 0.28)

## GameState flag holding the player's HUD-tracked quest choice (set from the Quests
## menu). Empty = auto-pick the top active quest; NONE = explicitly hide the bar; any
## other value = that quest id.
const TRACKED_FLAG: StringName = &"tracked_quest"
const TRACK_NONE: StringName = &"__none__"

# Built once in _build_ui(); thereafter only their text / visibility change.
var _root: VBoxContainer
var _tier: Label
var _title: Label
var _stage: Label
var _check: ColorRect
var _objective: Label

# True once we've successfully wired QuestSystem/Inventory signals.
var _bound: bool = false
# Bounded retries so a missing QuestSystem autoload can't spin call_deferred forever.
var _bind_attempts: int = 0

func _ready() -> void:
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_bind_systems()
	_refresh()

# --- Setup -----------------------------------------------------------------

func _build_ui() -> void:
	# Root column: tab stacked directly on the card (no gap), top-left under the bars.
	_root = VBoxContainer.new()
	_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# Below the top-left stat-bar stack (info strip + 3 bars); clears the mana bar.
	_root.position = Vector2(22, 172)
	_root.custom_minimum_size = Vector2(240, 0)
	_root.add_theme_constant_override("separation", 0)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# --- gold tier tab ---
	var tab := PanelContainer.new()
	tab.theme_type_variation = &"QuestTab"
	tab.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(tab)

	_tier = Label.new()
	_tier.theme_type_variation = &"Display"
	_tier.add_theme_font_size_override("font_size", 10)
	_tier.add_theme_color_override("font_color", TAB_TEXT_COLOR)
	_tier.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tab.add_child(_tier)

	# --- cream card ---
	var card := PanelContainer.new()
	card.theme_type_variation = &"QuestCard"
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(card)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	card.add_child(v)

	_title = Label.new()
	_title.theme_type_variation = &"Display"
	_title.add_theme_font_size_override("font_size", 16)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_title)

	_stage = Label.new()
	_stage.theme_type_variation = &"Dim"
	_stage.add_theme_font_size_override("font_size", 12)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(_stage)

	# objective row: checkbox + step text
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(row)

	_check = ColorRect.new()
	_check.custom_minimum_size = Vector2(13, 13)
	_check.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_check.color = CHECK_TODO
	_check.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_check)

	_objective = Label.new()
	_objective.theme_type_variation = &"Dim"
	_objective.add_theme_font_size_override("font_size", 13)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_objective.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_objective.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_objective)

# Wire QuestSystem (quest changes) + Inventory (live collect counts). Reached via
# get_node_or_null so registration order can't break us; retried next frame if the
# QuestSystem autoload hasn't initialised yet.
func _bind_systems() -> void:
	if _bound:
		return
	var quests: Node = get_node_or_null("/root/QuestSystem")
	if quests == null:
		_bind_attempts += 1
		if _bind_attempts <= 10:
			call_deferred("_bind_systems")
		return
	for sig in ["quest_started", "quest_updated", "quest_stage_advanced",
			"quest_completed", "task_offered", "task_expired", "quest_failed"]:
		if quests.has_signal(sig):
			quests.connect(sig, _on_changed)
	var inv: Node = get_node_or_null("/root/Inventory")
	if inv != null and inv.has_signal("item_changed"):
		inv.connect("item_changed", _on_item_changed)
	# Live-refresh the moment the player tracks/untracks a quest (GameState flag change).
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_signal("flag_changed"):
		gs.connect("flag_changed", _on_flag_changed)
	_bound = true
	_refresh()

# Only the tracked-quest flag affects this panel; ignore every other flag.
func _on_flag_changed(flag_name: StringName, _value: Variant) -> void:
	if flag_name == TRACKED_FLAG:
		_refresh()

# --- Refresh ---------------------------------------------------------------

# QuestSystem signals carry varying payloads; we always redraw the whole panel, so
# swallow up to three optional args to match any of their signatures.
func _on_changed(_a = null, _b = null, _c = null) -> void:
	_refresh()

func _on_item_changed(_id = null, _count = null) -> void:
	_refresh()

func _refresh() -> void:
	if _root == null:
		return
	var quests: Node = get_node_or_null("/root/QuestSystem")
	if quests == null:
		_root.visible = false
		return
	var quest = _pick_quest(quests)
	if quest == null:
		_root.visible = false
		return
	_root.visible = true

	var tier_index: int = clampi(int(quest.tier), 0, TIER_NAMES.size() - 1)
	_tier.text = TIER_NAMES[tier_index]
	_title.text = quest.title

	_apply_stage(quests, quest)
	_apply_objective(quests, quest)

# The single quest to feature. The player's explicit choice (GameState flag
# &"tracked_quest", set from the Quests menu tab) wins as long as that quest is still
# active; otherwise we fall back to highest tier first (Main, then Side, then Task), and
# within a tier the first active one. Returns null when nothing is active.
func _pick_quest(quests: Node):
	# Honour the player's explicit choice from the Quests menu first.
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("get_flag"):
		var tid = gs.get_flag(TRACKED_FLAG, &"")
		# Player explicitly untracked the featured quest → show nothing.
		if tid == TRACK_NONE:
			return null
		if tid != &"" and quests.has_method("is_active") and quests.is_active(tid):
			if quests.has_method("get_quest"):
				var chosen = quests.get_quest(tid)
				if chosen != null:
					return chosen
	if not quests.has_method("get_active_by_tier"):
		return null
	for tier in [0, 1, 2]:
		var arr = quests.get_active_by_tier(tier)
		if arr != null and not arr.is_empty():
			return arr[0]
	return null

# Show "Stage X/Y" only for genuinely multi-stage quests; hide otherwise.
func _apply_stage(quests: Node, quest) -> void:
	var count: int = 1
	if quests.has_method("get_stage_count"):
		count = int(quests.get_stage_count(quest.id))
	if count > 1:
		var idx: int = 0
		if quests.has_method("get_current_stage_index"):
			idx = int(quests.get_current_stage_index(quest.id))
		_stage.visible = true
		_stage.text = "Stage %d/%d" % [idx + 1, count]
	else:
		_stage.visible = false

# Show the first current-stage objective with its live progress + checkbox state. Hides
# the whole row if the quest has no objectives we can read.
func _apply_objective(quests: Node, quest) -> void:
	if not quests.has_method("get_current_objectives"):
		_set_objective_visible(false)
		return
	var objectives = quests.get_current_objectives(quest.id)
	if objectives == null or objectives.is_empty():
		_set_objective_visible(false)
		return
	var progress = quests.get_objective_progress(quest.id)
	var obj = objectives[0]
	var current: int = 0
	if progress != null and progress.size() > 0:
		current = int(progress[0])
	_set_objective_visible(true)
	var done: bool = _objective_done(obj, current)
	_check.color = CHECK_DONE if done else CHECK_TODO
	_objective.text = _objective_text(obj, current)

func _set_objective_visible(v: bool) -> void:
	_check.visible = v
	_objective.visible = v

# Whether the first objective is satisfied (REACH_FLAG: reached; COLLECT_ITEM: count met).
func _objective_done(objective, current: int) -> bool:
	var is_flag: bool = "kind" in objective and int(objective.kind) == 1
	if is_flag:
		return current >= 1
	return current >= maxi(int(objective.required_count), 1)

# One objective line WITHOUT the old ASCII checkbox (the ColorRect is the checkbox now):
# COLLECT_ITEM shows "desc (cur/req)", REACH_FLAG shows just the desc.
func _objective_text(objective, current: int) -> String:
	var desc: String = objective.description
	var is_flag: bool = "kind" in objective and int(objective.kind) == 1
	if is_flag:
		return desc
	var required: int = maxi(int(objective.required_count), 1)
	if current >= required:
		return desc
	return "%s (%d/%d)" % [desc, current, required]
