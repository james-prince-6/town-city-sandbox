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
# whenever QuestSystem starts/updates/completes a quest, the list rebuilds.

extends CanvasLayer

const Glass = preload("res://ui/glass_style.gd")

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

	# Rebuild whenever the quest picture changes.
	QuestSystem.quest_started.connect(_on_quests_changed)
	QuestSystem.quest_updated.connect(_on_quests_changed)
	QuestSystem.quest_completed.connect(_on_quests_changed)

	# Draw once so the panel is correct the first time it's shown.
	_rebuild()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("quest_log"):
		_toggle()
		get_viewport().set_input_as_handled()
	elif visible and event.is_action_pressed("ui_cancel"):
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

# QuestSystem signals pass a quest id, but we don't care which — we always redraw
# the whole list. The argument is ignored.
func _on_quests_changed(_id: StringName) -> void:
	if visible:
		_rebuild()

# Clears and repopulates the list from the current active quests.
func _rebuild() -> void:
	for child in list.get_children():
		child.queue_free()

	var quests := QuestSystem.get_active_quests()
	empty_label.visible = quests.is_empty()

	for quest in quests:
		list.add_child(_make_quest_entry(quest))

# Builds one quest block: a bold-ish title, its description, and one line per
# objective drawn as a checkbox ("[x]" done / "[ ]" with progress).
func _make_quest_entry(quest: Quest) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	var title := Label.new()
	title.text = quest.title
	box.add_child(title)

	var desc := Label.new()
	desc.text = quest.description
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(desc)

	# Per-objective progress lives in QuestSystem, not on the template objectives.
	var progress := QuestSystem.get_objective_progress(quest.id)

	for i in quest.objectives.size():
		var objective := quest.objectives[i]
		var required := objective.required_count
		var current := progress[i] if i < progress.size() else 0

		var line := Label.new()
		if current >= required:
			line.text = "[x] %s" % objective.description
		else:
			line.text = "[ ] %s (%d/%d)" % [objective.description, current, required]
		box.add_child(line)

	return box
