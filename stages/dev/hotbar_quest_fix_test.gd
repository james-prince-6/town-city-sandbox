# hotbar_quest_fix_test.gd
# Headless checks for two playtest fixes. Asserts in _ready(), writes PASS/FAIL to
# user://_test_result.txt, quits 0/1. Run:
#   Godot --headless --path <project> res://stages/dev/hotbar_quest_fix_test.tscn --quit-after 120
#
# 1. QUEST DIAGNOSIS: simulate the New Game quest start and confirm the mayor's quest
#    (getting_started) is ACTIVE, NOT completed, and surfaces under tier MAIN (what the
#    quest log / tracker read). If this passes, the log display is fine and any "doesn't
#    show" is a flow gap (Orbo gives no follow-up), not a quest-system bug.
# 2. HOTBAR SYNC: a newly-gained item auto-lands on the hotbar; gaining more doesn't
#    duplicate it; and when it runs out (count 0) it disappears from the hotbar — while the
#    four seeded tools stay put.
extends Node

var _lines: Array[String] = []
var _ok := true

func _ready() -> void:
	await get_tree().process_frame

	# --- 1. Quest diagnosis ---------------------------------------------------
	GameState.set_flag(&"met_orbo", false)
	GameState.set_flag(&"starting_tools_granted", false)
	QuestSystem.start_quest(&"getting_started")
	if QuestSystem.is_active(&"getting_started"):
		_pass("getting_started is ACTIVE after start_quest")
	else:
		_fail("getting_started is NOT active after start_quest")
	if QuestSystem.is_completed(&"getting_started"):
		_fail("getting_started COMPLETED immediately (should be open until you meet Orbo)")
	else:
		_pass("getting_started not completed (open as expected)")
	var main_ids: Array = []
	for q in QuestSystem.get_active_by_tier(0):  # 0 = MAIN
		if q != null:
			main_ids.append(String(q.id))
	if main_ids.has("getting_started"):
		_pass("getting_started shows under MAIN tier (what the log/tracker read)")
	else:
		_fail("getting_started NOT in MAIN-tier active list: %s" % str(main_ids))

	# --- 1b. The follow-up quest chain (the actual fix for the empty log) ------
	for f in [&"met_barry", &"met_droghnaut", &"met_sally"]:
		GameState.set_flag(f, false)
	# Simulate meeting Orbo: completes getting_started + hands out help_the_town (orbo.dialogue).
	GameState.set_flag(&"met_orbo", true)
	QuestSystem.mark_flag(&"met_orbo")
	QuestSystem.start_quest(&"help_the_town")
	if QuestSystem.is_completed(&"getting_started"):
		_pass("meeting Orbo completes getting_started")
	else:
		_fail("getting_started did not complete on meeting Orbo")
	if QuestSystem.is_active(&"help_the_town"):
		_pass("help_the_town is ACTIVE after meeting Orbo (log no longer empty)")
	else:
		_fail("help_the_town NOT active after meeting Orbo")
	# Meet the three venue owners -> their dialogues mark the flags -> quest completes.
	QuestSystem.mark_flag(&"met_barry")
	QuestSystem.mark_flag(&"met_droghnaut")
	QuestSystem.mark_flag(&"met_sally")
	if QuestSystem.is_completed(&"help_the_town"):
		_pass("help_the_town completes after meeting Barry/Droghnaut/Sally")
	else:
		_fail("help_the_town did NOT complete after meeting all three")

	# --- 2. Hotbar sync -------------------------------------------------------
	# Sanity: the four starter tools are seeded on slots 0-3.
	var seeds: Array[StringName] = [&"pickaxe", &"hatchet", &"iron_sword", &"bow"]
	var seeds_ok := true
	for i in seeds.size():
		if Hotbar.slots[i] != seeds[i]:
			seeds_ok = false
	if seeds_ok:
		_pass("seeded tools intact on hotbar slots 0-3")
	else:
		_fail("seeded tools wrong: %s" % str(Hotbar.slots))

	var item := &"health_potion"
	# Start clean: remove any the player happens to hold so the first add is a true gain.
	if Inventory.count_of(item) > 0:
		Inventory.remove(item, Inventory.count_of(item))

	# Gain one -> it should auto-appear on the hotbar.
	Inventory.add(item, 1)
	if Hotbar.slots.has(item):
		_pass("newly-gained '%s' auto-added to the hotbar" % item)
	else:
		_fail("newly-gained '%s' did NOT appear on the hotbar" % item)

	# Gain another -> must not duplicate onto a second slot.
	Inventory.add(item, 1)
	if _count_slots(item) == 1:
		_pass("gaining more of '%s' does not duplicate the slot" % item)
	else:
		_fail("'%s' occupies %d hotbar slots (expected 1)" % [item, _count_slots(item)])

	# Run it out -> it should disappear from the hotbar (like the bag).
	Inventory.remove(item, Inventory.count_of(item))
	if not Hotbar.slots.has(item):
		_pass("depleted '%s' (count 0) disappeared from the hotbar" % item)
	else:
		_fail("depleted '%s' still on the hotbar" % item)

	_write()
	get_tree().quit(0 if _ok else 1)

func _count_slots(id: StringName) -> int:
	var n := 0
	for s in Hotbar.slots:
		if s == id:
			n += 1
	return n

func _pass(m: String) -> void:
	_lines.append("PASS " + m)

func _fail(m: String) -> void:
	_ok = false
	_lines.append("FAIL " + m)

func _write() -> void:
	var f := FileAccess.open("user://_test_result.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(("HOTBAR+QUEST FIX TEST: " + ("ALL PASS" if _ok else "FAILURES")) + "\n" + "\n".join(_lines))
		f.close()
