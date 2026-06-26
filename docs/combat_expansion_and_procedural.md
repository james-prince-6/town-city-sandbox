# Combat Expansion & Procedural Dungeons — Scope & Roadmap

Scope for the ranged-combat expansion and the procedural dungeon system. Tracks the
overall design plus what is built vs. still planned, so the work can continue across
sessions.

## Goals (from the request)
- More **ranged weapons** building on the bow.
- **Spells** cast from a **wand**.
- Keep the **"bullet in the air" travel delay** that makes ranged feel bullet-hell-y —
  for the player *and* for enemies.
- **Sound, particles, animations** wherever possible.
- A **spawning system / procedural enemy placement** for dungeons (fresh each run).
- **Procedural dungeon generation** — levels assembled at runtime.

## Architecture it builds on
- Items are data `Resource`s auto-loaded from `global/items/resources/` by `id`
  (drop a `.tres` in and it registers — no code edit).
- Damage always flows `HitBox -> HurtBox -> Health/PlayerStats` (teams: PLAYER/ENEMY).
- Projectiles travel in `_physics_process` (the air-travel delay) and own a child `HitBox`.
  - Player projectiles implement `setup(damage, damage_type, source, velocity, is_crit, knockback, piercing)`
    and are driven by `RangedWeaponItem.use()`.
  - Enemy projectiles implement `launch(direction, amount, damage_type, source, knockback)`
    and are driven by `enemy.gd`.
- Game feel via the `CombatFeel` autoload (hitstop, shake, damage numbers, impact
  particles, sound pools).
- Spells cost **mana** — `PlayerStats.use_mana()` / `mana` / `max_mana`, with its own
  regen + post-cast delay and a blue HUD bar. Wands set `mana_cost` on their
  `RangedWeaponItem`; bow/crossbow leave it 0 and stay on stamina.

---

## Phase 1 — Combat expansion  ✅ (built)

### Player weapons (`entities/items/weapons/`, resources in `global/items/resources/`)
- **Crossbow** (`crossbow.tres`) — heavy, slow, fast piercing bolt (`crossbow_bolt`).
- **Flame Wand** (`flame_wand.tres`) — FIRE; fires a **fireball** that explodes (AoE) on impact.
- **Frost Wand** (`frost_wand.tres`) — ICE; fast **ice shard**, pierces.
- **Arcane Wand** (`arcane_wand.tres`) — **homing** arcane missile.
- **Throwing Knives** (`throwing_knife.tres`) — stackable consumable, consumed per throw.
- Generalized magic projectile `spell_projectile.gd/.tscn` with exported knobs
  (`explode_radius`, `homing_strength`, pierce) + inherited variants
  `fireball.tscn` / `ice_shard.tscn` / `arcane_missile.tscn`. Emissive colour by element.

### Enemy ranged + bullet-hell (`entities/enemies/`)
- New projectiles: `frost_bolt_projectile`, `magma_orb_projectile` (big slow telegraphed orb).
- New `SpecialStyle`s appended: **RING** (360° barrage) and **SPIRAL** (rotating barrage).
- Normal ranged attack can now fan multiple shots (`projectiles_per_shot`,
  `shot_spread_degrees`; defaults preserve old single-shot behaviour).
- New enemies: **Cinder Caster** (RING barrages of magma orbs), **Frost Caster**
  (frost-bolt volley + 3-shot burst).

### FX/sound
- Reuses existing `CombatFeel` hooks (impact particles/numbers auto-fire through the
  damage path; explosions add a light shake). Dedicated spell-cast/explosion SFX are a
  follow-up (see below).

### Try it
- `stages/dev/combat_arena.tscn` — loadout now puts bow/crossbow/3 wands/throwing knives
  on the hotbar; Cinder + Frost casters added to the arena.

---

## Phase 2 — Procedural systems  ✅ (built, v1)

