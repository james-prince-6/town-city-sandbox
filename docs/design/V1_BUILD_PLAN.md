# Town City — v1 Build Plan (for Claude Code)

> **Audience:** Claude Code, working **inside the game repo** (`town-city-sandbox`).
> **Goal:** ship the **v1 vertical slice** defined in the design docs.
> **Prime directive:** a **working, audited prototype already exists**. You are **building on it,
> not rebuilding it.** Reuse the existing systems; touch foundation files only when a task says so.

---

## 0. Read first (do not skip)

**Codebase ("how it's wired") — in `docs/`:**
- `docs/ARCHITECTURE.md` — autoloads/systems layer, data-driven `.tres` content, duck-typed
  interaction, NPC AI/schedule/animation, save system, **conventions & gotchas**. This is the contract.
- `docs/combat.md`, `docs/combat_expansion_and_procedural.md` — combat backbone, enemies, procedural dungeon.
- `docs/dialogue_conversations.md`, `docs/adding_content.md` — dialogue system + the cookbook for
  adding items/NPCs/quests/recipes/shops.
- `docs/AUDIT.md`, `docs/PLAYTEST_CHECKLIST.md` — known-good state + James's annotated playtest feedback.

**Design ("what to build") — the v1 spec, in `docs/design/`:**
- `docs/design/GAME_DESIGN_DOCUMENT.md` **§9.6** — the locked v1 content slice.
- `docs/design/WORLD_BIBLE.md` — canonical cast, businesses, facilities.
- `docs/design/minigames/bartending.md` — the headline mini-game spec.
- `docs/design/quests/help-the-town.md` — the v1 story questline.
- `docs/design/ROADMAP.md` — milestone/backlog context (optional).

**Golden rules (from ARCHITECTURE.md — restate to yourself before each task):**
1. Persistent state lives in **autoloads**; per-scene state dies with the scene.
2. Content is **data** (`.tres` Resources auto-loaded from their folders) — prefer authoring data
   over writing code.
3. **Do not edit foundation/shared files** (`entities/player/player.*`, `components/*`, `item.gd`,
   `hotbar.gd`, `project.godot`, existing shipped scenes) unless the task explicitly calls for it.
4. Damage always flows `HitBox → HurtBox → Health/PlayerStats`.
5. Watch the gotchas: cold **class-cache** (use `load("res://….gd").new()` in throwaway scripts),
   `:=` Variant inference on dict subscripts, **zero-init cooldowns** (init to a large negative),
   binary save round-tripping. Add a system to `SaveManager._save_targets` if it holds state.
6. **Test headless** with the project's `_ready()`-assertion pattern; **one Godot process at a time**.

---

## 0.5 Assets & importing (James added a large library — check it and import what you need)

A big external asset library lives at **`C:\Users\kingb\OneDrive\Game assets\`** (outside the
repo — ensure you have read access to it). **Start from its catalog:** `ASSETS_INDEX.md` (and
`ASSETS_INDEX.json`) lists **15 libraries / ~94k files**; several have their own detailed
`ASSETS_INDEX.md` (Kenney, Mixamo, Stylized Nature). Re-run `build_index.py` there if a library is added.

**For each v1 feature, check the index and import any new models/assets it needs.** Workflow
(matches `docs/ARCHITECTURE.md` §8 — **do not bulk-copy the 94k files**):
1. Search the index for a fitting asset.
2. **Copy only the needed files** into the repo under `assets/…`, grouped by system (existing
   convention). Let Godot import them — an imported `.fbx`/`.gltf` becomes a `PackedScene`;
   reference it by the `uid` in its sibling `.import`. **Prefer glTF** where both exist (some
   Kenney/Quaternius FBX are vertex-colored and import white).
3. Wire the imported scene in as a `Prop` / `world_model` / character per the `adding_content.md` cookbook.
4. Keep the full library external — curate only what a feature actually uses.

**Likely sources per v1 need (verify in the index — don't assume a file exists):**
- **Bartending props** (4 glass types, keg, bottles, broom/mop, bar fixtures): **Kenney** food/drink
  + props; **KayKit RPG Tools & Bits / Resource Bits**.
- **Venue buildings/interiors** (Fishing shop, Adventurers Guild, Arcade, Town Hall): **Quaternius**
  Medieval Village / Downtown City / Fantasy Props MegaKits; **Kenney** buildings/furniture.
- **Characters:** **PSX Characters** pack (textured humans incl. police/doctor/firefighter — good for
  the professions cast); **KayKit Adventurers** (Sally) & **Skeletons** (enemies). ▶ **Droghnaut
  (alien) and Fredward (frog being) have no obvious match** — flag for a custom model or a creative
  substitution; don't block on them.
- **Animations:** **Mixamo** + **Universal Animation Library 1/2** (the project already retargets
  Kenney/Mixamo rigs — see ARCHITECTURE `NPCAnimator`/`EnemyAnimator`); bartending idle/gestures from
  the Mixamo Gestures pack.
- **Wild area / nature:** **Stylized Nature MegaKit**, **KayKit Forest Nature**, **Binbun Grass**
  (Godot grass shader).
- **Dungeon:** **KayKit Dungeon Remastered** (already used) and/or **Quaternius Modular Dungeon**.
- **Fishing water / toon look:** **Godot Water** shader, **Ultimate Toon** shader. (UI is already
  shipped — the flat **sticker** theme `res://ui/town_city_theme.tres` + helper `res://ui/ui_style.gd`;
  the old glass-UI shader is **retired**, so don't import it.)
