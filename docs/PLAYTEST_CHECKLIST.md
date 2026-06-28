# Town City — Full Playtest & Asset Review

A large amount has been built and verified **headless** (logic/structure confirmed) but
anything *visual*, *feel*, or *balance* can only be judged by playing. This is your
sit-down review guide. Mark items ✅ / ❌ and tell me the ❌s — I'll fix them.

---

## How to run the review

There are two dev scenes (open the `.tscn` in the editor, press **F6**):

### 1. `stages/dev/review_hub.tscn` — the gameplay test bench
Spawns you with a **full kit** (all tools, the new crafted gear, money, a stack of every
quest/rare/craft item, and food) plus:
- A **TEST BENCH** row of pillars right in front of you — aim + **E** to fire a debug action:
  `+Rep All` / `-Rep All` (test reputation tiers, discounts, gifts, HOSTILE branches),
  `+Day` (expire tasks, reset shop hours, roll the day), `+6h` (watch the sky tint),
  `+XP` (level-up feel + skill points), `Give Gear` (every weapon/tool for held-model + combat feel),
  `Hurt 60` (test healing/low-HP), `Heal`, `+Money`.
- **Warp gates** grouped Wild / Interiors / Dungeons / Misc (Town, Combat Arena) — aim + **E** to jump.
- Workflow: warp out → review → **F8** to stop → **F6** to return to the hub for the next spot.
  (Most destinations' own Leave/Exit door also returns to town.)

### 2. `stages/dev/asset_review.tscn` — the asset/scale review
Every model from the kit folders laid out at **native scale** with a 1.8 m human reference
and a 1 m ruler, each labelled with its measured W×H×D. Walk among them and flag anything
mis-scaled. (Edit the `folders` list on the root node to review other asset folders, e.g.
`assets/models/characters/psx`, `assets/models/furniture`, `assets/models/critters/cube-pets`.)

### Controls
WASD move · Shift sprint · Space jump · **E** interact · LMB use/attack · 1–8 hotbar ·
I inventory/player menu · J quest log · Esc pause (Settings + Controls page).

---

## Suggested 20–30 min "golden path" (exercises the whole loop)
From the **Town** gate: talk to an NPC → take a quest → enter a **Wild area**, gather with the
right tool, fight an animal → enter a **Dungeon**, clear a room, grab rare loot, find the exit →
back in town: **craft** at the workbench/smelter, **sell** at the store, **buy** a house upgrade →
turn the quest in → check you **leveled up**. Use the Test Bench to skip the grind where noted.

---

## A. First-run & onboarding
- [y ] New Game shows the controls toast; a **persistent controls reference** exists (pause menu → Controls, and/or a first-run panel).
- [ n] Interaction prompts read clearly (ideally with an "[E]" key hint).
- [ n] On spawn there's an obvious first goal (quest markers over NPCs, a starter/main quest, or a nudge) — you're not lost once the toast fades.
- [y ] Quest markers "!" (available) / "?" (turn-in) / task icon appear over the right NPCs; the on-HUD quest tracker shows the current objective + next step.

## B. Town
- [y ] Gate posts (4 wild + 6 interior + sewer + dungeon) sit **on the ground** (not floating/buried) on the sculpted terrain — nudge any that are off.
- [y ] NPCs present + animated (Marlo, Sela, Ember, Gus, Mira, Pip); each is talkable; dialogue offers the right quests/tasks.
- [ couldnt find notice board but other are all reachable] Notice board + crafting stations (workbench/smelter/brewer/cooking) + shop all reachable and working.

## C. Wild areas (Woods / Hills / Meadow / Barrens)
- [y ] **You spawn standing on the ground** (the spawn-tunnel bug is fixed — confirm anyway).
- [y ] Theme reads (ground/sky/fog); Barrens is smoky; **time-of-day sky tint** shifts (use `+6h` on the bench).
- [ y] Tree/rock/foliage + new **biome particle ambience** look natural (not floating/clipping/too dense).
- [ n, just square] Resource nodes use the right models and harvest with the kit (hatchet→trees, pickaxe→stone/ore, hand→bushes/herbs; gem/glow nodes need the better pickaxe).
- [ n floating on aboove ground] Animals: right scale/skin/facing; peaceful flee, hostile chase + bite, both drop loot. **Iron Hills should feel rebalanced** (not a relentless predator gauntlet).
- [ y - howver dungeons are all the same theme] Dungeon-entrance cave-mouths in Hills/Barrens/Woods are placed sensibly; return gate + portal glow/pulse work.

## D. Interiors & the player house
- [ some furnature like beds and lamp are way too big. placement is a bit odd, but i can come in and refine myself] Furniture placement looks deliberate (no overlaps/floating/blocked doors); lighting/mood reads; interiors don't feel empty.
- [ y ] NPCs/shopkeepers present where expected; Leave door returns to town at the right doorstep.
- [y ] **Player house upgrades**: at the upgrade station, buy one → its fixture appears live; money + items deduct.
- [ ] **Abandoned Cabin** (woods): trapdoor → Cabin Cellar → exit returns to the cabin.

## E. Dungeons & combat
- [n ] Each theme reads (cave/mine/sewer/power plant/cellar/procedural).
- [ y] Enemies spawn, animate, chase, attack; **death anims** play; you can clear a room. Hit feedback (crosshair markers, flashes, knockback, telegraphs) feels good.
- [ ] **Boss difficulty feels tiered by depth** (early bosses are fair, not a random 600hp wall). Descend a few floors via the DescendPortal.
- [ ] **Loot improves with depth** (descending is rewarding); rare nodes/chests yield rare items.
- [ ] **Death has stakes**: use `Hurt 60` then die — on respawn you lose some consumables + a little XP, with a summary on the death screen. (NOTE: on a *dungeon* death the dropped consumables are currently lost rather than recoverable — tell me if you want that changed.)
- [ ] Exit portal returns to the correct source area.

## F. Economy, crafting & shops
- [ need to start with starting tools, or at least have some way to build them without needing tools. Maybe the resources to make the most basic tools can be collected without needing tools. additonally when you enter a dungeon it overwrites your hotbar tools with the weapons. this should not happen. I want the player to start with maybe a pickaxe, axe, swoard, and bow. only basic versions of these] Workbench: craft **Wood Plank** (wood_log→plank), and the new gear (Reinforced Pickaxe, Radiant Sword, Glow Staff, Glow Lamp, Gemstone Pendant) — inputs consume, output appears.
- [ ] Smelter: refine scrap→refined metal etc. (timed).
- [ ] Crafting UI shows can-craft/ready badges + ingredient status + rarity colors.
- [ ] Shop: rare mats + **food** sell (hunting/cooking now pay); **health potions are buyable**; the new gear is in stock; Sell-All **skips active-quest items**.
- [ ] Held viewmodels for the new weapons (Radiant Sword, Glow Staff, etc.) look right in first person (use `Give Gear`).

## G. Quests & tasks
- [ it works, hard but the quest menu does not work well. it clips top and bottom of the screen and is hard to navigate. I want the quest menu to be a tab in the general menu, where items and map and such are. then i want the ability to select the tracked quest that shows up in the hud.] Accept a main quest → quest log groups it under **Main** with "Stage 1/3"; collecting items advances the stage; finishing pays out.
- [ y] A timed **task** shows an amber countdown; completing in time bumps reputation; **`+Day`** expires an in-progress task (it leaves the log).
- [ ] Quest turn-ins **consume** the items (TAKE_ITEM sinks).
- [ ] `powering_the_town` (needs wood planks) is now completable.

## H. Reputation (use `+Rep All` / `-Rep All`)
- [ ] High reputation unlocks **Friendly/Beloved dialogue branches** + gifts, and gives **cheaper shop prices** (shop header shows your tier).
- [ ] Low/HOSTILE reputation unlocks the cold dialogue branches.

## I. Progression, UI & menus
- [ ] `+XP` → **level-up feedback** (toast/flourish) + skill points; the skill tree (incl. the 3 new end-game perks) reads clearly.
- [ ] Player menu: inventory (category tabs, quest badges, tooltips, item values), character sheet (shows NPC reputation tiers), **Map tab legend**.
- [ ] Pause menu: Resume/Save/Load/Settings (volume sliders, mouse sensitivity, **font size**, **Controls page**)/Main Menu/Quit all work; Esc doesn't stack over other menus.
- [ ] **Clock pauses** while any menu/shop is open (time stops draining).
- [ ] Save (F5) in a dungeon, reload (F9) → you land safely; quest/upgrade/money/rep all persist.

## J. Audio & game-feel
- [ ] Footsteps, landing thud, harvest/craft/pickup/sell, hotbar select, level-up, combat impacts have audio cues (procedural fallback is fine — there are no music/ambience `.ogg` files yet; areas are otherwise silent until you add them to `assets/audio/{music,ambient}/<mood>.ogg`).
- [ ] Camera/impact feel (sprint FOV, landing dip, hit-stop) reads good, not nauseating.

## K. Assets (use `asset_review.tscn`; also eyeball in-world)
- [ ] Character models/skins (PSX humans + cube-pet animals) — right scale, correct skin, facing forward, **not T-posing or sunk into the floor**, animations read (the Mixamo retarget has known minor arms-wide/leg-stiffness).
- [ ] Weapon/tool/furniture/nature/prop models — sensible native scale, no obviously broken/white materials.
- [ ] Held-item viewmodels sit in-hand correctly.

---

## Known caveats (already on my radar — confirm or tell me to change)
- **Dungeon death** drops consumables into the dungeon (freed on exit) = currently unrecoverable; the summary implies otherwise. Say the word to reword or change it.
- **No music/ambience audio** until `.ogg` files are added to `assets/audio/`.
- **Deferred tuning is in** but numbers are first-pass (death-penalty fractions, boss tiers, loot tiers, predator counts, reputation discount sizes are all tunable consts) — flag anything that feels off and I'll retune.
- The `theme_values.gd` "Nil→Color" errors in the editor console are pre-existing **dialogue-addon** noise — ignore.


## Additonal playthrough notes:

inventory is hard to navigate, scrolling with mousewheel causes tabs to change. I want scrolling just to scroll whatever element the mouse is on, not tabs. 


its hard to test the game in a small box, how can i run at a better resolution? I want to target 1920x1080

I want a way to drop items

time of day is not changing--there is no night

gifts get sent autoimatically from npcs, it should be given on next time spoken, maybe a little icon appears when they have somethign to give


need to start with more stamina, and maybe run a bit faster.

also i see no sky in the town


i dont want tools to be controlled by the e button, they should be the same button as attack. also they dont swing when they work, and its unclear if they are doing anything. 