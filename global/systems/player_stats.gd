# player_stats.gd
# Autoload singleton (registered in Project Settings -> Autoload as "PlayerStats").
#
# Tracks the player's two survival numbers: health and stamina. Like the other
# systems in global/systems/, this lives OUTSIDE the swappable scene so the
# player's condition survives walking from one area into another.
#
# Two different feels on purpose:
# - Stamina is "spent" by actions (sprinting, swinging a tool) and slowly
#   regenerates on its own once you stop using it for a moment.
# - Health does NOT regen automatically — you have to heal it deliberately
#   (food, potions, sleeping, etc., added later). When it hits 0 the player dies.
#
# Access from anywhere: PlayerStats.health, PlayerStats.take_damage(10), etc.

extends Node

# --- Tuning knobs ----------------------------------------------------------

## How fast stamina refills, in stamina-points per second, once regen kicks in.
const STAMINA_REGEN_PER_SEC: float = 15.0

## After spending stamina with use_stamina(), wait this long (seconds) before
## regen resumes. Stops you from instantly refilling between rapid actions.
const STAMINA_REGEN_DELAY: float = 1.0

## How fast mana refills, in mana-points per second, once its regen kicks in.
## Slower than stamina on purpose so spell-casting feels like a resource you manage.
const MANA_REGEN_PER_SEC: float = 9.0

## After spending mana with use_mana(), wait this long (seconds) before regen resumes.
const MANA_REGEN_DELAY: float = 1.5

## Second Wind perk (survival tree): when an otherwise-lethal hit lands and the perk is
## owned and off cooldown, the player survives at this fraction of max health instead of
## dying, then the save goes on cooldown for SECOND_WIND_COOLDOWN seconds.
const SECOND_WIND_HEAL_FRACTION: float = 0.35
const SECOND_WIND_COOLDOWN: float = 60.0

# --- Signals ---------------------------------------------------------------

## Emitted whenever health changes. UI (a health bar) connects to this instead
## of polling every frame. Sends the new current value and the max for ratios.
signal health_changed(current: float, max: float)

## Emitted whenever stamina changes. Same idea as health_changed.
signal stamina_changed(current: float, max: float)

## Emitted whenever mana changes. Same idea as stamina_changed; the HUD's mana bar
## listens to this. Spells (wands) spend mana via use_mana().
signal mana_changed(current: float, max: float)

## Emitted exactly once, the moment health first reaches 0. Death handling
## (respawn screen, game over) hangs off this.
signal died

# --- Core state ------------------------------------------------------------

var max_health: float = 100.0
var health: float = max_health

var max_stamina: float = 100.0
var stamina: float = max_stamina

var max_mana: float = 100.0
var mana: float = max_mana

## Counts down after spending stamina; while > 0, stamina regen is paused.
var _regen_cooldown: float = 0.0

## Counts down after spending mana; while > 0, mana regen is paused.
var _mana_regen_cooldown: float = 0.0

## Guards the died signal so it only ever fires once per death.
var _has_died: bool = false

## Counts down after a Second Wind save; while > 0 the perk can't save the player again.
var _second_wind_cooldown: float = 0.0

func _ready() -> void:
	# This singleton should keep ticking even when the game is "paused" by a
	# blocking UI, so stamina regen and timers behave predictably.
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Start the player at full bars and announce it so any UI already listening
	# draws the correct values immediately.
	health = max_health
	stamina = max_stamina
	mana = max_mana
	health_changed.emit(health, max_health)
	stamina_changed.emit(stamina, max_stamina)
	mana_changed.emit(mana, max_mana)

func _process(delta: float) -> void:
	# Bleed off the Second Wind cooldown independently of stamina regen so the clutch save
	# rearms even while the player is spending stamina.
	if _second_wind_cooldown > 0.0:
		_second_wind_cooldown -= delta
	# Mana regen runs on its OWN post-use delay, independent of stamina, so casting a spell
	# doesn't stall stamina regen (and vice-versa).
	if _mana_regen_cooldown > 0.0:
		_mana_regen_cooldown -= delta
	elif mana < max_mana:
		add_mana(MANA_REGEN_PER_SEC * delta)
	# Tick down the post-use cooldown first; stamina regen only resumes once it's spent.
	if _regen_cooldown > 0.0:
		_regen_cooldown -= delta
		return
	# Refill stamina toward the max while the player isn't spending it.
	if stamina < max_stamina:
		add_stamina(STAMINA_REGEN_PER_SEC * delta)

# --- Health ----------------------------------------------------------------

