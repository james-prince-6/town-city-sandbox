# Town City — Architecture Guide

A first-person 3D action-RPG in **Godot 4.5 / GDScript**. You run a small business in a town:
gather ingredients, brew/craft/cook goods in machines, sell them to NPCs, take on quests, and
build reputation — and increasingly **fight** (first-person melee + ranged + throwables) through
monster-filled dungeons, with minigames on the side. All progress persists to save files.

> Theme note: the project was previously themed around "lava"; it is now **generic ("Town City")**.
> Internal item **ids** still contain legacy lava words (e.g. `lava_ash`, `magma_pick`) — those are
> stable save keys and were intentionally left unchanged; only player-visible display names were
> de-themed. Don't rename ids.

This doc explains how the project is wired so you can extend it confidently. It assumes you
know general software architecture and a little Godot.

---

## 1. The one rule that drives everything: persistent state lives in autoloads

Godot's scene switching (`change_scene_to_file`) **destroys the entire current scene**, including
the player, and builds the next one fresh. So the project draws a hard line:

- **Persistent state** (money, inventory, time of day, health, quests, reputation, in-progress
  brews) lives in **autoload singletons**. These nodes hang off `/root` and survive every scene
  change. They are the "systems layer."
- **Per-scene state** (an NPC standing in the plaza, a rock you can mine, a dropped item) lives in
  **scene nodes** that are *meant* to die with the scene.

If you ever find yourself wanting state to survive a scene change, it belongs in an autoload (or in
a resource the autoload owns) — never in a scene node. This is the same class of bug as storing
session state in a React component vs. a store.

Every stateful autoload exposes `capture_state() -> Dictionary` / `restore_state(Dictionary)`.
`SaveManager` walks them all to produce one save file (§9).

---

## 2. The systems layer (autoloads)

