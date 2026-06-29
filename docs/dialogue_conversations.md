# Conversations (deeper, BG3-lite)

> ⚠ **SUPERSEDED (2026-06-28).** This document describes an **earlier, custom `.tres` dialogue
> system** (`DialogueResource` / `DialogueChoice` / `ConditionalDialogue`, `mira_*.tres`) that has
> since been **replaced by Nathan Hoad's Dialogue Manager addon**. Conversations are now authored as
> **`.dialogue`** files (one per NPC, under `entities/npc/dialogue/`) and opened via the **`Dialogue`**
> wrapper autoload — `Dialogue.start_dialogue(resource, speaker, title)` — which fronts the addon's
> `DialogueManager`. For the current authoring flow see the HOW-TO at the top of
> `global/npc/npc_definition.gd` and any existing `*.dialogue` file (e.g.
> `entities/npc/dialogue/marlo.dialogue`). The conceptual goals below (reactive greetings, per-line
> gestures, conditions/effects) still hold — only the **authoring format** changed. Kept for
> historical context; **do not author new dialogue from this doc.**
>
> **Presentation rebuilt (Town City "sticker" look).** The on-screen panel is now
> `ui/dialog/dialogue_balloon.gd` — a code-built CanvasLayer in the flat sticker style (cream
> bottom box, bobbing speaker portrait, dark name plate, numbered reply list with caret +
> selection highlight; all StyleBoxes inline). It still drives the conversation entirely through
> the addon: `Dialogue` (`ui/dialog/dialogue.gd`) instances the balloon and calls
> `balloon.start(resource, cue, [{"speaker": …}])`, and the balloon advances ONLY via
> `resource.get_next_dialogue_line(next_id, states)` (so the addon emits `got_dialogue` per line
> and `dialogue_ended` at the end). The text reveal reuses the addon's `DialogueLabel` for its
> **typewriter** + inline `[speed=…]`/`[wait=…]` pacing. The cinematic-lite camera fix:
> `dialogue.gd._begin_cinematic()` now frees any `Camera3D` orphaned when a prior conversation's
> ease-back tween was killed mid-flight (before its `_restore_player_cam` callback could free it),
> so starting a new conversation during the ease-back no longer leaks a camera.

The dialogue system extended for richer, more reactive conversations. Still 100% data-driven
(`.tres`), still the one `DialogueManager` autoload — `start_dialogue(resource, speaker)`.

## What's new
- **Cinematic-lite presentation**: pass the talking NPC as `speaker` and a dedicated dialogue
  camera eases from the player's view to an over-the-shoulder framing of the NPC + a gentle
  push-in, then eases back on exit. The NPC turns to face you and **gestures per line**. Signs /
  machines can omit `speaker` and just get the panel (no camera change).
- **Richer panel** (built in code in `dialogue_manager.gd`): bottom panel with a **portrait**
  (texture, or a colored speaker-initial fallback), speaker name, **typewriter** text reveal
  (click / A to skip to full, again to advance), and **numbered choices** (press 1–9 or use the
  d-pad + A).
- **Random / variant lines** — the headline ask:
  - `DialogueResource.pick_random_line = true` → the node says ONE random line from
    `dialogue_lines` (then any choices). Perfect for varied greetings / goodbyes / barks.
  - `ConditionalDialogue.extra_dialogues` → a single condition gate can hold several whole
    conversations; one is chosen at random when the gate wins (`pick()`), so e.g. a "morning"
    gate can open a different greeting each time.
- **Per-line speaker animation**: `DialogueResource.line_animations` (parallel to
  `dialogue_lines`) sets a gesture cue per line (e.g. `&"interact"` to gesture, `&"idle"` for a
  calm beat). Defaults to a talking gesture. Cues map to the NPC animator's clips.
- **More options**: choices already support per-choice `conditions` (item / reputation / quest /
  flag / mood / time) and `effects` (give/take item, money, reputation, mood, flags, quests,
  time). Author as many as you like; only the available ones show.

## Author a conversation
1. Make `DialogueResource` `.tres` nodes (`speaker_name`, `dialogue_lines`, optional
   `pick_random_line` / `line_animations` / `portrait`, `on_enter_effects`, `player_choices`).
2. Each `DialogueChoice`: `choice_text`, optional `next_dialogue` (branch; empty = end),
   `conditions`, `effects`.
3. Point an NPC at an opener: either set `npc.dialogue`, or (preferred) an `NPCDefinition` with
   ordered `dialogues` (`ConditionalDialogue` gates, most-specific first) + `fallback_dialogue`.
4. Branches can loop back to a hub node, but avoid authoring a `.tres` ↔ `.tres` reference cycle
   (Godot resource cycles are fragile); leaves that simply end and let the player re-talk are the
   safe pattern (re-talking re-rolls the random greeting).

## Worked example — "Mira" (in `town_template`)
`global/npc/definitions/mira.tres` → `entities/npc/dialogue/mira_*.tres`:
- `mira_greet` — random greeting + 5 options (one **reputation-gated**: only shows at rep ≥ 20).
- `mira_about` — two lines with gesture cues. `mira_rumor` — a **random** rumor each visit.
- `mira_compliment` — bumps Mira's reputation + mood on enter. `mira_friend` — gated branch that
  gifts a potion. `mira_bye` — random sign-off.

## Notes / limits
- The Kenney rig has no talk/nod/shake clips, so speech animation is a looping **gesture**
  (`interactStanding`), not lip-sync.
- Cinematic-lite reuses the player's camera framing via a temporary `Camera3D`; it's not a
  multi-shot cinematic. (Full speaker-cutting camera was the heavier option we didn't take.)
