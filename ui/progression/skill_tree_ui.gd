# skill_tree_ui.gd
# Autoload singleton (registered as "SkillTreeUI"). A full-screen overlay that shows the
# player's combat progression — level, an XP bar, unspent skill points — and the three
# playstyle branches (Melee / Ranged / Survival), each listing its skills with name,
# current rank x/max, and a "+" button to spend a point on it.
#
# Like PauseMenu, the whole UI is BUILT IN CODE so there's no layout file to maintain; the
# .tscn is just a CanvasLayer with this script attached. Toggle it with the "skill_tree"
# input action (default K), handled in _input like a menu. While open the mouse is freed
# and the tree is paused; the player reacts to our opened/closed signals (mirroring the
# inventory/brewing/shop menus) to stop movement and free the cursor.
#
# It listens to Progression's signals (xp_changed / leveled_up / skills_changed) and
# rebuilds the rows, so buying a skill or gaining a level updates the panel live.

extends CanvasLayer

const Flat = preload("res://ui/ui_style.gd")

## Emitted when the panel opens / closes. The player connects these to its existing
## _on_menu_opened / _on_menu_closed so gameplay pauses and the mouse frees, exactly like
## the inventory and shop menus.
signal opened
signal closed

## Branch -> column header label, in display order.
const BRANCH_TITLES := {
	0: "Melee",
	1: "Ranged",
	2: "Survival",
}

var is_open: bool = false

var _root: Control
var _level_label: Label
var _points_label: Label
var _xp_bar: ProgressBar
var _xp_label: Label
var _branch_rows: VBoxContainer  # holds the three branch columns, rebuilt on change

func _ready() -> void:
	# Above the HUD but below the pause menu (20). Always process so it works while paused.
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	hide()
	# Live-refresh whenever progression changes.
	Progression.xp_changed.connect(_on_progression_changed)
	Progression.skills_changed.connect(_refresh)
	Progression.leveled_up.connect(_on_leveled_up)

func _input(_event: InputEvent) -> void:
	# Retired: the unified PlayerMenu now owns the "skill_tree" key and opens its Skills
	# tab. This standalone overlay no longer opens itself; the autoload stays only so
	# existing references keep resolving.
	pass

# True when some other UI already owns the screen, so we shouldn't open over it.
func _other_ui_blocking() -> bool:
	if Dialogue.is_active:
		return true
	if InventoryUI.is_open:
		return true
	if is_instance_valid(ShopUI) and ShopUI.visible:
		return true
	if is_instance_valid(BrewingUI) and BrewingUI.visible:
		return true
	return false

# --- Open / close ----------------------------------------------------------

func open() -> void:
	if is_open:
		return
	is_open = true
	_refresh()
	show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	opened.emit()

func close() -> void:
	if not is_open:
		return
	is_open = false
	hide()
	closed.emit()

# --- UI construction (all in code) -----------------------------------------

func _build_ui() -> void:
	# Dim backdrop that also eats clicks behind the panel.
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	Flat.frost(dim)
	_root = dim

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 0)
	Flat.apply(panel, 18, 22)
	center.add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 12)
	panel.add_child(outer)

	# Title.
	var title := Label.new()
	title.text = "Skills"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	outer.add_child(title)

	# Level + points header row.
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 24)
	outer.add_child(header)

	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", 22)
	header.add_child(_level_label)

	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 22)
	header.add_child(_points_label)

	# XP bar with an overlaid text readout.
	var xp_holder := HBoxContainer.new()
	xp_holder.add_theme_constant_override("separation", 10)
	outer.add_child(xp_holder)

	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size = Vector2(480, 22)
	_xp_bar.show_percentage = false
	_xp_bar.min_value = 0.0
	xp_holder.add_child(_xp_bar)

	_xp_label = Label.new()
	xp_holder.add_child(_xp_label)

	# Container for the three branch columns (rebuilt each refresh).
	_branch_rows = VBoxContainer.new()
	_branch_rows.add_theme_constant_override("separation", 16)
	outer.add_child(_branch_rows)

	# Close button.
	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 44)
	close_btn.pressed.connect(close)
	outer.add_child(close_btn)

