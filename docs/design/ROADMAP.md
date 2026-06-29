# Roadmap & Work Breakdown — *Town City* (working title)

> **Companion to:** `GAME_DESIGN_DOCUMENT.md`
> **Audience:** solo dev, aiming to ship
> **Core strategy:** *vertical slice first.* Build one small, complete, fun chunk of the game
> before going wide. It de-risks the whole project and is the single best habit for a solo
> dev who wants to actually finish.

## Why vertical-slice-first

You have a lot of systems (combat, crafting, jobs, tycoon, dialog, quests). Building them all
to 50% leaves you with a game that's 0% playable. Instead, pick the *smallest path through the
game that's still fun* and finish it end-to-end. If that slice is fun, the game is worth
scaling. If it isn't, you've learned that cheaply. Everything below is ordered to get you to a
playable slice as fast as possible, then widen.

A reminder on division of labor: this roadmap covers **what to build and in what order**. The
creative content that fills these systems — characters, quests, dialog, the world — comes from
you (see the GDD markers).

---

## Milestone 0 — Foundations (make the project sane to work in)

Boring but load-bearing. Skipping these costs you weeks later.

- [ ] **Confirm the v1 scope decisions** in GDD §9 and §1.3. You can't plan honestly until the
      pillars and "what's allowed to be thin" are locked.
- [ ] **Settle the project architecture.** You already have a sensible folder layout
      (`entities`, `stages`, `ui`, `components`, `global`, `tools`, `addons`). Write a one-page
      `docs/ARCHITECTURE.md` describing what goes where so future-you stays consistent.
- [ ] **Autoloads / singletons plan.** Decide your global managers early: e.g. `GameState`,
      `SaveManager`, `EventBus` (signals), `EconomyManager`, `QuestManager`. (`global/` is the
      natural home.)
- [ ] **Save/load system (skeleton).** Even a stub. Retrofitting persistence late is one of the
      most painful jobs in game dev — stand it up now so every system saves from day one.
- [ ] **Establish the render pipeline for the PS2/low-res look** (GDD §7.2). Lock internal
      resolution + filtering so all art is authored to match from the start.
- [ ] **Input map** for KB/M (and controller if in scope) defined in one place.
- [ ] **Decide: custom dialog system vs. addon** (GDD §6.1). This gates a lot of quest/story work.

**Exit criterion:** you can open the project, there's a clear place for everything, and a new
scene can save & reload its state.

---

## Milestone 1 — Combat prototype (prove the core feels good)

Combat is a top pillar and the riskiest "does it feel good" question. Prototype it in
isolation — no town, no story, just a gray-box room.

- [ ] First-person controller: move, look, jump.
- [ ] One melee weapon (sword) with real-time hit detection and satisfying feedback.
- [ ] One enemy with basic AI (approach, attack, take damage, die).
- [ ] Health, damage, death/respawn.
- [ ] Hit feedback: hitstop, sound, visual — the stuff that makes swinging *feel* good.
- [ ] **Greybox combat arena** in `stages/` to test encounters.
- [ ] Then add a second weapon class to prove the system generalizes: bow **or** a spell.

**Exit criterion:** a stranger can pick up the controller, fight the enemy, and say "that felt
good." If not, iterate here before building anything else. *(See GDD §5.1 "minimum fun combat
encounter.")*

---

## Milestone 2 — The town & traversal (a place to be)

- [ ] One greybox town area (your "Town City" — even blockout geometry).
- [ ] Player can walk the town, enter/exit interiors or zones.
- [ ] One NPC you can walk up to and talk to (uses the dialog system from M0).
- [ ] Basic interaction prompt system ("Press E to talk / pick up / use").
- [ ] Day/time skeleton **only if** schedules/survival are in scope (GDD §5.7) — otherwise skip.

**Exit criterion:** you can spawn in town, walk to a character, and have a (placeholder) conversation.

---

## Milestone 3 — Dialog & quests (the town does something)

- [ ] Dialog system: branching choices + the "mini cutscene" emote/expression layer (GDD §6.1, §6.3).
- [ ] Quest system: track available/active/complete, objectives, rewards, branches (GDD §6.2).
      Data-driven so you author quests in files, not code.
