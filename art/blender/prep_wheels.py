"""Spire's downloaded wheels (art/models/wheels/*.glb) -> game wheels
(godot/models/wheels/<name>.glb + wheels.json).

    blender -b --factory-startup --python art/blender/prep_wheels.py

Each comes at its own scale and axis. For each: bake + join, find the axle
(the thinnest side of its box), turn it so the axle runs along Blender Y with
the wheel's FACE toward -Y (a right-side wheel: the game turns it round for
the left), scale it (with a tire: the DX's tire, 0.594 m across; "_nt" = no
tire: a 15" rim, RIM_D across, and the game adds the tire), center it on the
axle, and slim it to TARGET triangles. The biggest non-tire material becomes
"Rim" (the body shop's rim colors recolor it).

Which side is the face: the side the wheel's surface area leans to (spokes
and the lip are out front; the barrel behind is plain).
"""
import json
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(REPO, "art", "models", "wheels")
OUT = os.path.join(REPO, "godot", "models", "wheels")
TIRE_D = 0.594             # 185/65R14 (the DX's)
RIM_D = 0.40               # a 15" rim, lip included
TARGET = 4000
FLIP_FACE = {"s1j": True}   # name: True if the face check gets one wrong (s1j: its brake disc outweighs the face)
TARGETS = {"countergram": 12000, "eqp40_nt": 16000}   # fine spokes need more


def bake_join(path):
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
        if o.data.users > 1:
            o.data = o.data.copy()
    for o in [o for o in bpy.data.objects if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


def bounds(ob):
    vs = [v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def is_tire(name):
    n = name.lower()
    return "tire" in n or "tyre" in n or "rubber" in n


def prep(name, has_tire):
    ob = bake_join(os.path.join(SRC, name + ".glb"))
    lo, hi = bounds(ob)
    size = hi - lo
    axis = min(range(3), key=lambda i: size[i])
    # axle -> Blender Y
    if axis == 0:
        ob.data.transform(Matrix.Rotation(math.pi / 2, 4, "Z"))
    elif axis == 2:
        ob.data.transform(Matrix.Rotation(math.pi / 2, 4, "X"))
    lo, hi = bounds(ob)
    c = (lo + hi) / 2
    ob.data.transform(Matrix.Translation(-c))
    # Face toward -Y: the area-weighted mean y of the faces (the face side has the detail)
    area = sum(p.area for p in ob.data.polygons)
    mean_y = sum(p.center.y * p.area for p in ob.data.polygons) / max(area, 1e-9)
    face_at_plus = mean_y > 0
    if face_at_plus != FLIP_FACE.get(name, False):
        ob.data.transform(Matrix.Rotation(math.pi, 4, "Z"))
    # Scale: the wheel's diameter (x/z extent)
    lo, hi = bounds(ob)
    d = max(hi.x - lo.x, hi.z - lo.z)
    k = (TIRE_D if has_tire else RIM_D) / d
    ob.data.transform(Matrix.Scale(k, 4))
    # Slim it
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    target = TARGETS.get(name, TARGET)
    if tris > target:
        mod = ob.modifiers.new("lod", "DECIMATE")
        mod.ratio = target / tris
        bpy.ops.object.modifier_apply(modifier="lod")
    # The rim's main material -> "Rim"
    areas = {}
    for p in ob.data.polygons:
        m = ob.data.materials[p.material_index]
        if m and not is_tire(m.name):
            areas[m.name] = areas.get(m.name, 0.0) + p.area
    if areas:
        main = max(areas, key=areas.get)
        bpy.data.materials[main].name = "Rim"
    for m in ob.data.materials:
        if m:
            m.use_backface_culling = False
    tris2 = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    lo, hi = bounds(ob)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    out_name = name.removesuffix("_nt")
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, out_name + ".glb"), export_format="GLB",
                              use_selection=True, export_yup=True, export_image_format="JPEG")
    print(f"WHEEL {name}: {tris} -> {tris2} tris, {hi.x - lo.x:.3f} across, {hi.y - lo.y:.3f} wide, tire {has_tire}")
    return out_name, {"tire": has_tire, "width": hi.y - lo.y}


info = {}
for f in sorted(os.listdir(SRC)):
    if f.endswith(".glb"):
        n = f[:-4]
        out, meta = prep(n, not n.endswith("_nt"))
        info[out] = meta
with open(os.path.join(OUT, "wheels.json"), "w") as fh:
    json.dump(info, fh, indent=1)
