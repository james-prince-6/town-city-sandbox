# Quest Line: Help the Town — *Town City* v1 main spine

> The v1 story spine (GDD §9.6). Connects every v1 system, the six-character cast, and the five
> venues into one short arc. **Premise:** the town's in a slump. **Shape:** linear intro → a hub of
> resident errands (any order) → a gated finale → wrap.
>
> Dialog hooks below are first-draft, in each character's voice — **final writing is James's**.
> Design choices that are still open are marked **▶**.

## Premise

Town City is in a **slump**. The local **mine/caves have turned dangerous** — **gem-eating monsters
have moved in** (cave-problem nature decided 2026-06-29; full lore in `WORLD_BIBLE.md` §9). The mine
is a gem-rich seam, and the monsters depend on the gems to survive and breed, so they've infested
it; the **miners can't work**, and the miners are the town's economic backbone. With them idle,
money's tight: George's shelves are bare, the Flaming Pebble's full of glum out-of-work regulars,
and morale is low. **Mayor Orbo Orland**, hands-on and caring, recruits the capable newcomer (you)
to help the town get back on its feet — and, ultimately, to get to the bottom of what's wrong in the
caves.

This frames the slump up front (jobs/crafting carry the middle) while justifying the **combat +
dungeon finale** that reopens the mine and lifts the slump.

> **Parked reveal (do NOT pay off in v1):** *why* the monsters surged is a gate to the monsters'
> world, likely opened by Orbo himself while chasing an economic revival (WORLD_BIBLE §9). The mayor
> who sends you to fix the crisis may be its unwitting cause. v1 only **foreshadows** this in the
> wrap (Beat 4) — the reveal belongs to the larger main story (GDD §4.1).

## How it threads v1

| Beat | System exercised | Venue / character |
|---|---|---|
| 1. New in Town | dialog, onboarding | Town Hall — Orbo; George's Store — George |
| 2a. Bare Shelves | exploration, harvest, light combat, crafting | Wild area + George's General Store |
| 2b. Last Call | the **bartending mini-game** | The Flaming Pebble — Barry |
| 2c. Spirits Up | light alt-play (arcade *or* fishing) | Kippie Arcade — Kippie / Astros — Droghnaut |
| 3. To the Source | combat, the procedural dungeon, a boss | Adventurers Guild — Sally; the dungeon |
| 4. Town City Thanks You | dialog, payoff, post-v1 tease | Town Hall — Orbo + cast |

---

## Beat 1 — "New in Town" *(intro · linear)*

