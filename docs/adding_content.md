# Adding Content to Town City

This guide shows you how to add new **items**, **tools**, **weapons**,
**consumables**, **harvestables**, **critters**, **enemies**, **interactables /
dungeons**, **minigames**, and **world pickups** — mostly WITHOUT writing new
scripts. The systems are data-driven: you usually duplicate an example scene or
create a `.tres` resource and fill in fields in the Inspector. (Combat has its own
deep-dive in `docs/combat.md`.)

Read this top-to-bottom once; after that you'll usually only need the cheat
sheet at the very bottom.

---

## 0. How the pieces fit together (the 30-second tour)

- **Autoloads** (global singletons that survive scene changes) live in
  `global/systems/`. They are referenced by a global name anywhere in code:
  `GameState`, `Inventory`, `SceneManager`, `DialogueManager`, `InventoryUI`,
  `Clock`, `PlayerStats`, `Hotbar`, `HUD`.
- **Items** are data resources (`.tres`) in `global/items/resources/`. The
  `Inventory` autoload scans that folder at startup and registers every item by
  its `id`. Drop a new `.tres` in there and it "just works" — no code edits.
- **Tools** are a special kind of item (`ToolItem`) that also carry a tool type,
  power, stamina cost, and weapon damage.
- **Harvestables** (rock/plant/lava) and **critters** are *scenes* under
  `entities/`. They use Godot **scene inheritance** so you can duplicate a base
  and only tweak values + swap the placeholder mesh.
- **WorldItem** is the little physical pickup that pops out when a rock breaks or
  a critter dies. You normally never place these by hand — harvestables/critters
  spawn them for you.

---

## 1. Adding a plain Item (ingredient, material, drink, misc)

1. In the FileSystem dock, right-click `global/items/resources/` →
   **New Resource…** → choose **Item** → save as e.g. `ash.tres`.
2. Select the new file and fill in the Inspector:
   - **id** — a unique `StringName`. Type it WITHOUT the `&`; e.g. `ash`.
     This is the permanent key used in the inventory, hotbar, and save files.
     **Never change it once items exist in a save.**
   - **display_name** — shown in UI, e.g. `Volcanic Ash`. Safe to change anytime.
   - **description** — tooltip / flavor text.
   - **category** — `INGREDIENT`, `DRINK`, `TOOL`, `MATERIAL`, or `MISC`.
   - **icon** — optional `Texture2D`. If left empty, the UI shows the name as text.
   - **max_stack** — how many fit in one slot (1 = unstackable).
   - **base_value** — buy/sell price baseline.
3. That's it. Restart play and `Inventory.get_item(&"ash")` resolves.

Existing examples to copy: `stone.tres`, `iron_ore.tres`, `plant_fiber.tres`,
`lava_vial.tres`.

---

## 2. Adding a Tool (pickaxe, hatchet, ladle, weapon)

Tools are items too, so they live in the same folder and stack in the inventory
and hotbar transparently. They just use the **ToolItem** resource type.

1. Right-click `global/items/resources/` → **New Resource…** → **ToolItem** →
   save as e.g. `stone_hatchet.tres`.
2. Fill in the normal Item fields (set **category** to `TOOL`, **max_stack** to
   `1`), PLUS the tool fields:
   - **tool_type** — one of `PICKAXE`, `HATCHET`, `LADLE`, `WEAPON`, `NONE`.
     This is what harvestables check. `WEAPON` is what deals combat damage.
   - **power** — mining/harvest strength. A harvestable that requires power N is
     only worked by a tool whose `power >= N`.
   - **stamina_cost** — stamina spent per swing/use (drawn from `PlayerStats`).
   - **damage** — damage per hit, only used when `tool_type == WEAPON`.

Existing examples: `pickaxe.tres` (PICKAXE, power 2) and
`driftwood_club.tres` (WEAPON, damage 12).

> **Tool type enum order** (so the `.tres` integer matches if you ever edit by
> hand): `PICKAXE=0, HATCHET=1, LADLE=2, WEAPON=3, NONE=4`.
> **Item category enum order**: `INGREDIENT=0, DRINK=1, TOOL=2, MATERIAL=3, MISC=4`.

### Putting a tool on the hotbar

The `Hotbar` autoload seeds slot 0 with `pickaxe` and slot 1 with
`driftwood_club` at startup — but ONLY if those ids resolve in the item
database. To start the player with a different tool, either rename your tool to
one of those ids, or change the seeding lines in
`global/systems/hotbar.gd` (`_seed_slot_if_known(...)` in `_ready`). At runtime
you can also call `Hotbar.set_slot(index, &"your_tool_id")`.

---

## 3. Adding a Harvestable (rock / plant / lava pool)

All harvestables share ONE script: `entities/harvestables/harvestable.gd`. The
concrete kinds (`rock.tscn`, `plant.tscn`, `lava_pool.tscn`) are **inherited
scenes** of `harvestable.tscn` — they change exported values and the mesh
material, nothing else.

