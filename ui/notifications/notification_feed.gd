# notification_feed.gd
# Autoload singleton (registered as "NotificationFeed"). A small stack of transient
# "toast" messages in the top-right corner of the screen.
#
# Built entirely in code (no .tscn), mirroring main_menu.gd / death_screen.gd so there
# is no layout resource to maintain. It is a CanvasLayer that processes ALWAYS, so a
# toast still fades correctly even if one pops while the tree is paused (e.g. a level-up
# landing as a menu opens).
#
# What it shows:
#   - Inventory.item_gained -> "+N DisplayName" when the player picks up / crafts / buys.
#   - Progression.leveled_up -> "Level N!" in gold, a louder colour than item toasts.
#   - QuestSystem.quest_completed -> a larger "[TIER] Title Complete!" toast in a
#     tier colour (gold MAIN / silver SIDE / bronze TASK), with a reward summary.
#   - QuestSystem.quest_stage_advanced -> "Quest Updated: Title (Stage 2/3)".
#   - QuestSystem.task_expired -> "Task Failed: Name (timeout)" in amber.
#   - Reputation.reputation_shifted -> "+10 Reputation with Marlo" (neutral up /
#     reddish down), only for changes big enough to matter (see Reputation).
#
# Every quest/reputation handler is purely additive: it connects GUARDED through
# the tree (get_node_or_null) so this view stays safe even if an optional autoload
# isn't registered yet, and routes through the same notify()/Glass toast stack.
#
# Toasts stack newest-on-top in a VBoxContainer. Each one fades itself out after a few
# seconds and frees, so the feed naturally trims back to empty when things go quiet. We
# never touch game state here — this is a pure VIEW that listens to the gameplay autoloads.
#
# NOTE: intentionally NO class_name. The autoload is registered under the name
# "NotificationFeed"; giving the script the same class_name would collide with that global.

extends CanvasLayer

const Glass = preload("res://ui/glass_style.gd")

## How long a toast stays fully visible before it begins to fade, in seconds.
const HOLD_SECONDS: float = 2.2
## How long the fade-out itself takes, in seconds. HOLD + FADE is the total lifetime.
const FADE_SECONDS: float = 0.8
## Cap on how many toasts are shown at once; the oldest is dropped past this so a flood
## of pickups can't run off the screen.
const MAX_TOASTS: int = 5
## Dark default text for toasts so they read on the light frosted-glass backing.
const TOAST_COLOR: Color = Color(0.09, 0.1, 0.13)
## Deep amber for level-up toasts — sets them apart while staying legible on the glass.
const LEVEL_UP_COLOR: Color = Color(0.5, 0.36, 0.0)

## Quest-completion tier colours. Kept dark/saturated so they still read as
## gold / silver / bronze against the light frosted-glass backing.
# gold (MAIN), silver/slate (SIDE), bronze (TASK).
const TIER_COLOR_MAIN: Color = Color(0.55, 0.42, 0.0)
const TIER_COLOR_SIDE: Color = Color(0.30, 0.34, 0.40)
const TIER_COLOR_TASK: Color = Color(0.45, 0.28, 0.10)
## Amber for a failed/expired task — warns without the alarm of pure red.
const TASK_FAIL_COLOR: Color = Color(0.60, 0.38, 0.04)
## Reddish for a reputation LOSS; gains reuse the neutral TOAST_COLOR.
const REP_DOWN_COLOR: Color = Color(0.52, 0.12, 0.12)
## Default font size for a toast, and the slightly larger size used for the
## louder quest-completion banner.
const TOAST_FONT_SIZE: int = 18
const COMPLETE_FONT_SIZE: int = 22

## Soft UI ping played when a toast pops (an existing UI click, reused). Routed to
## the UI/SFX bus and kept quiet so it never competes with gameplay audio.
const PING_SOUND: AudioStream = preload("res://assets/audio/ui/click_a.ogg")
const PING_VOLUME_DB: float = -14.0

## Celebratory chime for a level-up, distinct (and a touch louder) than the soft per-
## toast ping so reaching a new level feels like an event. Played in place of the ping.
const LEVEL_UP_CHIME: AudioStream = preload("res://assets/audio/ui/levelup.ogg")
const LEVEL_UP_CHIME_VOLUME_DB: float = -8.0

# The column the toasts live in, pinned to the top-right. Built once in _ready().
var _stack: VBoxContainer

func _ready() -> void:
	# Above the HUD (layer 5) so toasts read over the bars, but below full-screen menus
	# like the bag (10) / pause (20) which should cover everything. Always-process so a
	# toast's fade tween keeps running even while a menu pauses the rest of the tree.
	layer = 8
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_connect_signals()

# --- Public API ------------------------------------------------------------