# --- Refresh ---------------------------------------------------------------

func _on_progression_changed(_xp: int, _level: int, _xp_to_next: int) -> void:
	_refresh()

func _on_leveled_up(_level: int, _points_gained: int) -> void:
	_refresh()

func _refresh() -> void:
	# Cheap to skip building rows while hidden, but the header is light; only rebuild the
	# heavy branch columns when actually visible.
	var level: int = Progression.get_level()
	var points: int = Progression.get_points()
	var xp: int = Progression.get_xp()
	var to_next: int = Progression.xp_to_next(level)

	if _level_label:
		_level_label.text = "Level %d" % level
	if _points_label:
		_points_label.text = "Points: %d" % points
	if _xp_bar:
		_xp_bar.max_value = float(maxi(to_next, 1))
		_xp_bar.value = float(xp)
	if _xp_label:
		_xp_label.text = "%d / %d XP" % [xp, to_next]

	if not is_open:
		return
	_rebuild_branches()

func _rebuild_branches() -> void:
	# Clear old columns.
	for child in _branch_rows.get_children():
		child.queue_free()

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	_branch_rows.add_child(columns)

	for branch in [0, 1, 2]:
		columns.add_child(_build_branch_column(branch))

func _build_branch_column(branch: int) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(220, 0)
	col.add_theme_constant_override("separation", 8)

	var header := Label.new()
	header.text = String(BRANCH_TITLES.get(branch, "Branch"))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 26)
	col.add_child(header)

	var skills: Array[Skill] = Progression.get_skills_in_branch(branch)
	for skill in skills:
		col.add_child(_build_skill_row(skill))

	return col

func _build_skill_row(skill: Skill) -> Control:
	var rank: int = Progression.get_rank(skill.id)
	var maxed: bool = rank >= skill.max_rank
	var affordable: bool = Progression.can_allocate(skill.id)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)

	# Name + rank line, with a "+" button.
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	box.add_child(top)

	var name_label := Label.new()
	var perk_tag: String = "  [Perk]" if skill.is_perk else ""
	name_label.text = "%s (%d/%d)%s" % [skill.display_name, rank, skill.max_rank, perk_tag]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(name_label)

	var plus := Button.new()
	plus.text = "MAX" if maxed else "+"
	plus.custom_minimum_size = Vector2(48, 0)
	plus.disabled = maxed or not affordable
	plus.pressed.connect(_on_allocate_pressed.bind(skill.id))
	top.add_child(plus)

	# Description / requirement subtext, greyed when locked.
	var desc := Label.new()
	desc.text = _row_subtext(skill, rank, maxed, affordable)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	if not maxed and not affordable and rank == 0:
		desc.modulate = Color(0.7, 0.7, 0.7)
	box.add_child(desc)

	return box

# A short status line under each skill: its effect, plus why it's locked if it is.
func _row_subtext(skill: Skill, rank: int, maxed: bool, affordable: bool) -> String:
	if maxed:
		return skill.description
	if affordable:
		return "%s  (cost %d)" % [skill.description, skill.cost]
	# Locked: explain the gate.
	if Progression.get_level() < skill.required_level:
		return "%s  (needs level %d)" % [skill.description, skill.required_level]
	if skill.prerequisite != &"" and Progression.get_rank(skill.prerequisite) < skill.prerequisite_rank:
		var prereq: Skill = Progression.get_skill(skill.prerequisite)
		var prereq_name: String = prereq.display_name if prereq != null else String(skill.prerequisite)
		return "%s  (needs %s rank %d)" % [skill.description, prereq_name, skill.prerequisite_rank]
	if Progression.get_points() < skill.cost:
		return "%s  (need %d points)" % [skill.description, skill.cost]
	return skill.description

func _on_allocate_pressed(skill_id: StringName) -> void:
	if Progression.allocate(skill_id):
		_refresh()  # skills_changed also fires, but refresh now for snappy feedback