### To make a new variant (recommended workflow)

1. In the FileSystem dock, right-click `harvestable.tscn` → **New Inherited
   Scene** (or duplicate an existing variant like `rock.tscn`).
2. Rename the root node — the name shows up in the prompt
   (`get_interaction_prompt()` returns `"<prompt_verb> <node name>"`, e.g.
   `"Mine Rock"`).
3. Swap the placeholder: select the `MeshInstance3D` child and either replace its
   mesh or override the material to recolor the box. (Later you can drop in real
   art by changing the mesh here — no code change needed.)
4. Set the exported values on the root node in the Inspector:
   - **required_tool_type** — which `ToolItem.ToolType` is needed. `NONE` means
     hand-pickable (no tool required).
   - **required_power** — minimum tool power.
   - **durability** — how many successful harvests before it depletes.
   - **drop_item_id** — the item id awarded (must exist in the item database).
   - **drop_amount** — how many to award.
   - **drop_as_world_item** — `true` spawns physical pickups the player walks
     over to grab; `false` adds straight to the inventory (good for hand-picked
     plants).
   - **prompt_verb** — the verb in the prompt: `Mine`, `Pick`, `Collect`, etc.
   - **respawn_seconds** — `0` = removed when depleted; `> 0` = hides and
     refills after that many seconds (used by `lava_pool.tscn`).
5. Place instances of your variant scene in a level. Done.

### How harvesting plays out at runtime (for reference)

When the player looks at the node and presses **interact** (E), the harvestable
reads the equipped tool via `Hotbar.get_selected_item()`, validates the tool
type and power, spends `PlayerStats.use_stamina(...)`, and knocks one off
`durability`. When durability hits 0 it awards the drops (via `WorldItem.spawn`
or `Inventory.add`) and frees or respawns.

The three shipped examples:

| Scene           | Tool needed | Drops         | Notes                          |
|-----------------|-------------|---------------|--------------------------------|
| `rock.tscn`     | PICKAXE     | 2x iron_ore   | Physical pickups               |
| `plant.tscn`    | NONE (hand) | 1x plant_fiber| Added straight to inventory    |
| `lava_pool.tscn`| LADLE       | 1x lava_vial  | Respawns after 8s, glows       |

---

## 4. Adding a Critter (light combat)

Critters use the **hybrid component** pattern: the critter scene
(`entities/critters/critter.tscn`) is a `CharacterBody3D` with the critter brain
script PLUS a reusable **Health** component (`components/health.gd`) added as a
CHILD node, AND a **HurtBox** child (team `ENEMY`) so the player's weapons can
actually land hits. `critter.gd` wires `HurtBox.hit -> Health.apply_damage` in
`_ready`, so a duplicated critter scene is damageable out of the box.

### To make a new critter

1. Duplicate `critter.tscn` (right-click → **Duplicate**, or **New Inherited
   Scene** off it) and rename it.
2. Swap the `MeshInstance3D` mesh/material for your creature's look.
3. On the root node, tune the exported values:
   - **wander_speed**, **move_duration**, **rest_duration** — the tiny wander AI.
   - **loot_item_id** / **loot_amount** — what it drops when killed.
4. On the **Health** child node, set **max_health** in the Inspector to make the
   critter tougher or weaker.

### How combat works (for reference)

Damage flows through the shared combat backbone (`HitBox -> HurtBox -> Health`;
see `docs/combat.md`). The player uses a `WEAPON` item, which spawns a `HitBox`
that overlaps the critter's **HurtBox** (team `ENEMY`). The HurtBox emits
`hit(info: DamageInfo)`, which `critter.gd` has connected to
`Health.apply_damage(info)`. When `Health` emits `died`, the critter drops loot
via `WorldItem.spawn(...)` and frees itself.

> The takeaway for any **damageable mob** (critter, animal, enemy): the scene
> needs a `HurtBox` (team `ENEMY`) wired to its `Health.apply_damage` — without a
> HurtBox the player's weapons pass right through. `critter.gd` and
> `entities/animals/animal.gd` both wire this in `_ready`.

> The **Health** component is reusable: you can add it as a child of a
> destructible harvestable too, then connect its `died` signal to drop loot.

---

## 5. World pickups (WorldItem) — usually automatic

`entities/items/world_item.tscn` is the physical pickup that pops out of broken
rocks and dead critters. You rarely place it by hand; harvestables/critters call
the static helper:

```gdscript
WorldItem.spawn(item_id, amount, world, global_pos)        # basic
WorldItem.spawn(item_id, amount, world, global_pos, index) # index fans bursts out
```

If you DO want a pickup sitting in a level by hand, instance `world_item.tscn`,
then set **item_id** and **amount** on it in the Inspector. Walking up and
pressing **interact** (E) adds it to the inventory.

---

## 6. What the orchestrator wires up (so you know where things live)

You normally don't touch `project.godot` by hand, but here's what is registered
there so you can find it:

**Autoloads** (Project → Project Settings → Autoload), in dependency order:

