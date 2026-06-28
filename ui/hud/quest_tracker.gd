# quest_tracker.gd
# Autoload singleton (registered as "QuestTracker", pointing at THIS .gd script).
#
# A tiny always-on "what am I doing / where" panel pinned top-left, just under the
# money readout. It shows the single most-important active quest: its tier label
# (colour-coded), title, current stage (for multi-stage quests), and the first
# objective with a LIVE collect count (e.g. "[ ] Gather lava ash (2/5)"). When no
# quest is active it hides entirely.
#
# WHY a standalone CanvasLayer autoload (not an edit to hud.gd): this keeps the
# quest-discoverability work completely OFF the Combat HUD so the two never collide.
# Like the HUD/QuestLog it owns NO state — it is a pure VIEW that reads QuestSystem
# and redraws on its signals (+ Inventory.item_changed for live collect counts).
#
# It sits on CanvasLayer layer 6 (with the quest log) and process_mode = ALWAYS so it
# stays readable while a menu pauses the tree. Dark text on the frosted glass matches
# the project's "dark text on glass" readability convention.
#
# Robustness: every autoload it touches is reached via get_node_or_null and guarded,
# so it boots cleanly regardless of autoload registration order (it retries the bind
# on the next frame if QuestSystem isn't up yet). All reads off the QuestSystem Node
# reference are Variant, so we use untyped/explicitly-typed vars — never `:=`.

extends CanvasLayer

const Glass = preload("res://ui/glass_style.gd")

# Tier index -> label + colour (mirrors Quest.Tier: MAIN=0, SIDE=1, TASK=2). Colours
# are dark/saturated so they read against the light frosted glass (matches quest_log).
const TIER_NAMES: Array = ["Main Quest", "Side Quest", "Task"]
const TIER_COLORS: Array = [
	Color(0.58, 0.36, 0.02),   # MAIN - dark gold
	Color(0.16, 0.20, 0.30),   # SIDE - slate (matches quest_log header)
	Color(0.72, 0.42, 0.04),   # TASK - amber (matches quest_log task colour)
]
## Near-black body / title text for readability on the bright glass panel.
const BODY_COLOR: Color = Color(0.12, 0.14, 0.18)
const TITLE_COLOR: Color = Color(0.08, 0.10, 0.15)
## Dark gold the title switches to while the featured quest is the MAIN story quest, so
## the backbone goal is unmistakable at a glance (matches the MAIN tier colour).
const MAIN_TITLE_COLOR: Color = Color(0.58, 0.36, 0.02)
## Small marker prepended to the immediate (current-stage, first) objective so the very
## next thing to do reads as a call to action. Kept ASCII for the default UI font.
const NEXT_STEP_PREFIX: String = "[NEXT STEP] "

# Built once in _build_ui(); thereafter only their text/colour/visibility change.
var _panel: PanelContainer
var _tier: Label
var _title: Label
var _stage: Label
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
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	# Top-left, sitting under the HUD's health/stamina/mana/money stack.
	_panel.position = Vector2(16, 150)
	_panel.custom_minimum_size = Vector2(240, 0)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Frosted-glass box (rim + blurred game view behind it), like the other panels.
	Glass.apply(_panel, 12, 14)
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	margin.add_child(vbox)

	_tier = _make_label(vbox, 12, TIER_COLORS[0])
	_title = _make_label(vbox, 17, TITLE_COLOR)
	_stage = _make_label(vbox, 12, TIER_COLORS[1])
	_objective = _make_label(vbox, 13, BODY_COLOR)
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _make_label(parent: Node, size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

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
	_bound = true
	_refresh()

# --- Refresh ---------------------------------------------------------------

# QuestSystem signals carry varying payloads; we always redraw the whole panel, so
# swallow up to three optional args to match any of their signatures.
func _on_changed(_a = null, _b = null, _c = null) -> void:
	_refresh()

func _on_item_changed(_id = null, _count = null) -> void:
	_refresh()

func _refresh() -> void:
	if _panel == null:
		return
	var quests: Node = get_node_or_null("/root/QuestSystem")
	if quests == null:
		_panel.visible = false
		return
	var quest = _pick_quest(quests)
	if quest == null:
		_panel.visible = false
		return
	_panel.visible = true

	var tier_index: int = clampi(int(quest.tier), 0, TIER_NAMES.size() - 1)
	_tier.text = TIER_NAMES[tier_index]
	_tier.add_theme_color_override("font_color", TIER_COLORS[tier_index])
	_title.text = quest.title
	# Gild the title while the MAIN story quest is featured (tier 0); plain near-black
	# otherwise. Read straight off the resource's tier so it tracks the picked quest.
	var is_main: bool = tier_index == 0
	if quests.has_method("get_quest_tier"):
		is_main = int(quests.get_quest_tier(quest.id)) == 0
	_title.add_theme_color_override("font_color", MAIN_TITLE_COLOR if is_main else TITLE_COLOR)

	_apply_stage(quests, quest)
	_apply_objective(quests, quest)

# The single quest to feature. The player's explicit choice (GameState flag
# &"tracked_quest", set from the Quests menu tab) wins as long as that quest is still
# active; otherwise we fall back to highest tier first (Main, then Side, then Task), and
# within a tier the first active one. Returns null when nothing is active.
func _pick_quest(quests: Node):
	# Honour the player-chosen tracked quest first, if it's still active.
	var gs: Node = get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("get_flag"):
		var tid = gs.get_flag(&"tracked_quest", &"")
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

# Show the first current-stage objective with its live progress, mirroring the quest
# log's checkbox style. Hides if the quest has no objectives we can read.
func _apply_objective(quests: Node, quest) -> void:
	if not quests.has_method("get_current_objectives"):
		_objective.visible = false
		return
	var objectives = quests.get_current_objectives(quest.id)
	if objectives == null or objectives.is_empty():
		_objective.visible = false
		return
	var progress = quests.get_objective_progress(quest.id)
	var obj = objectives[0]
	var current: int = 0
	if progress != null and progress.size() > 0:
		current = int(progress[0])
	_objective.visible = true
	# Prefix the immediate goal with a small call-to-action marker so a new player knows
	# exactly what to do next, not just what the objective is.
	_objective.text = NEXT_STEP_PREFIX + _objective_text(obj, current)

# One objective line: REACH_FLAG reads done/not-done, COLLECT_ITEM shows "(cur/req)".
func _objective_text(objective, current: int) -> String:
	var desc: String = objective.description
	# QuestObjective.Kind: COLLECT_ITEM = 0, REACH_FLAG = 1 (enums here are append-only).
	var is_flag: bool = false
	if "kind" in objective:
		is_flag = int(objective.kind) == 1
	if is_flag:
		return ("[x] %s" % desc) if current >= 1 else ("[ ] %s" % desc)
	var required: int = maxi(int(objective.required_count), 1)
	if current >= required:
		return "[x] %s" % desc
	return "[ ] %s (%d/%d)" % [desc, current, required]
