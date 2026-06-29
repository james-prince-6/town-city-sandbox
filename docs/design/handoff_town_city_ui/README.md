# Handoff: Town City — UI Screens

## Overview
This package specifies six UI screens for **Town City**, a comedic first-person combat/craft RPG built in **Godot 4**:

1. **Combat HUD** — in-world heads-up display
2. **Player Menu** — full pause-screen inventory hub (Inventory / Skills / Crafting / Quests / Reputation / Map)
3. **Shop Menu** — vendor buy/sell ("Barry's Bar & Bric-a-Brac")
4. **Dialog Menu** — NPC conversation with branching choices
5. **Main Menu** — bright cartoon title screen
6. **Pause Menu** — frosted pause overlay with Settings & Controls sub-panels

## About the Design Files
The `.dc.html` files in this bundle are **design references** — HTML/CSS prototypes that show the intended look, layout, copy, and interaction behavior. **They are not production code to copy.** The task is to **recreate these designs inside the existing Godot 4 project**, using its established UI conventions:

- Most menus are **built entirely in GDScript** (no `.tscn`), mirroring `pause_menu.gd` / `main_menu.gd` / `death_screen.gd`. Some have scenes (`player_menu.tscn`, `shop_ui.tscn`, `inventory_ui.tscn`, `dialogue_balloon.tscn`, etc.).
- A shared style helper exists: **`ui/ui_style.gd`** (referenced as `Flat` via `preload`), plus **`ui/town_city_theme.tres`** / **`ui/theme/ui_theme.tres`** and **`ui/glass_style.gd`**. Put the tokens below into the theme/helper and reuse them; don't hardcode per-widget.
- Autoload singletons drive state: `Inventory`, `Hotbar`, `QuestSystem`, `SaveManager`, `SceneManager`, `Clock`, `MenuManager`, `NotificationFeed`, `GameState`, `InputDevice`, etc. Wire the UI to these — don't invent parallel state.
- Fonts are already in the project: `ui/fonts/ChakraPetch-SemiBold.ttf` and `ui/fonts/SpaceGrotesk-Bold.ttf`.

## Fidelity
**High-fidelity.** Colors, typography, spacing, borders, and interactions are final. Recreate pixel-faithfully using Godot Controls + a shared Theme. All designs are authored at a **1200 × 675** reference frame (16:9); scale layouts proportionally to the actual viewport using anchors/containers rather than fixed pixel positions where possible.

---

## Design Tokens

### Colors
| Token | Hex | Use |
|---|---|---|
| `ink` | `#0e0d12` | Borders (3px standard), darkest outlines, hotbar tray bg |
| `text` | `#221f1a` | Primary text on light; dark UI chips/badges; near-black fills |
| `dim` | `#6a655c` | Secondary/inactive text, meta labels |
| `cream` | `#e7e1d4` | Default panel / card / chip surface |
| `bright` | `#fbf8f0` | Selected/active surface (one step lighter than cream) |
| `panel-cream-α` | `rgba(231,225,212,0.92–0.95)` | Floating menu panels over gameplay |
| `dark-chip` | `#3a3226` | Dark inset chips (name plates, gold counter, portraits) |
| `track` | `#cabfac` | Slider tracks, scrollbar thumb, divider rules |
| `divider` | `#cabfac` / `#d6cdba` | Hairline rules between rows |

### Accent / semantic colors
| Token | Hex | Use |
|---|---|---|
| `gold` | `#c8941e` | Primary accent: confirm buttons, selection caret, currency, XP/level highlights, perk buttons |
| `gold-text` | `#e7d9a8` / `#1a1407` | Text on dark gold counter / text on gold buttons |
| `green` (ready/positive) | `#5ba36a` | Craftable, completed objectives, positive rep, sell price |
| `red` (alert) | `#ef5340` | Time-sensitive, missing materials, hostile rep, low health |
| `blue` | `#4f9ed6` / `#4a86a4` | Side quests, materials category, info |
| `purple` | `#8b6fc4` | Goo/sewers flavor |
| Category — Weapons | `#cf9279` (muted) / `#df6f3c` (vivid) | Inventory item tinting |
| Category — Consumables | `#8fb89a` / `#57a065` | |
| Category — Materials | `#93b2cc` / `#4f9ed6` | |
| Category — Quest | `#cdba88` / `#d2a233` | |
| Category — Junk | `#b1a796` / `#8f8576` | |

