# enemy_stats.gd
# The DATA sheet for one kind of monster. This is the resource a designer edits in
# the Inspector to tune a creature's strength, weaknesses, attack, and loot — the
# enemy.gd "body + brain" reads these numbers on _ready and behaves accordingly.
#
# It's deliberately just numbers + ids (a Resource), so the same enemy.gd /
# enemy.tscn can become a fast little lunger or a slow brute purely by swapping
# which EnemyStats .tres is assigned. Make a new monster type by duplicating one of
# the .tres files in entities/enemies/ and editing the values.
#
# Damage flows through the shared combat backbone (see docs/combat.md): the numbers
# here become a HitBox the enemy spawns at the player, and the weaknesses below feed
# the enemy's own Health.damage_multipliers so player weapons scale correctly.

class_name EnemyStats
extends Resource

## How the monster attacks. MELEE briefly spawns a HitBox in front of the body;
## RANGED spits a projectile scene that carries a one_shot HitBox toward the player.
enum AttackStyle { MELEE, RANGED }

## Shape of the telegraphed SPECIAL/heavy attack (only used when has_special is true).
## SLAM: after the wind-up, spawn one big AoE HitBox centered on the body (a ground
##   pound) with special_radius / special_knockback — good for a melee Brute.
## VOLLEY: after the wind-up, fire special_projectile_count projectiles in a spread
##   toward the player — good for a ranged caster's burst.
## RING: bullet-hell barrage — fire special_ring_count projectiles evenly around the
##   full 360° circle, ignoring the player's position. The arena fills with an expanding
##   ring the player has to weave out of — good for a stationary caster.
## RING and SPIRAL are appended at the END so existing saved SpecialStyle ints (0 = SLAM,
## 1 = VOLLEY) keep their meaning; do NOT reorder.
## SPIRAL: like RING (special_ring_count projectiles around 360°) but the WHOLE ring is
##   rotated by a per-cast offset that advances every cast, so successive barrages spin —
##   the classic rotating bullet-hell spiral. Reuses the same ring math as RING.
## A standalone enum (order is runtime-only / not serialized into the .tres), so it's
## safe to read by name.
enum SpecialStyle { SLAM, VOLLEY, RING, SPIRAL }

@export_group("Identity")
## Shown in debug / death messages and handy for the designer to tell types apart.
@export var display_name: String = "Monster"

@export_group("Vitals")
## Starting (and max) hit points. Seeded into the enemy's Health child on _ready.
@export var max_health: float = 40.0

## Per-element multipliers applied to incoming damage, keyed by
## DamageInfo.DamageType (int) -> float. >1 = WEAKNESS, <1 = RESISTANCE, 0 = immune,
## missing = 1.0. Copied straight into the enemy's Health.damage_multipliers so the
## player's typed weapons (fire sword, ice arrow...) hit for the right amount.
## Example (weak to fire, resists physical):
##   { DamageInfo.DamageType.FIRE: 2.0, DamageInfo.DamageType.PHYSICAL: 0.5 }
@export var damage_multipliers: Dictionary = {}

@export_group("Movement")
## Chase speed (m/s) while pursuing the player in a straight line.
@export var move_speed: float = 3.5

@export_group("Attack")
## Which moveset this monster uses (see AttackStyle).
@export var attack_style: AttackStyle = AttackStyle.MELEE

## Raw damage each landed hit deals (before the player's own resistances).
@export var damage: float = 8.0

## Element of this monster's attack (feeds the spawned HitBox.damage_type).
@export var damage_type: DamageInfo.DamageType = DamageInfo.DamageType.PHYSICAL

## How close (m) the player must be before the monster can attack. For MELEE this is
## roughly arm's reach; for RANGED it's the firing distance the spitter holds at.
@export var attack_range: float = 2.0

## How far (m) the monster can "see" the player and start chasing from Idle.
@export var detect_range: float = 14.0

## Minimum seconds between attacks (the attack's recovery / wind-up gate).
@export var attack_cooldown: float = 1.5

## Visible NORMAL-attack telegraph (seconds). During this beat the body pulses an amber
## warning (see enemy.gd._pulse_attack_tell) and CombatFeel.play_attack_tell() fires before
## the blow lands. 0 = no telegraph (instant swing), matching the pre-field behavior.
@export var attack_windup: float = 0.0