## Pop a toast reading `text` in `color`. The single entry point — both the signal
## handlers below and any future caller go through here. Auto-fades and frees itself.
##
## `play_sound` (default true) plays a soft UI ping so a toast is noticed even when
## the player isn't looking at the corner; pass false for silent/bulk toasts.
## `font_size` lets louder toasts (e.g. quest completion) render slightly larger.
func notify(text: String, color: Color = TOAST_COLOR, play_sound: bool = true, font_size: int = TOAST_FONT_SIZE) -> void:
	var toast := _make_toast(text, color, font_size)
	# Newest on top: insert at index 0 so the freshest message sits nearest the corner.
	_stack.add_child(toast)
	_stack.move_child(toast, 0)
	_trim_overflow()
	_animate(toast)
	if play_sound:
		_play_ping()

# --- Setup -----------------------------------------------------------------

func _connect_signals() -> void:
	# Inventory + Progression are registered ahead of this autoload, so they already
	# exist when we connect. Both signals are one-liners straight into notify().
	Inventory.item_gained.connect(_on_item_gained)
	Progression.leveled_up.connect(_on_leveled_up)
	# Quest + reputation feeds are ADDITIVE and connected GUARDED through the tree,
	# with has_signal() checks and string-based connect(), so a missing autoload or
	# an older build without these signals simply means no toast — never an error.
	var quests := get_node_or_null("/root/QuestSystem")
	if quests != null:
		if quests.has_signal("quest_completed"):
			quests.connect("quest_completed", _on_quest_completed)
		if quests.has_signal("quest_stage_advanced"):
			quests.connect("quest_stage_advanced", _on_quest_stage_advanced)
		if quests.has_signal("task_expired"):
			quests.connect("task_expired", _on_task_expired)
	var rep := get_node_or_null("/root/Reputation")
	if rep != null and rep.has_signal("reputation_shifted"):
		rep.connect("reputation_shifted", _on_reputation_shifted)

# --- Signal handlers -------------------------------------------------------

func _on_item_gained(id: StringName, amount: int) -> void:
	# Resolve a friendly name through the item database, falling back to the raw id for
	# anything not yet defined as an Item resource.
	var item := Inventory.get_item(id)
	var label_text: String = item.display_name if item else String(id)
	notify("+%d %s" % [amount, label_text])

func _on_leveled_up(level: int, points_gained: int) -> void:
	# Spell out the reward so the player knows a level-up is worth opening the skill tree.
	var text := "Level %d!" % level
	if points_gained > 0:
		var unit: String = "Skill Point" if points_gained == 1 else "Skill Points"
		text += "  +%d %s" % [points_gained, unit]
	# Suppress the soft ping (play_sound=false) and play the dedicated chime instead, so a
	# level-up reads as a louder, distinct event; both degrade silently if audio is absent.
	notify(text, LEVEL_UP_COLOR, false, COMPLETE_FONT_SIZE)
	_play_chime()

# A quest finished: pop a louder, tier-coloured banner with an optional reward
# summary. Reads the (still-registered) Quest definition by id; the quest has been
# removed from the active set by now, but its template is always in the database.
func _on_quest_completed(id: StringName) -> void:
	var quest: Quest = _lookup_quest(id)
	var title: String = quest.title if quest != null else String(id)
	var tier: int = int(quest.tier) if quest != null else int(Quest.Tier.SIDE)
	var prefix := "SIDE"
	var col: Color = TIER_COLOR_SIDE
	match tier:
		int(Quest.Tier.MAIN):
			prefix = "MAIN"
			col = TIER_COLOR_MAIN
		int(Quest.Tier.TASK):
			prefix = "TASK"
			col = TIER_COLOR_TASK
	var text := "[%s] %s Complete!" % [prefix, title]
	var summary := _reward_summary(quest)
	if summary != "":
		text += "\n" + summary
	notify(text, col, true, COMPLETE_FONT_SIZE)

# A multi-stage quest moved on. `stage_index` is the NEW current stage (0-based);
# show it 1-based with the total so progress reads naturally.
func _on_quest_stage_advanced(id: StringName, stage_index: int) -> void:
	var quest: Quest = _lookup_quest(id)
	var title: String = quest.title if quest != null else String(id)
	var total := 1
	var quests := get_node_or_null("/root/QuestSystem")
	if quests != null and quests.has_method("get_stage_count"):
		total = maxi(int(quests.get_stage_count(id)), 1)
	notify("Quest Updated: %s (Stage %d/%d)" % [title, stage_index + 1, total])

# A timed task ran out before it was finished.
func _on_task_expired(id: StringName) -> void:
	var quest: Quest = _lookup_quest(id)
	var task_name: String = quest.title if quest != null else String(id)
	notify("Task Failed: %s (timeout)" % task_name, TASK_FAIL_COLOR)

# A reputation change big enough to surface (Reputation gates the threshold). The
# delta already carries its sign; gains read neutral, losses reddish.
func _on_reputation_shifted(npc_id: StringName, delta: int, _value: int) -> void:
	# Friendly-ish name from the raw id, e.g. &"marlo" -> "Marlo".
	var who := String(npc_id).capitalize()
	var col: Color = TOAST_COLOR if delta >= 0 else REP_DOWN_COLOR
	notify("%+d Reputation with %s" % [delta, who], col)