- **Audio** (none in the build yet — playtest gap): **music-loop-bundle** + **Kenney Audio** →
  `assets/audio/{music,ambient}/`.

**Licensing:** most are CC0 (Kenney, KayKit, Stylized Nature, Quaternius, Universal Anim). **Mixamo**
is free-to-use-in-project but **not redistributable standalone** — bake it into the game, don't ship
the raw FBX library.

---

## 1. v1 — definition of done

A new player can: spawn into town with basic tools and an obvious first goal → take Mayor Orbo's
arc → restock George's store (gather/craft/light combat in **one** wild area) → work a **bartending
shift** at The Flaming Pebble → do a light morale beat at Kippie's arcade *or* Droghnaut's → get
sent by Sally into **one** procedurally-generated dungeon (single theme) → clear it, reopen the mine
→ return to Orbo for the payoff → and **save/load works across the whole arc**. Cast = the six v1
characters; venues = the five v1 interiors. Everything else stays parked (don't delete it).

---

## 2. Open decisions — confirm with James or use the default

| # | Decision | Default if unanswered |
|---|---|---|
| D1 | **Leveling:** ~~rework to use-based now, or ship the built XP/skill-tree for v1?~~ | ✅ **RESOLVED — use-based is implemented** (2026-06-28; `global/systems/progression.gd`). Four skills (Melee/Ranged/Magic/Survival) rise by use; perk points feed per-skill trees. The old XP/skill-tree model is retired (GDD §5.2, ROADMAP backlog). No longer an open decision; remaining work is tuning the constants in `progression.gd`. |
| D2 | What's wrong in the caves (questline root cause)? | **Monsters** moved in. |
| D3 | Hub gate to unlock the finale | **2 of 3** errands. |
| D4 | Does Sally fight alongside you in the dungeon? | **No** — she sends you in (no companion AI). |
| D5 | Bartending: flat base wage on top of tips? "Perfect Pour!" flourish? | **Small base wage + tips**; flourish **optional/last**. |
| D6 | Quest 2c: build light **fishing**, or reuse the existing **arcade** game only? | **Reuse arcade** for v1; stub fishing as a parked activity. |

Surface the still-open ones early (D3 hub gate; the dungeon-end boss/objective under D2); don't silently make large choices. (D1 and D4 are now resolved.)

---

## 3. Work breakdown (do milestones in order; one at a time)

### M-A · Scope lock & onboarding
- Select **one** wild area and **one** dungeon theme as the v1 set; gate the rest behind a flag or
  scene selection — **do not delete** parked content.
- Player **spawns in town with basic starter tools** (pickaxe, axe, sword, bow — basic tiers) and
  these are **not overwritten** when entering a dungeon (playtest feedback). Ensure a basic-tool
  path that doesn't require tools to bootstrap.
- **Acceptance:** new game → spawn in town, basic tools on hotbar, one wild area + one dungeon
  reachable, parked areas hidden.

### M-B · Cast migration (mostly data)
- Add/define the canonical v1 NPCs (WORLD_BIBLE §8): **Orbo Orland** (Town Hall), **George Coral**
  (rename/replace the existing **Gus**), **Barry Barnson** (Flaming Pebble), **Kippie Kip**
  (arcade), **Droghnaut** (fishing), **Sally Steelfield** (Adventurers Guild).
- **Retire or rename** placeholder NPCs (Mira, Marlo, Sela, Pip, Ember) and **fix every dialogue
  `.tres` reference** to them (e.g. `mira_*.tres`, `marlo_*.tres`) and NPC definitions.
- **Acceptance:** town is populated by the v1 cast; a headless validity pass finds **no broken
  dialogue/quest references**; reputation keys (`npc_id`) are consistent (e.g. the store's
  `reputation_npc` matches George).

### M-C · Venues / interiors
- Ensure these five exist as interiors with the right **owner NPC + door/teleport** wired:
  **George's General Store** (exists), **The Flaming Pebble** (exists), **Kippie Arcade** (arcade
  cabinet exists — give it a venue/owner), **Astros Fishing Friends** (new; vendor + a fishing
  spot), **Adventurers Guild** (new; Sally + the dungeon entrance hook).
