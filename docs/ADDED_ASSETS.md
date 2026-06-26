# Added Assets — Crystal & Gold Tier + Shader Pack

Added 2026-06-26. A self-contained content pack that extends the existing
mining → smelting → crafting loop with a higher-tier resource chain, plus six
reusable procedural shaders and four decorative props. Everything follows the
project's existing conventions and **auto-registers** — no autoload edits needed.

> All shaders are procedural (no textures), so they import and run with zero
> setup. The new items have no `world_model` assigned (same as `copper_ore.tres`);
> they fall back to the placeholder cube until you drag a model into the `world_model`
> slot in the Inspector.

---

## 1. Shaders (`assets/shaders/`) + Materials (`assets/materials/`)

| Shader | Material | What it does | Suggested use |
|---|---|---|---|
| `lava_flow.gdshader` | `LavaFlowMaterial.tres` | Domain-warped molten lava with glowing cracks | Lava pools, fountains, caldera, rivers |
| `force_field.gdshader` | `ForceFieldMaterial.tres` | Additive fresnel shield + scanlines + pulse | Barriers, shields, dungeon gates |
| `dissolve.gdshader` | `DissolveMaterial.tres` | Noise dissolve/burn with glowing edge (`dissolve` 0→1) | Enemy death, harvestable break, teleport-in |
| `hologram.gdshader` | `HologramMaterial.tres` | Scanline hologram + flicker + fresnel | Quest markers, shop holograms, ghosts |
| `magic_portal.gdshader` | `PortalMaterial.tres` | Swirling vortex disc | Teleporters, dungeon entrances |
| `energy_crystal.gdshader` | `EnergyCrystalMaterial.tres` | Translucent glowing gem with pulsing core | Crystal harvestable, crystal lamp, gems |

**Apply a material:** select a `MeshInstance3D` → Inspector → `Surface Material Override → 0`
→ load the `.tres`. Or in a scene file: `surface_material_override/0 = ExtResource("res://assets/materials/<name>.tres")`.

**Driving the dissolve effect from code:**
```gdscript
var mat: ShaderMaterial = $MeshInstance3D.get_active_material(0)
create_tween().tween_method(
    func(v): mat.set_shader_parameter("dissolve", v), 0.0, 1.0, 0.6)
```

**Tip:** the existing `entities/harvestables/lava_pool.tscn` uses a plain
`StandardMaterial3D`. To upgrade it, swap its `surface_material_override/0` to
`LavaFlowMaterial.tres` for animated lava.

---

## 2. Items (`global/items/resources/`)

New resource tier (category `MATERIAL`) and two tools/weapons:

| id | Type | Notes |
|---|---|---|
| `gold_ore` | Item / MATERIAL | Raw gold, smelt into ingots |
| `gold_ingot` | Item / MATERIAL | Refined gold, crafting input |
| `raw_crystal` | Item / MATERIAL | Mined from crystal clusters |
| `polished_crystal` | Item / MATERIAL | Polished at a workbench |
| `crystal_pickaxe` | ToolItem (PICKAXE, power 3) | Best pick: low stamina, breaks power-3 nodes |
| `crystal_blade` | MeleeWeaponItem (ARCANE, 28 dmg) | Fast, high-damage endgame sword |

---

## 3. Crafting Recipes (`global/crafting/recipes/`)

| id | Machine | Inputs → Output |
|---|---|---|
| `gold_smelt` | Smelter (1) | 2 × `gold_ore` → 1 × `gold_ingot` (40 min) |
| `polish_crystal` | Workbench (2) | 1 × `raw_crystal` → 1 × `polished_crystal` (instant) |
| `crystal_pickaxe_craft` | Workbench (2) | 3 × `polished_crystal` + 2 × `gold_ingot` → `crystal_pickaxe` |
| `crystal_blade_craft` | Workbench (2) | 2 × `polished_crystal` + 1 × `gold_ingot` → `crystal_blade` |

Full loop: **mine** gold veins / crystal clusters → **smelt** gold, **polish**
crystal → **craft** the Crystal Pickaxe & Crystal Blade.

---

## 4. Harvestables (`entities/harvestables/`)

Drop these into any stage like `rock.tscn`. Each inherits `harvestable.tscn`.

| Scene | Tool / Power | Drops | Respawn |
|---|---|---|---|
| `crystal_cluster.tscn` | Pickaxe / 2 | 2 × `raw_crystal` (glowing crystal material) | no |
| `gold_vein.tscn` | Pickaxe / 2 | 2 × `gold_ore` (metallic gold) | no |
| `sulfur_vent.tscn` | Pickaxe / 1 | 2 × `sulfur_crystal` (existing item) | 12 s |

---

## 5. Decorative Props (`entities/props/`)

Built from primitive meshes + the new shaders — drop them into a stage like any
other prop. All use `prop.gd`.

| Scene | Uses | Notes |
|---|---|---|
| `crystal_lamp.tscn` | EnergyCrystal shader + OmniLight | Glowing decorative light |
| `portal_gate.tscn` | Portal shader + torus frame | Walk-through (collision off); pair with `global/teleport area` |
| `lava_fountain.tscn` | LavaFlow shader + basin | Animated molten basin with orange light |
| `force_field_wall.tscn` | ForceField shader | Solid energy barrier (collision on) |

---

## Placing items in the world for testing

Use the existing `WorldItem.spawn(&"crystal_pickaxe", 1, parent, position)` pattern,
or grant directly while debugging: `Inventory.add(&"polished_crystal", 5)`.

## Next steps (optional polish)
- Assign real `world_model` FBX/glTF to the new items (KayKit "Resource Bits" /
  "RPG Tools & Bits" in your asset library are a good match).
- Re-run the editor once so Godot imports the new `.gdshader`/`.tres` files and
  bakes their UIDs.
