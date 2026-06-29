# Town City — UI Overhaul Brief (for the design LLM)

> **STATUS — DONE (shipped).** This overhaul has been fully implemented in-engine. The frosted
> **glass UI is retired**; the flat **sticker** theme shipped as `res://ui/town_city_theme.tres`
> (now the **project default theme**), with `res://ui/ui_style.gd` as the flat helper (the old
> `ui/glass_style.gd` is kept only as an unused package). The **HUD and every menu/overlay listed
> below** were rebuilt to the `docs/design/handoff_town_city_ui/*` designs — Player Hub Menu, Shop,
> Pause + Settings/Controls, Death, Save/Load, Main Menu, all HUD overlays (tracker, toasts,
> prompt, onboarding, dialogue balloon), the crafting/brewing/upgrade windows, and the minigame
> frame. Reusable shells `ui/menu_window.tscn` + `ui/list_card.tscn` exist. This brief is retained
> as the design record; treat it as historical, not a to-do list.

You already delivered the **Combat HUD** package (`town_city_theme.tres`, `combat_hud.tscn`,
`combat_hud.gd`). That flat "sticker" style — cream panels, 3px ink outlines, no shadows,
restrained color — is now the **locked design language for the whole game**. We are retiring
the old frosted-glass UI everywhere.

This document describes **every other menu/overlay in the game** structurally, so you can design
and deliver Godot scenes (and the theme additions they need) in the new style. The HUD itself is
being ported in-engine by us; **your job is the menus and overlays below.**

---

## 1. What you're working against (the design system)

- **Theme:** `res://ui/town_city_theme.tres` (your file). It ships fonts (Chakra Petch SemiBold =
  display; Space Grotesk Bold = body), the cream/ink palette, and these **type variations**:
  `Display`, `DisplayGold`, `Dim`, `Gold`, `Chip`, `QuestTab`, `QuestCard`, `HotbarOuter`,
  `IconWell`, `Keycap`, `SlotButton`, `BarOuter`, `MeterHP/SP/MP`.
- **Palette (locked):** ink `#0e0d12`, cream `#e7e1d4`, cream-bright `#fbf8f0`, text `#221f1a`,
  dim `#6a655c`, gold `#c8941e`, health `#ef5340`, stamina `#5ba36a`, mana `#8b6fc4`.
- **The theme is being set as the project default theme**, so any `Label`, `PanelContainer`,
  `ProgressBar`, `Button`, etc. inside a menu inherits the look for free. Design to the theme;
  only add `theme_type_variation` overrides where a node needs a specific role.

### 1a. The theme needs to GROW into a full menu kit — please design these additions

The current theme covers the HUD. Menus need more. Please **extend `town_city_theme.tres`** with
base styles + new type variations so every screen is cohesive. Concretely, we need:

