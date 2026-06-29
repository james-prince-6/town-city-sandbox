# Game Design Document — *Town City* (working title)

> **Status:** Living draft · Last structured: 2026-06-28 (reconciled against working prototype)
> **Genre:** Story-driven Action RPG with tycoon elements and skill-based mini-games
> **Engine:** Godot · **Repo:** `james-prince-6/town-city-sandbox`
> **Full creative vision:** see `docs/design/WORLD_BIBLE.md` (cast, businesses, world). This GDD stays the lean v1 target.

## How to read this document

This GDD organizes the ideas you've already written down and gives every part of the
game a home. It does **not** invent story, characters, or creative content — those are
yours. Where something hasn't been decided yet, you'll see one of these markers:

- **▶ DECIDE:** a concrete question for you to answer. Fill the answer in below it.
- **▶ EXPAND:** an idea you've already had that needs more detail from you.
- *Italic placeholder text* — a slot waiting for your content.

Everything **not** in italics or a marker is either your existing material (reorganized)
or structural/framework suggestions you can keep or cut. When you fill a marker in,
delete the marker.

## Decisions locked — 2026-06-26

The foundational design questions are now answered. Details live in their sections; this is
the quick reference.

| Area | Decision |
|---|---|
| Non-negotiable pillars | Wacky characterful world · Combat feels good (FP) · A town worth knowing |
| Pillar allowed to be thin in v1 | Meaningful alternative play (ship **one** solid mini-game, not many) |
| World shape | A small region — the town plus a few connected outlying areas |
| Leveling | Use-based (Skyrim-style): skills improve through use |
| Tycoon / base-building | A single shop/workshop the player upgrades over time |
| "Survive" | Flavor only — no hunger/needs systems |
| Dialog tech | **Dialogue Manager** Godot plugin (code-based, customizable) |
| Pixel/PS2 look | Low internal resolution, upscaled |
| Art-style rule | 3D base; other styles (2D, 8-bit) used as deliberate "special" moments/gags |
| Platform | PC, with controller support from the start |
| v1 size | Short game, ~1–2 hours |
| World/people naming | **Townsfolk** (residents) · **Out-of-towners** (visitors) — island flavor dropped |
| Player character | Silent · fixed appearance · player-named |

---

## Prototype status — 2026-06-28

A working **prototype already exists** and implements most systems below end-to-end: combat,
crafting, economy, shop, custom dialog, quests, save/load, a town + outlying areas, dungeons, and
two mini-games. It has been audited and is playable start-to-finish. Build-level detail lives in
the prototype's own `docs/` (ARCHITECTURE, combat, dialogue_conversations, ADDED_ASSETS, AUDIT,
PLAYTEST_CHECKLIST) — this GDD does not duplicate it.

**This GDD stays the lean v1 *target*, not a description of the prototype.** The prototype
explored wide; several built features sit **beyond v1 scope** and are parked (not cancelled) in
the ROADMAP backlog:

- **Extra dungeon themes** — v1 *keeps* the procedural dungeon system (runs stay fresh) but ships **one** distinct theme; the other themes are parked.
- **More than one mini-game** — v1 ships one polished (§5.4).
- **Player-house upgrade system** beyond the single shop/workshop (§5.5).
- **Extra wild biomes** — v1 ships **one** outlying wild area; the others (Woods/Hills/Meadow/Barrens) are parked (§2).

**~~Known divergence~~ RESOLVED (2026-06-28):** leveling was reworked from XP + a skill tree to
**use-based** (Skyrim-style), matching the design intent (§5.2). Four skills (Melee/Ranged/Magic/
Survival) rise by use; perk points from leveling buy each skill's perks.

Sections below marked **▶ built** are already satisfied by the prototype; the remaining
**▶ DECIDE / ▶ EXPAND** markers are still genuinely open creative calls that are yours.

---

## 1. Vision & Pillars

### 1.1 One-line pitch
> You've just moved into a new city, and things are done a bit differently here.
> Explore, craft, survive, and meet the villagers in this wacky world.

