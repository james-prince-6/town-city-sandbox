# Combat System — Contract & Foundation

This is the shared spec for the combat system. The **foundation below already exists and
is verified** — build weapons, consumables, and enemies on top of it. Do not change the
foundation files; treat them as the API.

## The damage backbone (components/)

Every attack in the game — sword swing, arrow, bomb blast, enemy claw — works the same
way: a **HitBox** (Area3D) overlaps a **HurtBox** (Area3D) and deals a **DamageInfo**,
which a **Health** component applies after scaling by the target's weakness/resistance.

### `DamageInfo` (components/damage_info.gd, `class_name DamageInfo extends RefCounted`)
- `enum DamageType { PHYSICAL, FIRE, ICE, POISON, EXPLOSIVE }`
- fields: `amount: float`, `type: DamageType`, `source: Node`
- `DamageInfo.create(amount, type := PHYSICAL, source := null) -> DamageInfo`

### `HurtBox` (components/hurt_box.gd, `class_name HurtBox extends Area3D`)
- `enum Team { PLAYER, ENEMY, NEUTRAL }`
- `@export var team: Team`
- `signal hit(info: DamageInfo)` — the OWNER connects this to its Health/stats.
- `take_hit(info)` — called by HitBox; just re-emits `hit`.

### `HitBox` (components/hit_box.gd, `class_name HitBox extends Area3D`)
- `@export`: `amount: float`, `damage_type: DamageInfo.DamageType`, `target_team: HurtBox.Team`,
  `one_shot: bool` (free on first hit — use for projectiles), `lifetime: float` (auto-free
  after N seconds, 0 = manual), `active: bool`
- `var source: Node` — set this to the attacker (kill credit).
- Only hits HurtBoxes whose `team == target_team` (no friendly fire). Hits each HurtBox once
  until `reset()`.

### `Health` (components/health.gd, child Node) — upgraded
- `@export var max_health: float`
- `@export var damage_multipliers: Dictionary` — `DamageInfo.DamageType (int) -> float`.
  `>1` weakness, `<1` resistance, `0` immune, missing = `1.0`.
- `apply_damage(info: DamageInfo) -> float` — scales by multiplier, applies, returns dealt.
- still has `take_damage(amount)`, `heal(amount)`, `is_dead()`, signals `damaged`/`died`.

### Collision / teams
HitBoxes and HurtBoxes use the **default area layer/mask (1)** and find each other by
overlap; the **team check is in code**. So you do NOT need to configure physics layers —
just give each Area a CollisionShape3D and set `team` / `target_team`.

- Player attacks → `target_team = ENEMY`.
- Enemy attacks → `target_team = PLAYER`.
- The **player already has a HurtBox** (team PLAYER) wired to PlayerStats — enemy HitBoxes
  with `target_team = PLAYER` will damage the player automatically.

## Player API (entities/player/player.gd — do not edit)
- In group `"player"`.
- `player.get_camera() -> Camera3D` — first-person camera; use for aim origin/direction
  (`-camera.global_transform.basis.z` is forward) and projectile spawn points.
- Using an item: on the `use_item` action (left-click) the player calls
  `selected_item.use(self)`. **This is the entry point for all player combat.**

## Item API (global/items/item.gd — do not edit)
- `Item` has `id`, `display_name`, `category` (enum now includes `WEAPON`, `CONSUMABLE`),
  `world_model: PackedScene` (shown in-hand + when dropped), and:
  - `func use(_player: Node) -> void` — base no-op; **override in your Item subclass.**
- Make weapons/consumables by subclassing `Item` (see `global/items/tool_item.gd` for an
  example subclass) and overriding `use(player)`.
- Items are **data Resources** (.tres). One instance is shared, so don't store per-shot
  mutable state on them carelessly; for cooldowns use `Time.get_ticks_msec()`.

## Autoloads you'll use
- `PlayerStats` — `take_damage(amount)`, `heal(amount)`, `use_stamina(amount) -> bool`,
  `health`, `max_health`.
- `Inventory` — `add(id, n)`, `remove(id, n)`, `has(id, n) -> bool`, `count_of(id) -> int`,
  `get_item(id) -> Item`. Consumables should `Inventory.remove(id, 1)` when used.
