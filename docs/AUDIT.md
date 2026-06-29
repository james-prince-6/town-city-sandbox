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

## 2026-06-29 — Codebase audit (multi-agent) + bug-fix pass

> Second multi-agent audit pass: ~16 candidate findings → adversarial verification →
> **10 confirmed real bugs (all fixed)** + 2 partials completed afterward. Two further
> claims were rejected as false positives.

### Confirmed bugs fixed (by file)

- **`global/systems/clock.gd`** — auto-pause menu wiring (PlayerMenu/ShopUI/BrewingUI/
  CraftingUI/UpgradeUI) ran in `Clock._ready` before those later-registered autoloads
  existed, so the clock never paused for those menus; now deferred via
  `_wire_blocking_menus.call_deferred()`.
- **`entities/animals/animal.gd`** — facing yaw was inverted (`atan2(heading.x, heading.z)`
  → `atan2(-heading.x, -heading.z)`); animals ran backwards and hostile bites whiffed
  because the model faced away from its target.
- **`ui/minigames/simon_minigame.gd`** — tapping a pad during the post-round gap indexed
  `_sequence` out of bounds (runtime error/crash); input is now locked (`_state = SHOWING`)
  during the gap.
- **`entities/items/consumables/consumable_item.gd`** — `_throw_from_camera()` could crash
  on a null world; now null-guards `SceneManager.current_world()` before `add_child`.
- **`ui/death/death_screen.gd`** — the death XP penalty was always 0 (it read the inert
  `Progression.get_xp()` shim); now sums real per-skill use-XP via `get_skill_xp()` over
  Melee/Ranged/Magic and reconciles displayed vs actually-removed XP, so death finally has
  the intended stakes.
- **`global/systems/progression.gd`** — `magic_cooldown_mult()` read the *ranged* cooldown
  stat key; now reads `&"magic_cooldown_reduction"` so ranged perks no longer speed up spells.
- **`entities/enemies/enemy_stats.gd`** — added the missing `@export var attack_windup`
  (default `0.0`), re-enabling the normal-attack telegraph path in `enemy.gd` that silently
  no-op'd without the property.
- **`ui/dialog/dialogue.gd`** — fixed a `Camera3D` leak when a new conversation starts mid
  camera ease-back; the prior cam is now guarded before `queue_free`.

### Partials completed afterward

- **`stages/interiors/adventurers_guild.gd`** (+ new `stages/dungeons/procedural/guild_mine.tscn`)
  — the Guild's Mine entrance exited to Town; it now points at `guild_mine.tscn` (inherited
  from `generated_dungeon.tscn`) whose exit returns to the Guild (spawn `from_town`).
- **`entities/critters/critter.tscn` + `critter.gd`** — critters had no HurtBox so weapons
  passed through them; added a HurtBox (team ENEMY) in the scene and wired
  `hurt_box.hit -> health.apply_damage` in `critter.gd` so they take damage.

### Rejected (false positives)

Adversarial verification dismissed three claims — do not treat as bugs: a dialogue
name-tint "clobber" (the addon emits `got_dialogue` deferred, so no clobber occurs); a
`quest_system` re-entrancy double-grant (the implicated trigger never fires that path); and
a collector save-persistence "gap" (the per-scene reset is intended behavior).
