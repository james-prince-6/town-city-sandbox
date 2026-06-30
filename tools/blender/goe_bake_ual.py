# goe_bake_ual.py  -  retarget the Quaternius Universal Animation Library onto the GoE character
# and export a game-ready GLB with all the baked clips + facial morphs.
#
# Run headless (point Blender at the GoE .blend):
#   blender --background "<...>_CCGOE.blend" --python tools/blender/goe_bake_ual.py
#
# UAL source: Game assets/Animations/Universal Animation Library[Standard]/Unreal-Godot/
#   UAL1_Standard.glb  (CC0, 43 clips, T-pose rig: pelvis/spine_01/upperarm_l/thigh_l/...).
#
# Reuses every ARP gotcha fix learned for this rig (see docs/goe_character_pipeline.md §5):
#   pose_position='REST' freeze; constraint-slaved + locked deform bones; driver segfaults;
#   FLAT deform skeleton (re-parent into a chain); custom-shape meshes dragged into export.
# Retarget: (1) align the SOURCE body frame to the GoE rig; (2) legs/spine = rest-relative world
# frame-delta; (3) ARMS are rest-aligned to the source T-pose direction so the same delta works.

import bpy, math, os
from mathutils import Quaternion, Matrix, Vector

ARM_NAME = "FemaleR_Rig"
PROJ = r"C:\Users\kingb\Documents\Town City"
OUT  = os.environ.get("GOE_OUT", os.path.join(PROJ, r"assets\models\characters\goe\goe_female_base.glb"))
UAL  = r"C:\Users\kingb\OneDrive\Game assets\Animations\Universal Animation Library[Standard]\Unreal-Godot\UAL1_Standard.glb"
LOG = os.path.join(os.environ.get("TEMP", PROJ), "goe_ual_bake.txt")

# Which UAL actions to bake. Empty list = ALL (minus A_TPose). For fast iteration set a subset.
ONLY = []   # e.g. ["Idle_Loop", "Walk_Loop", "Jog_Fwd_Loop"]; empty = ALL 43 (minus A_TPose)
if os.environ.get("GOE_ONLY"): ONLY = [s for s in os.environ["GOE_ONLY"].split(",") if s]
SKIP = {"A_TPose"}

# UAL bone -> GoE deform bone
MAP = {
    "pelvis": "root.x",
    "spine_01": "spine_01.x", "spine_02": "spine_02.x", "spine_03": "spine_03.x",
    "neck_01": "neck.x", "Head": "head.x",
    "upperarm_l": "arm_stretch.l", "lowerarm_l": "forearm_stretch.l", "hand_l": "hand.l",
    "upperarm_r": "arm_stretch.r", "lowerarm_r": "forearm_stretch.r", "hand_r": "hand.r",
    "thigh_l": "thigh_stretch.l", "calf_l": "leg_stretch.l", "foot_l": "foot.l", "ball_l": "toes_01.l",
    "thigh_r": "thigh_stretch.r", "calf_r": "leg_stretch.r", "foot_r": "foot.r", "ball_r": "toes_01.r",
}
REST_ALIGN = {"arm_stretch.l", "arm_stretch.r", "forearm_stretch.l", "forearm_stretch.r",
              "hand.l", "hand.r"}

_log = []
def w(s):
    _log.append(str(s)); print(s)

arp = bpy.data.objects[ARM_NAME]
scene = bpy.context.scene
vl = bpy.context.view_layer
arp.data.pose_position = 'POSE'

# ---- GoE-rig prep (see header) ----
for o in bpy.data.objects:
    if o.animation_data: o.animation_data_clear()
for k in bpy.data.shape_keys:
    if k.animation_data: k.animation_data_clear()
for coll in (bpy.data.materials, bpy.data.node_groups, bpy.data.armatures, bpy.data.meshes):
    for d in coll:
        ad = getattr(d, "animation_data", None)
        if ad: d.animation_data_clear()
for pb in arp.pose.bones:
    for c in list(pb.constraints): pb.constraints.remove(c)
    pb.lock_rotation = (False, False, False); pb.lock_rotation_w = False
    pb.lock_location = (False, False, False); pb.lock_scale = (False, False, False)
w("GoE rig: drivers/constraints cleared, channels unlocked")

