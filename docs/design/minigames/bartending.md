# Mini-game / Job: Bartending @ The Flaming Pebble

> The v1 mini-game (GDD §5.4, §9.6) — the one job built to the full "meaningful progression" bar.
> **v1 constraint (James):** no mixing or creating drinks yet — just 4 fixed drinks. Mixing,
> cocktails, and new drinks are a deliberate **post-v1 tier** (see Progression / Notes).

- **Fantasy / theme:** You're working the bar at **The Flaming Pebble**, Barry Barnson's gruff,
  miner-favored dive. First-person, behind the counter — pull pints, pour spirits, keep the bar
  clean, and pocket the tips.
- **Where / who:** The Flaming Pebble (built interior). **Barry Barnson** hires you and runs the
  place; reputation with him grows as you work good shifts.

## Core loop

The 10-second action, repeated, with a cleaning beat slotted into the gaps:

1. A customer steps up to the counter and **places an order** — one of **4 drinks**: beer, wine,
   shot, or whiskey (shown as an icon/speech bubble above them).
2. **Grab the correct glass** from the rack — each drink has its own glass.
3. Go to the **right source** — beer from the **keg/tap**, the rest from their **bottle** on the
   back shelf.
4. **Pour (the skill beat):** *hold to fill, release at the fill line.* Overfill spills (waste +
   a mess), underfill leaves the customer less satisfied. **Beer** adds a **foam head** — ease off
   / tilt to pour a clean pint.
5. **Serve** the glass to the customer → collect **cash** (drink price) **+ tip**. The faster and
   cleaner the pour, the bigger the tip and the happier the customer.
6. **Clean between orders:** customers leave **messes** (spills, dirty spots). **Sweep** the floor
   or **wipe** the counter to clear them — this fills the downtime between orders and keeps the bar
   running well.

**Multiple customers queue at once** — a good shift is juggling several orders *and* the cleaning
under a shift timer.

| Drink | Glass | Source |
|---|---|---|
| Beer | Pint glass | Keg / tap *(foam head to manage)* |
| Wine | Wine glass | Wine bottle |
| Shot | Shot glass | Spirit bottle |
| Whiskey | Tumbler / rocks glass | Whiskey bottle |

## Skill element

What separates a good bartender from a button-masher:

- **Pour accuracy** — the hold-to-fill release at the line; controlling beer foam. Overpour wastes
  product and makes a mess; underpour disappoints.
- **Recognition & memory** — read the order and map it instantly to *correct glass + correct
  source* without backtracking.
- **Routing & prioritization** — with a queue, plan the path behind the bar (rack → source →
  customer), serve the most impatient first, and tuck cleaning into the gaps.
- **Time pressure** — each customer has a **patience meter**; speed and accuracy drive both tips
  and satisfaction.

## Progression

- **What improves (use-based — ties to the GDD §5.2 intent):** a **Bartending skill** that rises
  with use. Higher skill →
  - faster baseline pour and a **wider, more forgiving fill window**,
  - **bigger tips** and more **customer patience**,
  - ability to handle **more concurrent customers**,
  - *(post-v1)* unlocks **mixing / cocktails** and **new drinks**.
- **Bar upgrades (money sinks — GDD §5.6), bought via Barry / the shop:**
  - **Better tap** — faster beer pour, less foam to fight.
  - **Pre-stocked / bigger glass rack** — less running back and forth.
  - **Bus tub or bar-back helper** — auto-clears some messes.
  - **Bigger crowd capacity** — more customers per shift = more income, but harder.
- **Reward curve:** early shifts are 1–2 patient customers at a slow pace (learn the layout); the
  arrival rate and concurrency ramp over a shift and across skill levels. It stays from going stale
  via (a) rising customer pace, (b) the cleaning tax on downtime, and (c) escalating upgrade costs
  so money always has somewhere to go. v1 deliberately **tops out at "fast, clean, juggling 4
  drinks well"** — the skill ceiling is raised later by adding mixing and new drinks, not in v1.

## Economy hook

- **Produces money:** drink price (cash) **+ skill-scaled tips** across a shift, optionally on top
  of a small **base wage** from Barry.
- **Feeds the rest of the game (GDD §5.6):** that money buys gear, crafting materials, the
  workshop/house upgrades — and bar upgrades that loop back into higher bartending income.
- **Builds reputation with Barry** → friendlier dialog, quests, and (later) a profit cut or a
  stake in the bar.

## Failure state

Soft only — **no game-over**, in line with "more satisfied customers = more tip":

- **Patience runs out** → the customer **leaves angry**: no cash, no tip, and a small ding to the
  bar's satisfaction / Barry reputation.
- **Overpour** → wasted product + a mess to clean.
- **Messes left too long** → overall satisfaction drops (slower tips, faster patience drain) and a
  spot at the bar can get blocked.
- A shift runs on a **timer** and ends by **paying out total earnings**. Barry may set a soft
  **target** — miss it and you just forgo a bonus (and get a grumble), never a hard fail. The only
  real cost is lost income and reputation.

## Notes

- **v1 scope lock:** exactly **4 drinks** (beer, wine, shot, whiskey), each with its own glass;
  beer from the keg, the rest from bottles. **No mixing / no new drinks in v1.** Mixing, cocktails,
  regulars-with-preferences, and bar events are the **post-v1 expansion** of this same loop.
- **Controls (GDD §9.1):** must feel good on **KB/M and controller** — grabbing a glass, the
  hold-to-pour/release, serving, and the sweep/wipe should all sit on held-button + context
  interact.
- **Art (GDD §7.2):** first-person behind-bar in the PS2 look; simple glass/bottle/keg props,
  spills as decals/particles. Optional on-brand flourish — a brief **2D/8-bit "Perfect Pour!"** pop
  on a flawless fill, used as a deliberate "special moment."
- **Build status:** The Flaming Pebble interior **exists** in the prototype; the **job loop is
  net-new** and is the headline v1 mini-game build (GDD §9.6). It reuses existing systems:
  duck-typed `interact`, `GameState` money, reputation, the `Clock` for shifts, and the shop for
  upgrades.
- **New pieces to build:** customer NPCs that approach + order (extends the NPC system), a
  shift/time wrapper, glass-rack + keg + bottle interaction points with the hold-to-fill pour, and
  a cleaning tool (broom/rag) + mess spawner.