> The Player Menu supports 3 item-color schemes (Vivid / Muted / Tint). Muted (scheme **B**) is the default. Full palette table is in the Player Menu section.

### Main Menu (bright variant only)
The Main Menu deliberately breaks from the muted in-game palette into a **bright cartoon** look:
- Sky gradient: `#5fc3e4 → #7fd0e8` (top) over `#ffe08a → #ffd54a` (horizon/ground band)
- Sun: `#ffec9e` with 5px ink border; sunburst is a slowly rotating `conic-gradient` of `rgba(255,255,255,.34)` wedges
- Hills: `#5ba36a` / `#69b478` rounded blobs, 5px ink border
- Goo blobs (bobbing): purple `#8b6fc4`, red `#ef5340`, blue `#4a86a4`, each 5px ink border, organic `border-radius`
- Clouds: white `#fff`, 4px ink border, pill shape
- Title fill `#fbf8f0` with **6px ink text-stroke** and **8px 8px `#c8941e` hard shadow**
- Buttons: chunky **sticker** style — 4px ink border, 12px radius, **hard offset shadow `4px 4px 0 #221f1a`** (grows to `7px 7px 0` + `translate(-3px,-3px)` when selected), per-button accent fill when selected (green/blue/gold/red)

### Typography
- **Display / headings / labels / buttons:** `Chakra Petch` SemiBold (600) — also 700 for big titles. (`ui/fonts/ChakraPetch-SemiBold.ttf`)
- **Body / paragraph / dialog lines / meta:** `Space Grotesk` (500/600, 700 Bold). (`ui/fonts/SpaceGrotesk-Bold.ttf`)
- Type sizes (at 1200×675 reference):
  - Screen title (Paused, Settings): **38–40px / 700**
  - Big title (Town City): **108–120px / 700**, letter-spacing −1 to −2
  - Panel/section heading: **20–28px / 600**
  - Menu button label: **19–23px / 600–700**, letter-spacing .3–.5
  - Tab / mode label: **14–15px / 600**
  - Dialog line: **21px / 500**, line-height 1.4
  - Choice text: **17px / 600**
  - Body / item name: **13–15px / 600**
  - Meta / sub-label: **10–12px / 600–700**, letter-spacing .3–1.5 (uppercase eyebrows use 1–1.5)
  - Tiny count badges: **10px / 700**

### Borders, radius, shadows, spacing
- **Standard border:** `3px solid #0e0d12` (in-game menus). Main Menu uses `4–5px`.
- **Selected outline:** `3px solid #ffffff` (white) on grid cells/cards inside dark panels; gold left-border (`4px`) on list-style selections.
- **Radius:** chips/buttons `5–8px`; pills/category filters `999px`; big panels `6–8px`; grid thumbs `3–4px`.
- **Shadows:** in-game menus are mostly flat (no soft shadows — flat ink borders do the work). Main Menu uses **hard offset shadows** only (`Npx Npx 0 #221f1a`), never blurred.
- **Spacing rhythm:** panel padding 16–22px; gaps 6–14px; card grids use 8px gaps; row lists 5–8px gaps.
- **Frame:** every screen is a 1200×675 rounded container, `background:#0e0d12`, `overflow:hidden`.

### Iconography
No raster icons. Glyphs are **typographic**: `▸` caret (selection), `▾` scroll hint, `‹` back, `▶ ↻ ⊞ ✕` menu icons, `☐ ☑` quest objectives, `–`/`+` steppers, `×N` counts. Item thumbnails are **3–4 letter abbreviation chips** (e.g. `SWD`, `POT`, `ASH`) on a tinted square — in Godot these map to `item_thumbnail.gd`; use real item icons there if available, else the abbreviation fallback.

---