- **Acceptance:** each venue is enterable from town, has its owner present, and its leave-door
  returns to the correct doorstep.

### M-D · Bartending mini-game  ← the headline net-new build
Implement per `minigames/bartending.md`. **Important:** this is an **in-world "job mode"** behind
the bar (first-person), **not** a `CanvasLayer` overlay like the arcade `Minigame`. Enter the mode
by interacting with the bar station; exit when the shift ends.
- **Customers:** an NPC that walks to the counter, **places an order** (1 of 4: beer/wine/shot/
  whiskey) shown as an icon, and has a **patience meter**.
- **Stations:** glass rack (4 glass types), **keg/tap** (beer), **bottle shelf** (wine/shot/whiskey).
  Interaction points reuse the duck-typed `interact` pattern.
- **Pour:** **hold-to-fill, release at the fill line**; a fill window scores accuracy; **overfill
  spills** (waste + a mess), underfill lowers satisfaction; **beer has a foam head** to manage.
- **Serve → pay:** deliver the correct glass to the customer → `GameState.add_money` (price + tip);
  **tip scales with speed + pour accuracy + remaining patience**.
- **Cleaning:** customers leave **messes**; a **broom (sweep)** and **rag (wipe)** clear them;
  uncleaned messes lower satisfaction / can block a spot.
- **Shift wrapper:** a timer; pays out total at end; uses `Clock` (pause-aware) and `GameState`.
- **Progression:** a **Bartending skill** that improves with use (faster pours, wider fill window,
  bigger tips, more concurrent customers) — keep it a **self-contained skill stat**; don't entangle
  it with the global use-based progression in `progression.gd` (D1, now resolved). **Bar upgrades** bought via the shop/Barry
  (better tap, bigger glass rack, bus tub, crowd capacity) as money sinks.
- **Save:** persist bartending skill + purchased upgrades (`capture_state`/`restore_state`,
  registered in `SaveManager`).
- **Acceptance:** you can enter a shift, serve a multi-customer queue with hold-to-fill pours, clean
  messes, earn skill-scaled money, and the shift pays out and **saves**.

### M-E · Light morale activity (D6)
- **Default:** reuse the existing arcade game for quest 2c; no new fishing build. If James picks
  fishing, implement a **minimal** catch loop only.
- **Acceptance:** quest 2c is completable via the chosen activity.

### M-F · "Help the Town" questline (mostly data)
Author the four beats from `quests/help-the-town.md` as `Quest` `.tres` + dialogue `.tres`:
- **Beat 1 New in Town** (onboarding + starter tools + first-goal marker over Orbo).
- **Beat 2 Lend a Hand** (hub of 3 errands, any order; gate per D3): 2a restock George
  (COLLECT_ITEM in the wild), 2b a bartending shift (M-D), 2c the morale activity (M-E).
- **Beat 3 To the Source** (gated finale; Sally → dungeon clear; objective/boss per D2/D4).
- **Beat 4 Town City Thanks You** (payoff + set post-v1 tease **flags** for Han/Fredward).
- Use `DialogueEffect`/`DialogueCondition` for rewards and the finale gate flag; givers via NPCs or
  the notice board.
- **Acceptance:** the arc is **playable start → finish**, the gate works, rewards apply, and the
  whole thing **survives save/load** mid-arc.

### M-G · Playtest polish (from PLAYTEST_CHECKLIST)
- **Quest menu:** make it a **tab inside the general menu** (with inventory/map), fix the top/bottom
  clipping, and let the player **select which quest is tracked** in the HUD. (James's explicit ask.)
- Interaction prompts show a clear **"[E]"** hint.
- Fix obviously **oversized furniture** (beds/lamps) scale in interiors.
- (Already listed in M-A) basic starter tools + don't overwrite the hotbar on dungeon entry.
- **Acceptance:** James's flagged ❌ items above read clean in a playthrough.

### M-H · Verification
- Run the headless test suite; add tests for the bartending state + questline flags.
- Do a **full golden-path playthrough** (per PLAYTEST_CHECKLIST §"golden path") and a **save/load at
  each beat**.
- Report ❌s back rather than marking done on partial work.

---

## 4. How to work

- **One milestone at a time**, in order. Don't start M-D systems while M-B references are still broken.
- **Greybox over art:** wire and prove the loop with placeholder visuals before any art pass — but
  when you do need a model/sound, pull it from the asset library per **§0.5** rather than leaving a cube.
- **Import assets as each milestone needs them** (§0.5): check the library index, curate, import, wire.
- After each milestone: summarize what changed, how you tested it, and any decision you needed.
- If a task conflicts with the design docs, **flag it** — don't silently diverge.
- Keep the design docs honest: if you change the design while building, note it in the relevant doc.
