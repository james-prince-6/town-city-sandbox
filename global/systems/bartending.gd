# bartending.gd
# Autoload singleton (registered as "Bartending").
#
# The persistent brain for the Bartending JOB at The Flaming Pebble (M-D, the v1 headline
# mini-game). Holds the player's self-contained, USE-BASED Bartending skill + their purchased
# bar upgrades, and owns the pure scoring/economy math the in-world shift reads. It is kept
# OUT of the combat Progression autoload on purpose (build plan / D1): the job has its own
# progression that rises purely by working shifts, so it never entangles with combat skills.
#
# The runtime shift (entities/minigames/bartending/bartending_shift.gd) is a throwaway in-world
# controller; THIS autoload is the bit that survives scene changes and is saved. Registered in
# SaveManager._save_targets, so the skill + upgrades persist (build plan acceptance).
#
# Design (D5): a small flat BASE WAGE per shift on top of per-drink cash + skill-scaled TIPS.
# All numbers are TUNABLE — expect a playtest balance pass.

extends Node

## Emitted when the skill levels up (carries the new level). The shift HUD listens.
signal skill_changed(level: int)
## Emitted when an upgrade is purchased. Upgrade UIs refresh off this.
signal upgrades_changed

# --- The four v1 drinks (no mixing — fixed set) -----------------------------
# Each drink is poured from its OWN bottle behind the bar (the four food-kit bottle models in
# barinside.tscn). The shift wires each bottle prop to one of these via its node name.
enum Drink { RED_WINE, WHITE_WINE, WHISKEY, GIN }
const DRINK_NAMES: Dictionary = {0: "Red Wine", 1: "White Wine", 2: "Whiskey", 3: "Gin"}
## Base cash a drink sells for (before tip). Tunable.
const DRINK_PRICES: Dictionary = {0: 8, 1: 8, 2: 10, 3: 9}

# --- The three glasses (the food-kit glass models) --------------------------
# A served drink must be in its CORRECT glass (the player grabs one of the three glass props,
# then pours). Both wines take the stemmed wine glass; whiskey a short tumbler; gin a tall glass.
enum Glass { TALL, SHORT, WINE }
const GLASS_NAMES: Dictionary = {0: "tall", 1: "short", 2: "wine"}
## The glass each drink must be served in (Drink -> Glass).
const REQUIRED_GLASS: Dictionary = {0: Glass.WINE, 1: Glass.WINE, 2: Glass.SHORT, 3: Glass.TALL}

## The glass a drink must be served in (Bartending.Glass).
func glass_for(drink: int) -> int:
	return int(REQUIRED_GLASS.get(drink, Glass.TALL))

## "Red Wine in a wine glass" — used in order text + serve prompts so the required glass reads.
func order_text(drink: int) -> String:
	return "%s in a %s glass" % [String(DRINK_NAMES.get(drink, "?")), String(GLASS_NAMES.get(glass_for(drink), "?"))]

# --- Patrons (real NPCs that show up to drink) ------------------------------
# A weighted pool of who walks into the bar. Mostly generic MINERS (the town's backbone, idled
# by the mine trouble), with a few other townsfolk for variety. Each entry is a PSX character
# model + skin + display name; the shift builds a lightweight NPCDefinition from it per spawn, so
# customers are full NPCs (Mixamo-animated bodies) without needing a hand-authored .tres each.
# EXTENSIBLE: add named characters here (or push to the list at runtime) to have specific cast
# members turn up — keep weights low so they're a rare treat among the miner crowd.
const PSX := "res://assets/models/characters/psx/"
const PATRON_POOL: Array = [
	{"model": PSX + "Male/Character_09.fbx", "skin": PSX + "Textures/Character_09.png", "name": "Miner", "weight": 5},
	{"model": PSX + "Male/Character_10.fbx", "skin": PSX + "Textures/Character_10.png", "name": "Miner", "weight": 5},
	{"model": PSX + "Male/Character_11.fbx", "skin": PSX + "Textures/Character_11.png", "name": "Miner", "weight": 5},
	{"model": PSX + "Male/Character_12.fbx", "skin": PSX + "Textures/Character_12.png", "name": "Miner", "weight": 4},
	{"model": PSX + "Male/Character_13.fbx", "skin": PSX + "Textures/Character_13.png", "name": "Off-Duty Miner", "weight": 3},
	{"model": PSX + "Male/Character_14.fbx", "skin": PSX + "Textures/Character_14.png", "name": "Townsfolk", "weight": 2},
	{"model": PSX + "Female/Character_Female_07.fbx", "skin": PSX + "Textures/Character_Female_07.png", "name": "Townsfolk", "weight": 2},
]