## Screen 1 — Combat HUD
**File:** `Combat HUD.dc.html` → Godot `ui/hud/hud.gd` + `hud.tscn` (and `quest_tracker.gd`, `first_run_panel.gd`).
**Purpose:** Persistent in-world status while playing. Always visible, non-interactive (pass-through), anchored to screen edges.
**Layout & components:** health/stamina/mana bars, hotbar (8 slots, mirrors `Hotbar` autoload, selected slot highlighted), quest tracker, minimap/compass, crosshair, notification feed anchor. Bars use track `#cabfac` + ink border with semantic fills (health red `#ef5340`, stamina gold, mana blue). Hotbar cells: 58px, cream bg, ink border, slot number top-left in `#6a655c`, selected = bright bg + white outline. *(Re-open `Combat HUD.dc.html` for exact bar positions/sizes.)*

## Screen 2 — Player Menu
**File:** `Player Menu.dc.html` → `ui/player_menu/player_menu.gd` + `.tscn`, `inventory_slot.gd`, `hotbar_drop_slot.gd`; tabs map to `inventory_ui`, `skill_tree_ui`, `quest_log`.
**Purpose:** Paused hub with 6 tabs. Opens with `I`; `Esc` closes; `Q/E` or `[`/`]` switch tabs.
**Layout:** centered 900×560 panel (`rgba(231,225,212,0.9)`, 3px ink, 6px radius, 18px padding). Header row: "Menu" title (Chakra 26/600) + CLOSE·ESC chip. Tab bar: 6 equal tabs (active = bright bg + text color, inactive = cream + dim). Body switches by tab.
**Tabs:**
- **Inventory:** category filter pills (All/Weapons/Consumables/Materials/Quest/Junk); 6-column grid, 96px rows, 8px gap; draggable item cards (ab chip + name + `×count` badge); arrow-key focus (white outline); focused-item info line; **HOTBAR** row of 8 drop slots (drag item → slot, or press 1–8 to assign). Item color scheme switcher (Vivid/Muted/Tint) lives in the bottom bar.
- **Skills:** 4 columns (Melee/Ranged/Magic/Survival), each with level, XP bar (green fill `#5ba36a` on track), bonus line (gold), perk points, perk cards with cost/MAX buttons (locked perks dimmed).
- **Crafting:** master-detail. Left = stations (Smelter/Workbench/Cooking/Bar Mixing) with recipes; right = selected recipe (ab thumb, name, flavor, INGREDIENTS list with `have/need` colored green/red, output line, Craft button gold when craftable else disabled cream).
- **Quests:** grouped Main/Side/Tasks; each quest card has colored badge (MAIN gold / SIDE blue / TASK green), title, optional stage, Track/Tracked toggle, `[TIME-SENSITIVE]` flag in red, objective checklist (`☐`/`☑`, `cur/max`).
- **Reputation:** rows of NPC name + tier (color-coded) + signed score.
- **Map:** left map graphic placeholder; right "Discovered Areas" list with color swatches.
**Item color palette (3 schemes)** — see the `_pal()` table in `Player Menu.dc.html` for exact per-category hex triples `[card, thumb, ab-text]` for schemes A (Vivid) / B (Muted, default) / C (Tint).
**Bottom bar:** BOX COLORS scheme buttons (left) + control hints (right): `LB/RB switch tabs · ↑↓←→ navigate · 1–8 assign · drag to hotbar · Esc close`.

## Screen 3 — Shop Menu
**File:** `Shop Menu.dc.html` → `ui/shop/shop_ui.gd` + `shop_ui.tscn`.
**Purpose:** Buy/sell with a vendor. Opens on interact (`F`/`Talk to Barry`).
**Layout:** 920×560 panel. Header: vendor portrait chip `BAR` (dark `#3a3226`), shop name "Barry's Bar & Bric-a-Brac" + tagline, **player gold counter** (dark chip, gold "G" disc + `#e7d9a8` amount), LEAVE·ESC. **Buy/Sell toggle** (2 equal tabs). Body = list (left) + detail panel (right, 320px).
- **List rows:** ab thumb (40px, `#d6cdba`), name + sub (category, or `own ×N` in sell mode), price with gold "G" disc; selected row = bright bg + white border. Buy prices in `text`, sell prices in green.
- **Detail panel (cream, 3px ink):** 66px ab thumb, name, category, flavor desc, divider, UNIT/SELL PRICE row, **QUANTITY stepper** (–/+ chunky buttons, clamped 1..99 buy / 1..owned sell), TOTAL COST/YOU GET dark chip (gold amount), **confirm button** (gold when affordable, else disabled cream — "Buy"/"Sell"/"Not enough gold"/"Not for sale").
- **Toast** on transaction; gold updates live. Keyboard: `Q/E` buy↔sell, `↑↓` browse, `←→` quantity, `Enter` confirm, `Esc` leave.