## Apply `amount` of damage. Clamps health to [0, max] and emits health_changed.
## Triggers the died signal once if this drops health to 0.
func take_damage(amount: float) -> void:
	if amount <= 0.0:
		return
	# Second Wind: if this hit would be lethal and the perk is owned & ready, survive at a
	# chunk of max health and put the save on a long cooldown instead of dying.
	if health - amount <= 0.0 and not _has_died and _can_second_wind():
		_second_wind_cooldown = SECOND_WIND_COOLDOWN
		health = max_health * SECOND_WIND_HEAL_FRACTION
		health_changed.emit(health, max_health)
		return
	health = clampf(health - amount, 0.0, max_health)
	health_changed.emit(health, max_health)
	if health <= 0.0 and not _has_died:
		_has_died = true
		died.emit()

## True when the Second Wind perk can save the player right now (off cooldown and owned).
## Progression is an autoload, present once registered; guarded for load-order safety.
func _can_second_wind() -> bool:
	if _second_wind_cooldown > 0.0:
		return false
	return Progression != null and Progression.has_perk(&"second_wind")

## Restore `amount` of health, never above max. No effect when already dead —
## use reset() to bring the player back to life.
func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	if is_dead():
		push_warning("PlayerStats.heal: player is dead; call reset() to revive.")
		return
	health = clampf(health + amount, 0.0, max_health)
	health_changed.emit(health, max_health)

func is_dead() -> bool:
	return health <= 0.0

# --- Stamina ---------------------------------------------------------------

## Tries to spend `amount` of stamina (sprinting, a tool swing...). Returns true
## and deducts it if there's enough; returns false and changes NOTHING if not.
## Always check the return value before letting the action happen.
func use_stamina(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if stamina < amount:
		return false
	stamina = clampf(stamina - amount, 0.0, max_stamina)
	# Pause regen briefly so spending stamina actually feels costly.
	_regen_cooldown = STAMINA_REGEN_DELAY
	stamina_changed.emit(stamina, max_stamina)
	return true

## Add stamina back (regen tick, a stamina potion...). Clamped to [0, max].
func add_stamina(amount: float) -> void:
	if amount <= 0.0:
		return
	stamina = clampf(stamina + amount, 0.0, max_stamina)
	stamina_changed.emit(stamina, max_stamina)

# --- Mana ------------------------------------------------------------------

## Tries to spend `amount` of mana (casting a spell). Returns true and deducts it if
## there's enough; returns false and changes NOTHING if not. Mirrors use_stamina().
## Always check the return value before letting the cast happen.
func use_mana(amount: float) -> bool:
	if amount <= 0.0:
		return true
	if mana < amount:
		return false
	mana = clampf(mana - amount, 0.0, max_mana)
	# Pause mana regen briefly so casting actually feels costly.
	_mana_regen_cooldown = MANA_REGEN_DELAY
	mana_changed.emit(mana, max_mana)
	return true

## Add mana back (regen tick, a mana potion...). Clamped to [0, max].
func add_mana(amount: float) -> void:
	if amount <= 0.0:
		return
	mana = clampf(mana + amount, 0.0, max_mana)
	mana_changed.emit(mana, max_mana)

# --- Lifecycle -------------------------------------------------------------

## Restore the player to full health and stamina (e.g. after respawning).
func reset() -> void:
	_has_died = false
	_regen_cooldown = 0.0
	_mana_regen_cooldown = 0.0
	_second_wind_cooldown = 0.0
	health = max_health
	stamina = max_stamina
	mana = max_mana
	health_changed.emit(health, max_health)
	stamina_changed.emit(stamina, max_stamina)
	mana_changed.emit(mana, max_mana)

# --- Save / load -----------------------------------------------------------
# A single dictionary snapshot, mirroring the other systems so a future save
# system can gather one of these from each autoload.

func capture_state() -> Dictionary:
	return {
		"health": health,
		"max_health": max_health,
		"stamina": stamina,
		"max_stamina": max_stamina,
		"mana": mana,
		"max_mana": max_mana,
	}

func restore_state(data: Dictionary) -> void:
	max_health = data.get("max_health", 100.0)
	max_stamina = data.get("max_stamina", 100.0)
	max_mana = data.get("max_mana", 100.0)
	health = clampf(data.get("health", max_health), 0.0, max_health)
	stamina = clampf(data.get("stamina", max_stamina), 0.0, max_stamina)
	mana = clampf(data.get("mana", max_mana), 0.0, max_mana)
	# A restored save with health > 0 is alive again; keep the death guard honest.
	_has_died = health <= 0.0
	_regen_cooldown = 0.0
	_mana_regen_cooldown = 0.0
	_second_wind_cooldown = 0.0
	health_changed.emit(health, max_health)
	stamina_changed.emit(stamina, max_stamina)
	mana_changed.emit(mana, max_mana)
