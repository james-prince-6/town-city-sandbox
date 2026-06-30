# goe_bake_character.py  -  retarget Mixamo locomotion onto a GoE (Auto-Rig Pro) character
# and export a game-ready GLB with baked idle/walk/run clips + facial morphs.
#
# Run headless:
#   blender --background "<...>_CCGOE.blend" --python tools/blender/goe_bake_character.py
#
# Why this exists / the ARP gotchas it works around (all were dead-ends until handled):
#   * The rig ships with data.pose_position = 'REST' -> the armature is FROZEN at rest and
#     ignores every bone transform and action. Must flip to 'POSE'.  (This was the big one.)
#   * The deform bones (root.x, arm_stretch.l, ...) are constraint-slaves of the control rig
#     AND have locked rot/loc channels -> direct keyframes are ignored. Strip constraints +
#     unlock channels so our baked keys actually pose them.
#   * Hundreds of drivers make the glTF exporter segfault -> clear all anim/drivers first.
#   * The deform skeleton is FLAT (every bone parented to c_traj), so there is no usable
#     chain for runtime retargeting -> we fully BAKE absolute per-bone world poses instead.
# Retarget math: per frame, set each mapped bone's WORLD rotation = mixamo bone's world
# delta-from-rest applied onto the GoE bone's rest (rig-agnostic), via Blender's own
# pose_bone.matrix setter (exact FK). In-place (no root translation); game code moves the body.
#
# To bake the MALE (or any new character): point Blender at its .blend and set ARM_NAME +
# OUT below (e.g. "MaleR_Rig" / goe_male_base.glb). The bone names are shared across GoE rigs.
import bpy, math, os
from mathutils import Quaternion, Matrix, Vector

ARM_NAME = "FemaleR_Rig"
PROJ = r"C:\Users\kingb\Documents\Town City"
OUT  = os.path.join(PROJ, r"assets\models\characters\goe\goe_female_base.glb")
ANIM = os.path.join(PROJ, r"assets\models\characters\psx\anim")
RENDER = os.path.join(os.environ.get("TEMP", PROJ), "goe_walk_preview.png")
LOG = os.path.join(os.environ.get("TEMP", PROJ), "goe_bake.txt")

CLIPS = {"idle": "Idle.fbx", "walk": "Walking (1).fbx", "run": "Running.fbx"}

MAP = {
    "Hips": "root.x",
    "Spine": "spine_01.x", "Spine1": "spine_02.x", "Spine2": "spine_03.x",
    "Neck": "neck.x", "Head": "head.x",
    "LeftShoulder": "shoulder.l", "LeftArm": "arm_stretch.l",
    "LeftForeArm": "forearm_stretch.l", "LeftHand": "hand.l",
    "RightShoulder": "shoulder.r", "RightArm": "arm_stretch.r",
    "RightForeArm": "forearm_stretch.r", "RightHand": "hand.r",
    "LeftUpLeg": "thigh_stretch.l", "LeftLeg": "leg_stretch.l",
    "LeftFoot": "foot.l", "LeftToeBase": "toes_01.l",
    "RightUpLeg": "thigh_stretch.r", "RightLeg": "leg_stretch.r",
    "RightFoot": "foot.r", "RightToeBase": "toes_01.r",
}

_log = []
def w(s):
    _log.append(str(s)); print(s)

arp = bpy.data.objects[ARM_NAME]
scene = bpy.context.scene
vl = bpy.context.view_layer

# The rig ships in REST pose mode, which freezes the armature at rest and ignores
# ALL bone transforms/actions. Switch to POSE so our baked keyframes take effect.
arp.data.pose_position = 'POSE'

# ---- 1. nuke ALL drivers/anim (incl. shape-key Key datablocks -> silent eval) ----
for o in bpy.data.objects:
    if o.animation_data: o.animation_data_clear()
for k in bpy.data.shape_keys:
    if k.animation_data: k.animation_data_clear()
for coll in (bpy.data.materials, bpy.data.node_groups, bpy.data.armatures, bpy.data.meshes):
    for d in coll:
        ad = getattr(d, "animation_data", None)
        if ad: d.animation_data_clear()
w("drivers/anim cleared")

# The ARP deform bones are constraint-slaves of the control rig (Copy Transforms),
# so direct keyframes on them get overridden at eval time. Strip ALL pose-bone
# constraints so our retargeted keyframes ARE the evaluated (and exported) pose.
ncon = 0
for pb in arp.pose.bones:
    for c in list(pb.constraints):
        pb.constraints.remove(c); ncon += 1
w("removed %d pose-bone constraints" % ncon)

# The deform bones ship with LOCKED rotation/location channels (they're meant to
# be driven only by the control rig). Unlock so our baked keyframes actually pose them.
for pb in arp.pose.bones:
    pb.lock_rotation = (False, False, False); pb.lock_rotation_w = False
    pb.lock_location = (False, False, False); pb.lock_scale = (False, False, False)
w("unlocked all pose-bone channels")