Registered in `project.godot` under `[autoload]`, **in dependency order** (a system that connects to
another's signals in `_ready()` must load *after* it). Current order and responsibilities:

| # | Autoload | File | Responsibility |
|---|---|---|---|
| 1 | `GameState` | `global/systems/game_state.gd` | Money, day counter, story flags. `add_money/spend_money/set_flag/get_flag`. Signals `money_changed`, `day_changed`. |
| 2 | `Inventory` | `global/systems/inventory.gd` | What the player carries (`id -> count`). Loads `Item` `.tres` from `global/items/resources/`. `add/remove/count_of/has/get_item`. Signal `item_changed`. |
| 3 | `SceneManager` | `global/systems/scene_manager.gd` | Scene transitions that place the player at a named `Marker3D` spawn point. Signal `scene_loaded`. |
| 4 | `DialogueManager` | `ui/dialog/dialogue_manager.tscn` | The one dialogue system. `start_dialogue(DialogueResource)`. Signals `dialogue_started/ended`. (Registered as the **scene**, not the script — it needs its UI nodes.) |
| 5 | `InteractionUI` | `ui/interactions/interaction_prompt.tscn` | The floating "[E] …" prompt. |
| 6 | `InventoryUI` | `ui/inventory/inventory_ui.tscn` | Bag panel (toggle **I**). |
| 7 | `Clock` | `global/systems/clock.gd` | Time of day (hour/minute), advances real-time, rolls `GameState.day` at midnight. Auto-pauses in menus/dialogue. Signals `time_changed`, `day_started`. |
| 8 | `PlayerStats` | `global/systems/player_stats.gd` | Health + regenerating stamina. `take_damage/heal/use_stamina/reset`. Signals `health_changed/stamina_changed/died`. |
| 9 | `Hotbar` | `global/systems/hotbar.gd` | 8 equip slots of item ids + selection. `select/get_selected_item`. Signals `slots_changed/selection_changed`. |
| 10 | `Reputation` | `global/systems/reputation.gd` | Per-NPC score (-100..100) and tier (Hostile→Beloved). `get/add/set_reputation/get_tier`. |
| 11 | `QuestSystem` | `global/systems/quest_system.gd` | Loads `Quest` `.tres` from `global/quests/resources/`. Tracks active/completed, auto-progresses `COLLECT_ITEM` objectives off `Inventory.item_changed`, applies rewards on completion. |
| 12 | `CraftingSystem` | `global/systems/crafting_system.gd` | Loads `Recipe` `.tres` from `global/crafting/recipes/`. Per-machine brew state keyed by `machine_id`, **timed in game-minutes** so brews continue while you're away. |
| 13 | `HUD` | `ui/hud/hud.tscn` | Health/stamina bars, money, day+time, hotbar strip. Pure view. |
| 14 | `QuestLog` | `ui/quest_log/quest_log.tscn` | Active-quest overlay (toggle **J**), non-blocking. |
| 15 | `BrewingUI` | `ui/crafting/brewing_ui.tscn` | Brewing menu (opened by a machine). Blocking. |
| 16 | `SaveManager` | `global/systems/save_manager.gd` | Gathers every system's snapshot into one save file. **F5** save / **F9** load. |
| 17 | `ShopSystem` | `global/systems/shop_system.gd` | Pricing (off `Item.base_value`), buy/sell, reputation-adjusted prices. |
| 18 | `ShopUI` | `ui/shop/shop_ui.tscn` | Buy/sell menu (opened by a shopkeeper). Blocking. |
| 19 | `PauseMenu` | `ui/pause/pause_menu.gd` | **Esc** pause overlay (Resume/Settings/Quit). Fully pauses (tree + Clock). Code-built. |
| 20 | `DeathScreen` | `ui/death/death_screen.gd` | "You Died" overlay on `PlayerStats.died`; respawns at nearest `respawn_point` (or the player's start). |
| 21 | `MinigameManager` | `global/minigames/minigame_manager.gd` | Opens a minigame (pauses world), pays out `GameState.add_money` on finish. |

**Two ordering constraints worth remembering:** `Clock` connects to `DialogueManager`/`InventoryUI`
signals, so it's listed after them; `QuestSystem` connects to `Inventory.item_changed`, so it's after
`Inventory`. UIs that read a system come after it.

---

## 3. Data-driven content (Resources)

Game *content* is data, not code. Each is a `Resource` subclass (`class_name`), authored as `.tres`
files and edited in the Inspector. Systems that own a catalog scan a folder at startup (mirroring
`Inventory._load_database`).

| Resource | File | Loaded from | Notes |
|---|---|---|---|
| `Item` | `global/items/item.gd` | `global/items/resources/` | id, display_name, description, `category` (INGREDIENT/DRINK/TOOL/MATERIAL/MISC/FOOD), icon, max_stack, base_value, **`world_model`** (§6). |
| `ToolItem` | `entities/items/tool_item.gd` | same folder | `extends Item`. Adds `tool_type` (PICKAXE/HATCHET/LADLE/WEAPON/NONE), power, stamina_cost, damage. |
| `Recipe` / `RecipeIngredient` | `global/crafting/` | `global/crafting/recipes/` | inputs[], output_id, output_count, `brew_minutes` (game-minutes), machine_type. |
| `Quest` / `QuestObjective` | `global/quests/` | `global/quests/resources/` | objectives[] (`COLLECT_ITEM` auto-tracked, or `REACH_FLAG`), rewards[] (reuse `DialogueEffect`). |
| `DialogueResource` / `DialogueChoice` | `ui/dialog/` | referenced, not scanned | A node in a dialogue tree: lines[], choices[], `on_enter_effects[]`. Choices branch via `next_dialogue`. |
| `DialogueEffect` / `DialogueCondition` | `ui/dialog/` | embedded in dialogues/quests | The **shared consequence/gate system**: an effect `apply()`s (set flag, give/take item, change rep, money, start/complete quest); a condition `is_met()` gates a choice. Used by both dialogue *and* quest rewards. |
| `ShopInventory` | `global/shop/shop_inventory.gd` | assigned to a `Shopkeeper` | stock[], markups, `buy_categories`, optional `reputation_npc`. |

The `DialogueEffect`/`DialogueCondition` pair is the key reuse: "choices that matter" and "quest
rewards" are the same data type, so you author consequences in the Inspector without scripting.

---

## 4. Entity patterns (scene nodes)

### Duck-typed interaction
There's **no interaction registry**. The player has a forward `RayCast3D`; each frame it asks
whatever body it hits:

```gdscript
if collider.has_method("get_interaction_prompt"):
    interaction_ui.show_prompt("[E] " + collider.get_interaction_prompt())
if Input.is_action_just_pressed("interact"):
    collider.interact(self)
```

So **anything** becomes interactable just by implementing `get_interaction_prompt() -> String` and
`interact(player)`. NPCs, harvestables, machines, shopkeepers, dropped items, and `Prop`s all do.

### Hybrid: base scenes + components
- **Base scenes + scene inheritance** for entity variants: `harvestable.tscn` → inherited
  `rock.tscn` / `plant.tscn` / `lava_pool.tscn` (swap mesh + exported values in the Inspector).
- **Components** for orthogonal behavior dropped onto any entity: `components/health.gd` (HP +
  `take_damage/died`) is reused by critters and could be reused by destructibles.

### The entities
| Entity | File | Pattern |
|---|---|---|
| Player | `entities/player/player.gd` | `CharacterBody3D`. FPS controller, stamina-gated sprint, hotbar input, weapon swing (raycast → `Health`), interaction. Listens to all blocking-UI `opened/closed` to freeze movement. |
| `NPC` | `entities/npc/npc.gd` | `CharacterBody3D`. `npc_name`, `npc_id` (reputation key), `dialogue`, optional `schedule`. Owns a state machine + nav + animated body (see §6.5). `interact()` → freeze + `DialogueManager.start_dialogue`. |
| `Shopkeeper` | `entities/npc/shopkeeper.gd` | `extends NPC`. Overrides `interact()` → `ShopUI.open_for(shop)`. |
| `Harvestable` | `entities/harvestables/harvestable.gd` | `StaticBody3D`. `interact()` checks the equipped `ToolItem` via `Hotbar`, spends stamina, decrements durability, drops loot via `WorldItem.spawn` or straight to `Inventory`. |
| `Critter` | `entities/critters/critter.gd` | `CharacterBody3D` + `Health` child. Wanders; on `Health.died` drops loot. Damaged by the player's weapon swing. |
| `WorldItem` | `entities/items/world_item.gd` | `RigidBody3D`. A physical, pick-up-able pile of one item. Static `spawn()` for loot. Shows the item's `world_model` (§6). |
| `BrewingMachine` | `entities/machines/brewing_machine.gd` | `StaticBody3D`. `machine_id` (unique!). `interact()` → `BrewingUI.open_for(self)`. |
| `Prop` | `entities/props/prop.gd` | `StaticBody3D`. A placeable shell: drop a model child, it **auto-fits a box collider** to the model's AABB at runtime. Optional `interaction_prompt`. |

---

## 5. UI layer

UIs are `CanvasLayer` autoloads, `process_mode = ALWAYS`, view-only (they read systems and rebuild
on signals; they own no game state). Z-order is the `layer` property:

| Layer | UI |
|---|---|
| 5 | HUD |
| 6 | QuestLog (non-blocking overlay) |
| 9 | ShopUI, BrewingUI (blocking menus) |
| 10 | InventoryUI (blocking) |
| 11 | DialogueManager (on top of everything) |

**Blocking menus** emit `opened`/`closed`; the player connects each to `_on_menu_opened/_closed`,
which set `is_menu_open` (→ `_is_ui_blocking()`), stop movement, and free the mouse. To add a new
blocking menu, follow that two-line pattern in `player.gd`.

**Input note (a real bug we hit):** dialogue advances on **`ui_accept` / left-click**, *not* the
`interact` (E) key — because E *opens* dialogue, and reusing it to advance made the closing press
instantly re-open the conversation. Keep the open key and the advance key separate for any modal.

---

## 6. Items ↔ world models (held & dropped)

`Item.world_model: PackedScene` is the single hook for an item's 3D appearance:

- **Dropped:** `WorldItem._ready()` instances `world_model`, hides its placeholder cube, **normalizes
  it** (scales so its largest dimension = `pickup_size` 0.35 m, re-centers it, and resizes the
  collision box to the scaled silhouette — so every drop reads at a consistent grabbable size). No
  model set → it keeps the cube. (Loot drops, manual placements, and `spawn()` all funnel through this.)
- **Held:** `entities/player/held_item_display.gd` is a `Node3D` parented under the camera. It
  watches `Hotbar.selection_changed` and shows the selected item's `world_model` in hand. The player
  spawns it in `_ready()`.

29 items currently point at Kenney models. Held placement (`held_position/scale/rotation`) is rough
by design — tune in the Inspector, or add a dedicated viewmodel camera/layer later to stop near-wall
clipping.

---

## 6.5 NPC behaviour: state machine + schedule + animation

An `NPC` is a body plus three cooperating pieces. The script itself only provides *services*
(movement, animation, location lookup); the *decisions* live in swappable states and a data-driven
schedule.

**State machine** (`entities/npc/ai/`). A tiny code-built FSM (`NPCStateMachine`, a `RefCounted` —
no extra scene nodes). States are `RefCounted` subclasses of `NPCState`, registered by name in
`NPC._register_states()`:

| State | Does |
|---|---|
| `Idle` | stand, play `idle`. Default / fallback. |
| `Wander` | roam random points near `home_position` (spawn), pause, repeat. Enable with `wander_when_idle`. |
| `MoveTo` | navigate to `msg.target`, then transition to `msg.on_arrive`. The walking workhorse. |
| `Sleep` | rest at a spot (idle anim for now — no lie-down clip in the kit). |
| `Work` | busy at a spot, looping `interact` anim. |
| `Talk` | frozen during a conversation; `interact()` enters it, dialogue end leaves it. |

`NPC._physics_process` applies gravity, calls `machine.physics_update(delta)` (the active state sets
horizontal `velocity`), then `move_and_slide()` once. **To add a behaviour:** write an `NPCState`
subclass and register it (override `_register_states()` in an `NPC` subclass, calling `super()`).

**Navigation.** Optional `NavigationAgent3D` child (`NavAgent`). `NPC.nav_step()` follows the navmesh
when one is baked, and **falls back to straight-line movement when there's no navmesh** — so NPCs
still move in un-baked scenes (just without obstacle avoidance). A scene needs a `NavigationRegion3D`
with a baked/authored navmesh for real pathfinding. **Already baked:** `town_square` (carves around the
buildings), `shop-interior`, and `bar-inside` (region lives inside its SubViewport). Each references an
external `*_nav.res` next to its scene. To re-bake after editing level geometry, run
`tools/bake_navmeshes.tscn` headless (it parses each scene, strips dynamic actors, bakes, and saves the
`.res`) — see the cheat sheet in `adding_content.md`. We bake offline into a resource rather than via the
editor's in-place button because the level geometry isn't parented under the `NavigationRegion3D`.

**Schedule** (`global/npc/`). `NPCSchedule` is a list of `ScheduleEntry` (`hour`/`minute`,
`location_id`, `activity`). The NPC subscribes to `Clock.time_changed`; when the in-effect entry
changes it walks (`MoveTo`) to the named `WorldLocation` and switches to the entry's `activity` state
on arrival. The routine wraps midnight (before the first entry, the last is still in effect). Talking
suspends schedule reactions until the conversation ends.

**Locations.** `WorldLocation` (a `Marker3D` in group `world_location`) gives a spot a `location_id`.
`NPC.resolve_location(id)` finds one in the current scene. Locations are **per-scene** — cross-scene
NPC travel isn't modelled yet.

**Animated body** (`NPCAnimator`, the `Animator` child). The Kenney rigged kit ships the mesh and each
animation as *separate* FBX files on a shared 58-bone rig. `NPCAnimator` assembles them at runtime:
instance the base model, pull each clip out of its animation FBX into one `AnimationLibrary`, attach
an `AnimationPlayer`. `NPC.play_anim(&"walk")` drives it. It's tolerant: no `model_scene` → the NPC
keeps its placeholder capsule and `play_anim` is a no-op. Clips loaded by default: `idle`, `walk`,
`run`, `interact` (unknown names fall back to `idle`). `target_height` normalizes model scale;
`face_offset_degrees` (180°) aligns the model's facing with `look_at`.

Playable reference scenes: `stages/overworld/npc_demo/npc_demo.tscn` (navmesh + `home`/`market`/`grove`
markers + scheduled Sela + coconut pickups + player), and the live `town_square` (baked navmesh + 4
location markers + scheduled Marlo + wandering Pip + an arcade cabinet + a dungeon entrance). The
`shop-interior` has the `Shopkeeper` (Gus) placed.

---

## 6.6 Combat (full detail in `docs/combat.md`)

Every attack — sword swing, arrow, bomb blast, enemy claw — runs through one backbone in
`components/`: a **`HitBox`** (Area3D) overlaps a **`HurtBox`** (Area3D) and delivers a
**`DamageInfo`** (amount + element + source), which a **`Health`** component applies after scaling
by the target's **weakness/resistance** multipliers. `HurtBox.team` (PLAYER/ENEMY) + `HitBox.target_team`
keep friendly fire out — the check is in code, so no physics-layer config is needed.

The player has a `HurtBox` (team PLAYER, wired to `PlayerStats`) and a generic input path: left-click
(`use_item`) calls `selected_item.use(player)`. So **all player combat lives in `Item` subclasses**:

- `MeleeWeaponItem` / `RangedWeaponItem` (`entities/items/weapons/`) — sword spawns a brief HitBox in
  front of the camera; bow fires an `arrow.tscn` projectile. Resources: `steel_sword`, `obsidian_blade`
  (FIRE), `bow`.
- `ConsumableItem` (`entities/items/consumables/`) — `health_potion` (heal), `fire_bomb` (thrown →
  EXPLOSIVE AoE), `smoke_grenade` (thrown → smoke). Each consumes one from the Inventory on use.

`DamageType` = PHYSICAL / FIRE / ICE / POISON / EXPLOSIVE. Cooldown stamps use `Time.get_ticks_msec()`
and must be initialised to a large negative number (ticks start near 0 — see combat.md).

## 6.7 Enemies (`entities/enemies/`)

`Enemy` (CharacterBody3D) + a data-driven **`EnemyStats`** resource (HP, speed, damage, element,
ranges, attack cooldown, **`damage_multipliers`** for weaknesses, loot). A compact inline FSM:
IDLE → CHASE (straight-line, **no navmesh needed**) → ATTACK (melee HitBox or projectile, target PLAYER).
A `Health` + `HurtBox` (team ENEMY) child make it damageable by player weapons; on death it drops loot
(`WorldItem.spawn`) and frees. Bodies are rigged Kenney characters via **`EnemyAnimator`** (mirrors
`NPCAnimator` but also loads `attack`/`death` clips; death plays before the body frees). Three monsters
ship: **Husk** (fast melee), **Spitter** (ranged), **Brute** (tanky). Test scene:
`stages/dev/combat_arena.tscn` (its loadout script auto-equips the player).

## 6.8 Interactables & dungeons (`components/interactables/`, `stages/dungeons/`)

Reusable, duck-typed (`get_interaction_prompt()`/`interact(player)`) world objects:

- **`Chest`** — one-shot; grants a `LootTable` to the Inventory and/or spills `WorldItem`s; remembers
  opened-state via a `GameState` flag keyed by `chest_id`.
- **`Door`** — opens on interact or via a `Lever`; optional `required_key` (item id) consumed on first open.
- **`Lever`** — calls a method on a target node (e.g. a Door's `open()`).
- **`Breakable`** — reuses the combat backbone (`Health` + `HurtBox` team ENEMY) so **weapons smash it**;
  spills a `LootTable` on death.
- **`LootTable`** / **`LootEntry`** — data resources (`roll()` → `{id: count}`).

Two playable dungeons (`dungeon_caverns.tscn`, `dungeon_mine.tscn`): greyboxed rooms with enemies,
chests, breakables, a **locked door + key**, `respawn_point`-group markers, and a teleport back to town.
Reachable from `town_square` via the "Enter Dungeon" teleport.

## 6.9 Minigames (`global/minigames/`, `ui/minigames/`)

`MinigameManager` (autoload) `play(scene)` pauses the world, shows a `Minigame` (CanvasLayer) overlay,
and on its `finished(score, reward)` signal pays `GameState.add_money(reward)` and resumes. Two games
ship (`whack_minigame`, `simon_minigame`), launched from an **`ArcadeCabinet`** prop (in the town square).

## 6.10 Death/respawn & pause

- **Death/respawn** (`DeathScreen` autoload): `PlayerStats.died` → full pause + "You Died" overlay →
  Respawn moves the player to the nearest node in group **`respawn_point`** (fallback: the player's
  recorded start transform), restores health, resumes. Combat feedback (crosshair, damage flash,
  low-health vignette) lives in the `HUD`.
- **Pause** (`PauseMenu` autoload): **Esc** → Resume / Settings (volume, fullscreen) / Quit; fully
  pauses (`get_tree().paused` + `Clock.pause()`). Opens only when no other menu/dialogue owns Esc.

---

## 7. Input map (`project.godot [input]`)

`move_forward/back/left/right` (WASD), `interact` (E), `sprint` (Shift), `inventory` (I),
`hotbar_1`…`hotbar_8` (number row), `hotbar_next/prev` (mouse wheel), `use_item` (LMB — swing
weapon / fire bow / throw or drink the selected item), `quest_log` (J), `pause` (Esc — pause menu),
`quicksave` (F5), `quickload` (F9). Menus also close on built-in `ui_cancel` (Esc).

---

## 8. Assets

```
assets/models/
  characters/ critters/ nature/ food_drink/ furniture/
  buildings/  machines/ props/  tools_weapons/ arcade/ dev/   ← Kenney FBX, by game system
  environment/  (your custom road/volcano .gltf — left in place)
entities/props/{bar,furniture,roads}/   ← placeable Prop shells wrapping those models
```

- The full Kenney library (~646 MB, CC0) stays **external** in OneDrive; only curated FBX were
  copied in (~97 MB). See `assets/models/KENNEY_ASSETS.md`.
- An imported `.fbx` becomes a `PackedScene`; reference it in a `.tscn` by the `uid` from its sibling
  `.fbx.import` file (+ path). `Prop` shells and item `world_model`s do exactly this.
- The `.godot/` import cache is large (FBX-heavy) but is gitignored and regenerates on import.

---

## 9. Save system

`SaveManager` snapshots every stateful autoload (`_save_targets`) plus the current scene path and
player transform, and writes it with `FileAccess.store_var` — **binary, not JSON**, on purpose: it
round-trips `StringName` dict keys, `int` vs `float`, and `Transform3D` exactly (JSON would coerce
them and corrupt inventory keys). To make a new system save: give it `capture_state/restore_state`
and add it to `_save_targets`.

---

## 10. Cookbook — how to add things

- **An item:** drop a `.tres` in `global/items/resources/` (model on `lava_ash.tres` for plain,
  `pickaxe.tres` for a tool). Set a unique `id`. It's auto-loaded next launch. Add `world_model` to
  give it a 3D look.
- **A recipe:** a `Recipe` `.tres` in `global/crafting/recipes/` with `RecipeIngredient` sub-resources
  and an existing `output_id`.
- **A quest:** a `Quest` `.tres` in `global/quests/resources/`; start it from a dialogue choice's
  `START_QUEST` effect.
- **A branching dialogue:** chain `DialogueResource` `.tres`; gate choices with `DialogueCondition`,
  attach consequences with `DialogueEffect`. (See `entities/npc/dialogue/marlo_*.tres`.)
- **An NPC / shopkeeper:** instance `npc.tscn` (or `shopkeeper.tscn`), set `npc_name`/`npc_id`, assign
  `dialogue` (or `shop`).
- **A harvestable:** inherit `harvestable.tscn`, set required tool/durability/drop.
- **A prop:** duplicate a shell in `entities/props/…`, swap the `Model` child's `.fbx` (grab its `uid`
  from the `.fbx.import`).
- **A brewing machine:** place `brewing_machine.tscn`, give it a **unique `machine_id`**.

---

## 11. Conventions & gotchas

- **`class_name` cache (headless):** running Godot headless does **not** rebuild the global class
  registry, so a freshly added `class_name X` parse-errors as "Could not find type X" until you open
  the editor once (or run `Godot --headless --editor --import`). In throwaway scripts, prefer
  `load("res://….gd").new()` over a static `X.new()` to dodge this.
- **GDScript type inference:** `var x := <int> - some_dict["k"]` fails to compile (the `Dictionary`
  subscript is `Variant`). Write `var x: int = …`.
- **Nested `.tres`:** typed-array exports of sub-resources (`Array[DialogueEffect]`, etc.) are
  hand-authorable but fiddly — keep `load_steps` in the header correct.
- **Vertex-color kits:** a few Kenney kits (Nature, Furniture) ship no texture and rely on vertex
  colors; in FBX import they can appear white unless the material uses vertex-color-as-albedo (the
  GLB variants are more forgiving).
- **Testing:** systems are verified with headless scene tests that run assertions in `_ready()` and
  write results to `user://_test_result.txt` (stdout capture proved unreliable here). One Godot
  process at a time — concurrent runs fight over the import lock.

---

## 12. Top-level map

```
global/systems/   autoload singletons (the systems layer)
global/items|crafting|quests|shop/   data-resource classes + their .tres catalogs
entities/         in-scene actors: player, npc, items, harvestables, critters, machines, props
components/        reusable behavior nodes (health)
ui/               dialog, hud, inventory, quest_log, crafting, shop, interactions
stages/overworld/ the actual game scenes (town, bar, shops)
assets/           models (Kenney + custom), materials, shaders, textures
docs/             this file + adding_content.md + KENNEY_ASSETS.md
```

Still TODO at the systems level: real death/respawn, NPC schedules off the `Clock`, a save-slot menu,
minigames, and the big one — placing all this content into the actual `stages/` scenes (the
content/world-building pass).
