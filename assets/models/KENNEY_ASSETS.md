# Kenney Asset Index — Lava Town

3D models from [Kenney](https://kenney.nl), licensed **CC0 1.0** (public domain — attribution appreciated, not required). See `ATTRIBUTION.txt`.

All counts below are **real `.fbx` files on disk** (FBX format kits). Totals exclude the project's own custom `.gltf` scenes (lava town bar, storefront, houses, volcano, roads, custom bar furniture) which live in some of these category folders but are not Kenney assets.

**Total Kenney `.fbx` models on disk: 1535**

## Categories

| Category | Source kit(s) | #Models | What it's for in Lava Town | Example models |
|---|---|---|---|---|
| `characters/` | Mini Characters, Blocky Characters, Animated Characters Bundle | 65 | Townsfolk NPCs, shopkeepers, quest-givers; rigged player/NPC bodies | `character-male-a`, `character-a`, `characterMedium`, `aid-sunglasses` |
| `critters/` | Cube Pets | 24 | Light-combat critters and island wildlife/pets | `animal-fox`, `animal-crab`, `animal-bee`, `animal-penguin` |
| `nature/` | Nature Kit | 329 | Tropical island terrain + harvestable ingredients (plants, rocks, wood) | `cactus_tall`, `cliff_blockCave_rock`, `bridge_wood`, `campfire_logs` |
| `food_drink/` | Food Kit | 91 | Brew vessels/containers + raw produce ingredients for recipes | `mug`, `cocktail`, `bottle-oil`, `barrel`, `pineapple`, `coconut` |
| `furniture/` | Furniture Kit | 140 | Interiors for the bar/brewery/home/shops; appliances & seating | `stoolBar`, `kitchenBlender`, `kitchenStove`, `tableRound`, `bookcaseOpen` |
| `buildings/` | Fantasy Town Kit, City Kit - Commercial, City Kit - Suburban, Modular Buildings | 356 | Town structures: quirky stalls/mills, shops, houses, modular facades | `stall-green`, `windmill`, `building-a`, `building-type-a`, `roof-gable` |
| `machines/` | Factory Kit | 143 | Lava-brewing equipment: tanks, vats, pipes, valves, conveyors | `pipe-large-valve`, `hopper-high-round`, `conveyor-long`, `crane-magnet` |
| `props/` | Mini Market, Pirate Kit, Watercraft Pack | 138 | Shop fixtures, dock/harbor/ship dressing, boats for the island | `cash-register`, `shopping-cart`, `ship-pirate-medium`, `boat-sail-a`, `crate` |
| `tools_weapons/` | Survival Kit, Weapon Pack (knives only) | 84 | Gathering/crafting tools, workbenches, melee knives for combat | `tool-pickaxe`, `tool-axe`, `workbench-anvil`, `knife_sharp` |
| `arcade/` | Mini Arcade | 20 | Minigame/amusement machines for town venues | `arcade-machine`, `pinball`, `claw-machine`, `prize-wheel` |
| `dev/` | Prototype Kit | 145 | Greybox primitives for blocking out brewery/town/level layouts | `button-floor-round-small`, `coin`, `animal-dog`, ramp/stair/block prims |

## How to use

- **Static props/buildings/etc.:** Drag any `.fbx` from these folders into your Godot scene. Godot imports it automatically (shared `Textures/colormap.png` resolves the materials for most kits).
- **Rigged characters** — see `assets/models/characters/animated-characters/`:
  - `Models/` — 4 base rigged meshes (`characterLargeFemale`, `characterLargeMale`, `characterMedium`, `characterSmall`).
  - `Skins/` — recolor textures (`.png`, e.g. `businessMaleA`, `farmerA`, `zombieA`) to vary the cast on a base mesh.
  - `Animations/` — 17 shared `.fbx` clips (`idle`, `walk`, `run`, `attack`, `punch`, `kick`, `jump`, `death`, `crouch`, `interactGround`, etc.). Retarget these onto a base mesh's skeleton.