- **Base `Button`** (normal / hover / pressed / focus / disabled) in the sticker style — cream
  fill, 3px ink border, radius 5, ink text; hover = cream-bright; disabled = dim text. (Menus are
  full of plain Buttons that currently fall back to Godot's gray default.)
- **`ButtonPrimary`** — the affirmative action (Buy / Craft / Respawn / New Game): gold fill, ink
  text. **`ButtonDanger`** — destructive/quit: muted, with a warm outline.
- **`TabButton`** — the toggle tabs in the player menu (idle cream, selected cream-bright + gold
  underline or gold fill). 6 tabs, ~150×40.
- **Base `LineEdit`, `HSlider`, `CheckButton`, `ScrollBar`** in the sticker style (used in
  Settings: volume/sensitivity sliders, fullscreen toggle).
- **`Window`** — the standard centered menu panel: cream, 3px ink border, radius 6, generous
  content margin (~18). This is the shell every full-screen menu sits in.
- **`Title`** (Chakra Petch, large, ink), **`TitleGold`** (gold variant for level-ups/quest
  headers), **`Subtitle`**/section header (Chakra Petch, medium), **`Card`** (a row/entry panel:
  cream, 3px ink, radius 5, ~10px margin — the repeating list item), **`CardLocked`** (same but
  dim/desaturated for gated content).
- **State accent colors** as named theme colors or small variations: `Ready` (stamina-green
  "affordable/✓"), `Shortfall` (health-red "can't afford / failed"), so list rows can tint
  consistently instead of hardcoding.

Deliver these as edits to `town_city_theme.tres` plus a short table of "which variation to use
where." Keep color restraint: gold = titles + affirmative only; green/red = state only;
everything else cream/ink.

---

## 2. Conventions every scene must respect (integration contract)

These are hard requirements from our codebase — please honor them in the scenes you build:

1. **No glass, no shadows, no blur.** Flat sticker only. Remove any `material`/shader on panels.
   Full-screen backdrops are a flat translucent **ink** wash (≈ `#0e0d12` at ~50% alpha), **not**
   black, **not** frosted.
2. **Containers, not absolute pixels.** Use anchors + `VBox/HBox/Grid/Center/Margin/Scroll`
   containers so layouts scale to any resolution. Center full-screen menus with a
   `CenterContainer → PanelContainer(Window)`.
3. **Two surface tiers only:** the **Window** (the menu shell) and the **Card** (a repeating list
   row/entry). Don't invent a third nested panel depth — the old UI's panel-in-panel-in-panel is
   what we're flattening.
4. **`unique_name_in_owner` (`%Name`) on every node our scripts touch** (titles, lists, money
   labels, progress bars, buttons). Our controllers look nodes up by unique name; keep the names
   stable per the specs below or tell us the new names.
5. **Accessibility font scaling:** menus route every font size through a `_fs(base)` multiplier
   (0.7–1.6). Prefer theme font sizes / type variations over hardcoded `font_size` so this keeps
   working; where you must set a size, set it on a named node we can rescale.
6. **Controller + keyboard focus:** every interactive control is a real focusable `Button`/etc.
   wired into a focus loop (you did this for the hotbar). Menus grab focus on their primary
   control when opened. Keep `focus_mode = ALL` on actionable controls.
7. **Pause/clickblock:** full-screen menus put a `mouse_filter = STOP` backdrop behind the Window
   so the world doesn't receive clicks. Tracker/toasts/prompt are click-through (`IGNORE`).
8. **Most menus are built in code today.** You don't have to match that — **prefer delivering
   `.tscn` scenes** (like `combat_hud.tscn`) that we can instance, plus the controller hooks listed
   per menu. Where a menu's body is a dynamic list, build the **static chrome** as a scene with an
   empty, named container (e.g. `%List`) that we populate at runtime.

---

## 3. The menus & overlays to design

Grouped by type. For each: when it shows, the shell size/anchor, the structure, and the
theme roles to apply. Sizes are current values — treat as guidance, adjust for the new style.

### A. Player Hub Menu — the big one (`player_menu`)
- **Shell:** centered **Window** ~900×560, on a full-screen ink backdrop. Pauses game.
- **Top:** `Title` "Menu"; below it a **tab bar** of **6 `TabButton`s** in this exact order:
  `Inventory · Skills · Crafting · Quests · Reputation · Map`; below that a `Dim` hint line
  ("LB / RB or click to switch tabs • Esc to close"). Bottom: a `Close` button.
- **Body:** one content area (`%Content`) that swaps per tab. Design each tab body:
  - **Inventory:** a category filter row (`All` + one toggle per item category), a
    `ScrollContainer → GridContainer (6 columns)` of **item slots** (~120×96 Card: thumbnail +
    `x{count}` badge, tooltip), and **below the grid a fixed 8-slot hotbar row** of ~64×64 cells
    (slot number 1–8 faint in corner + thumbnail). Slots are **drag sources** (drag data
    `{"item_id": id}`); hotbar cells are **drop targets**. Reuse the HUD hotbar cell look
    (`SlotButton`) for the hotbar row so they read as the same object across HUD and menu.
  - **Skills:** 4 columns (Melee / Ranged / Magic / Survival). Each column = header
    "{name} — Lv {n}", an XP `ProgressBar`, an auto-bonus line (gold/dim), a "Perk points: N"
    line, then perk rows: `[perk name (rank/max)] [MAX | "{cost} pt" button]` + wrapped
    description (grayed when locked).
  - **Crafting:** scroll list grouped by station (`Subtitle` headers: Smelter / Workbench /
    Cooking Station / Bar Mixing Station), each recipe a read-only line
    "name: inputs → output xN (time)".
  - **Quests:** scroll list grouped by tier (`Main Quests / Side Quests / Tasks` headers). Each
    quest = tier badge `[MAIN]/[SIDE]/[TASK]` + title (gold if task) + a `Track/Tracked` toggle
    button; optional `[TIME-SENSITIVE]`, `Stage X/Y`, countdown; wrapped description; objective
    lines `[ ]/[x] desc (cur/max)` (first objective larger).
  - **Reputation:** title + scroll list of `NPC name … {tier} (score)` rows, tier color-coded.
  - **Map:** title "Discovered Areas" + scroll list of `[color swatch] area name` rows + a dim
    "(more to discover)" hint.
- **Signals:** emits `opened` / `closed` (HUD listens). Tabs cycle on `hotbar_next/prev`.

### B. Full-screen menus (centered Window + ink backdrop, pause game)
- **Skill Tree** (standalone, same data as the Skills tab): Window ~720 wide. Title "Skills";
  header row `Level X` + `Points: N`; an XP `ProgressBar` + "150 / 300 XP"; **3–4 columns** of
  skill rows (it is a **grid of columns, NOT a node-graph with connector lines**); Close button.
- **Pause Menu:** Window ~280 wide. `Title` "Paused" + a vertical stack of buttons (Resume, Save,
  Load, Settings, Controls, Main Menu, Quit). Two sub-panels swap in place:
  - **Settings:** Master volume `HSlider`, Music/SFX/Ambient sliders, Mouse Sensitivity slider,
    Fullscreen `CheckButton`, "UI Text Size" Small/Normal/Large toggle group, Back button.
  - **Controls:** scroll list, 2-column grid of `[glyph] Action` rows (glyphs come from our
    `InputDevice` autoload — leave them as labels we fill), Back button.
- **Death Screen:** Window ~320 wide. Big `Title` "You Died" (use health-red), a dim summary line
  ("Dropped X consumables — lost Y XP"), `Respawn` (primary) + `Quit to Desktop` buttons.
- **Save Slot Menu:** Window ~420 wide. Title "Save Game"/"Load Game", **3 slot rows** (each a
  wide Button: "Slot 1 — Empty" or "Slot 1 — Saved (timestamp)"; disabled when empty in Load
  mode), Back button.
- **Main Menu / Title screen:** the one screen with **no game behind it** — full opaque dark
  field (not the ink wash, a deliberate title backdrop), a large `Title` "Town City", and buttons
  New Game (primary) / Continue / Load Game / Quit. No Window panel; buttons sit on the field.
  This is the place to make the brand feel strongest — feel free to art-direct it more than the
  others (logo lockup, etc.), as long as it uses the kit's fonts/colors.

### C. Commerce & crafting windows (centered Window, pause game)
- **Shop:** Window ~600×440. Title (shop name; may append "— Gold rep, 10% off"), a money line,
  then **two columns**: **Buy** (scroll list of Cards) and **Sell** (scroll list of Cards + a
  "Sell All" button under the header). Buy/Sell Card = item name, price line, optional dim "Base
  value", a Buy/Sell Button (Buy disabled when unaffordable). **Locked Card** = "? ? ?" + "Unlocks
  at Gold reputation" (use `CardLocked`). "Sell All" opens a small confirm Window (item list +
  green total + Confirm/Cancel).