### 1.2 Elevator description (your words)
A zany, story-driven action RPG with tycoon elements and skill-based mini-games. Core
combat plays like *Oblivion*/*Skyrim* (first-person, swords/bows/spells/throwables) wrapped
around a deep town-life RPG of crafting, jobs, and eccentric characters.

### 1.3 Design pillars
The four pillars, in priority order. **Non-negotiable:** 1, 2, and 4 — protect these even when
cutting scope. **Allowed to be thin in v1:** pillar 3 (ship one solid mini-game rather than
many — see §9).

1. **Wacky, characterful world.** *(non-negotiable)* Eclectic art, funny characters,
   *Smiling Friends*-style tonal freedom. Personality over realism.
2. **Combat that feels good first-person.** *(non-negotiable)* Skyrim-like melee/ranged/magic
   that's satisfying on its own, not just a backdrop.
3. **Meaningful alternative play.** *(thin in v1)* Jobs and mini-games each have real
   progression — the player *wants* to step away from combat to do them. The full vision is
   many; v1 ships one done well.
4. **A town worth knowing.** *(non-negotiable)* Characters, dialog, and branching quests make
   the place feel alive.

### 1.4 Player fantasy
The player should feel like an unsung hero whos landed in a strange land, getting involved with the lives of the villagers, and helping improve their lives through crafting, combat, jobs, and quests.

---

## 2. Setting & World

### 2.1 Town City
> A modest village full of crazy characters.

**Decided:** the game is set in **a small region** — the town itself plus a few connected
outlying areas (which gives you natural space for combat zones outside town).

**▶ built (world shape):** the prototype has a central **town** plus outlying **wild areas** and
**dungeons** — matching "town + a few connected outlying areas." For v1 keep the count tight: the
town, **1–2** outlying combat areas, and one small dungeon. (The four wild biomes + procedural
roguelike are parked beyond v1 — see Prototype status.)

**▶ EXPAND (still yours):**
- The in-world reason "things are done a bit differently here."
- Which town districts/landmarks matter for v1 (where the cast and the shop sit).

**Decided (naming):** residents are **Townsfolk**; visitors/outsiders are **Out-of-towners**.
The island framing is dropped — it's a land-locked region. Use these two terms consistently in
all writing (§3.2, §3.3).

### 2.2 World map / locations
**▶ built (prototype):** Town hub with interiors (general store, bar), reachable wild areas, and
dungeons. **v1 target subset** — keep to roughly:

| Location | Purpose | Notes |
|---|---|---|
| Town | social / vendor / quest hub | the cast lives here; the shop/workshop is here (§5.5) |
| 1–2 outlying areas | combat / gather | the "wild" combat zones (§5.1) |
| 1 dungeon | combat set-piece | hand-built for v1; procedural system parked |

*Add named landmarks as you write; everything past this subset is parked (Prototype status).*

**Full place list** — the businesses (Kippie Arcade, The Flaming Pebble, Bedrock Bank, Astros
Fishing Friends, George's General Store, Keep It Real-estate, …) and town facilities (Town Hall,
Adventurers Guild, Magic Council, Library, Bike Shop, …) live in `docs/design/WORLD_BIBLE.md` §6–7. v1
draws a small subset from them.

### 2.3 Tone & rules of the world
**▶ EXPAND:** *Smiling Friends* / *Everhood* / *Undertale* imply a world that can be absurd,
dark-comic, and sincere in turns. Note any hard tonal rules (e.g. "comedy can get crude but
the heart is sincere," or "no fourth-wall breaks"). This keeps writing consistent.

---

## 3. Characters

### 3.1 The Player
> Intentionally blank backstory. New to the town.

This is a deliberate design choice (player as audience surrogate). Worth noting the
implications so they're intentional:
- Blank backstory → the *town* must carry the story's color, since the player won't.
**Decided (player identity):**
- **Silent protagonist** — no voiced/written player lines. Keeps the blank-surrogate design and
  cuts writing/VO cost.
- **Fixed appearance** — one defined look, so the player can be framed reliably in the
  "mini-cutscene" dialogs (§6.3).
- **Player-named** — the player enters a name at the start. Dialogue Manager can interpolate it
  into NPC text lines (§6.1); since there's no VO, NPCs spoken-naming the player isn't a problem.

### 3.2 Townsfolk (residents)
*Placeholder — your roster of town characters.* Suggested fields per character so they slot
straight into dialog/quest work later:

| Field | Notes |
|---|---|
| Name | |
| Role in town | vendor, quest-giver, rival, etc. |
| Personality / voice | one line so writing stays consistent |
| Default art treatment | 3D base; note if this character is a deliberate 2D/8-bit "special" (§7) |
| Quests they give | links to §5 |
| Schedule/location | where the player finds them |

**Canonical cast lives in `docs/design/WORLD_BIBLE.md` §8.** As of 2026-06-28 the real, named roster is
defined there — Orbo Orland (Mayor), Stella Flandano (fashion designer), Barry Barnson (bar/chef),
Droghnaut (alien fisherman), Samantha Field (librarian), Kippie Kip (arcade), Bo Bossman (tycoon),
Sally Steelfield & Al Firestorm (adventurers), Xavier (wizard), Fredward (frog being), and more.

**Prototype placeholders (Gus, Mira, Marlo, Sela, Pip, Ember) have been migrated** (done
2026-06-28): Gus → **George Coral**; Mira/Marlo/Sela/Pip/Ember retired and parked on disk; the v1
cast added as new NPCs, each with its own `.dialogue` file (see WORLD_BIBLE "Prototype cast
migration").

**▶ DECIDE (James):** which ~4–6 of the canonical cast are the **v1 speaking roster** (WORLD_BIBLE
"v1 subset"). A small, memorable cast still beats a big one for the ~1–2 hour slice.

### 3.3 Out-of-towners (visitors)
**Defined:** out-of-towners are outsiders on their own agenda, distinct from the resident Townsfolk.
The anchor is **Han de Seciro** (WORLD_BIBLE §8) — a mysterious man whose hidden purpose (reveal: he's the **crown prince** of his kingdom, sent
to retrieve a power from the **hell gate** — and, unknowingly, after the **Balrog's heart**; see
WORLD_BIBLE §8–9) is a natural main-story thread. **Fredward**,
the reclusive ancient frog being, is a related outsider-of-the-land figure.

**▶ EXPAND (still yours):** how many out-of-towners v1 needs and how Han's thread connects to the
main story (§4.1).

---

## 4. Story

> Main story to be determined.

This is intentionally open, which is fine — the systems below don't depend on the main plot
being finished. Structuring the *kinds* of story content so you can write into them:

### 4.1 Main story
**v1 spine (designed):** the full main plot is still parked, but **v1 ships a self-contained story
arc** — *"Help the Town"* — led by Mayor Orbo around a **town-in-a-slump** premise that climaxes in
the dungeon. Full beat-by-beat in **`docs/design/quests/help-the-town.md`**. It leaves hooks (Han de
Seciro, Fredward) for the larger plot without resolving it.

**▶ EXPAND:** the larger main story beyond v1 — central hook, act beats, ending — when you're ready.

### 4.2 Quests
Two quest types, in your words:
- **Gameplay-specific quests** — tied to systems (combat, crafting, jobs).
- **Character-specific quests** — tied to individual residents.

Your example quest seeds (kept verbatim — these set the tone perfectly):
> - "I need a yummy snack"
> - "I know where treasure is hidden, can you find it?"
> - "My wife is cheating on me, can you catch her?"
> - "Can you help me find my lost coin?"

**▶ EXPAND:** For the quests you want in the vertical slice (see ROADMAP), capture per quest:
giver, trigger, objective, which system(s) it exercises, reward, and any branches. A reusable
quest template is provided in `docs/design/templates/QUEST_TEMPLATE.md`.

### 4.3 Branching & dialog
You note dialogs are "like mini cutscenes" with emoting/expression (Skyrim-style), and that
branches/decisions "need to be mapped out and written." That writing is yours; the prototype's
**Dialogue Manager**-based system (see §6.1) already provides the branching/scripting
machinery, plus a cinematic-lite camera and per-line gestures.

---

## 5. Gameplay Systems

This is the heart of the build. Each system below is one of your ideas, restated and given a
checklist of the sub-decisions it needs. None of these add creative content — they're the
questions every one of these systems eventually forces.

### 5.1 Core combat (first-person ARPG)
Your spec: "kinda like Oblivion or Skyrim. First person combat, with swords and bows and
spells and stuff. Throwables etc."

Sub-decisions to lock as you prototype:
- **Weapon classes:** melee (swords), ranged (bows), magic (spells), throwables. Any others?
- **Feel:** real-time hit detection? stamina? blocking/parrying? dodging?
- **First-person specifics:** how do you read enemy attacks in FP? camera, hit feedback.
- **Enemies:** what does the player fight, and where? The outlying areas of the region (§2.1)
  are the natural home for combat encounters.
- **Input:** must feel good on **both** KB/M and controller (platform decision, §9).

**▶ built (prototype):** combat is implemented and audited — first-person melee (swords), bow,
crossbow, three wands (fire/frost/arcane), throwables (knives, bombs), with stamina, mana, status
effects, hit-feedback (hitstop/shake/damage numbers), and enemies (melee/ranged/casters, elites,
bosses). Remaining work is **feel/balance tuning**, not "does it exist." The "minimum fun
encounter" question is answered.

### 5.2 Leveling & builds
Your spec: "Leveling up improves various combat things, we should have many fun upgrades and
builds that users can make."

**Decided (intent):** **use-based progression** (Skyrim-style) — skills improve through use
(swing swords to get better with swords, cast to improve magic, etc.).

> **✅ Implemented (2026-06-28 — D1 rework).** The prototype now does use-based progression. FOUR
> skills — **Melee, Ranged, Magic, Survival** — rise as you USE them (swing/shoot/cast/endure hits);
> each level grants an auto passive (more damage / faster fire / more HP & resist) plus a **perk
> point** for that skill's tree, spent on its perks (cleave, piercing shot, lifesteal, mana surge…).
> Anti-grind: rising use-cost per level + every trained action spends stamina/mana. See
> `global/systems/progression.gd` (the combat-facing getters kept their old names, so combat was
> untouched). Tuning constants live at the top of that file and want a playtest pass.

- **▶ EXPAND:** "Fun upgrades and builds" — list the build fantasies you want to enable
  (e.g. a stealth-archer equivalent, a spell-throwing brawler). The specific builds are yours.
- *Design note:* use-based systems need anti-grind guardrails (so players don't, say, hit a
  wall to level a skill). Worth keeping in mind when you spec the skill list.

### 5.3 Crafting & progression
Your spec: "Lots of crafting and other progression."

**▶ built (prototype):** a full gather → refine → craft loop exists — mine/harvest with tools,
**smelt** at a smelter and **craft** at a workbench (plus brew kettle + cooking), across a tiered
material chain (copper → gold → crystal). Recipes are data files; gear, consumables, and materials
are all craftable. **▶ EXPAND (still yours):** which recipes matter for v1, and how recipes unlock
(bought vs. found vs. taught vs. leveled) — keep the v1 set small.

### 5.4 Jobs & mini-games
Your spec: "Lots of mini games / jobs you can do. Each should have a meaningful progression
system and make the player want to pursue alternative gameplay tasks." Skill-based, à la
*Stardew Valley*.

**Scope note:** this is the pillar that's *thin in v1* — ship **one** mini-game done really
well, not many (§9). Design the rest later. Use `docs/design/templates/MINIGAME_TEMPLATE.md` per game.

**▶ built (prototype):** two arcade mini-games exist (a whack game and a Simon game), launched
from an arcade cabinet, paying out money on finish; plus a notice-board **task** system. Per the
scope rule, **v1 still ships ONE** mini-game polished to the full bar (real skill + progression +
economy hook); the second is parked.

**Decided (2026-06-28):** the v1 mini-game is **Bartending at The Flaming Pebble** (Barry Barnson's
bar) — see §9.6. It's the one job built to the full bar: real skill (serving/mixing under pressure),
a progression curve, and an economy hook (wages → shop/upgrade money). The arcade and fishing exist
as light activities only in v1. **Designed:** the full loop — timed hold-to-fill pours, juggling a
customer queue, cleaning between orders, use-based skill + bar upgrades, soft failure — is specified
in **`docs/design/minigames/bartending.md`**.

### 5.5 Tycoon / production & selling
Your spec (from *Stardew* inspirations): "Production and selling of items," plus a
"base building system (most likely much smaller implementation)."

**Decided:** the small version is **a single shop/workshop the player upgrades over time** —
no free-form base building.

**▶ built (prototype):** a shop/economy is implemented (buy/sell, reputation-adjusted prices) and
there's a **player-house upgrade** system. **Scope flag:** the house-upgrade system is *richer*
than the single "shop/workshop you upgrade" v1 calls for — keep v1 to the single upgradable
workshop and park the broader house-building (Prototype status). **▶ EXPAND (still yours):** the
production → sell loop — what the workshop produces, who buys it, and how its upgrades change it.

### 5.6 Economy (cross-cutting)
**▶ built (prototype):** a single money currency is the source of truth (`GameState`), with shop
pricing off each item's base value and reputation-adjusted prices. **▶ DECIDE (still yours):** rough
price/cost tiers and the main money sinks (workshop upgrades are the obvious one) — a quick balance
pass, since the mechanism already exists.

### 5.7 Exploration & survival
**Decided:** "survive" is **flavor only** — no hunger/energy/needs systems. Exploration of the
region's outlying areas remains (ties to combat zones, §5.1). Keep this de-scoped so it doesn't
creep back in.

---

## 6. Narrative & Dialog Systems (technical support for §3–4)

Distinct from the *writing* (yours), these are the *mechanisms* the writing needs.

### 6.1 Dialog system
**▶ built (prototype):** dialog runs on **Nathan Hoad's Dialogue Manager** addon (`.dialogue`
script files), wrapped by a game-facing **`Dialogue`** autoload (`ui/dialog/dialogue.gd`) that adds
**cinematic-lite camera framing** and **per-line `[#gesture=…]`** gestures — so the §6.3
"mini-cutscene" feel is largely in. Branching choices, conditions/gates and consequences (item,
reputation, quest, flag, mood, time) are authored **inline** in each NPC's `.dialogue` file
(`if …` / `do …`). *(History: an earlier custom `DialogueResource` `.tres` system was replaced by
the addon — see `docs/ARCHITECTURE.md` §2–3 and `docs/dialogue_conversations.md`, now superseded.)*
The writing (the actual branches) is still yours.

### 6.2 Quest system
Needs to track: available/active/completed quests, objectives, branching outcomes, and rewards,
read from data files so quests are authored without touching code.
**▶ built (prototype):** a dedicated **`QuestSystem`** autoload exists — loads `Quest` `.tres`,
tracks active/completed, auto-progresses collect-item objectives, applies rewards, with a quest log
UI and a notice-board task variant. The "separate quest manager vs. dialogue state" question is
answered: it's a separate, data-driven system.

### 6.3 Cutscene / emote system
For the "mini cutscene" feel — camera framing, character animations/expressions triggered from
dialog. Hooks into Dialogue Manager events.

### 6.4 Save / load
RPG progression (level/skills, inventory, quest state, shop state, money) must persist. **▶ built
(prototype):** a binary `SaveManager` snapshots every stateful system, with 3 save slots and a main
menu (New / Continue / Load). Done, not deferred.

---

## 7. Art & Audio Direction

### 7.1 Visual style (your words)
- "Old PS2 style graphics, pixelated low res low poly things. Lower res screen to mimic pixel
  art in 3D." Reference: **Jet Set Radio**.
- Eclectic art styles — "a mix of 2D, 3D, 8-bit, etc" — *Smiling Friends* vibes.

### 7.2 Render & style rules (decided)
- **Pixel/PS2 look:** render the 3D world at a **low internal resolution and upscale** it —
  the authentic pixelated-3D look. Lock the exact internal resolution + point filtering in
  Milestone 0 so every asset is authored to match.
- **Style rule:** **3D is the base** for the playable world. Other styles (2D, 8-bit) appear
  as **deliberate "special" moments or gags** — a specific character, a mini-game, a cutaway —
  not as the default. This keeps "eclectic" intentional rather than inconsistent, and is very
  on-brand for the *Smiling Friends* influence.

### 7.3 Tools (your notes)
- **2D / pixel art:** GIMP or Aseprite.
- **3D models:** sourcing assets online; reference thread on tile-set tools:
  <https://www.reddit.com/r/gamemaker/comments/y7bzhj/need_recommendations_for_apps_to_design_tile_sets/>
- **▶ DECIDE:** 3D modeling tool if you author your own (Blender is the standard free option).

### 7.4 Audio (your words)
- "Cool and fun music."
- **▶ EXPAND:** music style references, whether you'll compose/source/commission, and SFX
  approach. Jet Set Radio's soundtrack is a strong tonal reference if you want one.

---

## 8. Inspirations (reference)

Kept from your notes, with the specific thing you're drawing from each — useful as a north
star when a design question comes up ("what would *Stardew* do?").

- **Stardew Valley** — skill-based mini-games; small base-building (your shop/workshop);
  production & selling of items.
- **Smiling Friends** — eclectic styles used with intent; tonal freedom to be absurd, crude,
  and sincere in the same breath. The "3D base, other styles as special moments" rule (§7.2) is
  the *Smiling Friends* influence made into a production rule.
- **Oblivion / Skyrim** — the first-person ARPG combat feel (melee/ranged/magic/throwables) and
  use-based, skill-improves-through-use progression (§5.1, §5.2).
- **Everhood / Undertale** — a world that can swing between absurd, dark-comic, and earnest;
  reference for the tonal range and for treating dialog as character-forward "mini cutscenes."
- **Jet Set Radio** — the visual north star for the pixelated low-poly PS2 look (§7.2), and a
  strong tonal reference for the soundtrack (§7.4).

---

## 9. Scope & Platform (v1)

The reference contract for what v1 actually is. When a feature is proposed, it gets measured
against this section. Everything here is locked (see the decisions table at the top).

### 9.1 Target platform
- **PC** is the v1 target.
- **Controller support from the start** — every system must feel good on **both** KB/M and
  controller, not have it bolted on later (ties to combat input, §5.1).
- Build/export pipeline for PC is a ship task (ROADMAP M9); keep the project export-ready rather
  than discovering platform issues at the end.

### 9.2 Size of v1
- A **short game, ~1–2 hours** of play. This number is the main scope guardrail — when in doubt,
  cut to protect it.
- Implications: a **small, memorable cast** over a big one (§3.2), a **tight set of named
  locations** (§2.1), and **one** mini-game done well rather than many (§5.4).

### 9.3 What's in v1 (the vertical slice)
The slice that proves the game is worth scaling (full breakdown in ROADMAP M0–M4):
- Combat that feels good first-person — the non-negotiable core (§5.1).
- A small town you can traverse, with a few characters worth talking to (§2, §3).
- Branching dialog and at least one quest authored end-to-end, data-driven (§4, §6).
- **One** job/mini-game with real skill + progression feeding a simple economy (§5.4, §5.6).
- A single shop/workshop the player upgrades (§5.5).
- Save/load covering progression, inventory, quest and shop state (§6.4).

### 9.4 What's deliberately thin or out for v1
The pressure-release valve. These are decisions, not omissions — protect them from creep:
- **Alternative play (Pillar 3) is intentionally thin:** ship **one** solid mini-game — **bartending**
  (§9.6); other jobs stay light (§5.4).
- **No survival/needs systems** — "survive" is flavor only (§5.7).
- **No free-form base building** — just the single upgradable shop (§5.5).
- **Main story can stay open** — the systems don't depend on the final plot (§4.1); v1 can be
  built around character/gameplay quests.
- **Eclectic art is rationed:** 3D is the base; 2D/8-bit are special moments, not the default
  (§7.2).

### 9.5 Out of scope for v1 (parked, not cancelled)
Real ideas scheduled for after the slice proves out — see ROADMAP M5–M8 and the backlog parking lot.
From `docs/design/WORLD_BIBLE.md`, the parked set includes: the other businesses (Bedrock Bank, Fang's
Bowling, Keep It Real-estate, MovieBin, EatQuick!, Furniture Depot, SeedStore+, car dealership,
MaxTrax), extra dungeon themes and wild biomes, the wider cast and their quests, the Han de Seciro
main-story thread, house-building beyond the single workshop, and the final art/audio pass.

### 9.6 v1 content slice (locked 2026-06-28)
The concrete content the slice ships. Everything is drawn from `docs/design/WORLD_BIBLE.md`; anything not
named here is parked.

**Locations:**
- The **town hub**.
- **One outlying wild area** (combat + gathering).
- **One procedurally-generated dungeon, locked to a single distinct theme.** The procedural system
  *stays in v1* (it keeps runs fresh), but only one polished theme ships; additional themes are
  parked. *(Design intent: each future dungeon theme should feel very distinct — v1 nails one.)*
- Functional interiors: **George's General Store**, **The Flaming Pebble**, **Kippie Arcade**,
  **Astros Fishing Friends**, **the Adventurers Guild**.

**v1 cast (speaking roster, ~6):**
- **Orbo Orland** — Mayor; gives the "help the town" spine.
- **George Coral** — George's General Store (the v1 shop/workshop, §5.5).
- **Barry Barnson** — The Flaming Pebble; employer for the bartending job.
- **Kippie Kip** — Kippie Arcade.
- **Droghnaut** — Astros Fishing Friends (vendor / flavor).
- **Sally Steelfield** — Adventurers Guild; the dungeon hook. *(Al Firestorm optional/parked.)*

**The one mini-game (Pillar 3):** **Bartending at The Flaming Pebble**, built to the full bar —
real skill, a progression curve, and an economy hook. Other venues' jobs (fishing, arcade,
dungeon-running) are light activities or vendors only in v1. *(Needs building — the bar interior
exists, the job loop doesn't yet.)*

**Story:** a **"help the town" arc** — Mayor Orbo sends the player to help residents, threading them
through combat, crafting, the bartending job, and a dungeon run. The Han de Seciro mystery and the
larger plot are parked (§4.1).

**Systems (already built — tune/polish, don't rebuild):** combat, crafting, economy/shop, dialog,
quests, save/load (§5–6).
