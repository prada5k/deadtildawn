"""Builds the DX's wheels in Blender and exports one .glb per wheel to
godot/models/wheels/ (dx_model.gd uses them when they exist):

  wheels_stock   14" steelie + the hubcap (an object named "Hubcap": the game
                 hides it on the front right, lost years ago)
  wheels_light   lightweight 15", 7 spokes
  wheels_forged  forged 15", 10 thin spokes, deeper dish

How it's built: a wheel is round, so most of it is a LATHE (a profile spun
around the axle, like turning a part on a real lathe): the tire, the rim's
barrel and lip, the steelie's dish, the hubcap. The spokes are one spoke
copied around the circle. Change the numbers in WHEELS and run it again.

Frame: ONE RIGHT-SIDE wheel, centered on the axle at the origin. The axle runs
along Blender Y; the wheel's face points out the car's right side = Blender -Y
(the game turns it around for the left side). Meters.

Materials the game swaps by name: Rim (silver / bronze / steel, or the body
shop's rim color), Hubcap. Tire, Brake, Lug, Dark stay as modeled.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector


def find_repo():
    tries = [globals().get("DTD_REPO")]
    for base in (globals().get("__file__"), bpy.data.filepath):
        if base:
            tries.append(os.path.join(os.path.dirname(os.path.abspath(base)), "..", ".."))
    for t in tries:
        if t and os.path.exists(os.path.join(t, "godot", "project.godot")):
            return os.path.abspath(t)
    raise RuntimeError("Can't find the repo: open art/blender/dx.blend first, then run this script")


REPO = find_repo()
OUT_DIR = os.path.join(REPO, "godot", "models", "wheels")

TIRE_R, TIRE_W = 0.297, 0.185          # 185/65R14 (the 15s run a lower profile: same overall size)
SEGMENTS = 40                          # around the wheel

WHEELS = {
    # rim_r: where the tire's bead sits (14" = 0.178, 15" = 0.19 m)
    # spokes: (count, [(r, width, a), ...] from the hub out): a = how far out the face is,
    #   so a rising a = a concave (dished) face
    # hub: (radius, a): the center the spokes come out of; cap: the center cap (radius, material)
    # face_ring: a flat ring where the spokes meet the rim (r_in), or None
    "wheels_stock": {"rim_r": 0.178, "spokes": None, "color": (0.22, 0.22, 0.23, 1)},
    # Konig Countergram (Spire's pick), chrome: nine thin spokes that flare where they meet the
    # rim (teardrop windows), a deep dish, a raised hub with the black center cap
    "wheels_light": {"rim_r": 0.19, "color": (0.85, 0.86, 0.88, 1),
                     "spokes": (9, [(0.058, 0.020, 0.030), (0.10, 0.017, 0.048), (0.145, 0.022, 0.064),
                                    (0.168, 0.040, 0.072), (0.182, 0.062, 0.076)]),
                     "hub": (0.062, 0.040), "cap": (0.032, "Dark"), "face_ring": None},
    # Buddy Club P1 (Spire's pick), white: six wide flat spokes tapering in to a domed hub,
    # a wide flat ring around the outside where they meet the rim
    "wheels_forged": {"rim_r": 0.19, "color": (0.94, 0.94, 0.91, 1),
                      "spokes": (6, [(0.06, 0.042, 0.066), (0.12, 0.062, 0.069), (0.166, 0.092, 0.072)]),
                      "hub": (0.078, 0.070), "cap": (0.026, "Dark"), "face_ring": 0.162},
}

COLORS = {"Rim": (0.78, 0.79, 0.81, 1), "Tire": (0.04, 0.04, 0.045, 1), "Brake": (0.35, 0.35, 0.36, 1),
          "Lug": (0.6, 0.6, 0.62, 1), "Dark": (0.02, 0.02, 0.025, 1), "Hubcap": (0.72, 0.73, 0.75, 1)}


def material(name, color=None):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    c = color or COLORS[name]
    m.diffuse_color = c
    m.use_backface_culling = False       # -> glTF doubleSided: the barrel is seen from inside
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = c
        bsdf.inputs["Roughness"].default_value = 0.9 if name in ("Tire", "Dark") else 0.35
        bsdf.inputs["Metallic"].default_value = 0.0 if name in ("Tire", "Dark") else 0.8
    return m


def at(r, theta, a):
    """Radius r, angle theta around the axle, a = how far out toward the face."""
    return Vector((r * math.cos(theta), -a, r * math.sin(theta)))


def lathe(bm, profile, mat_index, closed=False):
    """Spin a profile [(r, a), ...] around the axle; returns the faces."""
    rings = [[bm.verts.new(at(r, TAU * k / SEGMENTS, a)) for k in range(SEGMENTS)] for r, a in profile]
    faces = []
    pairs = list(zip(rings, rings[1:])) + ([(rings[-1], rings[0])] if closed else [])
    for p, q in pairs:
        for k in range(SEGMENTS):
            j = (k + 1) % SEGMENTS
            f = bm.faces.new((p[k], p[j], q[j], q[k]))
            f.material_index = mat_index
            faces.append(f)
    return faces


TAU = 2 * math.pi


def spoke(bm, theta, stations, depth, mat_index):
    """One spoke along the angle theta, shaped by stations [(r, width, a), ...]
    from the hub out (a = how far out its face is: the dish), `depth` thick."""
    side = Vector((-math.sin(theta), 0, math.cos(theta)))     # across the spoke
    inward = Vector((0, depth, 0))                             # back = further in (+Y)
    left, right = [], []
    for r, w, a in stations:
        c = at(r, theta, a)
        left.append(bm.verts.new(c - side * w / 2))
        right.append(bm.verts.new(c + side * w / 2))
    left_b = [bm.verts.new(v.co + inward) for v in left]
    right_b = [bm.verts.new(v.co + inward) for v in right]
    for k in range(len(stations) - 1):
        for quad in ((left[k], right[k], right[k + 1], left[k + 1]),          # the face
                     (left_b[k + 1], right_b[k + 1], right_b[k], left_b[k]),  # the back
                     (left[k], left[k + 1], left_b[k + 1], left_b[k]),        # the sides
                     (right[k + 1], right[k], right_b[k], right_b[k + 1])):
            bm.faces.new(quad).material_index = mat_index
    for quad in ((left[0], left_b[0], right_b[0], right[0]), (right[-1], right_b[-1], left_b[-1], left[-1])):
        bm.faces.new(quad).material_index = mat_index


def disc(bm, r, a, thick, mat_index, center=(0.0, 0.0)):
    """A flat cylinder on the axle (or offset by center = (x, z)) between a - thick and a."""
    rings = []
    for aa in (a - thick, a):
        rings.append([bm.verts.new(at(r, TAU * k / 16, aa) + Vector((center[0], 0, center[1]))) for k in range(16)])
    for k in range(16):
        j = (k + 1) % 16
        bm.faces.new((rings[0][k], rings[0][j], rings[1][j], rings[1][k])).material_index = mat_index
    bm.faces.new(list(reversed(rings[0]))).material_index = mat_index
    bm.faces.new(rings[1]).material_index = mat_index


def new_object(name, bm, mats):
    me = bpy.data.meshes.new(name)
    bm.normal_update()
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for m in mats:
        ob.data.materials.append(m)
    for p in ob.data.polygons:
        p.use_smooth = True
    return ob


def build_wheel(wid, spec):
    mats = [material("Rim", spec["color"]), material("Tire"), material("Brake"), material("Lug"), material("Dark")]
    RIM, TIRE, BRAKE, LUG, DARK = range(5)
    rr = spec["rim_r"]
    hw = TIRE_W / 2
    bm = bmesh.new()
    # The tire: bead -> sidewall (bulging) -> shoulder -> tread -> back the other side
    lathe(bm, [(rr, 0.083), (rr + 0.025, 0.091), (0.25, 0.095), (0.283, 0.088), (TIRE_R, 0.066),
               (TIRE_R, -0.066), (0.283, -0.088), (0.25, -0.095), (rr + 0.025, -0.091), (rr, -0.083)], TIRE)
    # The rim: the lip at the face, the barrel going in (seen through the spokes), the back flange
    lathe(bm, [(rr + 0.012, 0.088), (rr + 0.012, 0.079), (rr - 0.004, 0.074), (rr - 0.012, 0.062),
               (rr - 0.012, -0.08), (rr + 0.01, -0.088)], RIM)
    # Behind it all: the brake rotor and the dark hub carrier
    disc(bm, 0.13, -0.01, 0.02, BRAKE)
    disc(bm, 0.07, -0.03, 0.04, DARK)
    if spec["spokes"]:
        n, shape = spec["spokes"]
        for k in range(n):
            spoke(bm, TAU * k / n + math.pi / 2, shape, 0.024, RIM)
        hr, ha = spec["hub"]
        lathe(bm, [(0.0, ha + 0.006), (hr * 0.6, ha + 0.004), (hr, ha - 0.004), (hr + 0.004, ha - 0.035)], RIM)  # the hub
        cap_r, cap_m = spec["cap"]
        disc(bm, cap_r, ha + 0.012, 0.012, DARK if cap_m == "Dark" else RIM)          # center cap
        if spec["face_ring"]:                                                          # the flat outer ring
            lathe(bm, [(rr - 0.004, 0.076), (spec["face_ring"], 0.074), (spec["face_ring"] - 0.004, 0.06)], RIM)
        lathe(bm, [(rr + 0.012, 0.0905), (rr + 0.004, 0.0905), (rr + 0.002, 0.084)], RIM)   # a step in the lip
        lug_a = ha + 0.006
    else:
        # The steelie: a pressed steel dish with vent holes
        lathe(bm, [(0.0, 0.05), (0.06, 0.05), (0.075, 0.042), (0.12, 0.046), (0.15, 0.058),
                   (rr - 0.012, 0.062)], RIM)
        for k in range(6):                                                             # vent holes (dark ovals)
            t = TAU * k / 6 + math.pi / 6
            disc(bm, 0.018, 0.0475 + 0.0035, 0.002, DARK, center=(0.135 * math.cos(t), 0.135 * math.sin(t)))
        lug_a = 0.06
    for k in range(4):                                                                 # 4 x 100 lug nuts
        t = TAU * k / 4 + math.pi / 4
        disc(bm, 0.009, lug_a, 0.014, LUG, center=(0.05 * math.cos(t), 0.05 * math.sin(t)))
    objs = [new_object(wid, bm, mats)]
    if not spec["spokes"]:
        # The hubcap: a plastic full cover with two rings and a domed middle (the game hides the lost one)
        bm = bmesh.new()
        lathe(bm, [(0.0, 0.097), (0.04, 0.096), (0.07, 0.093), (0.075, 0.088), (0.12, 0.09),
                   (0.13, 0.086), (0.175, 0.088), (0.188, 0.08), (0.188, 0.07)], 0)
        objs.append(new_object("Hubcap", bm, [material("Hubcap")]))
    return objs


def export(objs, path):
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True)


os.makedirs(OUT_DIR, exist_ok=True)
coll = bpy.data.collections.get("Wheels") or bpy.data.collections.new("Wheels")
for ob in list(bpy.data.objects):                    # rebuild only the wheels, leave the car alone
    if ob.get("dtd_wheel"):
        bpy.data.objects.remove(ob)
report = []
for i, (wid, spec) in enumerate(WHEELS.items()):
    objs = build_wheel(wid, spec)
    export(objs, os.path.join(OUT_DIR, wid + ".glb"))
    for ob in objs:                                  # keep them in the .blend, lined up beside the car
        ob["dtd_wheel"] = wid
        ob.location = Vector((-1.2 + 1.2 * i, -2.0, 0.297))
    tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
    report.append(f"{wid}: {tris} tris")
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(REPO, "art", "blender", "dx.blend"), copy=True)
print("wheels:", ", ".join(report), "->", OUT_DIR)