- **Crafting station** (Smelter/Workbench/Cooking/Bar): Window ~820×480, **3 columns** —
  **Recipes** (scroll list of selectable Buttons, tinted green "✓ Ready" / dim "Need N more X"),
  **Center** (title "Ingredients" + a row of **ingredient drop-slots** ~96×70 showing
  name/have-count/staged-state, an "→ output xN (time)" line, status line, a `ProgressBar` shown
  while working, and Auto-fill / Craft / Collect buttons), and **Your Bag** (scroll list of
  draggable item Buttons; drag data `{"craft_item": id}`). Has the ink backdrop.
- **Brewing station** (simpler bar/brewer): Window ~500×400. Title + a scroll list of recipe
  Cards (output xN, "Needs: …", red shortfall line, brew-time line, Brew button). While brewing:
  "Brewing: X" + `ProgressBar` + "Ready in ~N min". When done: "Ready: X" + Collect button.
- **House Upgrade:** Window ~440×520. Title "Improve Home" + money line + scroll list of upgrade
  Cards (name, wrapped description, "Cost: $400 + 8× Wood Log", and a state: "OWNED" green / Buy
  button / disabled button with reason).

### D. HUD-adjacent overlays (no pause; anchored, mostly click-through)
- **Quest Tracker:** top-left, below the HUD info strip. A compact panel (~240 wide) — reuse your
  **`QuestTab` + `QuestCard`** look from the combat HUD: gold "MAIN QUEST/SIDE QUEST/TASK" tab over
  a cream card with quest title + (optional "Stage X/Y") + one "[NEXT STEP] objective (cur/max)"
  line. Click-through.
