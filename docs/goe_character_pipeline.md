# GoE Character Pipeline

How the new high-detail characters (GoE Character Creator base, Auto-Rig Pro rig with facial
shape keys) get from Blender into Town City. **Status: one character (base Female) proven
end-to-end** — exported, imported, skinned, **facial expressions + a full body-animation set
working in-engine**, no editor steps required.

**Animation source: the Quaternius Universal Animation Library (CC0, 43 clips)** — idle/walk/
jog/sprint/crouch/jump/punch/sword/death/hit/roll/sit/talk/pickup/interact/push/dance/swim/
pistol/spell/… — retargeted and baked onto the GoE rig. The earlier 3-clip Mixamo path
(`goe_bake_character.py`) is kept as reference; **`goe_bake_ual.py` is the primary baker.**

## Source & license
- Source `.blend`s live ONLY in the external library: `OneDrive\Game assets\Characters\Male_Female_Basemesh_CCGOE_Bundle_Full\Female_Basemesh_CCGOE_Full\Female_Basemesh_CCGOE.blend`. **Never commit the raw `.blend`/full texture pack/addon** — the GoE license forbids redistributing source files in a public repo. Only the game-ready exported `.glb` (+ the textures it needs) goes in this repo (it's gitignored).
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
4. Selects the body meshes (Body, Eyes, Teeth Up/Down, Tongue, Eyebrows) + armature and
   exports **GLB** with `export_def_bones=True` (→ the **deform** skeleton, ~133 bones, not the
   527-bone control rig), `export_morph=True`, `export_apply=False` (so shape keys survive).

Output: `assets/models/characters/goe/goe_female_base.glb` (~13 MB) + extracted PBR textures.
The character is currently **bald** — the source has 3 bone-parented hairstyle meshes
(`F_Basemesh_B_GOE_Hair_1/2/3`, Indian/African/Asian) that aren't selected for export; to add
hair, explicitly select one in the export step (it has its own material/texture).

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

> **⚠ Skin must be forced OPAQUE.** The GoE materials ship **alpha-blended with an opacity
> texture that punches see-through holes in the skin** → black patches all over the body
> in-engine (Godot imports them as `transparency != 0`). The bake scripts now disconnect the
> Principled Alpha input + set `blend_method='OPAQUE'` on every character material. **Verify with
> a TEXTURED render** (`scene.display.shading.color_type='TEXTURE'`) — plain gray workbench
> renders hide it. Never "fix" it by re-importing+re-exporting the baked GLB (the def_bones glTF
> round-trip corrupts the poses) — re-run the bake.

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

## 5. Body animation — Mixamo retargeted + BAKED in Blender (no editor steps)
The clips are **retargeted and baked onto the GoE deform skeleton in Blender**, so the exported
GLB carries real `idle`/`walk`/`run` animations on its own AnimationPlayer. Godot just plays
them — no runtime retarget, no bone map, no Fix Silhouette. (Godot humanoid retargeting was
tried first and abandoned: Fix Silhouette mangles the ARP rest pose.)

**Primary script:** `tools/blender/goe_bake_ual.py`. Run:
`blender --background "<…>_CCGOE.blend" --python tools/blender/goe_bake_ual.py`. It imports the
Quaternius UAL GLB (`Game assets/Animations/Universal Animation Library[Standard]/Unreal-Godot/
UAL1_Standard.glb`, 43 actions on a T-pose rig), retargets each onto the ARP deform bones, bakes
one action per clip, and re-exports the GLB (skin albedo + `Anim*` facial morphs + all clips).
In-place (no root translation — game code drives world movement). Uses pure-Python FK (no
per-frame depsgraph updates) so the full 43-clip bake stays tractable (~15 min). Set `ONLY=[...]`
for a fast subset. (`goe_bake_character.py` is the same pipeline for the 3 Mixamo FBX clips.)

**The ARP traps it works around** (each was a dead end until handled — see the script header):
- `armature.data.pose_position` ships as **`'REST'`**, which *freezes* the rig at rest and
  ignores all bone transforms/actions. Must set to `'POSE'`. ← the one that cost the most time.
- Deform bones (`arm_stretch.l`, …) are **constraint-slaves** of the control rig **and** have
  **locked** rot/loc channels → direct keyframes are silently ignored. Strip constraints + unlock.
- The rig has hundreds of **drivers** → the glTF exporter segfaults; clear all anim/drivers first.
- The deform skeleton is **flat** (every bone parented to `c_traj`) → rotating a parent leaves
  its children behind and the mesh stretches. The script **re-parents the locomotion bones into
  a proper anatomical chain** (keeping rest positions) before baking so children follow parents.

Retarget (per frame, applied via Blender's `pose_bone.matrix` setter = exact FK, one depsgraph
update per hierarchy depth level for speed):
- **Body-frame align first:** the Mixamo FBX imports tilted/rotated vs the GoE rig, so the source
  armature is rotated so its up-axis (Hips→Head) + facing match the GoE rig — everything then
  lives in one consistent world frame. (Skip this and the rest-aligned arms come out 90° off.)
- **Legs / spine / head:** rest-relative world frame-delta `src_world @ src_rest⁻¹ @ goe_rest`
  (their Mixamo & GoE rests already align, so it's clean).
- **Arms:** the Mixamo **T-pose** vs GoE **A-pose** rest mismatch breaks the plain delta, so each
  arm bone's *reference rest* is **rest-aligned** — rotated so its bone direction matches the
  source bone's T-pose direction — and then the same world-delta works. This gives correct
  direction, stable roll, and natural elbow bend across idle/walk/run.

Runtime: `entities/characters/goe_animator.gd` (`GoeAnimator`, created by `GoeCharacter`) finds
the GLB's AnimationPlayer and plays clips by name (`play(&"walk")`). Add clips by baking more in
the Blender step and listing them in `GoeAnimator.clips`.

> Idle/walk/jog/run all read naturally (arms down + swinging, elbows bend). Fingers stay at rest
> (not mapped) — add them by extending `MAP` + `CHAIN` with the `c_*` finger deform bones.
>
> **Runtime:** `GoeAnimator` (in `goe_character.gd`) maps friendly names → UAL clips via `ALIAS`
> (`play(&"walk")` → `Walk_Loop`); you can also `play(&"Sword_Attack")` by literal clip name.
> `*_Loop` clips loop, others are one-shot.

## 6. NPC integration (next)
The current NPC/enemy system (`entities/npc/npc.gd` + `npc_animator.gd`) is built around the
PSX **Mixamo** rig with a custom aim-retarget. The GoE characters instead carry baked clips and
play them through `GoeAnimator`, so integration means: have `npc.gd` drive a `GoeCharacter`
(call `play_anim(&"idle"/"walk"/"run")` from its locomotion state + `set_emotion` from mood)
instead of `NPCAnimator`. Recommended: swap ONE named NPC's model to `goe_character.tscn`, wire
its locomotion + mood→expression, then roll out. (For blends between clips later, feed the
GLB's clips into an `AnimationTree` on `GoeCharacter`.)

## 7. Performance
High detail: ~19k-vert body + eyebrows + hair (15–37k) ≈ 50k+ verts/character vs the PSX
models' few hundred. Fine for a handful of hero NPCs; for crowds/enemies plan LODs, fewer
simultaneous characters, or a decimated low-poly export variant.