- **Type:** story / onboarding
- **Giver:** Mayor Orbo Orland
- **Where it starts:** Town Hall, the moment you arrive in town (the game's opening goal).
- **Trigger / prerequisites:** new game.

### Hook
> "Welcome, welcome! New blood in Town City — and not a moment too soon. Times are hard, friend.
> Go get yourself set up at George's store, then come find me. I could use a pair of willing hands."

### Objectives
1. Talk to Mayor Orbo at Town Hall.
2. Go to **George's General Store**; meet George Coral and pick up your starter gear.
3. Return to Orbo (he assigns the hub, Beat 2).

### Systems exercised
Dialog, interaction, basic movement — pure onboarding.

### Rewards
Starter tools (basic **pickaxe, axe, sword, bow**) + a little money; the town opens up; a clear
first quest marker.

### Notes
Fixes the prototype's onboarding gaps (playtest: *"obvious first goal"* and *"start with basic
tools"*). Establishes the slump in two lines so the player understands *why* they're helping.

---

## Beat 2 — "Lend a Hand" *(hub · any order)*

Orbo asks you to help three struggling residents. **Do them in any order.** Completing the hub
lifts town morale and unlocks the finale. **▶ Gate:** require **all 3**, or a threshold (e.g. **2 of
3**) so the lightest one stays optional — James's call.

### 2a — "Bare Shelves"
- **Giver:** George Coral (framed by Orbo). **Where:** George's General Store → the wild area.
- **Hook:**
  > "Oh — hello. Shelves are looking a bit… empty, aren't they. Folks stopped bringing in materials
  > once the wilds got rough. If you're headed out there anyway… I'd pay fair for what you bring back."
- **Objectives:** head into the **wild area**, gather materials (wood / ore / herbs) with your
  tools, fend off a critter or two, *(optional)* craft a basic good at the workbench, deliver to George.
- **Systems:** exploration, harvesting, light combat, crafting.
- **Rewards:** money, a crafting **recipe unlock**, George reputation; the store restocks.

### 2b — "Last Call"
- **Giver:** Barry Barnson. **Where:** The Flaming Pebble.
- **Hook:**
  > "You lookin' for work or lookin' for a drink? …Bartender quit on me. Place is full of miners with
  > nothing to do and long faces. Pour 'em a few, keep my bar clean, and I'll cut you in. Don't water
  > the beer."
- **Objectives:** work **one bartending shift** (the mini-game) — serve the customers, keep the bar
  clean, hit Barry's target.
- **Systems:** the **bartending mini-game** (`docs/minigames/bartending.md`).
- **Rewards:** wages + tips, Barry reputation, and a **rumor about the caves** (foreshadows the finale).

### 2c — "Spirits Up" *(morale beat · lighter)*
- **Giver:** **Kippie Kip** *or* **Droghnaut** — player picks one venue. **Where:** Kippie Arcade or
  Astros Fishing Friends.
- **Hook (Kippie):**
  > "Maaan, nobody's been comin' by — everyone's too bummed to play! That's backwards, baby. Come
  > knock out a high score with me and get the good vibes flowin' again!"
- **Hook (Droghnaut):**
  > "The fish, they sense the town's sadness. Come — sit, fish with me a while. A calm hour heals more
  > than you'd think. The fish agree."
- **Objectives:** play an arcade game and beat a score, *or* fish and land a few; bring the lifted
  spirits back.
- **Systems:** light alternative play (arcade *or* fishing), exploration.
- **Rewards:** a little money, character bonding/reputation, a town morale bump.
- **Notes:** deliberately light — shows the "alternative play" pillar without being the deep
  mini-game (that's bartending).

---

## Beat 3 — "To the Source" *(finale · gated · linear)*

- **Type:** gameplay / story
- **Giver:** Mayor Orbo → hands you to **Sally Steelfield** at the Adventurers Guild.
- **Where it starts:** Town Hall, then the Adventurers Guild → the dungeon.
- **Trigger / prerequisites:** the hub (Beat 2) complete to the chosen gate.

### Hook
> **Orbo:** "You've done more for this town in a week than most do in a year. But we both know the
> real trouble's down in the caves — the miners can't work, and that's the root of all of it. I've
> asked Sally at the Guild to take you down there. End this, and Town City's back on its feet."
>
> **Sally:** "So you're the newcomer everyone's on about. Good — I don't need a babysitter, but I'll
> take a sharp blade. Stick close, hit hard, and don't die. I'm not carrying you out."

### Objectives
1. Meet Sally at the Adventurers Guild.
2. Enter the **dungeon** (the single v1 theme), fight through.
3. Reach and clear **the source of the trouble** (▶ a boss / a monster nest / a blocked passage).
4. Return to town.

### Systems exercised
Combat, the procedural dungeon (single theme), a boss/objective, exploration.

### Branches & choices
**Decided (2026-06-29): Sally is NOT a companion.** She sends you into the dungeon **alone** (no escort/ally AI to build) and **appears once it’s cleared to congratulate you** — the player **never sees her fight** (a line can imply she "took the other tunnel"). Sally’s larger role is the player’s **combat mentor**: she introduces new combat techniques and weapons as the game progresses (WORLD_BIBLE §8).

### Rewards
A big money payout, rare gear / crafting materials, **the mine reopens** (slump resolved), and a
major reputation gain across town.

---

## Beat 4 — "Town City Thanks You" *(wrap · linear)*

- **Giver:** Mayor Orbo (with the cast gathered, if feasible). **Where:** Town Hall.
- **Trigger:** Beat 3 complete.

### Hook
> "The mine's open. The store's stocked, the Pebble's full, and folks are smiling again — and it's
> because of you. You're not the newcomer anymore. You're one of us… though I've a feeling this is
> only the start of your story here."

### Objectives
1. Return to Orbo; receive the town's thanks.

### Systems exercised
Dialog, payoff.

### Rewards
Town-wide reputation, money, and a permanent perk or recognition of your **own place** in town.

### Notes — post-v1 hooks (don't resolve)
Tease the parked future without paying it off: a glimpse of **Han de Seciro** watching from the
edge of the crowd (the treasure-hunter mystery), and/or a cryptic word from **Fredward** about the
land. These set up the main plot that v1 leaves open (GDD §4.1).

---

## Authoring notes (maps to the built QuestSystem)

- The prototype's **`QuestSystem`** is data-driven (`Quest` `.tres`, `COLLECT_ITEM` / `REACH_FLAG`
  objectives, rewards via `DialogueEffect`), with a **notice-board task** variant — so these beats
  drop in as resources without new code. Hub errands suit the board or direct NPC givers.
- Dialog runs through **Nathan Hoad's Dialogue Manager** (`.dialogue` files; conditions/effects via
  the game-facing `Dialogue` autoload: item, reputation, quest, flag, mood, time) — gating (e.g.
  finale unlock) uses a flag the hub sets.
- **Open design calls (▶):** ~~the cave problem's exact nature~~ (RESOLVED 2026-06-29 — gem-eating
  monsters, WORLD_BIBLE §9); the hub gate (all vs 2-of-3); ~~whether Sally is a companion~~ (RESOLVED
  2026-06-29 — no; combat mentor only); the boss/objective at the dungeon's end.
- **Cast/venue coverage:** all six v1 characters (Orbo, George, Barry, Kippie, Droghnaut, Sally) and
  all five venues appear. Zena (Orbo's wife) can add flavor at Town Hall but isn't required.
