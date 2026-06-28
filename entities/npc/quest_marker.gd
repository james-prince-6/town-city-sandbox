# quest_marker.gd
# A floating "this NPC has work for you" indicator that hovers above an NPC's head.
#
# It's a billboarded Label3D (always faces the camera, constant on-screen size, drawn
# over the world so it's findable from across the square) showing a single glyph:
#     "!"  a new quest is available to pick up here
#     "?"  an active quest tied to this NPC is ready to hand in
#     "T"  a repeatable task is available (QuestSystem.has_task_available)
#   or nothing at all when this NPC has no quest business right now.
#
# WHY a separate node (not a HUD edit): markers live IN the world above each NPC, so
# they belong to the NPC, not the 2D HUD. This script is instantiated as a child by
# npc.gd._ready() (loaded BY PATH, never by symbol, to dodge the cold class-cache
# pitfall for brand-new class_names). It owns NO quest state — it asks its parent NPC
# for the glyph (npc.gd.get_quest_marker_glyph()) and rebuilds whenever QuestSystem
# announces a change. While the player is in a conversation with this NPC it hides
# itself so it never floats in front of the dialogue framing.
#
# Everything is defensively guarded: with no QuestSystem (e.g. a unit-test scene) or a
# parent that can't answer, it simply shows nothing instead of erroring.

extends Label3D

# Glyph -> tint. Saturated-but-dark enough to read against the bright sky/world. Each
# glyph also gets a near-black outline (set in _ready) so it pops on any background.
const GLYPH_COLORS: Dictionary = {
	"!": Color(1.0, 0.85, 0.2),    # gold: a new quest to pick up
	"?": Color(0.35, 1.0, 0.5),    # green: ready to hand in
	"T": Color(1.0, 0.66, 0.2),    # amber: a repeatable task is on offer
}

# The NPC we float over (our parent). Asked for the current glyph on every refresh.
var _npc: Node = null
# True while a conversation with this NPC is open — we hide so we don't overlap it.
var _dialogue_active: bool = false
# The resting height (set by npc.gd before we enter the tree); the bob oscillates around it.
var _base_y: float = 0.0
# Phase of the gentle vertical bob, seeded random so a crowd of NPCs doesn't bob in lockstep.
var _bob_phase: float = 0.0

func _ready() -> void:
	_npc = get_parent()
	_base_y = position.y
	_bob_phase = randf() * TAU

	# Billboarded + fixed_size = always faces camera at a constant on-screen size.
	# no_depth_test draws it over the world so it's never hidden behind a wall/NPC.
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	fixed_size = true
	no_depth_test = true
	double_sided = true
	pixel_size = 0.0007
	font_size = 96
	outline_size = 28
	outline_modulate = Color(0, 0, 0, 0.85)
	render_priority = 8
	outline_render_priority = 7
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text = ""
	visible = false

	_connect_quest_signals()
	_refresh()

# Rebuild whenever the quest picture changes. The v2 signals (stage advance, task
# offered/expired, quest failed) may be absent in a stripped build, so each is guarded.
func _connect_quest_signals() -> void:
	var quests: Node = get_node_or_null("/root/QuestSystem")
	if quests == null:
		return
	for sig in ["quest_started", "quest_updated", "quest_completed",
			"quest_stage_advanced", "task_offered", "task_expired", "quest_failed"]:
		if quests.has_signal(sig):
			quests.connect(sig, _on_quest_changed)

# QuestSystem signals carry varying payloads (an id, sometimes a stage index / npc id).
# We never care which — we always re-ask the NPC — so swallow up to three optional args.
func _on_quest_changed(_a = null, _b = null, _c = null) -> void:
	_refresh()

# Called by npc.gd when a conversation opens/closes: get out of the way mid-dialogue,
# then re-evaluate the moment talking stops (the chat may have started/finished a quest).
func set_dialogue_active(active: bool) -> void:
	_dialogue_active = active
	_refresh()

# Ask the NPC for its current glyph and show/hide accordingly.
func _refresh() -> void:
	if _dialogue_active or _npc == null or not _npc.has_method("get_quest_marker_glyph"):
		visible = false
		return
	var glyph: String = _npc.get_quest_marker_glyph()
	if glyph == "":
		visible = false
		return
	text = glyph
	# Dictionary.get returns Variant; assigning straight to the Color property is fine
	# (the forbidden case is `var x := <Variant>`, which we avoid).
	modulate = GLYPH_COLORS.get(glyph, Color.WHITE)
	visible = true

func _process(delta: float) -> void:
	if not visible:
		return
	# A small idle bob so the marker reads as "alive" and draws the eye.
	_bob_phase += delta * 2.4
	position.y = _base_y + sin(_bob_phase) * 0.08