- **Notification Toasts:** top-right stack, newest on top, max 5, auto-fade (~2.2s hold + 0.8s
  fade). Each toast = your **`Chip`** style. Variants: item "+5 Lava Ash" (default), level-up
  (gold, larger), quest-complete (gold), task-failed (amber), reputation ±N (green/red). Multi-
  line allowed. Click-through.
- **Interaction Prompt:** small popup (bottom-center under reticle, or bottom-right — your call;
  the HUD uses bottom-center). One or more lines, each a **`Keycap`** + verb, e.g. `[E] Talk`.
  Glyphs come from `InputDevice` (leave as labels we fill). Click-through.
- **First-Run Onboarding Banner:** top-center, one-time, fades in/out, auto-dismiss after 30s or
  on a small "X". One line: "[E] Interact  [I] Inventory  [J] Quests  [Esc] Pause" + dismiss X.
  Cream Chip/Card.
- **Dialogue Balloon:** bottom-wide panel (~16px side margins, ~360 tall). Left: 96×96 portrait
  frame (texture, or a big initial letter on a tinted square). Right: speaker `name` (gold), a
  typewriter body text (bbcode), a scroll list of numbered response **Buttons** ("1. Option …",
  hotkeys 1–9), and a dim hint line ("► Space / Click to continue"). Pauses game; full-width.
- **Minigame frame** (Simon / Whack arcade games): centered Window on an ink backdrop with a big
  `Title`, a score/status line, a grid of game Buttons (Simon = 2×2 colored pads ~150²; Whack =
  3×3 cells ~110²), and a "Done" button. The colored pads/cells are gameplay, keep them vivid —
  but the surrounding frame is the standard Window. We supply the game logic; you supply the
  frame + a clean grid layout.
- **Area Title Card:** already styleless (big outlined title + tagline, fades in over the world).
  Just confirm the font is Chakra Petch and the cream/gold palette; no panel.

---

## 4. What to deliver

1. **Theme additions** to `town_city_theme.tres` (section 1a) + a one-page "variation → usage"
   table.
2. **Reusable scene templates** we can instance/extend:
   - `menu_window.tscn` — the standard centered Window shell (backdrop + panel + title slot +
     `%Body` container + optional footer button row). Most menus are just this + a body.
   - `list_card.tscn` — the repeating Card row (with named slots for title / detail lines /
     action button), and a `CardLocked` variant.
   - Tab-bar fragment for the player menu.
3. **Per-menu body scenes** where the structure is non-trivial (player menu tabs, shop two-column,
   crafting three-column, dialogue balloon, pause settings). For pure lists, the Window shell +
   an empty named container is enough — we fill it.
4. Keep node names from the specs above (or hand us a rename map). Mark every script-touched node
   `unique_name_in_owner`.

Build it like you built the combat HUD: anchors + containers, theme variations over hardcoding,
real focusable controls, zero glass. When in doubt, match the combat HUD scene's conventions
exactly — it is the reference implementation.