# --- Quest helpers ---------------------------------------------------------

# Look up a Quest definition by id through the (guarded) QuestSystem autoload.
# Returns null if the autoload or the quest is missing.
func _lookup_quest(id: StringName) -> Quest:
	var quests := get_node_or_null("/root/QuestSystem")
	if quests == null or not quests.has_method("get_quest"):
		return null
	var res = quests.get_quest(id)
	return res if res is Quest else null

# Builds a short "Rewards: +50 money, +1 Potion" line from a quest's GameEffect
# rewards, or "" if there are none worth showing.
func _reward_summary(quest: Quest) -> String:
	if quest == null:
		return ""
	var parts: Array[String] = []
	for reward in quest.rewards:
		if reward == null:
			continue
		var line := _describe_reward(reward)
		if line != "":
			parts.append(line)
	if parts.is_empty():
		return ""
	return "Rewards: " + ", ".join(parts)

# Turns one reward GameEffect into a short human phrase. Only the player-facing
# reward types are summarised; anything else (flags, quest chaining) is skipped.
func _describe_reward(reward: GameEffect) -> String:
	match reward.type:
		GameEffect.EffectType.ADD_MONEY:
			return "+%d money" % reward.amount
		GameEffect.EffectType.GIVE_ITEM:
			var item := Inventory.get_item(reward.target)
			var item_name: String = item.display_name if item != null else String(reward.target)
			return "+%d %s" % [reward.amount, item_name]
		GameEffect.EffectType.ADD_REPUTATION:
			var who := String(reward.target).capitalize()
			return "%+d rep (%s)" % [reward.amount, who]
		_:
			return ""

# --- Audio -----------------------------------------------------------------

# Plays the soft UI ping for a toast. Mirrors UISound's fire-and-forget pattern:
# spawn a one-shot player, route to the UI bus (falling back to SFX, then master),
# and free it when done. Degrades silently if the stream/bus is unavailable.
func _play_ping() -> void:
	if PING_SOUND == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = PING_SOUND
	p.volume_db = PING_VOLUME_DB
	if AudioServer.get_bus_index(&"UI") != -1:
		p.bus = &"UI"
	elif AudioServer.get_bus_index(&"SFX") != -1:
		p.bus = &"SFX"
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

# Plays the louder level-up chime. Same fire-and-forget pattern as _play_ping (spawn a
# one-shot player on the UI bus, free when done); degrades silently if unavailable.
func _play_chime() -> void:
	if LEVEL_UP_CHIME == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = LEVEL_UP_CHIME
	p.volume_db = LEVEL_UP_CHIME_VOLUME_DB
	if AudioServer.get_bus_index(&"UI") != -1:
		p.bus = &"UI"
	elif AudioServer.get_bus_index(&"SFX") != -1:
		p.bus = &"SFX"
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()

# --- Lifetime --------------------------------------------------------------

# Tween a toast: hold at full opacity, then fade out, then free it. Uses real time and
# survives a tree pause so it behaves the same whether or not the game is paused.
func _animate(toast: Control) -> void:
	# Bind the tween to the TOAST (not the feed). If _trim_overflow frees this toast early, a
	# feed-bound tween would step on the freed node next frame and spam errors; a toast-bound
	# tween is auto-killed when the toast is freed.
	var tween := toast.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_interval(HOLD_SECONDS)
	tween.tween_property(toast, "modulate:a", 0.0, FADE_SECONDS)
	tween.tween_callback(toast.queue_free)

# Drops the oldest toasts (those at the bottom of the stack) once we exceed MAX_TOASTS,
# so a burst of pickups can't grow the column past the cap.
func _trim_overflow() -> void:
	while _stack.get_child_count() > MAX_TOASTS:
		var oldest := _stack.get_child(_stack.get_child_count() - 1)
		oldest.queue_free()
		# queue_free() doesn't drop the node from the count until end of frame, so remove
		# it from the tree now to keep this loop honest.
		_stack.remove_child(oldest)

# --- UI construction (all in code) -----------------------------------------

func _build_ui() -> void:
	# Anchor a container to the top-right corner with a little margin, and let toasts
	# stack downward from there. MOUSE_FILTER_IGNORE so the feed never eats clicks.
	_stack = VBoxContainer.new()
	_stack.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_stack.alignment = BoxContainer.ALIGNMENT_BEGIN
	_stack.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_stack.add_theme_constant_override("separation", 6)
	_stack.offset_left = -316
	_stack.offset_top = 16
	_stack.offset_right = -16
	_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stack)

# Builds one toast widget: a dark rounded panel with the message label inside. Right-
# aligned so toasts hug the corner regardless of how long the text is.
func _make_toast(text: String, color: Color, font_size: int = TOAST_FONT_SIZE) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_horizontal = Control.SIZE_SHRINK_END

	# Frosted-glass backing (no dark box); the border width doubles as the text padding.
	Glass.apply(panel, 8, 10)

	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	label.add_theme_font_size_override("font_size", font_size)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return panel