## Weighted-random pick of a patron archetype from the pool (a {model, skin, name} dict).
func random_patron() -> Dictionary:
	var total: int = 0
	for p in PATRON_POOL:
		total += int(p.get("weight", 1))
	if total <= 0:
		return PATRON_POOL[0]
	var roll: int = randi() % total
	for p in PATRON_POOL:
		roll -= int(p.get("weight", 1))
		if roll < 0:
			return p
	return PATRON_POOL[0]

# A few in-character order barks, picked at random when the player greets a customer. Keyed by
# drink (Bartending.Drink) so the line matches what they ask for.
const ORDER_LINES: Dictionary = {
	0: ["Glass of the red, please.", "Red wine for me tonight.", "Somethin' nice — red wine."],
	1: ["A white wine, thanks.", "Glass of the white.", "White wine, nice and crisp."],
	2: ["Whiskey, neat.", "A whiskey to forget the mine.", "Whiskey — the good stuff."],
	3: ["Pour me a gin.", "Gin for me.", "Gin, and make it cold."],
}

## A random order line for a drink (Bartending.Drink). Varies by index to avoid Math.random.
func order_line(drink: int, salt: int) -> String:
	var lines: Array = ORDER_LINES.get(drink, ["..."])
	return String(lines[salt % lines.size()])

## How long (seconds) a customer will wait at the counter before leaving — generous, and biased
## EASY for new bartenders (the challenge ramps via customer COUNT/pace, not a shrinking timer).
## Tunable. Covers both being greeted and waiting for the drink.
func patience_seconds() -> float:
	return 32.0 + 0.6 * float(level - 1)

## Seconds a satisfied customer hangs around drinking before leaving.
func drink_seconds() -> float:
	return 7.0

# --- Skill (use-based, self-contained) -------------------------------------
const LEVEL_CAP: int = 20
const USE_XP_BASE: float = 6.0
const USE_XP_PER_LEVEL: float = 4.0
## Use-XP earned per drink served (scaled by how good the serve was, in the shift).
const XP_PER_SERVE: float = 2.0

## Small flat wage Barry pays per completed shift, on top of cash + tips (D5).
const BASE_WAGE: int = 15

# --- Skill state (persisted) ------------------------------------------------
var level: int = 1
var xp: float = 0.0

# --- Upgrades (money sinks, persisted): id -> bought(bool) ------------------
var _upgrades: Dictionary = {}

## Upgrade catalog. id -> { name, cost, desc }. Effects are read in the getters below.
const UPGRADES: Dictionary = {
	"better_tap": {"name": "Free-Flow Spouts", "cost": 120, "desc": "Drinks pour faster, with a wider clean-pour window."},
	"bigger_rack": {"name": "Pre-Stocked Rack", "cost": 150, "desc": "Glasses are ready to grab — start each pour a little filled."},
	"bus_tub": {"name": "Bus Tub", "cost": 180, "desc": "A bar-back clears the oldest mess for you now and then."},
	"crowd_cap": {"name": "Crowd Capacity", "cost": 220, "desc": "One more customer can wait at the bar at once."},
}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# --- Use-based skill --------------------------------------------------------

## Use-XP needed to go from `lvl` to `lvl + 1` (rising = anti-grind, like the combat skills).
func skill_xp_to_next(lvl: int) -> float:
	return USE_XP_BASE + float(maxi(lvl, 1)) * USE_XP_PER_LEVEL

## Train the Bartending skill (called on a served drink, scaled by serve quality).
func register_pour(amount: float = XP_PER_SERVE) -> void:
	if level >= LEVEL_CAP or amount <= 0.0:
		return
	xp += amount
	var leveled := false
	while level < LEVEL_CAP and xp >= skill_xp_to_next(level):
		xp -= skill_xp_to_next(level)
		level += 1
		leveled = true
	if leveled:
		skill_changed.emit(level)