for pb in arp.pose.bones:
    pb.rotation_mode = 'QUATERNION'
    pb.matrix_basis = Matrix()
vl.update()

# ---- constant rest data for EVERY arp bone (rotation only) ----
RWq = {}            # bone name -> world rest rotation quat
RWm = {}            # bone name -> world rest matrix
for b in arp.data.bones:
    m = arp.matrix_world @ b.matrix_local
    RWm[b.name] = m
    RWq[b.name] = m.to_quaternion()
parent_of = {b.name: (b.parent.name if b.parent else None) for b in arp.data.bones}

# Exact Blender FK uses FULL rest matrices (incl. any rest scale on ARP stretch
# bones). pose[bone] = pose[parent] @ BoneRel[bone] @ basis[bone].
L = {b.name: b.matrix_local.copy() for b in arp.data.bones}
Linv = {n: m.inverted() for n, m in L.items()}
BoneRel = {}
for b in arp.data.bones:
    BoneRel[b.name] = (Linv[b.parent.name] @ L[b.name]) if b.parent else L[b.name].copy()
aw = arp.matrix_world
aw_q = aw.to_quaternion(); aw_qinv = aw_q.inverted()
aw_inv3 = aw.inverted().to_3x3()
root_rest_arm = L["root.x"].translation.copy()

def depth(ap):
    b = arp.data.bones.get(ap); d = 0
    while b and b.parent: b = b.parent; d += 1
    return d
order = sorted(MAP.items(), key=lambda kv: depth(kv[1]))
root_restZ = RWm["root.x"].translation.z

# Unlink the heavy skinned meshes during baking so each per-frame depsgraph
# update only evaluates the armature pose (fast), not ~50k-vert mesh deform.
char_meshes = [o for o in bpy.data.objects
               if o.type == 'MESH' and any(m.type == 'ARMATURE' and m.object == arp for m in o.modifiers)]
mesh_colls = {o.name: list(o.users_collection) for o in char_meshes}
for o in char_meshes:
    for c in list(o.users_collection):
        c.objects.unlink(o)
w("unlinked %d meshes for baking" % len(char_meshes))

# ---- fbx import + yaw align (match GoE facing) ----
def import_fbx(path):
    before = set(o.name for o in bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path)
    new = [o for o in bpy.data.objects if o.name not in before]
    arm = next(o for o in new if o.type == 'ARMATURE')
    return arm, new

def facing(obj, lname, rname):
    lb = obj.data.bones.get(lname); rb = obj.data.bones.get(rname)
    lw = (obj.matrix_world @ lb.matrix_local).translation
    rw = (obj.matrix_world @ rb.matrix_local).translation
    right = (lw - rw); right.z = 0
    if right.length < 1e-6: return Vector((0, 1, 0))
    right.normalize()
    f = Vector((0, 0, 1)).cross(right); f.z = 0; f.normalize(); return f

def bake_clip(name, fbx):
    mixarm, created = import_fbx(os.path.join(ANIM, fbx))
    af = facing(arp, "shoulder.l", "shoulder.r")
    mf = facing(mixarm, "mixamorig:LeftShoulder", "mixamorig:RightShoulder")
    ang = math.atan2(af.y, af.x) - math.atan2(mf.y, mf.x)
    mixarm.rotation_euler = (0, 0, mixarm.rotation_euler.z + ang)
    vl.update()

    src = mixarm.animation_data.action
    f0, f1 = (int(round(x)) for x in src.frame_range)

    mix_rest_wq = {}; mix_hip_restZ = None
    for mx in MAP:
        b = mixarm.data.bones.get("mixamorig:" + mx)
        if b is None: continue
        mw = mixarm.matrix_world @ b.matrix_local
        mix_rest_wq[mx] = mw.to_quaternion()
        if mx == "Hips": mix_hip_restZ = mw.translation.z
    hb = mixarm.pose.bones.get("mixamorig:Hips")
    ratio = (root_restZ / mix_hip_restZ) if mix_hip_restZ else 1.0

    act = bpy.data.actions.new(name); act.use_fake_user = True
    arp.animation_data_create(); arp.animation_data.action = act

    # Drop the mixamo MESH (keep its armature) so per-frame updates stay light.
    for o in list(created):
        if o.type == 'MESH':
            bpy.data.objects.remove(o, do_unlink=True); created.remove(o)

    # Group mapped bones by hierarchy depth so we can update once per level
    # (parents-of-level already evaluated) instead of once per bone.
    levels = {}
    for mx, ap in order:
        levels.setdefault(depth(ap), []).append((mx, ap))
    level_keys = sorted(levels)
    aw_inv = aw.inverted()

    for f in range(f0, f1 + 1):
        scene.frame_set(f)
        # In-place locomotion: rotation only, every bone keeps its natural (rest-following)
        # head position. Game code drives world movement, so no root translation/bob.
        for d in level_keys:
            for mx, ap in levels[d]:
                mpb = mixarm.pose.bones.get("mixamorig:" + mx)
                apb = arp.pose.bones.get(ap)
                if mpb is None or apb is None: continue
                Mp = (mixarm.matrix_world @ mpb.matrix).to_quaternion()
                tgt = Mp @ mix_rest_wq[mx].inverted() @ RWq[ap]   # world-delta retarget (rotation)
                cur = aw @ apb.matrix                             # natural head (parent already posed)
                M = tgt.to_matrix().to_4x4()
                M.translation = cur.translation
                apb.matrix = aw_inv @ M                           # Blender derives the exact basis
            vl.update()                                           # one update per depth level
        for mx, ap in order:
            apb = arp.pose.bones.get(ap)
            if apb is not None:
                apb.keyframe_insert("rotation_quaternion", frame=f)

    for o in created:
        try: bpy.data.objects.remove(o, do_unlink=True)
        except Exception: pass
    try: bpy.data.actions.remove(src)
    except Exception: pass
    w("baked '%s' frames %d-%d yaw=%.1f ratio=%.3f" % (name, f0, f1, math.degrees(ang), ratio))
    return act