```
GameState     res://global/systems/game_state.gd
Inventory     res://global/systems/inventory.gd
Clock         res://global/systems/clock.gd
PlayerStats   res://global/systems/player_stats.gd
Hotbar        res://global/systems/hotbar.gd
SceneManager  res://global/systems/scene_manager.gd
DialogueManager res://ui/dialog/dialogue_manager.tscn
InteractionUI res://ui/interactions/interaction_prompt.tscn
InventoryUI   res://ui/inventory/inventory_ui.tscn
HUD           res://ui/hud/hud.tscn
```

**Input actions** (Project → Project Settings → Input Map):

- Movement / existing: `move_forward`, `move_backward`, `move_left`,
  `move_right`, `interact` (E), `sprint` (Shift), `inventory` (I).
- Hotbar: `hotbar_1` … `hotbar_8` (number keys 1–8), `hotbar_next` (wheel down),
  `hotbar_prev` (wheel up).
- Combat: `use_item` (left mouse button).

---

## 7. Branching dialogue: conditions, effects, and reputation

Conversations are data too. The pieces:

- **DialogueResource** (`ui/dialog/dialogue_resource.gd`) — one "node" of a
  conversation: a `speaker_name`, a list of `dialogue_lines`, and (on the LAST
  line) a list of `player_choices`. New: it also has `on_enter_effects` (see
  below).
- **DialogueChoice** (`ui/dialog/dialogue_choice.gd`) — one button the player can
  pick. It has `choice_text`, a `next_dialogue` to branch to (leave empty to end
  the conversation), and new: `conditions` and `effects`.
- **DialogueEffect** (`ui/dialog/dialogue_effect.gd`) — one consequence (give an
  item, set a flag, bump reputation, start a quest…). Reused by both dialogue AND
  quest rewards.
- **DialogueCondition** (`ui/dialog/dialogue_condition.gd`) — one true/false test
  (has item? flag set? reputation high enough?). A choice only appears if ALL of
  its conditions are met.

You author every one of these as a `.tres` resource in the Inspector. They are
small — usually an enum dropdown plus a `target` id and an `amount`.

### DialogueEffect — making something happen

Right-click → **New Resource…** → **DialogueEffect**. Set:

- **type** — what to do (see the list below).
- **target** — the id it acts on: a flag name, item id, npc id, or quest id.
  Type it WITHOUT the `&`.
- **amount** — meaning depends on `type`: item count, reputation delta (may be
  negative), money amount, or (for `COMPLETE_OBJECTIVE`) the objective's index.

> **EffectType enum order** (so the `.tres` integer matches if you edit by hand):
> `SET_FLAG=0, CLEAR_FLAG=1, GIVE_ITEM=2, TAKE_ITEM=3, ADD_REPUTATION=4,`
> `ADD_MONEY=5, START_QUEST=6, COMPLETE_OBJECTIVE=7, COMPLETE_QUEST=8`.

Drop a list of these into a choice's **effects** (applied in order the instant
the player picks it) or into a DialogueResource's **on_enter_effects** (applied
once, automatically, the first time that node is shown — handy for "you met
Marlo" flags or a reward just for reaching a line). On-enter effects fire ONCE
per node per conversation; re-displaying the same lines won't re-apply them.

### DialogueCondition — gating a choice

Right-click → **New Resource…** → **DialogueCondition**. Set:

- **type** — the test (see list below).
- **target** — flag name / item id / npc id / quest id.
- **amount** — minimum item count (`HAS_ITEM`) or minimum reputation
  (`MIN_REPUTATION`). Ignored by the other types.

> **ConditionType enum order**: `FLAG_SET=0, FLAG_NOT_SET=1, HAS_ITEM=2,`
> `MIN_REPUTATION=3, QUEST_ACTIVE=4, QUEST_COMPLETED=5, QUEST_NOT_STARTED=6`.

Put a list into a choice's **conditions**. ALL must pass for the button to show.
A choice with an empty `conditions` list is always shown. If a node's last line
has choices but NONE of them currently pass their conditions, the conversation
simply ends on accept — no soft-lock.

### Reputation

`Reputation` is an autoload that tracks one number per NPC, keyed by the NPC's
`npc_id` (the `npc_id` field you set on the NPC scene, e.g. `marlo`). Scores are
clamped to `[-100, 100]` and bucketed into tiers:

> **Tier thresholds**: `<= -50` HOSTILE, `-49..-15` DISLIKED, `-14..14` NEUTRAL,
> `15..49` FRIENDLY, `>= 50` BELOVED. (`Tier` enum order:
> `HOSTILE=0, DISLIKED=1, NEUTRAL=2, FRIENDLY=3, BELOVED=4`.)

You change reputation with an `ADD_REPUTATION` effect (target = npc id, amount =
delta, negative to anger them) and read it with a `MIN_REPUTATION` condition
(target = npc id, amount = threshold). That's the whole loop: be nice in a choice
(+rep effect), and a friendlier-only choice unlocks once the score clears the
threshold. From code you can also call `Reputation.get_reputation(&"marlo")`,
`Reputation.add_reputation(&"marlo", 5)`, or `Reputation.get_tier_name(&"marlo")`.

