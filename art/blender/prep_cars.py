"""Prepares Spire's downloaded low-poly cars (art/models/*.glb) for the game.

Run headless (no add-on needed):
    blender -b --factory-startup --python art/blender/prep_cars.py [-- name ...]

For each car in CARS: import it, bake its transforms, turn it so its long side
runs along X with the nose at +X (FLIP turns it round when the model faced the
other way), scale it to the real car's length, center it lengthwise and
across, set its tires on the ground (z = 0), and export
godot/models/cars/<name>.glb. The game uses that file instead of the
code-built shape (widgets/car_model.gd OPPONENT_MODELS).

THE DX (eg6): Faba's car is special. Its wheels come off (the game builds
its wheels from the parts), its seats come off (bucket seats / stripped
interior are parts), the stickers come off (a stock DX). It's fitted to the
DX's frame: scaled so the wheelbase is the DX's 2.62 m and the axles land on
x = +1.275 / -1.345, track 1.47 m. Its materials get the names the game
recolors (Paint, Roof, Hood, Fender, Glass, Headlight, Taillight, Amber), and
it exports to godot/models/dx.glb with godot/models/dx.json (where its
nose, tail, exhaust and taillights are, for the lights and flames).

Also renders a side view of each into art/models/_check/ (nose should be on
the RIGHT) so a wrong FLIP is easy to spot.

Frame: Blender +X = the nose, -Y = the car's right, +Z up (Godot +X / +Z / +Y).
"""
import json
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(REPO, "art", "models")
OUT = os.path.join(REPO, "godot", "models", "cars")
CHECK = os.path.join(SRC, "_check")

# name: (source file, real length m, flip 180)
CARS = {
    "370z": ("370z.glb", 4.25, True),
    "240z": ("240z.glb", 4.14, True),
    "ae86": ("ae86.glb", 4.2, False),
    "accord94": ("94accord.glb", 4.68, False),
    "fd2": ("fd2.glb", 4.54, False),
    "celica6": ("celica6th.glb", 4.42, True),
    "evo3": ("evo3.glb", 4.31, False),
    "eg6": ("eg6.glb", 4.07, True),         # -> the DX (godot/models/dx.glb)
}

DX_FRONT, DX_REAR, DX_TRACK = 1.275, -1.345, 1.47
DX_DROP = ("Tire", "Rim", "Nut", "Spring", "Seats", "Eg6_Sticker", "Myogi_Night_Kids_Logo")
DX_RENAME = {"Car_Paint": "Paint", "Glass": "Glass", "HeadLight": "Headlight", "Taillight": "Taillight",
             "Blinkers": "Amber"}


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for d in list(coll):
            if d.users == 0:
                coll.remove(d)


def import_joined(path):
    """Import a glb and bake it down to one mesh object (transforms applied)."""
    bpy.ops.import_scene.gltf(filepath=path)
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    for o in meshes:                               # bake the parents' transforms into each mesh
        mw = o.matrix_world.copy()
        o.parent = None
        o.matrix_world = mw
    bpy.ops.object.select_all(action="DESELECT")
    for o in meshes:
        o.select_set(True)
        if o.data.users > 1:                       # instanced meshes: make each its own before joining
            o.data = o.data.copy()
    bpy.context.view_layer.objects.active = meshes[0]
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    for o in [o for o in bpy.data.objects if o.type != "MESH"]:
        bpy.data.objects.remove(o)
    bpy.ops.object.join()
    return bpy.context.view_layer.objects.active


def bounds(ob):
    vs = [v.co for v in ob.data.vertices]
    lo = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
    hi = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
    return lo, hi


def transform(ob, m):
    ob.data.transform(m)
    ob.data.update()


def normalize(ob, length, flip):
    lo, hi = bounds(ob)
    size = hi - lo
    if size.y > size.x:                            # long side along Y: turn it onto X
        transform(ob, Matrix.Rotation(-math.pi / 2, 4, "Z"))
    if flip:
        transform(ob, Matrix.Rotation(math.pi, 4, "Z"))
    lo, hi = bounds(ob)
    s = length / (hi.x - lo.x)
    transform(ob, Matrix.Scale(s, 4))
    lo, hi = bounds(ob)
    transform(ob, Matrix.Translation(Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z))))


def faces_with(ob, names):
    idx = {i for i, m in enumerate(ob.data.materials) if m and any(m.name.startswith(n) for n in names)}
    return [p.index for p in ob.data.polygons if p.material_index in idx]