baked = [bake_clip(nm, fbx) for nm, fbx in CLIPS.items()]
arp.animation_data.action = next(a for a in baked if a.name == "walk")
w("actions: %s" % [a.name for a in baked])

# relink the meshes we hid during baking
sc = bpy.context.scene.collection
for o in char_meshes:
    cols = mesh_colls.get(o.name) or [sc]
    for c in cols:
        try: c.objects.link(o)
        except Exception: pass
vl.update()

# SELF-CHECK: assign walk, sample actual evaluated world rotation across frames.
try:
    arp.animation_data.action = next(a for a in baked if a.name == "walk")
    dg = bpy.context.evaluated_depsgraph_get()
    for bn in ("thigh_stretch.l", "arm_stretch.l", "forearm_stretch.l"):
        qs = []
        for f in (1, 8, 16, 24):
            scene.frame_set(f); vl.update()
            ev = arp.evaluated_get(bpy.context.evaluated_depsgraph_get())
            qs.append((ev.matrix_world @ ev.pose.bones[bn].matrix).to_quaternion())
        spread = max(math.degrees(qs[0].rotation_difference(q).angle) for q in qs)
        w("SELFCHECK %s world-rot spread across walk = %.1f deg" % (bn, spread))
except Exception as e:
    w("SELFCHECK error: %s" % e)

# ---- 2. skin albedo ----
def fix_skin():
    body = next((o for o in bpy.data.objects if o.type == 'MESH' and 'body' in o.name.lower()), None)
    if not body or not body.data.materials: w("skin: no body"); return
    img = next((im for im in bpy.data.images if "_body_" in (im.filepath+im.name).lower() and "base" in (im.filepath+im.name).lower()), None)
    if img is None: img = next((im for im in bpy.data.images if "body" in im.name.lower()), None)
    if img is None: w("skin: no tex"); return
    for mat in body.data.materials:
        if not mat or not mat.use_nodes: continue
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if not bsdf: continue
        tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    w("skin albedo linked: %s" % img.name)
fix_skin()

# ---- 3. keep only Anim* (+Basis) shape keys ----
for o in bpy.data.objects:
    if o.type != 'MESH' or not o.data.shape_keys: continue
    for kb in list(o.data.shape_keys.key_blocks):
        if kb.name != "Basis" and not kb.name.lower().startswith("anim"):
            o.shape_key_remove(kb)

# ---- 4. select + export ----
bpy.ops.object.select_all(action='DESELECT')
sel = 0
for o in bpy.data.objects:
    if o.type == 'ARMATURE' and o.name == ARM_NAME:
        o.select_set(True); sel += 1
    elif o.type == 'MESH' and any(m.type == 'ARMATURE' and m.object == arp for m in o.modifiers):
        o.select_set(True); sel += 1
vl.objects.active = arp
w("export selection = %d" % sel)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=OUT, export_format='GLB', use_selection=True,
    export_def_bones=True, export_apply=False,
    export_morph=True, export_morph_normal=False,
    export_animations=True, export_animation_mode='ACTIONS',
    export_bake_animation=True, export_anim_single_armature=True,
    export_optimize_animation_size=True, export_yup=True,
)
w("EXPORTED -> %.1f MB" % (os.path.getsize(OUT)/1e6))

# ---- 5. preview render mid-walk ----
try:
    arp.animation_data.action = next(a for a in baked if a.name == "walk")
    scene.frame_set(16)
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.render.resolution_x = 480; scene.render.resolution_y = 720
    scene.render.filepath = RENDER
    cam = bpy.data.objects.new("PrevCam", bpy.data.cameras.new("PrevCam"))
    scene.collection.objects.link(cam)
    cam.location = (0, -3.2, 1.0); cam.rotation_euler = (math.radians(88), 0, 0)
    scene.camera = cam
    bpy.ops.render.render(write_still=True)
    w("render -> %s" % RENDER)
except Exception as e:
    w("render skipped: %s" % e)

open(LOG, "w", encoding="utf-8").write("\n".join(_log))