### Worked example: Marlo's quest intro

`entities/npc/dialogue/marlo_quest_intro.tres` is the shipped reference. Its last
line offers three choices:

- **"I'll get your ore."** — no conditions (always shown). Effects: `START_QUEST`
  `marlo_first_delivery`, then `ADD_REPUTATION` `marlo` +5. Branches to
  `marlo_accepted.tres`.
- **"Do it yourself."** — no conditions. Effect: `ADD_REPUTATION` `marlo` -10.
  Branches to `marlo_rebuffed.tres`.
- **"Got a minute, friend?"** — condition `MIN_REPUTATION` `marlo` 15 (FRIENDLY+),
  so it only appears once Marlo likes you. Branches to `marlo_friendly.tres`.

To wire dialogue onto an NPC: set the NPC scene's `npc_id` (for reputation) and
drag the entry DialogueResource into its `dialogue` slot. No scripting needed.

---

## 8. Adding a Quest

Quests are data too, and they auto-load exactly like items. A quest is made of
two resource types:

- **QuestObjective** (`global/quests/quest_objective.gd`) — one goal. A TEMPLATE:
  it stores no progress (that lives in `QuestSystem`), so the same objective file
  can be shared.
- **Quest** (`global/quests/quest.gd`) — the whole quest: an `id`, `title`,
  `description`, a list of `objectives`, and a list of `rewards` (which are just
  **DialogueEffect** resources, applied when the quest completes).

### Steps

1. Right-click `global/quests/resources/` → **New Resource…** → **Quest** → save
   as e.g. `marlo_first_delivery.tres`. The `QuestSystem` autoload scans this
   folder at startup and registers every quest by its `id` — drop a new `.tres`
   in and it "just works", no code edits.
2. Fill in the Quest fields:
   - **id** — a unique `StringName` (no `&`), e.g. `marlo_first_delivery`. This is
     the permanent key used by `START_QUEST`/`COMPLETE_QUEST` effects, conditions,
     and save files. **Never change it once a save references it.**
   - **title** / **description** — shown in the quest log.
3. Add **objectives**: for each, create a **QuestObjective** sub-resource and set:
   - **description** — the quest-log line, e.g. "Bring Marlo 2 iron ore".
   - **kind** — `COLLECT_ITEM` or `REACH_FLAG` (enum order: `COLLECT_ITEM=0,`
     `REACH_FLAG=1`).
   - **target** — for `COLLECT_ITEM`, an item id (must exist in the item
     database, e.g. `iron_ore`); for `REACH_FLAG`, a GameState flag name.
   - **required_count** — how many for `COLLECT_ITEM` (ignored by `REACH_FLAG`).
4. Add **rewards**: a list of **DialogueEffect** resources (see section 7),
   applied in order when the quest finishes — e.g. `ADD_MONEY` 50 and
   `ADD_REPUTATION` `marlo` +10.

### How quests run (for reference)

- **Starting**: a `START_QUEST` effect (or `QuestSystem.start_quest(id)`) marks it
  ACTIVE and immediately evaluates `COLLECT_ITEM` objectives against the bag — so
  if you already hold the items, it can complete instantly.
- **COLLECT_ITEM** objectives update themselves: `QuestSystem` listens to
  `Inventory.item_changed` and re-checks progress whenever your bag changes.
