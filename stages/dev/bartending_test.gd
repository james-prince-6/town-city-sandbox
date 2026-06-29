# bartending_test.gd
# Headless verification for M-D bartending. Covers (A) the Bartending autoload logic — skill
# use-leveling, pour scoring, skill-scaled payout, upgrades + effects, save/load, patron pool,
# the drink/glass tables — and (B) integration: the shift instances + runs _ready without
# crashing, grabbing gives an EMPTY glass of a type, a correct drink-in-the-right-glass serve pays
# out / trains / clears, a wrong drink AND a wrong glass are both rejected, the talk-to-order flow
# advances a customer's phase, and the trash discards a held glass.
extends Node

const SHIFT := "res://entities/minigames/bartending/bartending_shift.gd"
const CUSTOMER_SCENE := "res://entities/minigames/bartending/bar_customer.tscn"
const STATION := "res://entities/minigames/bartending/bar_station.gd"

# BarCustomer.Phase ints (APPROACHING=0, AWAITING_ORDER=1, AWAITING_DRINK=2, DRINKING=3, LEAVING=4)
const PHASE_AWAITING_ORDER := 1
const PHASE_AWAITING_DRINK := 2

var _lines: Array = []
var _ok := true

func _ready() -> void:
	await get_tree().process_frame
	var B := get_node_or_null("/root/Bartending")
	if B == null:
		_fail("Bartending autoload missing (parse error?)"); _write(); get_tree().quit(1); return

	# --- A. Logic ---------------------------------------------------------
	B.level = 1
	B.xp = 0.0
	B._upgrades = {}
	for i in range(60):
		B.register_pour(3.0)
	_check(B.level > 1, "skill levels by use (reached Lv %d)" % B.level)
	_check(is_equal_approx(B.score_pour(1.0), 1.0), "score_pour(1.0) == 1.0 (perfect pour)")
	_check(B.score_pour(1.0 + B.fill_window() + 0.05) == 0.0, "overfill beyond the window spills (0)")
	var mid: float = B.score_pour(1.0 - B.fill_window() * 0.5)
	_check(mid > 0.0 and mid < 1.0, "partial pour scores between 0 and 1 (%.2f)" % mid)
	_check(B.payout_for(0, 1.0, 1.0) > int(B.DRINK_PRICES[0]), "a good serve pays price + tip")
	_check(B.patience_seconds() >= 30.0, "patience is generous (%.0fs at Lv %d)" % [B.patience_seconds(), B.level])
	_check(B.DRINK_NAMES.size() == 4 and B.glass_for(B.Drink.WHISKEY) == B.Glass.SHORT, "drink/glass tables: 4 drinks, whiskey -> short glass")
	_check(B.glass_for(B.Drink.RED_WINE) == B.Glass.WINE and B.glass_for(B.Drink.GIN) == B.Glass.TALL, "red wine -> wine glass, gin -> tall glass")
	var patron: Dictionary = B.random_patron()
	_check(patron.has("model") and patron.has("name"), "patron pool returns a {model,name} archetype (%s)" % str(patron.get("name")))

	GameState.money = 1000
	var before_window: float = B.fill_window()
	_check(B.buy_upgrade(&"better_tap") and B.has_upgrade(&"better_tap"), "bought 'better_tap' upgrade")
	_check(B.fill_window() > before_window, "better_tap widened the fill window")
	_check(not B.can_buy(&"better_tap"), "cannot re-buy an owned upgrade")

	B.level = 7
	B.xp = 4.0
	var snap: Dictionary = B.capture_state()
	B.level = 1
	B.xp = 0.0
	B._upgrades = {}
	B.restore_state(snap)
	_check(B.level == 7 and B.has_upgrade(&"better_tap"), "save/load round-trips skill + upgrades")

	# --- B. Shift + customers --------------------------------------------
	var player := Node3D.new()
	player.add_to_group("player")
	add_child(player)
	var shift: Node = load(SHIFT).new()
	add_child(shift)
	await get_tree().process_frame
	await get_tree().process_frame
	_check(is_instance_valid(shift), "shift instanced + ran _ready without crashing")

	# Grab a glass via a grab station -> an EMPTY glass of that type (drink set later by pouring).
	var grab = load(STATION).new()
	grab.kind = &"grab"
	grab.glass = B.Glass.WINE
	shift.station_interact(grab, player)
	_check(bool(shift._held.get("has", false)) and int(shift._held["drink"]) == -1 and int(shift._held["glass"]) == B.Glass.WINE, "grabbing gives an empty glass of that type")
	grab.queue_free()

	# Correct serve: right drink (red wine) in the right glass (wine).
	shift._held = {"has": true, "glass": B.Glass.WINE, "drink": B.Drink.RED_WINE, "fill": 1.0}
	var cust: Node = (load(CUSTOMER_SCENE) as PackedScene).instantiate()
	cust.setup_customer(shift, null, B.Drink.RED_WINE, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 30.0, 0)
	add_child(cust)
	await get_tree().process_frame
	cust.patience = 1.0
	var money_before: int = GameState.money
	var xp_before: float = B.xp
	var lvl_before: int = B.level
	shift.try_serve_customer(cust)
	_check(GameState.money > money_before, "correct serve paid out (+$%d)" % (GameState.money - money_before))
	_check(B.xp > xp_before or B.level > lvl_before, "serving trained the Bartending skill")
	_check(not bool(shift._held.get("has", false)), "held glass cleared after serving")

	# Talk-to-order: a customer in AWAITING_ORDER advances to AWAITING_DRINK on interact.
	var cust3: Node = (load(CUSTOMER_SCENE) as PackedScene).instantiate()
	cust3.setup_customer(shift, null, 2, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 30.0, 2)
	add_child(cust3)
	await get_tree().process_frame
	cust3._phase = PHASE_AWAITING_ORDER
	cust3.interact(player)
	_check(cust3._phase == PHASE_AWAITING_DRINK, "talking to a customer takes their order (phase advances)")
	cust3.queue_free()

	# Wrong-drink serve rejected (white wine held, red wine ordered).
	shift._held = {"has": true, "glass": B.Glass.WINE, "drink": B.Drink.WHITE_WINE, "fill": 1.0}
	var cust2: Node = (load(CUSTOMER_SCENE) as PackedScene).instantiate()
	cust2.setup_customer(shift, null, B.Drink.RED_WINE, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 30.0, 1)
	add_child(cust2)
	await get_tree().process_frame
	cust2.patience = 1.0
	var m2: int = GameState.money
	shift.try_serve_customer(cust2)
	_check(GameState.money == m2 and bool(shift._held.get("has", false)), "wrong-drink serve rejected (no pay, glass kept)")

	# Wrong-GLASS serve rejected (whiskey poured, but in a wine glass instead of a short tumbler).
	shift._held = {"has": true, "glass": B.Glass.WINE, "drink": B.Drink.WHISKEY, "fill": 1.0}
	var cust4: Node = (load(CUSTOMER_SCENE) as PackedScene).instantiate()
	cust4.setup_customer(shift, null, B.Drink.WHISKEY, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, 30.0, 3)
	add_child(cust4)
	await get_tree().process_frame
	cust4.patience = 1.0
	var m4: int = GameState.money
	shift.try_serve_customer(cust4)
	_check(GameState.money == m4 and bool(shift._held.get("has", false)), "wrong-glass serve rejected (no pay, glass kept)")
	cust4.queue_free()

	# The trash discards the held glass.
	var sink = load(STATION).new()
	sink.kind = &"trash"
	shift.station_interact(sink, player)
	_check(not bool(shift._held.get("has", false)), "the trash discards a held glass")
	sink.queue_free()

	shift.queue_free()
	_write()
	get_tree().quit(0 if _ok else 1)

func _check(cond: bool, msg: String) -> void:
	if cond:
		_lines.append("PASS " + msg)
	else:
		_ok = false
		_lines.append("FAIL " + msg)

func _fail(msg: String) -> void:
	_ok = false
	_lines.append("FAIL " + msg)

func _write() -> void:
	var f := FileAccess.open("user://_test_result.txt", FileAccess.WRITE)
	if f != null:
		f.store_string(("BARTENDING TEST: " + ("ALL PASS" if _ok else "FAILURES")) + "\n" + "\n".join(_lines))
		f.close()