### Enemy spawner (`global/systems/enemy_spawner.gd`)
- `class_name EnemySpawner` (a plain class, **not** an autoload).
- `populate(world, difficulty, rng)` — finds `Marker3D`s in group `"enemy_spawn"` and
  spends a difficulty-scaled **threat budget** on a weighted/costed table of enemy
  scenes, deterministically (seeded `rng`).

### Dungeon generator (`stages/dungeons/procedural/`)
- `dungeon_generator.gd` (`class_name DungeonGenerator extends Node3D`),
  `generated_dungeon.tscn` (directly playable with F6).
- `build(seed, difficulty)` — deterministic per seed. Room-graph on a macro grid,
  L-shaped corridors, geometry emitted from `BoxMesh`+`BoxShape3D` (matches the
  hand-built dungeons), auto-enclosing walls, lights, atmosphere.
- Drops markers: entry (`from_overworld` / `Respawn_Entrance`), per-room respawns
  (group `respawn_point`), scattered `enemy_spawn` points, and an `ExitTeleport`
  (instance of `teleport_raycast.tscn`) in the last room → returns to the hub
  (`town_template.tscn`, marker `from_dungeon`, which now exists).
- **Loot** (`_place_loot`): a chest in most rooms (consumables / materials, ~35% a weapon),
  a few grabbable floor pickups per room, and a **guaranteed reward chest in the end room**
  with a random weapon + potions + bombs. Chests are code-built `LootTable`s; chest ids
  include the seed so opened-state never bleeds across seeds. All seeded/deterministic.
- **Starter kit** (`grant_starter_kit`, default on): if the player owns no weapon (e.g.
  opening the scene directly on an empty save) they're handed a basic loadout so the dungeon
  is immediately playable. A player arriving armed from the overworld is untouched.

### Try it
- Open `stages/dungeons/procedural/generated_dungeon.tscn` and press F6. Change
  `start_seed` / `difficulty` in the Inspector for different layouts.
- To reach it in-game: point any door's `teleport_raycast` at
  `res://stages/dungeons/procedural/generated_dungeon.tscn`, spawn `from_overworld`.

---

## Done since v1
- **Navmesh + pathfinding** ✅ — `DungeonGenerator` now wraps its geometry in a
  `NavigationRegion3D` and bakes a `NavigationMesh` synchronously (verified: ~60 polys on
  the default seed). `enemy.gd` creates a `NavigationAgent3D` and, when the world has a baked
  navmesh, chases via the agent (`_chase_dir`); with no navmesh it falls back to the original
  straight line, so the arena/overworld are unchanged.
- **Mana pool** ✅ — see Architecture above; wands draw from it, HUD shows a blue mana bar,
  and it's in the save snapshot.

## Dungeon progression ✅ (built)
The procedural dungeon is now a multi-floor roguelike run (all deterministic per floor):
- **Floors & descent**: a `DescendPortal` (glowing pad) in the reserved end room rebuilds the
  dungeon one floor deeper (`_depth`). Each floor is its own seed (`start_seed + (depth-1)*stride`)
  and difficulty scales (`difficulty + (depth-1)*2`), so deeper = bigger seeded army. A
  "Leave Dungeon" teleport sits in the **start** room; a floating **FLOOR N** sign marks depth.
  Leaving to town and re-entering resets to floor 1 (scene reload); dying respawns on the
  current floor.
- **Boss floors**: every 3rd floor (`BOSS_EVERY`) spawns a boss (`boss_scene_path`, default the
  magma colossus) in the end room and the **descend portal stays sealed until the boss dies**
  (wired via the boss `Health.died` signal). Bigger reward chest on boss floors.
- **Locked vault**: each floor carves a side vault room sealed by a key-locked `Door`
  (`required_key = dungeon_key`, consumed on open). The `dungeon_key` is guaranteed in a chest
  in a mid "key room". The vault holds a premium two-weapon reward chest.
- New files: `stages/dungeons/procedural/descend_portal.gd`, `global/items/resources/dungeon_key.tres`.