- **REACH_FLAG** objectives are finished "manually" with a `COMPLETE_OBJECTIVE`
  effect (its `amount` is the objective's index in the list, starting at 0).
- When every objective is satisfied the quest auto-completes, its rewards apply,
  and `quest_completed` fires. You can also force completion with a
  `COMPLETE_QUEST` effect.

### The quest log

Press **J** (the `quest_log` action) to toggle the quest log overlay. It's
read-only and non-blocking (it does NOT free the mouse or pause), and it rebuilds
live as quests start, update, and complete. Active quests show their title,
description, and each objective as `[x] done` or `[ ] desc (progress/required)`.
There's nothing to wire up — `QuestLog` is an autoload.

---

## 9. Crafting & Brewing (the brew kettle)

Brewing turns ingredients into drinks over GAME time. Like everything else here
it's data-driven: you author recipes as `.tres` files and drop a pre-built
machine scene into a level — no scripting. The logic lives in the
`CraftingSystem` autoload; the menu lives in the `BrewingUI` autoload.

### How a brew works (the 30-second tour)

- A **Recipe** says: these inputs → this output, and it takes N **game minutes**.
- A **BrewingMachine** is a physical box you place in a scene. You walk up, press
  **interact** (E), and the `BrewingUI` opens bound to that machine.
- Pick a recipe and press **Brew**. The inputs leave your inventory immediately
  and the machine starts brewing.
- Brewing is **time-based off the Clock**, not a real-time countdown. The system
  records the game-minute the brew started and compares it to the current Clock
  time. That means a brew keeps progressing correctly even if you walk away and
  the machine's scene gets unloaded — the state lives in the `CraftingSystem`
  autoload, keyed by the machine's id, so it **survives scene changes** and saves.
- When enough game time has elapsed the machine flips to DONE (and its mesh
  glows). Walk back, press **interact**, and **Collect** to get the output.

### Adding a Recipe

1. Right-click `global/crafting/recipes/` → **New Resource…** → **Recipe** →
   save as e.g. `ember_ale.tres`. The `CraftingSystem` autoload scans this folder
   at startup and registers every recipe by its `id` — drop a new `.tres` in and
   it "just works", no code edits (same pattern as items and quests).
2. Fill in the Recipe fields in the Inspector:
   - **id** — a unique `StringName` (type it WITHOUT the `&`), e.g.
     `ember_ale_recipe`. Permanent key used in per-machine state and saves.
     **Never change it once a save references it.**
   - **display_name** — shown in the brewing menu, e.g. `Ember Ale`. Safe to
     change anytime.
   - **inputs** — the required ingredients. Expand the array, add an element for
     each input line; each element becomes a **RecipeIngredient** you fill in
     right there:
     - **item_id** — the input's item id (must exist in the item database, e.g.
       `lava_ash`, `lava_vial`).
     - **count** — how many of that item the brew consumes.
   - **output_id** — the item id produced (must exist as an **Item** `.tres` in
     `global/items/resources/`, e.g. `molten_mocha`, `ember_ale`).
   - **output_count** — how many of the output a single brew yields.
   - **brew_minutes** — how long the brew takes, in **GAME minutes** (not real
     seconds). The Clock advances over real time, so e.g. 30 game-minutes is a
     short wait, not 30 real minutes.
   - **machine_type** — which machine runs it. Only `BREWER` exists for now
     (enum order: `BREWER=0`).

   Shipped examples to copy: `global/crafting/recipes/molten_mocha.tres`
   (2x lava_ash + 1x lava_vial → 1 molten_mocha, 30 min) and
   `global/crafting/recipes/ember_ale.tres` (3x lava_ash → 1 ember_ale, 45 min).

### Placing a brewing machine

1. Drop `entities/machines/brewing_machine.tscn` into your level scene (drag it
   from the FileSystem dock into the scene tree, or instance it as a child).
2. Select the placed instance and set its exported fields in the Inspector:
   - **machine_id** — a unique `StringName` (type it WITHOUT the `&`), e.g.
     `shop_brewer_1`. **This MUST be unique per placed machine.** The
     `CraftingSystem` tracks each machine's brewing state by this id, so two
     machines that share an id would share (and clobber) one brew. Leaving it
     empty logs a warning and brewing won't persist.
   - **machine_type** — which recipes show up here. Leave on `BREWER`.
   - **display_name** — the name shown in the prompt and menu, e.g. `Brew Kettle`.
3. That's it. The machine registers itself with the `CraftingSystem` on `_ready`,
   shows a status-aware prompt (`Use Brew Kettle` / `Brew Kettle (brewing 60%)` /
   `Collect Mocha`), and opens the `BrewingUI` when you interact. While the
   menu is open the player stops moving and the mouse is freed, just like the
   inventory and dialogue.

### Brewing time & persistence (for reference)

- Progress is computed from the Clock: `elapsed = now - start`, where game-time is
  `((GameState.day - 1) * 1440) + (Clock.hour * 60) + Clock.minute`. There is no
  real-time countdown, so brews stay correct across scene loads and save/restore.
- The `CraftingSystem` ticks lightly each frame: any brew whose time has elapsed
  flips to DONE and emits `machine_changed` once, so machine visuals and any open
  menu react without polling.
- Per-machine brewing state is captured by `CraftingSystem.capture_state()` and
  restored by `restore_state()`, so an in-progress brew survives a save/load.

---

## 10. Shops & Economy (buying and selling)

A shop closes the money loop: the player BREWS drinks, SELLS them to a
shopkeeper for cash, then BUYS ingredients and upgrades. Like everything else
here it's data-driven — you author one `.tres` per storefront and drop a
pre-built shopkeeper scene into a level. The pricing/transaction logic lives in
the `ShopSystem` autoload; the buy/sell menu lives in the `ShopUI` autoload.

### How a shop works (the 30-second tour)