# Re-parent the locomotion deform bones into an anatomical chain (flat under c_traj otherwise).
CHAIN = {
    "spine_01.x": "root.x", "spine_02.x": "spine_01.x", "spine_03.x": "spine_02.x",
    "neck.x": "spine_03.x", "head.x": "neck.x",
    "shoulder.l": "spine_03.x", "arm_stretch.l": "shoulder.l",
    "forearm_stretch.l": "arm_stretch.l", "hand.l": "forearm_stretch.l",
    "shoulder.r": "spine_03.x", "arm_stretch.r": "shoulder.r",
    "forearm_stretch.r": "arm_stretch.r", "hand.r": "forearm_stretch.r",
    "thigh_stretch.l": "root.x", "leg_stretch.l": "thigh_stretch.l",
    "foot.l": "leg_stretch.l", "toes_01.l": "foot.l",
    "thigh_stretch.r": "root.x", "leg_stretch.r": "thigh_stretch.r",
    "foot.r": "leg_stretch.r", "toes_01.r": "foot.r",
}
vl.objects.active = arp; arp.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
eb = arp.data.edit_bones
for child, par in CHAIN.items():
    if child in eb and par in eb:
        eb[child].use_connect = False; eb[child].parent = eb[par]
bpy.ops.object.mode_set(mode='OBJECT')
for pb in arp.pose.bones:
    pb.rotation_mode = 'QUATERNION'; pb.matrix_basis = Matrix()
vl.update()
w("GoE rig: re-parented locomotion bones into a chain")

# ---- constant GoE rest data ----
RWq = {b.name: (arp.matrix_world @ b.matrix_local).to_quaternion() for b in arp.data.bones}
RWm = {b.name: (arp.matrix_world @ b.matrix_local) for b in arp.data.bones}
parent_of = {b.name: (b.parent.name if b.parent else None) for b in arp.data.bones}
L = {b.name: b.matrix_local.copy() for b in arp.data.bones}
Linv = {n: m.inverted() for n, m in L.items()}
BoneRel = {b.name: ((Linv[b.parent.name] @ L[b.name]) if b.parent else L[b.name].copy()) for b in arp.data.bones}
aw = arp.matrix_world; aw_inv = aw.inverted(); aw_qinv = aw.to_quaternion().inverted()
AP2UAL = {ap: u for u, ap in MAP.items()}

def depth(ap):
    b = arp.data.bones.get(ap); d = 0
    while b and b.parent: b = b.parent; d += 1
    return d
order = sorted(MAP.values(), key=depth)
levels = {}
for ap in order:
    levels.setdefault(depth(ap), []).append(ap)
level_keys = sorted(levels)

# Unlink heavy GoE meshes during baking (fast per-frame updates).
char_meshes = [o for o in bpy.data.objects
               if o.type == 'MESH' and any(m.type == 'ARMATURE' and m.object == arp for m in o.modifiers)]
mesh_colls = {o.name: list(o.users_collection) for o in char_meshes}
for o in char_meshes:
    for c in list(o.users_collection): c.objects.unlink(o)

# ---- import UAL (armature + 43 actions); drop its mesh ----
before = set(o.name for o in bpy.data.objects)
before_acts = set(a.name for a in bpy.data.actions)
bpy.ops.import_scene.gltf(filepath=UAL)
new = [o for o in bpy.data.objects if o.name not in before]
ual = next(o for o in new if o.type == 'ARMATURE')
for o in list(new):
    if o.type == 'MESH':
        bpy.data.objects.remove(o, do_unlink=True)
ual_action_names = set(a.name for a in bpy.data.actions) - before_acts   # the UAL source actions
actions = [a for a in bpy.data.actions if a.name in ual_action_names
           and a.name not in SKIP and (not ONLY or a.name in ONLY)]
w("UAL imported: armature '%s', %d actions to bake" % (ual.name, len(actions)))

# ---- align UAL body frame (up + facing) to the GoE rig ----
def rhead(obj, bone):
    b = obj.data.bones.get(bone); return (obj.matrix_world @ b.matrix_local).translation
def body_basis(up, right):
    z = up.normalized(); y = z.cross(right.normalized()).normalized(); x = y.cross(z).normalized()
    m = Matrix.Identity(3); m.col[0] = x; m.col[1] = y; m.col[2] = z; return m
Rg = body_basis(rhead(arp, "head.x") - rhead(arp, "root.x"), rhead(arp, "shoulder.l") - rhead(arp, "shoulder.r"))
Rs = body_basis(rhead(ual, "Head") - rhead(ual, "pelvis"), rhead(ual, "upperarm_l") - rhead(ual, "upperarm_r"))
ual.matrix_world = (Rg @ Rs.transposed()).to_4x4() @ ual.matrix_world
vl.update()
w("UAL body frame aligned to GoE")

