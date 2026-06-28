# Town City — Full-Game Audit Report

> Generated 2026-06-27 via a multi-agent audit (8 subsystem auditors → adversarial
> verification of every serious finding → synthesis). 1,020k tokens, 15 agents.
> **All confirmed findings below have since been FIXED** (see "Fixes applied").

## Summary

Overall health is strong: **no blockers and no confirmed major issues.** Of six serious
findings raised, adversarial verification against the real code rejected five as false
positives and downgraded the remaining one from major to minor. Net tally: 0 blockers,
0 majors, 3 minors (now fixed), 5 false positives filtered out. The game is fully playable
end-to-end with no reproducible crashes, soft-locks, unreachable content, or save/load
breakage in the audited surface.

## Fixes applied (post-audit)

- **Hand-authored dungeon exits** (`dungeon_mine.tscn`, `dungeon_caverns.tscn`) — added
  `target_spawn_point = &"from_dungeon"` to both `ExitTeleport` nodes so players exit at the
  dungeon gate instead of town center (matching the procedural/new dungeons).
- **Gus reputation now economic** (`global/shop/shops/general_store.tres`) — set
  `reputation_npc = &"gus"` (Gus's shopkeeper has `npc_id = &"gus"`). Building Gus's
  reputation (e.g. via the `task_gus_*` board tasks) now discounts the general store, so that
  reputation reward is meaningful rather than cosmetic.
- **PauseMenu gamepad defense** (`ui/pause/pause_menu.gd`) — `_other_ui_blocking()` now also
  checks CraftingUI/UpgradeUI, so the joypad "pause" button can't stack the pause overlay on
  top of those menus (keyboard was already covered by `ui_cancel` consumption + autoload order).

## Verified clean / false positives (dismissed after checking the real code)

- **Quest deadline/cooldown off by one game day** — False positive. `quest_system.now_minutes()`
  carries a constant +1440 offset on both the set side and the check side, so it cancels in
  every comparison; saved deadlines persist as absolute values from the same formula.
- **Unreachable Gus task quests** — False positive. `task_gus_crystals`/`task_gus_timber` are
  dispensed by the town notice board (keyed by bare quest id via `give_task`), not by an NPC
  giver, so the absence of a `gus` NPC *definition* does not gate them.
- **Unguarded null deref in enemy death loot spawn** — False positive. `WorldItem.spawn` runs
  synchronously inside `Health.died` before the function's only `await`, so `get_parent()` is
  guaranteed non-null; the death path also disables hurtbox monitoring first.
- **Three "unreachable" building interiors** (`arcade_inside`/`brewery_inside`/`farm_inside`) —
  False positive. These are self-documented blank authoring templates, superseded by the
  `stages/interiors/` RoomInterior system; town gates correctly point to the live interiors.
- **PauseMenu missing CraftingUI/UpgradeUI checks** — Largely false positive on keyboard
  (autoload ordering + `ui_cancel` consumption prevent stacking); only the gamepad-button edge
  was real, and it is now fixed.

## Coverage

Audited: boot + autoloads + input map; save/load (all stateful autoloads incl. quest v2 +
HouseUpgrades); quests + dialogue + reputation (winnability/offering of every quest, .dialogue
validity, task givers/board); combat + enemies + animals; world/scene reachability (full
teleport graph: town gates, wild-area dungeon entrances, interior leave doors, dungeon exits +
their spawn markers); items/economy/crafting/harvest; UI/menus/HUD; and a project-wide grep for
the engine-fatal gotchas (`:=` Variant inference, `#` in scene files, cold-cache class
instancing, zero-init cooldowns, broken resource paths).
