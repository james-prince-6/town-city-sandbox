# quest_log.gd
# Autoload singleton (registered as "QuestLog", pointing at quest_log.tscn).
#
# A read-only journal panel that VISUALISES the QuestSystem autoload. It owns no
# data of its own — it just reads QuestSystem and redraws. Because it lives in an
# autoload it's available in every scene without re-adding it.
#
# Toggle with the "quest_log" input action (bound to J). Unlike the inventory
# bag, this overlay is NON-blocking: it does not free the mouse or pause the
# game, so the player can keep moving while it's open. It stays in sync live:
# whenever QuestSystem starts/updates/completes a quest — or advances a stage,
# offers/expires a timed task, or fails a quest — the list rebuilds.
#
# QUEST v2: active quests are GROUPED by tier (Main / Side / Tasks). Multi-stage
# quests show "Stage X/Y: <title>" + only the CURRENT stage's objectives. Timed
# TASK-tier quests show an amber title + a "time left" countdown.

extends CanvasLayer

const Glass = preload("res://ui/glass_style.gd")

## Tier ids (mirror Quest.Tier: MAIN=0, SIDE=1, TASK=2).
const TIER_MAIN: int = 0
const TIER_SIDE: int = 1
const TIER_TASK: int = 2

## Section header colour — a dark slate, distinct from the body's near-black text.
const HEADER_COLOR: Color = Color(0.16, 0.2, 0.3, 1)
## Amber tint for timed TASK titles + their countdown, so timed work stands out.
const TASK_COLOR: Color = Color(0.72, 0.42, 0.04, 1)

## Per-tier badge colours (indexed by tier id) for the small [MAIN]/[SIDE]/[TASK] tag
## printed before each quest title, so priority reads at a glance even mid-section.
## Dark/saturated so they hold up against the bright frosted glass.
const BADGE_COLORS: Array = [
	Color(0.58, 0.36, 0.02, 1),   # MAIN - dark gold
	Color(0.16, 0.20, 0.30, 1),   # SIDE - slate
	Color(0.72, 0.42, 0.04, 1),   # TASK - amber
]
const BADGE_LABELS: Array = ["[MAIN]", "[SIDE]", "[TASK]"]
## Font sizes: the immediate (first) current-stage objective is rendered larger/bolder
## than the rest so the very next step stands out within the entry.
const PRIMARY_OBJECTIVE_FONT_SIZE: int = 16
const OBJECTIVE_FONT_SIZE: int = 13

@onready var list: VBoxContainer = $Panel/Margin/VBox/List
@onready var empty_label: Label = $Panel/Margin/VBox/EmptyLabel
@onready var _panel: PanelContainer = $Panel

func _ready() -> void:
	# Draw above the world (but below the inventory bag at 10) and keep working
	# even if something pauses the tree.
	layer = 6
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("exclusive_menu")  # so opening another menu closes this one (no stacking)
	# Frosted-glass backdrop instead of the default dark panel box.
	Glass.apply(_panel, 18, 22)
	hide()

	# Rebuild whenever the quest picture changes. The new v2 signals (stage
	# advance, timed-task offered/expired, quest failed) may not exist yet if the
	# quest-logic layer hasn't landed — guard each connection so the autoload
	# still boots cleanly either way.
	_connect_signal(&"quest_started")
	_connect_signal(&"quest_updated")
	_connect_signal(&"quest_completed")
	_connect_signal(&"quest_stage_advanced")
	_connect_signal(&"task_offered")
	_connect_signal(&"task_expired")
	_connect_signal(&"quest_failed")

	# Draw once so the panel is correct the first time it's shown.
	_rebuild()

## Connect a QuestSystem signal to the redraw handler if that signal exists.
func _connect_signal(sig: StringName) -> void:
	if QuestSystem.has_signal(sig):
		QuestSystem.connect(sig, _on_quests_changed)

func _unhandled_input(event: InputEvent) -> void:
	# The quest journal now lives as the QUESTS tab inside the player menu (opened on J there).
	# This standalone overlay no longer self-opens on the "quest_log" action, so the tab and the
	# overlay can never both appear (player_menu._input consumes J in the normal case; this stops
	# the old overlay from opening in the fall-through cases where player_menu declines). The
	# autoload stays registered as an inert, programmatically-toggleable view. ui_cancel still
	# closes it if some other code path ever shows it.
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	if visible:
		close()
	else:
		MenuManager.opening(self)  # close any other open menu first
		_rebuild()
		show()

## Close the journal. Named close() so MenuManager can shut it like the other menus.
func close() -> void:
	hide()

# QuestSystem signals carry varying payloads (most a quest id; stage-advance may
# carry an index). We never care which — we always redraw the whole list — so the
# handler swallows up to three optional args to match any of those signatures.
func _on_quests_changed(_a = null, _b = null, _c = null) -> void:
	if visible:
		_rebuild()

# --- Drawing ---------------------------------------------------------------