## Dungeon art pass ✅ (built)
The generator no longer renders grey BoxMesh — it lays **KayKit Dungeon Remastered** glTF pieces
(`assets/models/dungeon_kit/`: `floor_tile_large`, `wall`, `pillar` + shared `dungeon_texture.png`)
on the existing tile grid. The kit is natively a **4 m grid**, matching `TILE_SIZE` exactly — no
scaling. Pattern: each floor/wall keeps an **invisible BoxShape collider** (guaranteed physics +
clean navmesh) with the kit mesh laid on top; walls rotate to their edge (`_add_wall_edge`),
floors sit on the plane (`_add_floor_tile`), and decorative pillars go at each room's 4 corners
(`_place_pillars`). The navmesh now bakes from the **box colliders** (`PARSED_GEOMETRY_STATIC_COLLIDERS`)
so the detailed art doesn't complicate it (verified: ~68 polys, enemies still path). Theme tint
applies to lighting/fog/ambient only (kit meshes keep their own texture). Follow-ups: wall
torches (orientation needs care), props (barrels/crates), doorway pieces, themed kit recolors.

## Reachability ✅ (built)
The procedural dungeon + new weapons are now reachable in normal play (`town_template.tscn`,
the live town the game boots into):
- **Enter Dungeon** portal in town (`teleport_raycast` → `generated_dungeon.tscn`, spawn
  `from_overworld`); the dungeon exit returns to town (`from_dungeon` marker).
- **Gus the shopkeeper** placed in town; the general store now stocks the new weapons +
  `sulfur_crystal`.
- **Workbench** placed in town; new WORKBENCH recipes craft all four weapons
  (`flame_wand_craft` / `frost_wand_craft` / `arcane_wand_craft` / `crossbow_craft`).

## Status effects ✅ (built)
- `components/status_receiver.gd` — burn (FIRE DoT), poison (POISON DoT), chill (ICE slow +
  light DoT), ticked once/sec. Auto-applied by any elemental `HitBox` (new `applies_status`
  flag) via `apply_from_damage(element, amount, attacker)` — so wands, elemental enemies, etc.
  all inflict status with no per-attack wiring. Enemy DoT routes through `Health.apply_damage`
  (resistances + floating numbers apply); player DoT through `PlayerStats`. Chill multiplies
  move speed (player + enemy). Created via `load()` (not the global class) to dodge the
  script-class-cache gotcha.

## Dungeon variety ✅ (built, layered on progression)
- **Themed floors**: Stone / Frost / Ember / Bog palettes (floor/wall/ambient/fog/light),
  chosen per floor from a separate seeded rng so geometry/loot stay identical for a seed.
- **Boss pool**: `boss_pool` (magma colossus / obsidian brute / iron bruiser), one picked per
  boss floor; boss HP scales on deeper boss floors.
- **Elite enemies** (`enemy_spawner.gd`): difficulty-scaling chance to promote a spawn —
  ~2.2× HP, 1.6× damage, 3× XP, +1 loot, gold glow. Non-elite spawns unchanged.

## Shippability ✅ (built)
- **Main menu** (`ui/main_menu/main_menu.gd`, autoload): title + New Game / Continue (when a
  save exists) / Load Game / Quit. Boot now opens it instead of jumping into town.
- **Save slots** (`ui/save_menu/save_slot_menu.gd`, autoload): 3-slot SAVE/LOAD browser.
- Pause menu gained **Save Game / Load Game / Main Menu**.

## Backlog / follow-ups
- **Nav polish**: ranged enemies still kite in a straight line; doorway-width vs. agent radius.
- **Dedicated SFX**: spell-cast / explosion / status (burning) sounds in `CombatFeel`.
- **Status polish**: HUD status icons; burning/chill particle VFX on the body.
- **New Game reset**: invoked from an in-progress session it doesn't wipe autoload state yet.
- **Town re-theme**: the live town is generic but sparse — flesh out buildings/props; the old
  lava-themed models live only in archived scenes.
- **More spells**: chain lightning, AoE nova, channelled beam.
- **Player ranged animations**: distinct viewmodel poses per weapon class.