- A **ShopInventory** (`.tres`) describes ONE storefront: what it sells to the
  player, what it buys from the player, and its price markups. It has infinite
  stock — buying never depletes it — and it holds no money of its own (the
  player's cash lives in `GameState`).
- A **Shopkeeper** is an NPC you place in a scene. You walk up, press
  **interact** (E), and the `ShopUI` opens bound to that keeper's shop.
- The shop UI shows a **Buy** column (one row per item the shop sells, each with
  its price and a Buy button that's only enabled when you can afford it) and a
  **Sell** column (one row per item you're holding that this shop buys, with the
  count you hold and a Sell button). Press **Esc** (`ui_cancel`) to close.
- While the menu is open the player stops moving and the mouse is freed, just
  like the inventory, brewing, and dialogue menus.

### Adding a ShopInventory (the storefront)

1. Right-click `global/shop/shops/` → **New Resource…** → **ShopInventory** →
   save as e.g. `ore_trader.tres`. (Unlike items/quests/recipes there is no
   folder auto-scan — a shop is assigned directly to a shopkeeper in a scene, so
   you can keep these anywhere, but `global/shop/shops/` is the home folder.)
2. Fill in the fields in the Inspector:
   - **shop_id** — a unique `StringName` (type it WITHOUT the `&`), e.g.
     `ore_trader`. Used in the `transaction` signal and any bookkeeping.
   - **display_name** — shown at the top of the shop UI, e.g. `Ore Trader`.
     Safe to change anytime.
   - **stock** — the item ids this shop SELLS to the player (infinite quantity).
     Expand the array and add ids that exist in the item database, e.g.
     `lava_ash`, `lava_vial`. Leave empty for a shop that only buys.
   - **buy_markup** — price multiplier when the player BUYS. The player pays
     `max(round(base_value * buy_markup), 1)`. `1.25` means a 25% markup.
   - **sell_markup** — price multiplier when the player SELLS. The player
     receives `max(round(base_value * sell_markup), 1)`. `0.5` means the shop
     pays half of base value (it profits on the spread).
   - **buys_all** — if `true`, the shop buys ANY item with `base_value > 0` (a
     general fence). When `true`, `buy_categories` is ignored.
   - **buy_categories** — the `Item.Category` ints this shop buys from the
     player (only used when `buys_all` is false). Add the integer for each
     category: `INGREDIENT=0, DRINK=1, TOOL=2, MATERIAL=3, MISC=4`. Example:
     `[1]` to buy finished drinks only; `[0, 3]` to buy ingredients + materials.
   - **reputation_npc** — optional `npc_id` whose reputation tweaks prices (see
     "How reputation affects prices" below). Leave empty for fixed prices.

   Shipped examples to copy: `global/shop/shops/general_store.tres` (sells
   `lava_ash` + `lava_vial`, buys ingredients + materials, no reputation) and
   `global/shop/shops/lava_tap.tres` (a bar that sells nothing, buys DRINKs at a
   generous `0.85` markup, prices flex with reputation toward `marlo`).

### Placing a shopkeeper

1. Drop `entities/npc/shopkeeper.tscn` into your level scene (drag it from the
   FileSystem dock into the scene tree, or instance it as a child).
2. Select the placed instance and set its exported fields in the Inspector:
   - **npc_name** — the keeper's name, used in the prompt (`Shop with Gus`).
   - **npc_id** — a stable `StringName` (no `&`). Needed if any shop or dialogue
     references this keeper's reputation; safe to leave empty otherwise.
   - **shop** — drag your **ShopInventory** `.tres` into this slot. If you leave
     it empty the keeper logs a warning on interact and won't open a shop.
3. That's it. The shopkeeper extends the regular **NPC**, so it stands in the
   world and turns to face the player; pressing **interact** opens the `ShopUI`
   bound to its `shop` instead of starting a dialogue.

> A shopkeeper is just an `NPC` subclass (`entities/npc/shopkeeper.gd`). It
> reuses the NPC capsule body and `_face_toward` helper; only `interact()` and
> the prompt are overridden. You don't give it a `dialogue` resource.

### How reputation affects prices

If a shop sets **reputation_npc**, prices flex with how that NPC feels about the
player (the same score you change with `ADD_REPUTATION` effects — see section 7):

- Reputation is read with `Reputation.get_reputation(npc_id)` and normalised to
  `-1..1` (so `+100` rep = `+1.0`, `-100` = `-1.0`).
- `ShopSystem.REP_PRICE_SWING` (`0.2`) caps how far prices move: up to **±20%**.
- Higher rep makes buying **cheaper** (buy factor `1 - rep_norm * 0.2`) and
  selling **more profitable** (sell factor `1 + rep_norm * 0.2`). So a beloved
  shopkeeper sells to you for 20% less and buys from you for 20% more; a hostile
  one does the opposite. Leaving `reputation_npc` empty keeps prices fixed.

This means the loop rewards being nice: do a shopkeeper's quests / pick the
friendly dialogue choices, your reputation rises, and their shop gives you
better rates automatically — no extra wiring.

---

## 11. Living NPCs: animated bodies, schedules, and AI states

The base `entities/npc/npc.tscn` already includes an animated rigged body (`Animator`), a
navigation agent (`NavAgent`), and a built-in behaviour state machine. So a plain NPC instance
already walks, animates, and talks — you just feed it data.

### Give an NPC a daily routine (schedule)

A routine is an `NPCSchedule` resource: a list of `ScheduleEntry` lines, each "at HH:MM, go to
*location* and do *activity*". The NPC follows whichever entry is currently in effect (it wraps past
midnight), driven by the in-game `Clock`.

1. **Place locations.** In the scene, add `Marker3D` nodes, attach `entities/npc/world_location.gd`,
   and give each a unique `location_id` (e.g. `&"home"`, `&"market"`, `&"grove"`). (Or add a node and
   set its script to `WorldLocation`.) Locations are per-scene — an NPC only finds markers in the
   scene it's in.
2. **Author the schedule.** Right-click in FileSystem → New Resource → `NPCSchedule`. Add
   `ScheduleEntry` items; for each set `hour`/`minute`, the `location_id` to walk to, and the
   `activity` to start on arrival. Valid activities are the registered state names: `&"Idle"`,
   `&"Work"`, `&"Sleep"` (and `&"Wander"`, though Wander roams the spawn point, not the destination).
   Leave `location_id` empty to just change activity in place.
3. **Assign it.** Drop the schedule `.tres` into the NPC instance's `schedule` slot.

Worked example: `entities/npc/schedule/sela_schedule.tres` (home → market → grove → market → sleep).

### A navmesh is needed for real pathfinding

NPCs walk the navmesh when a scene has a `NavigationRegion3D` with a baked navmesh; **without one they
fall back to walking in a straight line** (no obstacle avoidance) so they still move. `town_square`,
`shop-interior`, and `bar-inside` are already baked (each `NavigationRegion3D` references a
`*_nav.res` next to its scene; the bar's region lives inside its SubViewport).

**To (re)bake** after editing a level's geometry: this project bakes navmeshes offline with a small tool,
`tools/bake_navmeshes.tscn`, because the level geometry isn't parented under the `NavigationRegion3D`
(so the editor's in-place "Bake NavMesh" button won't pick it up). Add a `CONFIG` entry for your scene
in `tools/bake_navmeshes.gd` (scene path, the node to parse from, an optional bounding box, and the
output `.res` path), then run it headless:
`Godot --headless --path . res://tools/bake_navmeshes.tscn --quit-after 600` and point your
`NavigationRegion3D.navigation_mesh` at the saved `.res`. (For a brand-new simple flat room you can
instead hand-author a `NavigationMesh` quad like `npc_demo.tscn` does.)

### Free-roaming idle NPCs

For an NPC that should mill about instead of standing when it has no schedule, tick
`wander_when_idle` on the instance and set `wander_radius` / `wander_pause`.

### A different look (model + skin)

The `Animator` child (`NPCAnimator`) builds the body. Swap `model_scene` for another Kenney base
character (`assets/models/characters/animated-characters/Models/`), and optionally set `skin_texture`
to one of `.../Skins/*.png` to recolor. Leave `model_scene` empty to fall back to the placeholder
capsule. Animations (`idle`/`walk`/`run`/`interact`) are loaded automatically from the kit.

### A custom behaviour (new AI state)

States live in `entities/npc/ai/states/` as small `NPCState` subclasses (`enter`/`exit`/
`physics_update`, driving the NPC via `npc.set_destination/nav_step/stop/play_anim/face_toward`).
To add one: write the subclass, then make an `NPC` subclass that overrides `_register_states()`
(call `super()` first) and registers it under a name — that name is then usable as a schedule
`activity` or a `transition_to` target.

### Try it

`stages/overworld/npc_demo/npc_demo.tscn` is a complete playable slice: a navmesh, the three
location markers, scheduled **Sela**, three coconut pickups, and the player. Open it and press Play
to walk up, talk to Sela, take her quest, grab the coconuts, and turn them in.

---

## 12. Combat: weapons, consumables, enemies (see also `docs/combat.md`)

Combat flows through `HitBox → HurtBox → Health` with `DamageInfo` (element) and
weakness/resistance multipliers; teams (PLAYER/ENEMY) prevent friendly fire. The
player uses the selected hotbar item on left-click via `item.use(player)`.

- **A weapon**: new `.tres` of `MeleeWeaponItem` or `RangedWeaponItem`
  (`entities/items/weapons/`), `category = 6` (WEAPON). Set damage / `damage_type` /
  range or `projectile_scene` / cooldown. A bow points at `arrow.tscn`.
- **A consumable** (potion/bomb/grenade): new `.tres` of a `ConsumableItem` subclass
  (`entities/items/consumables/`), `category = 7` (CONSUMABLE). It consumes one on use.
- **An enemy**: new `EnemyStats` `.tres` (HP, speed, damage, element, ranges, cooldown,
  `attack_windup` for the normal-attack telegraph, `damage_multipliers` for weak/resist,
  loot) + an inherited scene of `enemy.tscn`; set its `Animator` `model_scene`/`skin_texture`
  for the look. Place by instancing the scene. (`enemy.tscn` already carries the `HurtBox`
  the player's weapons hit — see "smashable" below for the general rule.)
- **Make something smashable**: give it a `Health` + a `HurtBox` (team ENEMY) — see
  `Breakable` (`components/interactables/`). Player weapons (target ENEMY) will damage it.

## 13. Interactables, dungeons & minigames

- **Chest / Door / Lever / Breakable** (`components/interactables/`): duck-typed
  interactables. A `Chest` grants a `LootTable` (`LootEntry` rows of item id + min/max);
  a `Door` can need a `required_key` (item id); a `Lever` calls a target's `open()`.
- **A dungeon**: copy `stages/dungeons/dungeon_caverns.tscn` — greybox geometry (with
  StaticBody colliders), a player at the entrance, enemies instanced by path, chests +
  breakables + a locked door & key, `Marker3D`s in group **`respawn_point`**, and a
  `teleport_raycast` exit. Add an entrance to it from the overworld with another
  `teleport_raycast` (`target_scene_path` = the dungeon's uid). Reuse existing item ids for loot.
- **A minigame**: a `CanvasLayer` scene whose root extends `Minigame` and emits
  `finished(score, reward)` (`ui/minigames/`). Launch it from an `ArcadeCabinet`
  (`entities/props/arcade_cabinet.tscn`, set its `minigame_scene`) — `MinigameManager`
  pauses the world, then pays `reward` money on finish.

---

## Cheat sheet

| I want to add a…        | Do this                                                        |
|-------------------------|----------------------------------------------------------------|
| Ingredient / material   | New **Item** `.tres` in `global/items/resources/`              |
| Tool / weapon           | New **ToolItem** `.tres` in `global/items/resources/`          |
| Rock / plant / lava node| New Inherited Scene from `harvestable.tscn`, set exports + mesh|
| Critter                 | Duplicate `critter.tscn` (keeps its `Health` + `HurtBox`), tune exports + `Health.max_health` |
| Hand-placed pickup      | Instance `world_item.tscn`, set `item_id` + `amount`           |
| Quest                   | New **Quest** `.tres` in `global/quests/resources/` (+ objectives + rewards) |
| Brewing recipe          | New **Recipe** `.tres` in `global/crafting/recipes/` (+ inputs + output + brew_minutes) |
| Brewing machine         | Drop `entities/machines/brewing_machine.tscn` into a scene, set a UNIQUE `machine_id` |
| Shop (storefront)       | New **ShopInventory** `.tres` in `global/shop/shops/` (stock + markups + buy_categories) |
| Shopkeeper              | Drop `entities/npc/shopkeeper.tscn` into a scene, set `npc_name` + assign a `shop` |
| Dialogue consequence    | New **DialogueEffect** `.tres`, drop into a choice's `effects` or a node's `on_enter_effects` |
| Gated dialogue choice   | New **DialogueCondition** `.tres`, drop into a choice's `conditions` |
| Change how an NPC feels | `ADD_REPUTATION` effect (target = npc_id, amount = delta)      |
| Talking NPC             | Instance `entities/npc/npc.tscn`, set `npc_name`/`npc_id`, assign a `DialogueResource` |
| NPC daily routine       | New **NPCSchedule** `.tres` (ScheduleEntry rows) + `WorldLocation` markers in the scene; assign to the NPC's `schedule` |
| Place a walkable area   | `NavigationRegion3D` + a `NavigationMesh`; (re)bake via `tools/bake_navmeshes.tscn` (add a CONFIG entry), else NPCs walk straight lines |
| Place a shopkeeper in a room | Instance `entities/npc/shopkeeper.tscn` (now animated), set `npc_name`/`npc_id` + a `shop`; e.g. Gus in `shop-interior` |
| New NPC AI behaviour    | `NPCState` subclass in `entities/npc/ai/states/`, registered via an `NPC` subclass `_register_states()` |
| Change an NPC's look     | On the NPC's `Animator`, swap `model_scene` (kit base char) / set `skin_texture` |
| Melee/ranged weapon     | New **MeleeWeaponItem** / **RangedWeaponItem** `.tres` in `global/items/resources/` (category 6) |
| Consumable (potion/bomb)| New **ConsumableItem** subclass `.tres` in `global/items/resources/` (category 7) |
| Enemy / monster         | New **EnemyStats** `.tres` + inherited scene of `enemy.tscn`; set Animator model/skin |
| Smashable object        | Give it `Health` + a `HurtBox` (team ENEMY) — see `Breakable` |
| Chest / loot container  | Instance `entities/props/chest.tscn`, set a unique `chest_id` + a `LootTable` |
| Locked door + key       | `Door` with `required_key` (an item id) + a `Lever` or a key item in a chest |
| Dungeon                 | Copy `stages/dungeons/dungeon_caverns.tscn`; add a `teleport_raycast` entrance from town |
| Minigame                | `CanvasLayer` extending `Minigame` (emit `finished`) + an `ArcadeCabinet` to launch it |
| Respawn point           | A `Marker3D` (or any Node3D) added to the **`respawn_point`** group in the scene |

Remember: the **id** on an item is permanent. Pick it carefully and never rename
it once it's in a save.