# --- Derived tunables (scale with skill + upgrades) ------------------------

## Accuracy tolerance around the fill line (wider = more forgiving). Grows with skill; the
## Better Tap upgrade widens it further. 1.0 is the fill line; a pour within this is "clean".
func fill_window() -> float:
	var w: float = 0.10 + 0.005 * float(level - 1)
	if has_upgrade("better_tap"):
		w += 0.03
	return w

## Tip multiplier — tips scale up with skill so a veteran bartender earns more per drink.
func tip_multiplier() -> float:
	return 1.0 + 0.06 * float(level - 1)

## How many customers can wait at the bar at once (the juggling ceiling). v1 tops out at 4.
func max_concurrent() -> int:
	var n: int = 1 + int(level / 6)
	if has_upgrade("crowd_cap"):
		n += 1
	return clampi(n, 1, 4)

## Fill units added per second while pouring (faster = quicker service). Better Tap speeds it.
func pour_speed() -> float:
	var s: float = 0.55 + 0.02 * float(level - 1)
	if has_upgrade("better_tap"):
		s += 0.15
	return s

## Fill a freshly-grabbed glass starts at (the Pre-Stocked Rack gives a small head start).
func starting_fill() -> float:
	return 0.15 if has_upgrade("bigger_rack") else 0.0

func base_wage() -> int:
	return BASE_WAGE

# --- Pure scoring / economy (unit-tested) ----------------------------------

## Score a pour by how close `fill` is to the line (1.0), within the current skill window.
## Returns 0..1. An overfill beyond the window spills (ruined → 0); underfill scales down.
func score_pour(fill: float) -> float:
	var window: float = fill_window()
	if fill > 1.0 + window:
		return 0.0  # overfilled and spilled — a mess, no good
	var err: float = absf(fill - 1.0)
	return clampf(1.0 - err / maxf(0.01, window), 0.0, 1.0)

## Cash + tip for one served drink. `pour_score` (0..1) and `patience_left` (0..1) drive the
## tip; the base price is always paid for a correct drink. Tip = price * skill mult * pour *
## (speed/patience factor). Rounds to whole coins.
func payout_for(drink: int, pour_score: float, patience_left: float) -> int:
	var price: int = int(DRINK_PRICES.get(drink, 5))
	var tip: int = int(round(float(price) * tip_multiplier() * clampf(pour_score, 0.0, 1.0) * (0.4 + 0.6 * clampf(patience_left, 0.0, 1.0))))
	return price + tip

## Use-XP a served drink trains, scaled by how good the serve was (better serves teach more).
func serve_xp(pour_score: float) -> float:
	return XP_PER_SERVE * (0.5 + 0.5 * clampf(pour_score, 0.0, 1.0))

# --- Upgrades ---------------------------------------------------------------

func has_upgrade(id: StringName) -> bool:
	return bool(_upgrades.get(id, false))

func upgrade_cost(id: StringName) -> int:
	return int(UPGRADES.get(id, {}).get("cost", 0))

## True if the upgrade exists, isn't owned, and the player can afford it.
func can_buy(id: StringName) -> bool:
	return UPGRADES.has(id) and not has_upgrade(id) and GameState.money >= upgrade_cost(id)

## Buy an upgrade (spends money). Returns true on success.
func buy_upgrade(id: StringName) -> bool:
	if not can_buy(id):
		return false
	if not GameState.spend_money(upgrade_cost(id)):
		return false
	_upgrades[id] = true
	upgrades_changed.emit()
	return true

# --- Save / load -----------------------------------------------------------

func capture_state() -> Dictionary:
	return {"level": level, "xp": xp, "upgrades": _upgrades.duplicate()}

func restore_state(data: Dictionary) -> void:
	level = clampi(int(data.get("level", 1)), 1, LEVEL_CAP)
	xp = float(data.get("xp", 0.0))
	var saved: Dictionary = data.get("upgrades", {})
	_upgrades = saved.duplicate() if saved is Dictionary else {}
	skill_changed.emit(level)
	upgrades_changed.emit()