- `Hotbar` — `get_selected_item() -> Item`, `get_selected_id()`.
- `WorldItem.spawn(id, amount, world_node, global_pos)` — drop loot (enemies on death).

## Spawning things into the world
From an item's `use(player)` or an enemy, add scene instances to
`player.get_tree().current_scene` (or the enemy's `get_parent()`), then set
`global_position`. Projectiles/thrown objects are their own scenes carrying a HitBox.

## .tres format
Mirror existing item resources (e.g. `global/items/resources/iron_sword.tres`,
`pickaxe.tres`). New `class_name` subclasses are referenced by their script path in the
`ext_resource`. Items with a `world_model` add a PackedScene ext_resource pointing at a
Kenney `.fbx` (browse `assets/models/tools_weapons/`, `assets/models/props/`).

## Build conventions
- Put new files only in your assigned area; do NOT edit foundation/shared files
  (player.*, item.gd, components/*, hotbar.gd, project.godot, existing scenes).
- Damage always flows HitBox → HurtBox → Health/PlayerStats. Never call take_damage directly
  across entities.
- Keep behaviour readable and commented in the house style (see existing scripts).

---

## Implemented on top of this foundation (2026-06-24)

- **Enemies** (`entities/enemies/`): `Enemy` (CharacterBody3D + Health + HurtBox + inline
  IDLE/CHASE/ATTACK brain, straight-line chase — no navmesh needed) driven by an
  `EnemyStats` resource (HP, speed, damage, attack style, ranges, cooldown, weaknesses,
  loot). Three monsters: **Ember Hound** (fast FIRE melee, weak to ICE), **Cinder Spitter**
  (ranged, resists POISON), **Obsidian Brute** (tanky, resists PHYSICAL, weak to ICE).
- **Weapons** (`entities/items/weapons/`): `MeleeWeaponItem` (spawns a brief HitBox in
  front of the camera), `RangedWeaponItem` (fires an `arrow.tscn` projectile). Resources:
  `steel_sword`, `obsidian_blade` (FIRE), `bow`.
- **Consumables** (`entities/items/consumables/`): `ConsumableItem` base (consumes one on
  use); `health_potion` (heal), `fire_bomb` (thrown → EXPLOSIVE AoE), `smoke_grenade`
  (thrown → visual smoke cloud).
- **Test arena**: `stages/dev/combat_arena.tscn` — open it and fight; its loadout script
  equips the player with every weapon/consumable on the hotbar automatically.

### Cooldown gotcha (learned the hard way)
Cooldowns stamped with `Time.get_ticks_msec()` must initialise the "last used" timestamp
to a large NEGATIVE number (e.g. `-100000`), NOT `0` — ticks start near 0, so a `0` init
blocks the first action during the first second of runtime.

## Fixes (2026-06-28)

- **Normal-attack telegraph is real.** `EnemyStats` now has the `@export var attack_windup`
  field (seconds, default `0.0`). When a sheet authors a positive value, `enemy.gd` first
  pulses an amber warning (`_pulse_attack_tell`) and fires `CombatFeel.play_attack_tell()`,
  waits out the wind-up, then strikes — re-enabling the telegraph path that had no data
  field to drive it. `0` keeps the old instant swing, so existing sheets are unchanged.
  (`enemy.gd` reads it defensively via `stats.get(&"attack_windup")`, so pre-field `.tres`
  files still load.)
- **Animal facing / bite fixed.** `animal.gd._face_heading()` now yaws with
  `atan2(-heading.x, -heading.z)` (was inverted). Hostile animals now face the player as
  they chase, so their bite HitBox — placed at local `-Z` (forward) in `_spawn_bite_hitbox`
  — actually lands.
- **Critters are damageable.** `critter.tscn` now carries a `HurtBox` child (team `ENEMY`);
  `critter.gd` wires `_hurt_box.hit -> health.apply_damage` on `_ready`, so player weapon
  HitBoxes overlapping it deal damage through the normal backbone (previously a critter had
  no HurtBox and could not be hit).
