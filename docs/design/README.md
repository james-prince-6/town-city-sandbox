# Town City — Design & Planning Docs

This folder is the planning home for *Town City* (working title). It's meant to live in the
repo next to your code so it stays current as you build.

## What's here

- **`GAME_DESIGN_DOCUMENT.md`** — the GDD. What the game *is*. Organized from your notes, with
  markers (▶ DECIDE / ▶ EXPAND) wherever a creative or design call is still yours to make.
- **`ROADMAP.md`** — the work breakdown. What to build and in what order, using a
  vertical-slice-first strategy sized for a solo dev aiming to ship.
- **`templates/`** — fill-in templates so new content slots in consistently:
  - `QUEST_TEMPLATE.md` — one per quest.
  - `MINIGAME_TEMPLATE.md` — one per job/mini-game.

## How to use them

1. **Start with the GDD's §10 "Open questions log."** Answering those seven decisions unblocks
   almost everything else.
2. **As you decide things, edit the GDD** and delete the marker — let the prose stand.
3. **Work top-down through `ROADMAP.md`**, one milestone at a time.
4. **Copy a template** into a real doc whenever you design a quest or mini-game (e.g.
   `docs/quests/lost-coin.md`).

## Division of labor

The creative content — story, characters, world, quest writing, art direction choices — is
**yours**. These docs organize and structure those ideas, flag gaps, and turn decisions into
buildable work. They deliberately don't invent fiction on your behalf.

## Suggested future docs

Create these when the relevant milestone comes up:

- `ARCHITECTURE.md` — what goes in each repo folder; autoloads/singletons (Milestone 0).
- `SYSTEMS/` — one deep-dive per major system (combat, crafting, economy) as they're built.
- `quests/`, `characters/` — instances created from the templates.