def wheel_centers(ob):
    """The four tire centers (x, y) and the tire radius, from the Tire faces."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    tire_idx = {i for i, m in enumerate(ob.data.materials) if m and m.name.startswith("Tire")}
    pts = [v.co.copy() for f in bm.faces if f.material_index in tire_idx for v in f.verts]
    bm.free()
    quads = {}
    for p in pts:
        quads.setdefault((p.x > 0, p.y > 0), []).append(p)
    out = {}
    for k, ps in quads.items():
        lo = Vector((min(p.x for p in ps), min(p.y for p in ps), min(p.z for p in ps)))
        hi = Vector((max(p.x for p in ps), max(p.y for p in ps), max(p.z for p in ps)))
        out[k] = ((lo + hi) / 2, (hi.z - lo.z) / 2)
    return out


def delete_faces(ob, face_ids):
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bm.faces.ensure_lookup_table()
    doomed = [bm.faces[i] for i in face_ids]
    bmesh.ops.delete(bm, geom=doomed, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()


def material_named(name, like):
    m = bpy.data.materials.get(name)
    if m is None:
        m = like.copy()
        m.name = name
    return m


def fit_dx(ob):
    """The EG6 as Faba's DX: wheels, seats and stickers off, fitted to the DX's axles."""
    wc = wheel_centers(ob)
    xs = sorted({round(c.x, 3) for c, _ in wc.values()})
    front_x = max(c.x for c, _ in wc.values())
    rear_x = min(c.x for c, _ in wc.values())
    track = max(c.y for c, _ in wc.values()) - min(c.y for c, _ in wc.values())
    sx = (DX_FRONT - DX_REAR) / (front_x - rear_x)                  # wheelbase -> 2.62 m
    sy = DX_TRACK / track                                           # track -> 1.47 m
    transform(ob, Matrix.Diagonal((sx, sy, 1.0, 1.0)))
    transform(ob, Matrix.Translation(Vector((DX_FRONT - front_x * sx, 0, 0))))
    print(f"  eg6: wheelbase {front_x - rear_x:.3f} -> 2.62 (x{sx:.3f}), track {track:.3f} -> 1.47 (x{sy:.3f})")
    drop = set(faces_with(ob, DX_DROP))
    # ...and anything inside a wheel (rims, nuts, brakes under generic material names):
    # within the tire's radius of an axle, out past the inner edge of the tire
    for c, r in wheel_centers(ob).values():
        for p in ob.data.polygons:
            q = p.center
            if math.hypot(q.x - c.x, q.z - c.z) < r + 0.005 and abs(q.y) > abs(c.y) - 0.14:
                drop.add(p.index)
    drop = sorted(drop)
    print("  eg6: dropping", len(drop), "faces of", len(ob.data.polygons), [m.name for m in ob.data.materials])
    delete_faces(ob, drop)
    # Rename what the game recolors
    for slot in ob.material_slots:
        if slot.material is None:
            continue
        for src, dst in DX_RENAME.items():
            if slot.material.name.startswith(src) and slot.material.name != dst:
                slot.material = material_named(dst, slot.material)
    # Split the paint: the roof and hood (sun-faded on Faba's car), the front right fender (primer)
    names = [s.material.name if s.material else "" for s in ob.material_slots]
    paint = names.index("Paint")
    for n in ("Roof", "Hood", "Fender"):
        ob.data.materials.append(material_named(n, ob.material_slots[paint].material))
        names.append(n)
    lo, hi = bounds(ob)
    for p in ob.data.polygons:
        if p.material_index != paint:
            continue
        c, n = p.center, p.normal
        if n.z > 0.55 and c.z > hi.z - 0.12:
            p.material_index = names.index("Roof")
        elif n.z > 0.55 and c.x > DX_FRONT - 0.55:
            p.material_index = names.index("Hood")
        elif c.y < -0.3 and n.y < -0.35 and DX_FRONT - 0.65 < c.x < hi.x - 0.25 and c.z > 0.3:
            p.material_index = names.index("Fender")          # -Y = the car's right
    lo, hi = bounds(ob)
    # Where things are, for the game: the tail lights, the exhaust, the nose and tail
    tails = [p.center.copy() for p in ob.data.polygons if names[p.material_index] == "Taillight"]
    meta = {"front": hi.x, "rear": lo.x, "width": hi.y - lo.y, "height": hi.z}
    if tails:
        for side in (-1, 1):
            ps = [t for t in tails if (t.y < 0) == (side < 0)]
            if ps:
                c = sum(ps, Vector()) / len(ps)
                meta.setdefault("tails", []).append([c.x, c.z, -c.y])      # Godot (x, y, z)
    ex = [p.center for p in ob.data.polygons if names[p.material_index].startswith("Exhaust")]
    if ex:
        c = sum(ex, Vector()) / len(ex)
        meta["exhaust"] = [min(p.x for p in ex), c.z, -c.y]
    return meta


def render_check(ob, name):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x, sc.render.resolution_y = 640, 300
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.location = Vector((0, -9.5, 0.8))
    cam.rotation_euler = (Vector((0, 0, 0.6)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    os.makedirs(CHECK, exist_ok=True)
    sc.render.filepath = os.path.join(CHECK, name + ".png")
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def export(ob, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True)


only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else list(CARS)
for name in only:
    src, length, flip = CARS[name]
    clear()
    ob = import_joined(os.path.join(SRC, src))
    ob.name = name
    normalize(ob, length, flip)
    if name == "eg6":
        meta = fit_dx(ob)
        export(ob, os.path.join(REPO, "godot", "models", "dx.glb"))
        with open(os.path.join(REPO, "godot", "models", "dx.json"), "w") as f:
            json.dump(meta, f, indent=1)
    else:
        export(ob, os.path.join(OUT, name + ".glb"))
    render_check(ob, name)
    tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    lo, hi = bounds(ob)
    print(f"PREP {name}: {tris} tris, {hi.x - lo.x:.2f} x {hi.y - lo.y:.2f} x {hi.z:.2f} m")
