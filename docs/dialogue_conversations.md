# Conversations (deeper, BG3-lite)

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