# Clears and repopulates the list, grouping active quests into Main / Side / Task
# sections. Headers only appear for tiers that have entries; the EmptyLabel shows
# only when every tier is empty.
func _rebuild() -> void:
	for child in list.get_children():
		child.queue_free()

	var main_quests: Array[Quest] = QuestSystem.get_active_by_tier(TIER_MAIN)
	var side_quests: Array[Quest] = QuestSystem.get_active_by_tier(TIER_SIDE)
	var tasks: Array[Quest] = QuestSystem.get_active_by_tier(TIER_TASK)

	empty_label.visible = main_quests.is_empty() and side_quests.is_empty() and tasks.is_empty()

	# Sections are emitted in tier-priority order (MAIN, then SIDE, then TASK) so the most
	# important work is always at the top of the journal.
	_add_section("Main Quests", main_quests, TIER_MAIN)
	_add_section("Side Quests", side_quests, TIER_SIDE)
	_add_section("Tasks", tasks, TIER_TASK)

# Adds a tier header + its quest entries, but only if the tier has any quests.
func _add_section(header: String, quests: Array[Quest], tier: int) -> void:
	if quests.is_empty():
		return
	list.add_child(_make_header(header))
	for quest in quests:
		list.add_child(_make_quest_entry(quest, tier))

# A bold-ish section header label.
func _make_header(text: String) -> Control:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", HEADER_COLOR)
	return label

# Builds one quest block: a tier badge + title (amber for timed tasks), an optional
# amber "time-sensitive" tag, an optional stage line for multi-stage quests, an optional
# countdown for timed tasks, the description, then one checkbox line per CURRENT-stage
# objective (the first rendered larger/bolder as the immediate next step).
func _make_quest_entry(quest: Quest, tier: int) -> Control:
	var is_task: bool = tier == TIER_TASK
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	# Title row: a small coloured [TIER] badge, then the quest title. The badge makes the
	# priority legible even when scanning the middle of a long list.
	var title_row := HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 6)
	box.add_child(title_row)

	var badge_index: int = clampi(tier, 0, BADGE_LABELS.size() - 1)
	var badge := Label.new()
	badge.text = BADGE_LABELS[badge_index]
	badge.add_theme_color_override("font_color", BADGE_COLORS[badge_index])
	title_row.add_child(badge)

	var title := Label.new()
	title.text = quest.title
	if is_task:
		title.add_theme_color_override("font_color", TASK_COLOR)
	title_row.add_child(title)

	# A standalone amber "time-sensitive" tag for any quest currently on a deadline, so
	# timed work is flagged before the player even reads the countdown below.
	if QuestSystem.get_task_minutes_remaining(quest.id) >= 0:
		var urgent := Label.new()
		urgent.text = "[TIME-SENSITIVE]"
		urgent.add_theme_color_override("font_color", TASK_COLOR)
		box.add_child(urgent)

	# Multi-stage quests: show progress through the stages + the current stage's
	# name. Single-stage (or legacy) quests skip this line entirely.
	var stage_count: int = QuestSystem.get_stage_count(quest.id)
	if stage_count > 1:
		var stage_index: int = QuestSystem.get_current_stage_index(quest.id)
		# Untyped on purpose: QuestStage is a new class_name that may not be in a
		# cold headless cache yet, so we read .title duck-typed instead of annotating.
		var stage = QuestSystem.get_current_stage(quest.id)
		var stage_title: String = ""
		if stage != null:
			stage_title = stage.title
		var stage_line := Label.new()
		stage_line.text = "Stage %d/%d: %s" % [stage_index + 1, stage_count, stage_title]
		box.add_child(stage_line)

	# Timed tasks: a "time left" countdown in amber. >= 0 means it's still ticking.
	if is_task:
		var remaining: int = QuestSystem.get_task_minutes_remaining(quest.id)
		if remaining >= 0:
			var clock := Label.new()
			clock.text = "time left: %s" % _format_minutes(remaining)
			clock.add_theme_color_override("font_color", TASK_COLOR)
			box.add_child(clock)

	var desc := Label.new()
	desc.text = quest.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)

	# Only the CURRENT stage's objectives, with their live progress.
	var objectives: Array[QuestObjective] = QuestSystem.get_current_objectives(quest.id)
	var progress: Array[int] = QuestSystem.get_objective_progress(quest.id)

	for i in objectives.size():
		var objective: QuestObjective = objectives[i]
		var current: int = progress[i] if i < progress.size() else 0
		# The first current-stage objective is the immediate next step: render it larger.
		box.add_child(_make_objective_line(objective, current, i == 0))

	return box

# One objective checkbox line. COLLECT shows "(cur/req)" counts; REACH_FLAG just
# reads done / not-done. `primary` (the stage's first objective) renders larger/bolder
# so the immediate next step stands out from the rest of the list.
func _make_objective_line(objective: QuestObjective, current: int, primary: bool = false) -> Label:
	var line := Label.new()
	if objective.kind == QuestObjective.Kind.REACH_FLAG:
		if current >= 1:
			line.text = "[x] %s" % objective.description
		else:
			line.text = "[ ] %s" % objective.description
	else:
		var required: int = objective.required_count
		if current >= required:
			line.text = "[x] %s" % objective.description
		else:
			line.text = "[ ] %s (%d/%d)" % [objective.description, current, required]
	line.add_theme_font_size_override("font_size", PRIMARY_OBJECTIVE_FONT_SIZE if primary else OBJECTIVE_FONT_SIZE)
	return line

# Formats a span of GAME minutes as "1h 20m" (or "45m" when under an hour).
func _format_minutes(total: int) -> String:
	var hours: int = total / 60
	var minutes: int = total % 60
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	return "%dm" % minutes