# ---- per-bone source rest + rest-aligned GoE reference (constant; UAL rest is fixed) ----
_Y = Vector((0.0, 1.0, 0.0))
ual_rest_wq = {}
for u in MAP:
    b = ual.data.bones.get(u)
    if b: ual_rest_wq[u] = (ual.matrix_world @ b.matrix_local).to_quaternion()
aligned_rest_q = dict(RWq)
for ap in REST_ALIGN:
    u = AP2UAL.get(ap)
    if u and u in ual_rest_wq:
        src_dir = (ual_rest_wq[u] @ _Y).normalized()
        goe_dir = (RWq[ap] @ _Y).normalized()
        aligned_rest_q[ap] = goe_dir.rotation_difference(src_dir) @ RWq[ap]

# ---- bake one UAL action onto the GoE rig ----
# Pure-Python FK (no per-frame depsgraph updates -> ~10x faster than the matrix setter). We
# replicate Blender's FK exactly: pose[bone] = pose[parent] @ BoneRel[bone] @ basis[bone], with
# unmapped bones (shoulder, controls) keeping their rest basis, and key only rotation.
def bake_action(src):
    ual.animation_data_create(); ual.animation_data.action = src
    f0, f1 = (int(round(x)) for x in src.frame_range)
    act = bpy.data.actions.new(src.name); act.use_fake_user = True
    arp.animation_data_create(); arp.animation_data.action = act
    for f in range(f0, f1 + 1):
        scene.frame_set(f)                       # poses the UAL armature (frame_set updates it)
        P = {}                                   # GoE bone -> posed armature-space matrix
        def P_of(n):
            if n in P: return P[n]
            p = parent_of[n]
            P[n] = (P_of(p) @ BoneRel[n]) if p else L[n].copy()
            return P[n]
        for ap in order:                         # parent-first (depth-sorted)
            u = AP2UAL[ap]
            upb = ual.pose.bones.get(u); apb = arp.pose.bones.get(ap)
            if upb is None or apb is None: continue
            Mp = (ual.matrix_world @ upb.matrix).to_quaternion()
            tgt = aw_qinv @ (RWq[ap] @ ual_rest_wq[u].inverted() @ Mp)  # rest-relative retarget GR @ SR^-1 @ SC (carries roll; fixes arms)
            natural = (P_of(parent_of[ap]) @ BoneRel[ap]) if parent_of[ap] else L[ap].copy()
            basis_q = natural.to_quaternion().inverted() @ tgt
            P[ap] = natural @ basis_q.to_matrix().to_4x4()
            apb.rotation_quaternion = basis_q
            apb.keyframe_insert("rotation_quaternion", frame=f)
    return act

baked = []   # (intended_name, action)
for a in actions:
    bk = bake_action(a)
    baked.append((a.name, bk))
    w("  baked %s (%d frames)" % (a.name, int(a.frame_range[1] - a.frame_range[0] + 1)))

# Remove the UAL armature + ALL its source actions (they reference UAL bones = dead weight on the
# GoE skeleton), then give the baked actions their clean names (baking suffixed them .001 because
# the same-named source still existed).
bpy.data.objects.remove(ual, do_unlink=True)
for a in list(bpy.data.actions):
    if a.name in ual_action_names:
        try: bpy.data.actions.remove(a)
        except Exception: pass
for intended, bk in baked:
    bk.name = intended
arp.animation_data.action = baked[0][1] if baked else None
w("renamed baked clips: %s" % [n for n, _ in baked])

# relink GoE meshes
sc = bpy.context.scene.collection
for o in char_meshes:
    for c in (mesh_colls.get(o.name) or [sc]):
        try: c.objects.link(o)
        except Exception: pass
vl.update()

# ---- skin albedo ----
def fix_skin():
    body = next((o for o in bpy.data.objects if o.type == 'MESH' and 'body' in o.name.lower()), None)
    if not body or not body.data.materials: return
    img = next((im for im in bpy.data.images if "_body_" in (im.filepath+im.name).lower() and "base" in (im.filepath+im.name).lower()), None)
    if img is None: img = next((im for im in bpy.data.images if "body" in im.name.lower()), None)
    if img is None: return
    for mat in body.data.materials:
        if not mat or not mat.use_nodes: continue
        nt = mat.node_tree
        bsdf = next((n for n in nt.nodes if n.type == 'BSDF_PRINCIPLED'), None)
        if not bsdf: continue
        tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = img
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    w("skin albedo linked: %s" % img.name)
fix_skin()