## Knockback force the NORMAL attack imparts to the player (stamped onto the spawned
## HitBox.knockback). Small for a light jab; a slam uses special_knockback instead.
@export var attack_knockback: float = 2.0

## RANGED only: how many projectiles a single NORMAL attack fires, fanned across
## shot_spread_degrees toward the player. Default 1 = exactly the old single-shot behavior
## (the projectile flies straight at the player). Set to e.g. 3 for a light shotgun burst.
@export var projectiles_per_shot: int = 1

## RANGED only: total spread angle (degrees) the NORMAL attack's projectiles_per_shot fan
## across. Ignored when projectiles_per_shot <= 1. Default 0 keeps a single shot dead
## straight (so the old behavior is byte-for-behavior unchanged at the defaults).
@export var shot_spread_degrees: float = 0.0

@export_group("Reactions")
## How hard this monster is to shove, 0..1. 0 = flung the full incoming force,
## 1 = immovable. The incoming knockback is scaled by (1 - knockback_resistance):
## a light Husk gets launched, a heavy Brute barely budges.
@export_range(0.0, 1.0) var knockback_resistance: float = 0.3

## Seconds the monster is briefly interrupted (stops advancing/attacking) when a hit
## staggers it. Kept short so it never soft-locks the brain.
@export var stagger_duration: float = 0.2

## "Poise": the minimum post-resistance damage a single hit must deal to STAGGER this
## monster. Light enemies set 0 (every hit flinches them); heavy/armored enemies set a
## high value so only big blows interrupt them. A critical hit ALWAYS staggers,
## regardless of this threshold.
@export var poise_threshold: float = 0.0

@export_group("Special Attack")
## Enables the telegraphed heavy/special attack. When false the monster only ever uses
## its normal attack and every field below is ignored.
@export var has_special: bool = false

## Which kind of special this monster performs after its wind-up (see SpecialStyle).
@export var special_style: SpecialStyle = SpecialStyle.SLAM

## Visible wind-up time (seconds) before the special fires. During this tell the
## monster plants and pulses an emissive warning so the player can dodge/back off.
@export var special_windup: float = 0.7

## Minimum seconds between specials (its own cooldown, separate from attack_cooldown).
@export var special_cooldown: float = 6.0

## How close (m) the player must be for the monster to CHOOSE to start a special.
@export var special_range: float = 4.0

## Chance (0..1), rolled once per attack-rhythm tick while in special_range and off
## cooldown, that the monster commits to a special instead of a normal attack.
@export_range(0.0, 1.0) var special_chance: float = 0.35

## Raw damage the special deals (before the player's resistances).
@export var special_damage: float = 18.0

## Element of the special attack (feeds the spawned HitBox.damage_type).
@export var special_damage_type: DamageInfo.DamageType = DamageInfo.DamageType.PHYSICAL

## SLAM only: radius (m) of the AoE ground-pound HitBox centered on the body.
@export var special_radius: float = 3.0

## Knockback force the special imparts (big — a slam should send the player flying).
@export var special_knockback: float = 9.0

## VOLLEY only: how many projectiles the burst fires in a spread.
@export var special_projectile_count: int = 3

## VOLLEY only: total spread angle (degrees) the projectiles fan across.
@export var special_spread_degrees: float = 28.0

## RING / SPIRAL only: how many projectiles the barrage fires evenly around the full 360°
## circle. A higher count = a denser ring with smaller gaps to thread. 12 is a readable
## default; a Cinder Caster might run ~14.
@export var special_ring_count: int = 12

@export_group("Loot")
## Item id dropped on death (must exist in the Inventory database). Empty = no drop.
@export var loot_item_id: StringName = &""

## How many of loot_item_id to drop.
@export var loot_amount: int = 1

@export_group("Progression")
## Reward / difficulty hints for whatever system later grants XP. Not consumed by the
## combat backbone yet, but stored here so monster sheets are the single source of
## truth for "how strong / how rewarding" a creature is.
@export var xp: int = 10

## Coarse difficulty rating for spawn tables / scaling. Purely informational for now.
@export var strength: int = 1