## Screen 4 — Dialog Menu
**File:** `Dialog Menu.dc.html` → `ui/dialog/dialogue.gd` + `dialogue_balloon.gd` + `dialogue_balloon.tscn` (`Dialogue` autoload, `is_active`).
**Purpose:** NPC conversation: multi-line speech then branching replies.
**Layout:** bottom dialog box (`left/right:46px`, `bottom:30px`, height 190px, `rgba(231,225,212,0.95)`, 3px ink, 8px radius, 20–24px padding). **Speaker portrait** (108px dark chip `#3a3226`, 4px ink, **no drop shadow**) sits above the box, **left edge aligned to box left (46px)**, gentle bob animation (`translateY ±3px`, 3s). **Name plate** (dark chip) to its right at `left:166px` with name (Chakra 18/600 cream) + role (`#cdb98a`).
- **Speech state:** line text (Space Grotesk 21/500, line-height 1.4); footer shows progress `n/total` + Continue/Reply + key chip.
- **Choice state:** rigid list (no card gaps) — rows divided by 2px `#cabfac` hairlines, `scroll-snap-type:y mandatory`. **Selected row:** gold `▸` caret + 4px gold left-border + `rgba(200,148,30,0.14)` bg + dark text; unselected = transparent + caret hidden + muted `#4a463f` text. Right-aligned number chip (dark when selected). Choices may carry a colored tag: `ACCEPT` (green), `SHOP` (gold), default blue. Cursor moves with `↑↓` (or hover), `Enter`/`Space` confirms, `1–4` direct select, `Esc` ends.
- **Sample tree (Barry):** intro (3 lines) → hub [Got work? / What's good to drink? (SHOP) / Heard anything? / Leave] → quest/haggle/accept, drinks, gossip branches looping back to hub; "Leave" is an end node.

## Screen 5 — Main Menu
**File:** `Main Menu.dc.html` → `ui/main_menu/main_menu.gd` (`MainMenu` autoload, layer 30, opaque backdrop).
**Purpose:** Title screen at boot and re-openable from pause.
**Buttons (exact, from code):** **New Game**, **Continue** (only shown/enabled when `SaveManager.has_loadable_save(0)`; show save slot info), **Load Game** (opens `SaveSlotMenu` in LOAD mode), **Quit**. New Game → `SceneManager.change_scene("res://stages/overworld/town_template.tscn")`, grants starter tools, starts `getting_started` quest, shows first-run controls toasts. `ui_cancel` does nothing here.
**Look:** bright cartoon variant (see Main Menu tokens above). Title "Town City" (two lines), tagline card "A small town. Big problems. Mostly goo." Buttons are sticker-style with accent fill + icon chip when selected; cursor wraps with `↑↓`, `Enter` selects. Footer: version chip + nav hint. *(The earlier dark version was rejected — use the bright one.)*

## Screen 6 — Pause Menu
**File:** `Pause Menu.dc.html` → `ui/pause/pause_menu.gd` (`PauseMenu` autoload, layer 20, `PROCESS_MODE_ALWAYS`). Opening pauses the tree AND `Clock`.
**Purpose:** Pause overlay. `Esc` opens; `Esc` again steps back from a sub-panel, else resumes. Only opens when no other UI owns Escape (`_other_ui_blocking()`).
**Backdrop:** **frosted glass, not black** — `rgba(231,225,212,0.28)` + `backdrop-filter: blur(3px)` + `rgba(14,13,18,0.42)` (use `ui/glass_style.gd` / `Flat.frost`).
**Main panel:** centered 360px, "Paused" title (Chakra 38/700), divider, cursor list: **Resume / Save Game / Load Game / Settings / Controls / Main Menu / Quit** (selected = bright bg + 3px ink border + gold caret). Handlers: Resume→close; Save/Load→`SaveSlotMenu.open(SAVE/LOAD)`; Settings/Controls→sub-panels; Main Menu→close then `MainMenu.open()`; Quit→`get_tree().quit()`.
**Settings sub-panel (440px):** back `‹` button + "Settings". Sliders (round gold thumb, ink-bordered `#cabfac` track): **Master / Music / SFX / Ambient Volume** (0–100%), **Mouse Sensitivity** (0.10–1.00, step .05). Drive `AudioServer` buses (Master/Music/SFX/Ambient with Master fallback) and player `mouse_sensitivity`. **Fullscreen toggle** (round knob, gold when on → `DisplayServer` windowed/fullscreen). **UI Text Size** radio Small(0.9)/Normal(1.0)/Large(1.2) → persist via `GameState.set_flag("ui_font_scale", …)`; Player Menu & Crafting read it on open.
**Controls sub-panel (460×520, scrollable):** 2-column `[glyph] Action` list from `DISPLAYED_ACTIONS`, glyphs via `InputDevice` (device-aware). Default keyboard glyphs: W/A/S/D move, Space jump, Shift sprint, Ctrl dodge, E interact, LMB use/attack, RMB block, Q prev, Scroll next, I inventory, K skills, J quest log, F5 quicksave, F9 quickload, Esc pause/back.

---

## State Management (wire to existing autoloads)
- **Combat HUD / Hotbar:** `Hotbar` (slots, selected), player stats node, `QuestSystem` (tracked quest), `NotificationFeed`.
- **Player Menu:** `Inventory` (items + counts), `Hotbar`, `QuestSystem`, skill/perk system, reputation system. Drag-to-hotbar and 1–8 assign call `Hotbar.set_slot`.
- **Shop:** vendor stock data + `Inventory` + a gold/currency store; buy/sell adjust both.
- **Dialog:** `Dialogue` autoload (`is_active`, current node, choices); dialog tree data resource.
- **Main Menu:** `SaveManager`, `SceneManager`, `QuestSystem`, `GameState`, `NotificationFeed`.
- **Pause:** `get_tree().paused`, `Clock`, `AudioServer`, `DisplayServer`, `GameState` (font scale), `InputDevice` (glyphs), `SaveSlotMenu`, `MainMenu`.

## Interactions & transitions
- Selection is **cursor-based** (keyboard `↑↓`/arrows + controller focus + mouse hover all move the same cursor). Confirm with `Enter`/`Space`/`A`.
- Toggles/sliders animate ~.08–.15s (knob slide, button press translate). Main Menu goo blobs bob 4–5s ease-in-out; sun sunburst rotates 60s linear.
- No blurred shadows in-game; Main Menu uses hard offset shadows only.
- Dialog choice list uses scroll-snap; long lists in Controls/Quests scroll with the styled scrollbar (thumb `#cabfac`, 3px cream border).

## Assets
- Fonts (already in repo): `ui/fonts/ChakraPetch-SemiBold.ttf`, `ui/fonts/SpaceGrotesk-Bold.ttf`. The HTML loads Google Fonts (Chakra Petch, Space Grotesk) — use the bundled TTFs in Godot.
- No image assets; all visuals are CSS/shape-based. Item thumbnails are abbreviation chips (`item_thumbnail.gd`) — swap in real item icons if the project has them.
- Theme target: fold tokens into `ui/town_city_theme.tres` / `ui/theme/ui_theme.tres` and helpers `ui/ui_style.gd`, `ui/glass_style.gd`.

## Files in this bundle
- `Combat HUD.dc.html`, `Player Menu.dc.html`, `Shop Menu.dc.html`, `Dialog Menu.dc.html`, `Main Menu.dc.html`, `Pause Menu.dc.html` — open these in any browser to see exact pixel layout, colors, copy, and behavior. They are the source of truth where this README is ambiguous.

> Note: these prototypes are authored as self-contained design references. Ignore the `support.js`/`<x-dc>` scaffolding — it's the prototyping runtime, not part of the design. Read the inline `style="…"` values and the logic class data tables for exact specs.