# ---- force the skin OPAQUE ----
# The GoE materials ship in alpha-blend mode with an opacity texture that punches transparent
# holes in the skin -> black see-through patches in-engine (Godot imports them as transparency!=0).
nop = 0
for o in bpy.data.objects:
    if o.type != 'MESH': continue
    for mat in o.data.materials:
        if not mat or not mat.use_nodes: continue
        try: mat.blend_method = 'OPAQUE'
        except Exception: pass
        try: mat.shadow_method = 'OPAQUE'          # Blender <= 4.1
        except Exception: pass
        try: mat.use_transparent_shadow = False    # Blender 4.2+ (EEVEE Next) equivalent
        except Exception: pass
        bsdf = next((b for b in mat.node_tree.nodes if b.type == 'BSDF_PRINCIPLED'), None)
        if bsdf and bsdf.inputs['Alpha'].is_linked:
            for l in list(bsdf.inputs['Alpha'].links): mat.node_tree.links.remove(l)
            bsdf.inputs['Alpha'].default_value = 1.0; nop += 1
w("forced %d skin materials opaque" % nop)

# ---- keep only Anim* (+Basis) shape keys ----
for o in bpy.data.objects:
    if o.type != 'MESH' or not o.data.shape_keys: continue
    for kb in list(o.data.shape_keys.key_blocks):
        if kb.name != "Basis" and not kb.name.lower().startswith("anim"):
            o.shape_key_remove(kb)

# ---- delete rig helper meshes (control-shape widgets, stray primitives) ----
for pb in arp.pose.bones:
    pb.custom_shape = None
_PRIM = ("cosphere", "sphere", "cube", "cylinder", "cs_", "circle", "torus", "cone")
for o in [m for m in bpy.data.objects if m.type == 'MESH']:
    if not any(mat is not None for mat in o.data.materials) or any(p in (o.data.name + o.name).lower() for p in _PRIM):
        bpy.data.objects.remove(o, do_unlink=True)

# ---- select GoE meshes + armature, export ----
bpy.ops.object.select_all(action='DESELECT')
sel = 0
for o in bpy.data.objects:
    if o.type == 'ARMATURE' and o.name == ARM_NAME:
        o.select_set(True); sel += 1
    elif o.type == 'MESH' and any(m.type == 'ARMATURE' and m.object == arp for m in o.modifiers):
        o.select_set(True); sel += 1
vl.objects.active = arp
os.makedirs(os.path.dirname(OUT), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=OUT, export_format='GLB', use_selection=True,
    export_def_bones=True, export_apply=False, export_morph=True, export_morph_normal=False,
    export_animations=True, export_animation_mode='ACTIONS', export_bake_animation=True,
    export_anim_single_armature=True, export_optimize_animation_size=True, export_yup=True,
)
final_clips = [a.name for a in bpy.data.actions if not a.name.startswith("F_Basemesh")]
w("EXPORTED %d clips -> %.1f MB  | clips: %s" % (len(baked), os.path.getsize(OUT) / 1e6, sorted(final_clips)))

# ---- self-check: confirm limbs rotate across a locomotion clip (arm orientation is the main
# thing the 4.5->5.1 importer jump could break). Prints world-rot spread per bone. ----
try:
    import math as _m
    _pick = next((bk for nm, bk in baked if nm in ("Walk_Loop","Jog_Fwd_Loop","Run_Fwd_Loop")), (baked[0][1] if baked else None))
    if _pick:
        arp.animation_data.action = _pick
        for _bn in ("thigh_stretch.l", "arm_stretch.l", "forearm_stretch.l"):
            _qs = []
            for _f in (1, 8, 16, 24):
                scene.frame_set(_f); vl.update()
                _ev = arp.evaluated_get(bpy.context.evaluated_depsgraph_get())
                _qs.append((_ev.matrix_world @ _ev.pose.bones[_bn].matrix).to_quaternion())
            _spread = max(_m.degrees(_qs[0].rotation_difference(_q).angle) for _q in _qs)
            w("SELFCHECK %s world-rot spread on %s = %.1f deg" % (_bn, _pick.name, _spread))
except Exception as _e:
    w("SELFCHECK error: %s" % _e)

open(LOG, "w", encoding="utf-8").write("\n".join(_log))