- [ ] **Author 1 character quest end-to-end** using one of your seed ideas (e.g. "Can you help me
      find my lost coin?"). Content is yours; this proves the pipeline.
- [ ] Quest log UI in `ui/`.

**Exit criterion:** an NPC offers a quest, you complete an objective in the world, and you get
a reward — fully data-driven.

---

## Milestone 4 — Economy, inventory & one mini-game (alternative play works)

- [ ] Inventory system (items, stacks, equip).
- [ ] Economy / currency manager — single source of truth (GDD §5.6).
- [ ] **One** job/mini-game built to the template in `docs/templates/MINIGAME_TEMPLATE.md`,
      with real skill + progression + an economy hook (GDD §5.4). Just one, fully.
- [ ] A vendor: sell what the mini-game produces; buy something useful with the proceeds.

**Exit criterion:** the player can do a non-combat activity, get better at it, earn money, and
spend it — the full "alternative play" loop in miniature. This validates Pillar #3.

---

## ▶ Vertical Slice complete (Milestones 0–4)

At this point you have the *whole game in microcosm*: combat that feels good, a town with a
character, a quest with a reward, and a mini-game that feeds an economy. **Play it. Show it to
people. Decide if it's fun before scaling.** This is your go/no-go gate.

---

## Milestone 5 — Crafting & progression

- [ ] Leveling/build system per GDD §5.2 (after you pick use-based vs. XP-based).
- [ ] Crafting system + recipe unlocks (GDD §5.3).
- [ ] Wire crafting into the economy and at least one mini-game's outputs.

## Milestone 6 — Tycoon / production & base-building (scoped small)

- [ ] Implement the *small* version you defined in GDD §5.5 — resist scope creep here.
- [ ] Production → sell loop integrated with the economy.

## Milestone 7 — Content & widening

- [ ] Add remaining characters (GDD §3.2) and their quests.
- [ ] Add remaining mini-games/jobs.
- [ ] Main story beats, once written (GDD §4.1).
- [ ] Additional combat content (enemies, weapons, the "fun builds" of GDD §5.2).

## Milestone 8 — Art & audio production pass

- [ ] Replace greybox with real assets in your chosen styles (GDD §7) under the locked-in
      render pipeline and the "when do we use which style" rule.
- [ ] Music & SFX (GDD §7.4).
- [ ] UI art pass.

## Milestone 9 — Ship

- [ ] Settings, accessibility, key rebinding.
- [ ] Full save/load coverage, balance pass, bug fixing.
- [ ] Build/export pipeline for target platform(s) (GDD §9).
- [ ] Store page, marketing assets *(your creative call)*, release.

---

## Solo-dev guardrails

A few habits that decide whether a solo project ships or stalls:

- **One milestone at a time.** Don't start M5 systems while M1 combat still feels mushy.
- **Greybox everything first.** Art is the most time-expensive work; never make final art for a
  system you haven't proven is fun.
- **Cut, don't polish, when behind.** The pillar you marked "allowed to be thin" (GDD §9) is your
  pressure-release valve.
- **Keep the GDD honest.** When you change the design while building, update the doc the same day.
- **Timebox prototypes.** "I'll spend 2 weeks on combat feel" beats open-ended tinkering.

---

## Backlog parking lot

Ideas that are real but not yet scheduled — drop things here so they're captured without
derailing the current milestone. *(Add to this as ideas come; pull from it when planning the
next milestone.)*

**Built in the prototype but beyond v1 scope (parked, not cancelled):**
- *Additional dungeon themes* — v1 keeps the procedural generator but ships **one** distinct theme;
  more themes are post-slice.
- *Extra mini-games* — v1 ships one polished; the second built game (whack/Simon) waits.
- *Player-house upgrade system* — beyond the single shop/workshop v1 calls for (GDD §5.5).
- *Additional wild areas* — v1 ships one wild area; the other biomes are post-slice (GDD §2).
- *Elite/boss enemy tiers, status effects, deeper crafting chain (gold/crystal)* — keep for widening.

**Open decision parked here:**
- *Leveling model* — prototype uses XP + skill tree; design intent is use-based (GDD §5.2). Reconcile
  before v1 leveling work.

---

## Suggested next step

Once you're happy with these docs, I can turn Milestones 0–4 into **GitHub Issues** with labels
and a **Project board**, so the work is trackable in the same repo. Say the word and I'll set
it up.
