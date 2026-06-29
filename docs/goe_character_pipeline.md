# GoE Character Pipeline

How the new high-detail characters (GoE Character Creator base, Auto-Rig Pro rig with facial
shape keys) get from Blender into Town City. **Status: one character (base Female) proven
end-to-end** — exported, imported, skinned, facial expressions working in-engine. Body
animation via Godot humanoid retargeting is set up and waits on one editor-dock step.

## Source & license
- Source `.blend`s live ONLY in the external library: `OneDrive\Game assets\Male_Female_Basemesh_CCGOE_Bundle_Full\`. **Never commit the raw `.blend`/full texture pack/addon** — the GoE license forbids redistributing source files in a public repo. Only the game-ready exported `.glb` (+ the textures it needs) goes in this repo.
- Blender used: `C:\Users\kingb\Documents\Blender\blender.exe` (4.5.3).

## 1. Export (Blender → game glTF)
Script: `$CLAUDE_JOB_DIR/tmp/export_female.py` (reproduced logic below). Run headless:
`blender --background "<…>_CCGOE.blend" --python export_female.py`. It:
1. **Clears all drivers / animation data** first — the ARP rig wires controls + corrective
   shape keys with hundreds of drivers and the glTF exporter *segfaults* on driver eval otherwise.
2. **Links the skin albedo** (`*_Body_Base.png`) straight into the body's Base Color (the
   original routes it through a face-decal mix the exporter can't bake, dropping the skin).
3. **Keeps only `Anim*` (facial-expression) shape keys** + Basis; drops the Face*/Body*
   customization morphs and the explicit-anatomy ones.
4. Selects the meshes (Body, Eyes, Teeth Up/Down, Tongue, Eyebrows, one Hair) + armature and
   exports **GLB** with `export_def_bones=True` (→ the **deform** skeleton, ~133 bones, not the
   527-bone control rig), `export_morph=True`, `export_apply=False` (so shape keys survive).

Output: `assets/models/characters/goe/goe_female_base.glb` (~23 MB) + extracted PBR textures.

**To export the Male (or any new character):** point the script at the Male `.blend`, change
the mesh/armature names (`M_…` / `MaleR_Rig`), pick a skin tone (Base/Asian/Black/… `*_Body_*.png`)
and hair, and output `goe_<name>.glb`. To make a *distinct* NPC, set the Face*/Body* shape
keys (or sculpt) in Blender and **apply them** before export so they bake into the mesh; the
`Anim*` expressions stay as runtime morphs.

## 2. Import result (verified)
- `Skeleton3D` with **133 deform bones** (body + fingers + full facial bones).
- Body mesh = **30 facial blend shapes** (`AnimHappy/Sad/Angry/Afraid/Surprise/Scream/Disgust/
  Smile/BrowUp/BrowDown/CheeksBalloon…`); eyebrows 24, teeth/tongue a few (open-mouth ones).
- `StandardMaterial3D` skin: albedo + normal + roughness; eyes (blue) + eyebrows textured.

## 3. Reusable character scene
- `entities/characters/goe_character.tscn` (+ `goe_character.gd`, `class_name GoeCharacter`):
  a `Node3D` wrapping the GLB `Model`; on `_ready` it finds the skeleton and attaches a
  `GoeFacialController`. API: `set_emotion(name, weight)`, `set_face_shape(shape, w)`,
  `available_emotions()`, `start_emotion` export.
- **Review scene:** `stages/dev/goe_demo.tscn` (F6) — slowly spins the model and cycles every
  facial expression, with a label. Use it to eyeball skin/rig/faces in-editor.

## 4. Facial expressions
`entities/characters/goe_facial_controller.gd` (`GoeFacialController`). Indexes every blend
shape across all the character's meshes, so one emotion (e.g. `AnimHappy`) drives the body +
eyebrows + teeth together. Blends smoothly toward a target each frame; an idle **blink** runs
on its own channel. 20 emotions mapped in `EMOTIONS` (happy/sad/angry/afraid/surprised/shock/
disgust/confused/concentrate/excited/pain/scream/glare/frown/flirt/smile/grin/snarl/fear/neutral).
Drive it from NPC mood/dialogue: `goe_char.set_emotion(&"happy")`.

## 5. Body animation — Godot humanoid retarget (one editor step left)
The rig is Auto-Rig Pro (names like `spine_01.x`, `arm_stretch.l`), not Mixamo, so we use
Godot's standard humanoid retargeting. The BoneMap is built:
`assets/models/characters/goe/goe_arp_bonemap.tres` (22 core bones → `SkeletonProfileHumanoid`).

**Editor steps (can't be done headlessly — the importer ignores an injected bone map):**
1. Select `goe_female_base.glb` → **Import** dock → **Advanced…**.
2. Scene → the `Skeleton3D` node → **Retarget → Bone Map** = `goe_arp_bonemap.tres`; enable
   **Fix Silhouette**. Reimport. (This renames the model's bones to the humanoid profile.)
3. The **animations** must be retargeted to the *same* profile: the Mixamo clips in
   `assets/models/characters/psx/anim/*.fbx` already have a map at
   `assets/models/characters/psx/mixamo_to_humanoid.tres` — set each Mixamo FBX's Skeleton3D
   Bone Map to it (or build one shared anim library). Both sides on `SkeletonProfileHumanoid`
   → the clips play on the GoE model directly.
4. Add an `AnimationPlayer`/`AnimationTree` to the character (or reuse a retargeted anim
   library) and play `idle`/`walk`/`run`.

> If finger detail is wanted later, extend `goe_arp_bonemap.tres` with the `c_thumb*/index*/…`
> bones (they're in the skeleton).

## 6. NPC integration (next)
The current NPC/enemy system (`entities/npc/npc.gd` + `npc_animator.gd`) is built around the
PSX **Mixamo** rig with a custom aim-retarget. The GoE characters use the humanoid-retarget
path instead, so integration means: give `GoeCharacter` an `AnimationTree` fed by the
retargeted humanoid clips, and have `npc.gd` drive *it* (idle/walk/run + `set_emotion`) rather
than `NPCAnimator`. Recommended: start by swapping ONE named NPC's model to `goe_character.tscn`
and wiring its locomotion + mood→expression, then roll out.

## 7. Performance
High detail: ~19k-vert body + eyebrows + hair (15–37k) ≈ 50k+ verts/character vs the PSX
models' few hundred. Fine for a handful of hero NPCs; for crowds/enemies plan LODs, fewer
simultaneous characters, or a decimated low-poly export variant.
