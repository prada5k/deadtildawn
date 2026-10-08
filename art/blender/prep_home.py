"""CONTRABAND96 HOME assets: the EG6 and the parking garage, prepared for Godot.

Raw sources (never modified):
    art/models/cars/eg6.glb              Sketchfab EG6, ~23.5k tris, ~2x too big, faces -Y, stickers
    art/models/scenes/parking_garage.glb photogrammetry scan, 679k tris, two 8192^2 photo textures

Game-ready outputs (what godot/home/home_garage.gd loads):
    godot/assets/models/cars/eg6_game.glb
    godot/assets/models/scenes/garage1_game.glb

Run (headless, repeatable):
    blender -b --factory-startup --python art/blender/prep_home.py [-- car|garage]
or send it through the Blender MCP add-on's socket (port 9876) with a wrapper that sets
STAGES = ["car"] and exec()s this file. Everything happens in a temporary scene that is
removed at the end, so a scene the user has open is not touched.

GAME FRAME (both files): Blender +X = the car's nose = Godot +X, Blender Z up, Blender -Y = the
car's right = Godot +Z (the glTF exporter turns Blender (x, y, z) into Godot (x, z, -y)). The
EG6's origin is the middle of its footprint with the tire bottoms on z = 0. The garage is moved so
the stall the EG6 parks in is centered on the origin with the nose pointing out of the stall
toward +X, the floor at z = 0, and the stall's back wall at about x = -2.4: so the garage and the
car share one origin and home_garage.gd can add both with no offsets.
"""
import math
import os
import re
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector

REPO = r"C:\Users\sam11\Downloads\dev\deadtildawn"
SRC_CAR = os.path.join(REPO, "art", "models", "cars", "eg6.glb")
SRC_GARAGE = os.path.join(REPO, "art", "models", "scenes", "parking_garage.glb")
OUT_CAR = os.path.join(REPO, "godot", "assets", "models", "cars", "eg6_game.glb")
OUT_GARAGE = os.path.join(REPO, "godot", "assets", "models", "scenes", "garage1_game.glb")

# ---- the car ----
CAR_LENGTH_M = 4.09          # 1995 EG6 hatch, bumper to bumper (the model's own proportions give width 1.66)
STICKER_MATS = {"Eg6_Sticker", "Myogi_Night_Kids_Logo"}   # Spire: plain, no stickers
WHEELS = {"Ft.L": "Wheel_FL", "Ft.R": "Wheel_FR", "Bk.L": "Wheel_RL", "Bk.R": "Wheel_RR"}
# the model's material -> (game name, base color or None, roughness, emission strength or None)
# Original lamp emission was 10 (a lit car); a parked car in a dim garage gets lenses, not floodlights.
CAR_MATERIALS = {
    "Car_Paint": ("Paint", None, 0.38, None),
    "Tire": ("Tire", None, 0.95, None),
    "material": ("Rim", None, 0.45, None),
    "Rim.001": ("RimAccent", None, 0.5, None),
    "material_3": ("WheelNut", None, 0.8, None),
    "Plastic": ("Plastic", None, 0.85, None),
    "Plastic.001": ("Plastic", None, 0.85, None),
    "Darkness": ("Darkness", None, 1.0, None),
    "Blinkers": ("Amber", None, 0.4, 0.35),
    "Taillight": ("Taillight", None, 0.3, 0.6),
    "HeadLight": ("Headlight", None, 0.3, 0.7),
    "Seats": ("Seats", None, 0.95, None),
    "Spring": ("Spring", None, 0.8, None),
    "Interior": ("Interior", None, 0.95, None),
    "Mirror": ("MirrorGlass", None, 0.15, None),
    "Exhaust": ("Exhaust", None, 0.7, None),
    "Glass": ("Glass", None, 0.1, None),
}
EMISSION_COLORS = {"Headlight": (0.82, 0.9, 1.0, 1.0)}   # the original's saturated blue reads as a flat blue rectangle

# ---- the garage ----
STALL_CENTER = Vector((7.1, -3.845))   # scan frame: the middle of the stall's two painted lines (measured), ~0.3 m off the back wall
STALL_LINES_Z = (1.275, -1.275, -3.825)   # game frame: the painted lines (measured from the photo: 2.55 m stalls); the car's stall is the middle one
LINE_X = (-2.2, 2.2)                   # from the back wall to the aisle
LINE_WIDTH = 0.10
SHELL_BACK_X, SHELL_CEILING_Z = -2.36, 3.16      # game frame: just behind the scan's back wall / just above its slab
RAGGED_X, RAGGED_Z = -1.7, 1.9                  # game frame: the back wall's top strip the scan got wrong (x behind this, z above this)
SHELL_Y = (-9.6, 6.8, 9.3)                     # the back wall's and the ceiling's extent: y0, y1, and how far the ceiling runs (x)
BRIGHT_GAMMA, BRIGHT_GAIN = 0.85, 1.15   # the scan's photo is dark: lift it a little
FLAT_INNER = (-2.15, 3.3, 1.5)         # game frame: the floor is flattened to z = 0 in x from -2.15 to 3.3, |y| < 1.5 ...
FLAT_OUTER = (-2.15, 4.2, 2.5)         # ... and blends back to the scan's own floor by here (so the tires truly touch it)
TEXTURE_PX = 1024                      # the photo is only sampled for colors: no need for 8192^2 in memory
CROP_MIN_X = -2.0                      # nothing behind the camera's view of the stall wing is kept
MIN_ISLAND_TRIS = 400                  # a disconnected piece smaller than this is a scrap, not structure
DISSOLVE_DEG = 5.0                     # coplanar to within this = one polygon
POSTERIZE = 20                         # color levels per channel: flat paint, not a photo
SMOOTH_ITER = 120                      # flatten the scan's lumps before collapsing it to facets
SMOOTH_FACTOR = 0.5

# ---- the warehouse (Garage 1, replaces the parking structure) ----
SRC_WAREHOUSE = os.path.join(REPO, "art", "models", "scenes", "warehouse_fbx.glb")
OUT_WAREHOUSE = os.path.join(REPO, "godot", "assets", "models", "scenes", "warehouse1_game.glb")
HALL_Y0 = 23.0                         # hall frame: the point along the 46 m hall that becomes game x = 0
HALL_CROP = (-7.5, 11.5)               # ...and how much of it is kept (game x), closed at both ends by plain walls
WALL_Y = 2.6                           # Blender-game frame: the long side wall the car parks beside (game z = -2.6)
FLOOR_TILE = 1.0                       # the matte concrete floor: faceted tiles
WH_GAIN, WH_TINT = 0.62, (1.0, 0.97, 0.9)   # the structure's brightness and warm tint

# ---- the props (the pack in art/models/warehouse props/) ----
SRC_PROPS = os.path.join(REPO, "art", "models", "warehouse props")
OUT_PROPS = os.path.join(REPO, "godot", "assets", "models", "scenes", "warehouse_props_game.glb")
FIXTURES = ((-0.8, -0.4, 3.0), (0.8, -0.4, 3.0), (-4.4, 0.1, 3.0))    # ceiling fluorescents (game frame: x, Blender y, z)
SWITCH_AT = (HALL_CROP[0] + 0.03, WALL_Y - 2.0, 1.3)   # on the end wall, beside the locker
SWITCH_SCALE = 0.035                   # the pack's switch is ~6 units wide: a real plate is ~7 cm
LOCKER_CHROMA, LOCKER_GAIN = 0.6, 1.7
BOXES = (((0.55, 0.42, 0.38), (HALL_CROP[0] + 0.45, WALL_Y - 1.75, 0.19), 0.12),     # placeholders (no box model supplied)
         ((0.42, 0.42, 0.42), (HALL_CROP[0] + 0.5, WALL_Y - 2.3, 0.21), -0.2),
         ((0.46, 0.34, 0.3), (HALL_CROP[0] + 0.45, WALL_Y - 1.75, 0.55), 0.35))
TRASH_AT = (-6.0, 2.2)                  # a placeholder bin (no model supplied) on the floor by the work area

STAGES = globals().get("STAGES") or [a for a in (sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else [])] or ["car", "garage"]


# ------------------------------------------------------------------ helpers
def base_name(name):
    """'Car_Paint.002' -> 'Car_Paint' (Blender suffixes a name that is already taken)."""
    return re.sub(r"\.\d{3}$", "", name)


def purge_orphans():
    """Datablocks nothing uses (left by an earlier run): else a new import's materials are suffixed .001."""
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for d in [d for d in coll if d.users == 0]:
            coll.remove(d)


def fresh_scene(name):
    old = bpy.data.scenes.get(name)
    if old is not None:
        for o in list(old.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.scenes.remove(old)
    purge_orphans()
    sc = bpy.data.scenes.new(name)
    if bpy.context.window is not None:
        bpy.context.window.scene = sc
    return sc


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    return [o for o in bpy.data.objects if o not in before]


def bake_world(objs):
    """Each mesh keeps its place but loses its parents; empties go."""
    for o in objs:
        if o.type != "MESH":
            continue
        mw = o.matrix_world.copy()
        o.data.transform(mw)
        if mw.determinant() < 0:
            o.data.flip_normals()
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
    for o in objs:
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)


def transform_meshes(objs, m):
    for o in objs:
        o.data.transform(m)
        if m.determinant() < 0:
            o.data.flip_normals()


def bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for v in o.data.vertices:
            w = o.matrix_world @ v.co
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def join(objs, name):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def tri_count(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def solids(o):
    """Welded components of a mesh: [(face indices, closed?, signed volume)]. The glTF import splits
    vertices per face, so topology is read by position. A CLOSED component with negative volume is
    inside-out; an open sheet (glass, a lens, a panel) has no inside and its facing is left as modeled."""
    me = o.data
    vk = [(round(v.co.x * 1e4), round(v.co.y * 1e4), round(v.co.z * 1e4)) for v in me.vertices]
    edge_faces = {}
    for p in me.polygons:
        ks = [vk[i] for i in p.vertices]
        for a, b in zip(ks, ks[1:] + ks[:1]):
            edge_faces.setdefault((a, b) if a < b else (b, a), []).append(p.index)
    parent = list(range(len(me.polygons)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for fs in edge_faces.values():
        for f in fs[1:]:
            parent[find(f)] = find(fs[0])
    closed = {}
    for fs in edge_faces.values():
        c = find(fs[0])
        closed[c] = closed.get(c, True) and len(fs) == 2
    comps = {}
    for p in me.polygons:
        comps.setdefault(find(p.index), []).append(p.index)
    out = []
    for c, faces in comps.items():
        vol = 0.0
        for fi in faces:
            vs = [me.vertices[i].co for i in me.polygons[fi].vertices]
            for i in range(1, len(vs) - 1):
                vol += vs[0].dot(vs[i].cross(vs[i + 1])) / 6.0
        out.append((faces, closed.get(c, False), vol))
    return out


def check_normals(o, report):
    s = solids(o)
    closed = [c for c in s if c[1]]
    inside_out = [c for c in closed if c[2] < 0]
    report.append(f"    {o.name!r}: {len(closed)} closed solids ({len(inside_out)} inside-out), {len(s) - len(closed)} open sheets")
    return inside_out


def set_input(node, key, value):
    if key in node.inputs:
        node.inputs[key].default_value = value


def tune_materials(objs, table):
    """Rename + tune the model's materials; duplicates are merged onto one."""
    made = {}
    for o in objs:
        me = o.data
        for i, m in enumerate(me.materials):
            key = m.name if m.name in table else base_name(m.name)   # 'Rim.001' is a real name in this model
            if m is None or key not in table:
                continue
            new, color, rough, emit = table[key]
            if new in made:
                me.materials[i] = made[new]
                continue
            m.name = new
            made[new] = m
            bsdf = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
            if color is not None:
                set_input(bsdf, "Base Color", color)
            set_input(bsdf, "Roughness", rough)
            set_input(bsdf, "Metallic", 0.0)
            if emit is not None:
                set_input(bsdf, "Emission Strength", emit)
            if new in EMISSION_COLORS:
                set_input(bsdf, "Emission Color", EMISSION_COLORS[new])
            m.use_backface_culling = False       # the model's glass and sheets are single-layer
            if new == "Glass":
                m.surface_render_method = "BLENDED"
            else:
                m.surface_render_method = "DITHERED"
                set_input(bsdf, "Alpha", 1.0)
    return made


def export(path, objs):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=False, export_cameras=False, export_lights=False)
    print(f"  wrote {os.path.getsize(path) / 1e6:.2f} MB -> {path}")


def cleanup(sc):
    mats, images = set(), set()
    for o in list(sc.objects):
        if o.type == "MESH":
            mats.update(m for m in o.data.materials if m)
            bpy.data.objects.remove(o, do_unlink=True)
    for m in mats:
        if m.use_nodes:
            images.update(n.image for n in m.node_tree.nodes if n.type == "TEX_IMAGE" and n.image)
        bpy.data.materials.remove(m)
    for im in images:
        bpy.data.images.remove(im)
    for me in [me for me in bpy.data.meshes if me.users == 0]:
        bpy.data.meshes.remove(me)
    bpy.data.scenes.remove(sc)


# ------------------------------------------------------------------ the car
def prep_car():
    print("== EG6")
    sc = fresh_scene("home_prep_car")
    objs = import_glb(SRC_CAR)

    # which wheel does each mesh belong to (the model groups them under Name-Wheel.* empties)
    wheel_of = {}
    for o in objs:
        if o.type != "MESH":
            continue
        p = o
        while p is not None and not p.name.startswith("Name-Wheel."):
            p = p.parent
        if p is not None:
            wheel_of[o.name] = WHEELS[p.name[len("Name-Wheel."):]]

    stickers = [o for o in objs if o.type == "MESH" and o.data.materials
                and all(m is not None and base_name(m.name) in STICKER_MATS for m in o.data.materials)]
    print(f"  removing {len(stickers)} sticker meshes: {[o.name for o in stickers]}")
    gone = {o.name for o in stickers}
    objs = [o for o in objs if o.name not in gone]
    for name in gone:
        wheel_of.pop(name, None)
        bpy.data.objects.remove(bpy.data.objects[name], do_unlink=True)

    bake_world(objs)
    meshes = [o for o in sc.objects if o.type == "MESH"]
    body = [o for o in meshes if o.name not in wheel_of]
    wheels = [o for o in meshes if o.name in wheel_of]

    # orientation (nose -Y -> +X) and size (real length)
    rot = Matrix.Rotation(math.radians(90.0), 4, "Z")
    transform_meshes(meshes, rot)
    lo, hi = bounds(body)
    scale = CAR_LENGTH_M / (hi.x - lo.x)
    transform_meshes(meshes, Matrix.Scale(scale, 4))
    # origin = middle of the body's footprint, tire bottoms on z = 0 (wheel contact height)
    lo, hi = bounds(body)
    wlo, whi = bounds(wheels)
    shift = Matrix.Translation(Vector((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -min(lo.z, wlo.z))))
    transform_meshes(meshes, shift)
    print(f"  scale {scale:.4f}")

    report = []
    flipped = 0
    for o in meshes:
        bad = check_normals(o, report)
        if bad:                                     # a closed solid turned inside-out: flip just its faces
            bm = bmesh.new()
            bm.from_mesh(o.data)
            bm.faces.ensure_lookup_table()
            bmesh.ops.reverse_faces(bm, faces=[bm.faces[i] for c in bad for i in c[0]])
            bm.to_mesh(o.data)
            bm.free()
            flipped += len(bad)
    print(f"  normals: {flipped} inside-out closed solids flipped")
    print("\n".join(r for r in report if "(0 inside-out)" not in r) or "    (every closed solid already faces outward)")

    made = tune_materials(meshes, CAR_MATERIALS)
    # drop materials that nothing uses any more (the stickers' textures went with their meshes)
    for m in [m for m in bpy.data.materials if m.users == 0]:
        bpy.data.materials.remove(m)
    for im in [im for im in bpy.data.images if im.users == 0 and im.name.startswith("Image_")]:
        bpy.data.images.remove(im)

    # wheels: one object per corner, origin at the hub; everything else one Body
    out = []
    groups = {name: [o for o in wheels if wheel_of[o.name] == name]       # (before join renames them)
              for name in ("Wheel_FL", "Wheel_FR", "Wheel_RL", "Wheel_RR")}
    for name, parts in groups.items():
        w = join(parts, name)
        bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")
        out.append(w)
    b = join(body, "Body")
    bpy.context.view_layer.objects.active = b
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")        # cursor sits at the world origin
    out.insert(0, b)

    lo, hi = bounds(out)
    print(f"  final size L {hi.x - lo.x:.3f}  W {hi.y - lo.y:.3f}  H {hi.z - lo.z:.3f}   z0 {lo.z:.4f}"
          f"  x [{lo.x:.2f}, {hi.x:.2f}]  y [{lo.y:.2f}, {hi.y:.2f}]")
    for o in out:
        print(f"  {o.name:10} tris {tri_count(o):6}  origin {tuple(round(v, 3) for v in o.location)}  mats {[m.name for m in o.data.materials]}")
    export(OUT_CAR, out)
    cleanup(sc)


# ------------------------------------------------------------------ the garage
def image_of(material):
    """The texture feeding the material's Base Color (else the first image in it)."""
    nodes = material.node_tree.nodes
    bsdf = next((n for n in nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is not None and bsdf.inputs["Base Color"].links:
        todo = [bsdf.inputs["Base Color"].links[0].from_node]
        while todo:
            n = todo.pop()
            if n.type == "TEX_IMAGE" and n.image is not None:
                return n.image
            todo += [i.links[0].from_node for i in n.inputs if i.links]
    for n in nodes:
        if n.type == "TEX_IMAGE" and n.image is not None:
            return n.image
    return None


def bake_corner_colors(o):
    """Every face corner takes the photo's color at its UV (a color attribute, like vertex paint)."""
    me = o.data
    n = len(me.loops)
    uv = np.empty(n * 2, dtype=np.float32)
    me.uv_layers.active.data.foreach_get("uv", uv)
    uv = uv.reshape(-1, 2)
    mat_of_poly = np.empty(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("material_index", mat_of_poly)
    loop_total = np.empty(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("loop_total", loop_total)
    mat_of_loop = np.repeat(mat_of_poly, loop_total)
    cols = np.ones((n, 4), dtype=np.float32)
    for mi, m in enumerate(me.materials):
        img = image_of(m) if m else None
        if img is None:
            continue
        w, h = img.size
        px = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(px)
        px = px.reshape(h, w, 4)
        sel = mat_of_loop == mi
        x = np.clip((uv[sel, 0] % 1.0) * (w - 1), 0, w - 1).astype(np.int32)
        y = np.clip((uv[sel, 1] % 1.0) * (h - 1), 0, h - 1).astype(np.int32)
        cols[sel] = px[y, x]
    attr = me.color_attributes.new("Col", "FLOAT_COLOR", "CORNER")
    attr.data.foreach_set("color", cols.ravel())
    me.color_attributes.active_color = attr


def face_data(o):
    """Per face: its center and its corners' average color (the dense scan, before it is decimated)."""
    me = o.data
    n = len(me.polygons)
    centers = np.empty(n * 3, dtype=np.float32)
    me.polygons.foreach_get("center", centers)
    cols = np.empty(len(me.loops) * 4, dtype=np.float32)
    me.color_attributes["Col"].data.foreach_get("color", cols)
    cols = cols.reshape(-1, 4)[:, :3]
    total = np.empty(n, dtype=np.int32)
    me.polygons.foreach_get("loop_total", total)
    sums = np.zeros((n, 3), dtype=np.float64)
    np.add.at(sums, np.repeat(np.arange(n), total), cols)
    return centers.reshape(-1, 3), sums / total[:, None]


def resample_colors(o, centers, rgb):
    """A decimated facet is big (and often a sliver): give it the average color of the dense scan faces that
    fall inside it instead of its three corners' colors, which can be far apart (they streak into rays)."""
    from mathutils.bvhtree import BVHTree
    me = o.data
    bvh = BVHTree.FromPolygons([v.co.copy() for v in me.vertices], [tuple(p.vertices) for p in me.polygons])
    n = len(me.polygons)
    owner = np.empty(len(centers), dtype=np.int64)
    for i, c in enumerate(centers):
        owner[i] = bvh.find_nearest(Vector(c))[2]
    sums = np.zeros((n, 3), dtype=np.float64)
    count = np.zeros(n, dtype=np.float64)
    np.add.at(sums, owner, rgb)
    np.add.at(count, owner, 1.0)
    own_centers, own_rgb = face_data(o)
    return np.where(count[:, None] > 0, sums / np.maximum(count, 1.0)[:, None], own_rgb)


def grade(face_rgb):
    """The photo's colors as the game wants them (n, 3 sRGB-encoded -> n, 3 linear): neutral concrete (the
    photo's green / purple chroma noise goes, strong colors stay: soft knee on saturation), a little
    lifted (the scan's photo is dark), posterized into flat paint."""
    rgb = np.asarray(face_rgb, dtype=np.float64)
    lum = rgb @ np.array([0.299, 0.587, 0.114])
    sat = (rgb.max(1) - rgb.min(1)) / np.maximum(rgb.max(1), 1e-4)
    k = np.clip((sat - 0.34) / 0.30, 0.0, 1.0)
    keep = 0.05 + 0.95 * (k * k * (3.0 - 2.0 * k))
    rgb = np.clip(lum[:, None] + (rgb - lum[:, None]) * keep[:, None], 0.0, 1.0)
    rgb = np.clip(rgb ** BRIGHT_GAMMA * BRIGHT_GAIN, 0.0, 1.0)
    rgb = np.round(rgb * POSTERIZE) / POSTERIZE
    # the photo's pixels are sRGB-encoded; glTF vertex colors are linear (else the whole garage renders washed out)
    return np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)


def flatten_colors(o, face_rgb=None):
    """One color per face, posterized, flat shading. face_rgb (n, 3): the colors to use (else each face's
    corners' average)."""
    me = o.data
    attr = me.color_attributes["Col"]
    n = len(me.loops)
    total = np.empty(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("loop_total", total)
    face_of_loop = np.repeat(np.arange(len(me.polygons)), total)
    if face_rgb is None:
        cols = np.empty(n * 4, dtype=np.float32)
        attr.data.foreach_get("color", cols)
        sums = np.zeros((len(me.polygons), 3), dtype=np.float64)
        np.add.at(sums, face_of_loop, cols.reshape(-1, 4)[:, :3])
        face_rgb = sums / total[:, None]
    lin = grade(face_rgb)
    out = np.ones((len(me.polygons), 4), dtype=np.float32)
    out[:, :3] = lin
    attr.data.foreach_set("color", out[face_of_loop].ravel())
    me.polygons.foreach_set("use_smooth", np.zeros(len(me.polygons), dtype=bool))


def manhattan_snap(ob, tol=0.08, bin_m=0.02, min_verts=300):
    """A parking structure is built from axis-aligned planes. Find them (peaks in the histogram of the
    vertices facing each axis) and pull every nearby vertex that faces that axis onto the plane: walls,
    slab undersides and pillar sides become clean planes with crisp corners, instead of a noisy scan
    that flat shading turns into crumpled paper."""
    me = ob.data
    n = len(me.vertices)
    co = np.empty(n * 3, dtype=np.float32)
    me.vertices.foreach_get("co", co)
    co = co.reshape(-1, 3)
    nr = np.empty(n * 3, dtype=np.float32)
    me.vertex_normals.foreach_get("vector", nr)
    nr = nr.reshape(-1, 3)
    min_height = (0.15, 0.15, 0.5)               # the floor is flattened separately: only walls and slabs snap
    for axis, name in enumerate("xyz"):
        facing = (np.abs(nr[:, axis]) > 0.4) & (co[:, 2] > min_height[axis])
        vals = co[facing, axis]
        planes = []
        left = vals.copy()
        while len(left) >= min_verts:
            lo, hi = float(left.min()), float(left.max())
            bins = max(int((hi - lo) / bin_m) + 1, 1)
            hist, edges = np.histogram(left, bins=bins, range=(lo, hi + 1e-6))
            k = int(hist.argmax())
            c = (edges[k] + edges[k + 1]) / 2
            near = np.abs(left - c) < tol / 2
            if near.sum() < min_verts:
                break
            planes.append(float(left[near].mean()))
            left = left[np.abs(left - planes[-1]) >= tol]
        if not planes:
            continue
        planes = np.array(sorted(planes))
        idx = np.abs(co[:, axis][:, None] - planes[None, :]).argmin(1)
        d = np.abs(co[:, axis] - planes[idx])
        move = facing & (d < tol)
        co[move, axis] = planes[idx[move]]
        print(f"  snap {name}: {len(planes)} planes, {int(move.sum())} vertices moved  {np.round(planes, 2).tolist()[:14]}")
    me.vertices.foreach_set("co", co.ravel())
    me.update()


def make_stall_lines(sc, mat):
    """The stall's painted lines, as thin raised quads (the decimated floor is a few huge triangles, which
    would average a 10 cm stripe away). Worn: broken into segments with gaps, a little uneven in width and
    in how white they still are."""
    rng = np.random.default_rng(96)
    bm = bmesh.new()
    col = bm.loops.layers.float_color.new("Col")

    def linear(s):
        return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4

    for z_line in STALL_LINES_Z:                 # game z = -(Blender y)
        by = -z_line
        x = LINE_X[0]
        while x < LINE_X[1] - 0.05:
            x1 = min(x + float(rng.uniform(0.5, 1.0)), LINE_X[1])
            w = LINE_WIDTH * float(rng.uniform(0.85, 1.1))
            g = linear(float(rng.uniform(0.42, 0.72)))     # faded paint
            quad = [bm.verts.new((x, by - w / 2, 0.006)), bm.verts.new((x1, by - w / 2, 0.006)),
                    bm.verts.new((x1, by + w / 2, 0.006)), bm.verts.new((x, by + w / 2, 0.006))]
            for loop in bm.faces.new(quad).loops:
                loop[col] = (g, g, g * 0.96, 1.0)
            x = x1 + float(rng.uniform(0.03, 0.14))
    me = bpy.data.meshes.new("StallLines")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new("StallLines", me)
    sc.collection.objects.link(ob)
    return ob


def make_shell(sc, mat, wall_rgb, ceiling_rgb):
    """Two plain dark planes behind the scan: the back wall (up to the ceiling) and the ceiling. The scan
    never captured the wall-to-ceiling junction, so without them a ragged wall top meets black void."""
    bm = bmesh.new()
    col = bm.loops.layers.float_color.new("Col")
    wall = tuple(float(v) for v in grade(np.array([wall_rgb]))[0])        # the scan's own wall / ceiling color
    ceil = tuple(float(v) for v in grade(np.array([ceiling_rgb]))[0])
    x, z_top = SHELL_BACK_X, SHELL_CEILING_Z
    y0, y1, x1 = SHELL_Y
    quads = [
        [(x, y0, 0.0), (x, y1, 0.0), (x, y1, z_top), (x, y0, z_top)],            # back wall, faces +x
        [(x, y0, z_top), (x, y1, z_top), (x1, y1, z_top), (x1, y0, z_top)],      # ceiling, faces down
    ]
    for q, c in zip(quads, (wall, ceil)):
        for loop in bm.faces.new([bm.verts.new(v) for v in q]).loops:
            loop[col] = (c[0], c[1], c[2], 1.0)
    me = bpy.data.meshes.new("Shell")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new("Shell", me)
    sc.collection.objects.link(ob)
    return ob


def prep_garage():
    print("== garage")
    sc = fresh_scene("home_prep_garage")
    objs = import_glb(SRC_GARAGE)
    bake_world(objs)
    meshes = [o for o in sc.objects if o.type == "MESH"]
    for o in meshes:                                      # the photo is only sampled for color
        for m in o.data.materials:
            img = image_of(m) if m else None
            if img is not None and img.size[0] > TEXTURE_PX:
                img.scale(TEXTURE_PX, TEXTURE_PX)
    for o in meshes:
        bake_corner_colors(o)
    ob = join(meshes, "Garage")
    tris0 = tri_count(ob)
    # The glTF import attaches the scan's own (noisy) normals as custom normals. They would override the
    # facets' flat shading and survive every edit below: clear them.
    print(f"  custom normals before: {ob.data.has_custom_normals}")
    bpy.context.view_layer.objects.active = ob
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    print(f"  custom normals after: {ob.data.has_custom_normals}")

    # keep the part of the scan the camera can see
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    cut = [f for f in bm.faces if f.calc_center_median().x < CROP_MIN_X]
    bmesh.ops.delete(bm, geom=cut, context="FACES")
    loose = [v for v in bm.verts if not v.link_faces]
    bmesh.ops.delete(bm, geom=loose, context="VERTS")
    # WELD: the glTF import splits vertices at every UV seam. Smoothing or collapsing an unwelded scan
    # moves the two sides of each seam apart and tears it into shards. The baked colors are per face
    # corner, so they survive the weld.
    verts0 = len(bm.verts)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    print(f"  welded {verts0} -> {len(bm.verts)} vertices")
    bm.to_mesh(ob.data)
    bm.free()
    tris1 = tri_count(ob)

    # the stall's floor level: median height of the floor near the stall
    near = [v.co.z for v in ob.data.vertices
            if (Vector((v.co.x, v.co.y)) - STALL_CENTER).length < 2.2 and v.co.z < 0.3]
    floor_z = float(np.median(near)) if near else -0.55
    print(f"  tris {tris0} -> {tris1} after crop; floor z {floor_z:.3f}")

    # smooth the scan's lumps (modifier: keeps the borders)
    sm = ob.modifiers.new("smooth", "LAPLACIANSMOOTH")
    sm.lambda_factor = SMOOTH_FACTOR
    sm.lambda_border = 0.0                       # the scan's open edges stay put
    sm.iterations = SMOOTH_ITER
    sm.use_volume_preserve = True                # walls and pillars don't shrink
    sm.use_normalized = True
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.modifier_apply(modifier="smooth")
    # to the game frame: stall center at the origin, nose out of the stall toward +X, floor at z = 0
    m = Matrix.Rotation(math.pi, 4, "Z") @ Matrix.Translation(Vector((-STALL_CENTER.x, -STALL_CENTER.y, -floor_z)))
    ob.data.transform(m)

    # the scan's floor is lumpy (+-5 cm): squash the noise out of everything near the floor (wall bases
    # fade out of it by 0.2 m), then flatten the stall exactly so the car's wheels really sit on it
    for v in ob.data.vertices:
        z = v.co.z
        if z < 0.2:
            t = min(max((z - 0.06) / 0.14, 0.0), 1.0)
            v.co.z = z * (1.0 - (1.0 - t * t * (3.0 - 2.0 * t)) * 0.9)
    flattened = 0
    for v in ob.data.vertices:
        c = v.co
        if c.z > 0.15 or c.x < FLAT_INNER[0]:
            continue
        ox = max(0.0, c.x - FLAT_INNER[1]) / (FLAT_OUTER[1] - FLAT_INNER[1])
        oy = max(0.0, abs(c.y) - FLAT_INNER[2]) / (FLAT_OUTER[2] - FLAT_INNER[2])
        t = max(ox, oy)
        if t >= 1.0:
            continue
        w = 1.0 - t * t * (3.0 - 2.0 * t)
        c.z *= 1.0 - w
        flattened += 1
    print(f"  flattened {flattened} floor vertices under and around the car")

    # the scan never captured the top of the back wall cleanly (ragged scraps hang off it like stalactites):
    # cut that strip away, the shell's plain wall and ceiling close it
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    rag = [f for f in bm.faces if f.calc_center_median().x < RAGGED_X and f.calc_center_median().z > RAGGED_Z]
    bmesh.ops.delete(bm, geom=rag, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    print(f"  cut {len(rag)} ragged faces off the top of the back wall")

    # clean planes: snap the walls and slabs onto their planes, then dissolve every coplanar run of
    # triangles into ONE polygon (a wall, a floor, a slab underside = a few big flat faces)
    manhattan_snap(ob)
    centers, dense_rgb = face_data(ob)
    dis = ob.modifiers.new("planar", "DECIMATE")
    dis.decimate_type = "DISSOLVE"
    dis.angle_limit = math.radians(DISSOLVE_DEG)
    dis.delimit = set()
    bpy.ops.object.modifier_apply(modifier="planar")
    print(f"  planar dissolve: {len(ob.data.polygons)} polygons ({tri_count(ob)} triangles)")
    # each polygon takes the average color of the scan under it, then the polygons are triangulated
    flatten_colors(ob, resample_colors(ob, centers, dense_rgb))
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.triangulate(bm, faces=bm.faces, quad_method="BEAUTY", ngon_method="BEAUTY")
    bm.to_mesh(ob.data)
    bm.free()
    print(f"  triangulated: {tri_count(ob)} triangles")
    # scraps of scan floating free of the structure (a shard hanging in the air): delete the tiny islands
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    parent = {v.index: v.index for v in bm.verts}

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for e in bm.edges:
        parent[find(e.verts[0].index)] = find(e.verts[1].index)
    faces_in = {}
    for f in bm.faces:
        faces_in.setdefault(find(f.verts[0].index), []).append(f)
    scraps = [f for fs in faces_in.values() if len(fs) < MIN_ISLAND_TRIS for f in fs]
    bmesh.ops.delete(bm, geom=scraps, context="FACES")
    bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
    bm.to_mesh(ob.data)
    bm.free()
    print(f"  removed {len(scraps)} triangles of floating scraps ({len(faces_in)} pieces before)")

    ob.data.materials.clear()
    mat = bpy.data.materials.new("Garage")
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    col = nt.nodes.new("ShaderNodeVertexColor")
    col.layer_name = "Col"
    nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
    set_input(bsdf, "Roughness", 0.92)
    set_input(bsdf, "Metallic", 0.0)
    mat.use_backface_culling = False
    ob.data.materials.append(mat)
    for uvl in list(ob.data.uv_layers):
        ob.data.uv_layers.remove(uvl)
    on_wall = (centers[:, 0] < -2.15) & (centers[:, 2] > 0.5) & (centers[:, 2] < 2.3)
    on_ceiling = centers[:, 2] > 2.45
    wall_rgb = dense_rgb[on_wall].mean(0) if on_wall.any() else np.array([0.3, 0.3, 0.3])
    ceiling_rgb = dense_rgb[on_ceiling].mean(0) if on_ceiling.any() else np.array([0.2, 0.2, 0.2])
    print(f"  shell colors from the scan: wall {np.round(wall_rgb, 2).tolist()} ceiling {np.round(ceiling_rgb, 2).tolist()}")
    ob = join([ob, make_stall_lines(sc, mat), make_shell(sc, mat, wall_rgb, ceiling_rgb)], "Garage")      # (they join the garage mesh: one draw call)
    invalid = ob.data.validate(verbose=True, clean_customdata=False)
    print(f"  mesh validate: {'fixed problems' if invalid else 'clean'}")
    if ob.data.has_custom_normals:
        bpy.ops.mesh.customdata_custom_splitnormals_clear()
    ob.data.shade_flat()
    lo, hi = bounds([ob])
    print(f"  final tris {tri_count(ob)}  custom normals {ob.data.has_custom_normals}  x [{lo.x:.2f}, {hi.x:.2f}] y [{lo.y:.2f}, {hi.y:.2f}] z [{lo.z:.2f}, {hi.z:.2f}]")
    export(OUT_GARAGE, [ob])
    cleanup(sc)


# ------------------------------------------------------------------ the warehouse
def hall_to_game():
    """Hall frame (x = width 0..16, y = length 0..46, z up) -> game frame (X along the hall, the near wall at
    Y = WALL_Y with the room toward -Y, z up). A proper rotation (-90 deg about z), no mirroring."""
    return Matrix(((0, 1, 0, -HALL_Y0), (-1, 0, 0, WALL_Y), (0, 0, 1, 0), (0, 0, 0, 1)))


def flat_quad_grid(bm, col, x0, x1, y0, y1, tile, base, jitter, rng, z=0.0):
    """A floor of faceted tiles: each tile two triangles with their own slight brightness (low-poly concrete)."""
    nx, ny = max(int(round((x1 - x0) / tile)), 1), max(int(round((y1 - y0) / tile)), 1)
    for i in range(nx):
        for j in range(ny):
            xa, xb = x0 + (x1 - x0) * i / nx, x0 + (x1 - x0) * (i + 1) / nx
            ya, yb = y0 + (y1 - y0) * j / ny, y0 + (y1 - y0) * (j + 1) / ny
            v = [bm.verts.new((xa, ya, z)), bm.verts.new((xb, ya, z)), bm.verts.new((xb, yb, z)), bm.verts.new((xa, yb, z))]
            for tri in ((v[0], v[1], v[2]), (v[0], v[2], v[3])):
                g = base * (1.0 + jitter * float(rng.uniform(-1, 1)))
                for loop in bm.faces.new(tri).loops:
                    loop[col] = (g, g, g * 1.02, 1.0)


def grade_warehouse(rgb):
    """Photo colors -> muted flat paint. The source texture is electric blue, so only its LIGHT / DARK is kept
    (panels vs ribs vs roof), re-tinted a warm putty gray, posterized, linear."""
    rgb = np.asarray(rgb, dtype=np.float64)
    lum = rgb @ np.array([0.299, 0.587, 0.114])
    g = np.clip(lum ** 1.1 * WH_GAIN, 0.0, 1.0)
    out = np.stack([g * WH_TINT[0], g * WH_TINT[1], g * WH_TINT[2]], axis=1)
    out = np.round(np.clip(out, 0.0, 1.0) * 18) / 18
    return np.where(out <= 0.04045, out / 12.92, ((out + 0.055) / 1.055) ** 2.4)


def new_vertex_color_material(name, rough=0.95):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    col = nt.nodes.new("ShaderNodeVertexColor")
    col.layer_name = "Col"
    nt.links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
    set_input(bsdf, "Roughness", rough)
    set_input(bsdf, "Metallic", 0.0)
    mat.use_backface_culling = False
    return mat


def prep_warehouse():
    print("== warehouse")
    sc = fresh_scene("home_prep_warehouse")
    objs = import_glb(SRC_WAREHOUSE)
    bake_world(objs)
    meshes = [o for o in sc.objects if o.type == "MESH"]
    for o in meshes:
        print(f"  {o.name}: {tri_count(o)} tris, materials {[m.name for m in o.data.materials if m]}")
    structure = next(o for o in meshes if any(m and base_name(m.name) == "Metal" for m in o.data.materials))
    glow = next((o for o in meshes if any(m and base_name(m.name) == "Emissive" for m in o.data.materials)), None)
    for o in list(meshes):                             # the glossy 2-triangle floor goes: a faceted matte one replaces it
        if o is not structure and o is not glow:
            bpy.data.objects.remove(o, do_unlink=True)
    bake_corner_colors(structure)                      # the metal's texture -> corner colors (it is only sampled)

    m = hall_to_game()
    keep = [structure] + ([glow] if glow else [])
    for o in keep:
        o.data.transform(m)
        bpy.context.view_layer.objects.active = o
        bpy.ops.mesh.customdata_custom_splitnormals_clear()   # (the import's own normals would override flat shading)
        bm = bmesh.new()
        bm.from_mesh(o.data)
        out = [f for f in bm.faces if not (HALL_CROP[0] <= f.calc_center_median().x <= HALL_CROP[1])]
        bmesh.ops.delete(bm, geom=out, context="FACES")
        bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
        bm.to_mesh(o.data)
        bm.free()
        print(f"  {o.name}: cropped to {tri_count(o)} tris")

    # structure: one flat color per face from the texture, muted
    me = structure.data
    attr = me.color_attributes["Col"]
    n = len(me.loops)
    total = np.empty(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("loop_total", total)
    face_of_loop = np.repeat(np.arange(len(me.polygons)), total)
    cols = np.empty(n * 4, dtype=np.float32)
    attr.data.foreach_get("color", cols)
    sums = np.zeros((len(me.polygons), 3))
    np.add.at(sums, face_of_loop, cols.reshape(-1, 4)[:, :3])
    lin = grade_warehouse(sums / total[:, None])
    res = np.ones((len(me.polygons), 4), dtype=np.float32)
    res[:, :3] = lin
    attr.data.foreach_set("color", res[face_of_loop].ravel())
    me.polygons.foreach_set("use_smooth", np.zeros(len(me.polygons), dtype=bool))
    print(f"  structure colors (linear) median {np.round(np.median(lin, axis=0), 3).tolist()}  p10 {np.round(np.percentile(lin, 10), 3)}  p90 {np.round(np.percentile(lin, 90), 3)}")
    for uvl in list(me.uv_layers):
        me.uv_layers.remove(uvl)
    me.materials.clear()
    mat = new_vertex_color_material("Warehouse")
    me.materials.append(mat)

    # floor + the two end walls, as plain faceted planes in the same mesh
    rng = np.random.default_rng(1996)
    bm = bmesh.new()
    col = bm.loops.layers.float_color.new("Col")
    x0, x1 = HALL_CROP
    y_far = WALL_Y - 16.0
    flat_quad_grid(bm, col, x0, x1, y_far, WALL_Y, FLOOR_TILE, 0.075, 0.14, rng)
    for x, facing in ((x0, 1), (x1, -1)):              # end walls (a rectangle: the arch hides its top corners)
        q = [bm.verts.new((x, y_far, 0)), bm.verts.new((x, WALL_Y, 0)), bm.verts.new((x, WALL_Y, 5.2)), bm.verts.new((x, y_far, 5.2))]
        if facing < 0:
            q.reverse()
        for loop in bm.faces.new(q).loops:
            loop[col] = (0.085, 0.085, 0.09, 1.0)
    fme = bpy.data.meshes.new("FloorAndEnds")
    bm.to_mesh(fme)
    bm.free()
    fme.materials.append(mat)
    fob = bpy.data.objects.new("FloorAndEnds", fme)
    sc.collection.objects.link(fob)
    wh = join([structure, fob], "Warehouse")
    wh.data.shade_flat()
    wh.data.validate()

    outs = [wh]
    if glow:                                           # the clerestory strips: dim cool light, not floodlights
        gm = bpy.data.materials.new("WindowGlow")
        gm.use_nodes = True
        b = gm.node_tree.nodes.get("Principled BSDF")
        set_input(b, "Base Color", (0.02, 0.025, 0.03, 1.0))
        set_input(b, "Emission Color", (0.7, 0.82, 1.0, 1.0))
        set_input(b, "Emission Strength", 0.6)
        set_input(b, "Roughness", 1.0)
        glow.data.materials.clear()
        glow.data.materials.append(gm)
        glow.data.shade_flat()
        glow.name = "WindowGlow"
        outs.append(glow)
    lo, hi = bounds(outs)
    print(f"  final tris {sum(tri_count(o) for o in outs)}  x [{lo.x:.2f}, {hi.x:.2f}] y [{lo.y:.2f}, {hi.y:.2f}] z [{lo.z:.2f}, {hi.z:.2f}]")
    export(OUT_WAREHOUSE, outs)
    cleanup(sc)


# ------------------------------------------------------------------ the props
def flat_material(name, color, rough=0.85, emission=None, strength=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    b = mat.node_tree.nodes.get("Principled BSDF")
    set_input(b, "Base Color", color)
    set_input(b, "Roughness", rough)
    set_input(b, "Metallic", 0.0)
    if emission is not None:
        set_input(b, "Emission Color", emission)
        set_input(b, "Emission Strength", strength)
    mat.use_backface_culling = False
    return mat


def srgb_to_linear(c):
    return tuple((v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4) for v in c[:3]) + (1.0,)


def box_object(sc, name, size, loc, mat, rot_z=0.0, color_jitter=0.0, rng=None):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]; v.co.y *= size[1]; v.co.z *= size[2]
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    me.shade_flat()
    ob = bpy.data.objects.new(name, me)
    ob.location = loc
    ob.rotation_euler = (0, 0, rot_z)
    sc.collection.objects.link(ob)
    return ob


def prep_props():
    print("== props")
    sc = fresh_scene("home_prep_props")
    outs = []
    rng = np.random.default_rng(96)

    # --- ceiling fluorescent fixtures: the pack's ON fixture (housing + diffuser), textures dropped
    objs = import_glb(os.path.join(SRC_PROPS, "ceiling_lowpoly_fluorescent_lamps_with_diffuser.glb"))
    bake_world(objs)
    meshes = [o for o in sc.objects if o.type == "MESH"]
    for o in list(meshes):                              # the pack holds an OFF and an ON fixture side by side
        ys = [v.co.y for v in o.data.vertices]
        if sum(ys) / len(ys) < 0:
            bpy.data.objects.remove(o, do_unlink=True)
    meshes = [o for o in sc.objects if o.type == "MESH"]
    housing = next(o for o in meshes if base_name(o.data.materials[0].name) == "Metal")
    diffuser = next(o for o in meshes if base_name(o.data.materials[0].name).startswith("Fluorescent"))
    housing.data.materials.clear(); housing.data.materials.append(flat_material("FixtureMetal", srgb_to_linear((0.30, 0.31, 0.32)), 0.7))
    diffuser.data.materials.clear(); diffuser.data.materials.append(
        flat_material("TubeOn", srgb_to_linear((0.9, 0.95, 1.0)), 0.5, emission=(0.85, 0.93, 1.0, 1.0), strength=2.5))
    fx = join([housing, diffuser], "FluorescentFixture")
    for uvl in list(fx.data.uv_layers):
        fx.data.uv_layers.remove(uvl)
    fx.data.transform(Matrix.Translation((0, -0.5, 0)))                           # centered
    fx.data.transform(Matrix.Rotation(math.pi, 4, "X"))                           # the lit face points down
    fx.data.shade_flat()
    for k, (x, y, z) in enumerate(FIXTURES):
        c = fx.copy()
        c.data = fx.data
        c.name = f"Fixture_{k + 1}"
        c.location = (x, y, z)
        sc.collection.objects.link(c)
        outs.append(c)
    bpy.data.objects.remove(fx, do_unlink=True)

    # --- locker, against the wall (front toward the room)
    objs = import_glb(os.path.join(SRC_PROPS, "lowpoly_locker.glb"))
    bake_world(objs)
    lk = next(o for o in sc.objects if o.type == "MESH" and o.name not in {x.name for x in outs} and o.data.materials and base_name(o.data.materials[0].name) == "metal")
    bake_corner_colors(lk)
    me = lk.data
    attr = me.color_attributes["Col"]
    total = np.empty(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("loop_total", total)
    face_of_loop = np.repeat(np.arange(len(me.polygons)), total)
    cols = np.empty(len(me.loops) * 4, dtype=np.float32)
    attr.data.foreach_get("color", cols)
    sums = np.zeros((len(me.polygons), 3))
    np.add.at(sums, face_of_loop, cols.reshape(-1, 4)[:, :3])
    rgb = sums / total[:, None]
    print(f"  locker texture colors (display) mean {np.round(rgb.mean(0), 2).tolist()} p5 {np.round(np.percentile(rgb, 5, axis=0), 2).tolist()} p95 {np.round(np.percentile(rgb, 95, axis=0), 2).tolist()}")
    lum = rgb @ np.array([0.299, 0.587, 0.114])
    rgb = np.clip(lum[:, None] + (rgb - lum[:, None]) * LOCKER_CHROMA, 0, 1)
    rgb = np.round(np.clip(rgb ** 1.0 * LOCKER_GAIN, 0, 1) * 18) / 18
    lin = np.where(rgb <= 0.04045, rgb / 12.92, ((rgb + 0.055) / 1.055) ** 2.4)
    res = np.ones((len(me.polygons), 4), dtype=np.float32)
    res[:, :3] = lin
    attr.data.foreach_set("color", res[face_of_loop].ravel())
    bpy.context.view_layer.objects.active = lk
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    me.shade_flat()
    for uvl in list(me.uv_layers):
        me.uv_layers.remove(uvl)
    me.materials.clear()
    me.materials.append(new_vertex_color_material("PropPaint", 0.8))
    lk.name = "Locker"
    # origin: bottom-center of its footprint; the pack's front (+x) already faces +X, into the room, so it stands
    # on the END wall in the far corner: the one place along the walls the camera sees past the car
    lo, hi = bounds([lk])
    me.transform(Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)))
    lk.location = (HALL_CROP[0] + (hi.x - lo.x) / 2 + 0.03, WALL_Y - (hi.y - lo.y) / 2 - 0.05, 0.0)
    outs.append(lk)

    # --- light switch by the wall (one plate of the pair), scaled from the pack's units to centimetres
    objs = import_glb(os.path.join(SRC_PROPS, "simple_light_switch.glb"))
    bake_world(objs)
    sws = [o for o in sc.objects if o.type == "MESH" and o.name not in {x.name for x in outs} and o is not lk and o.data.materials and base_name(o.data.materials[0].name).startswith("defaultMat")]
    sw = sws[0]
    for extra in sws[1:]:
        bpy.data.objects.remove(extra, do_unlink=True)
    bake_corner_colors(sw)
    sme = sw.data
    sattr = sme.color_attributes["Col"]
    stotal = np.empty(len(sme.polygons), dtype=np.int32)
    sme.polygons.foreach_get("loop_total", stotal)
    sfol = np.repeat(np.arange(len(sme.polygons)), stotal)
    scols = np.empty(len(sme.loops) * 4, dtype=np.float32)
    sattr.data.foreach_get("color", scols)
    ssum = np.zeros((len(sme.polygons), 3))
    np.add.at(ssum, sfol, scols.reshape(-1, 4)[:, :3])
    print(f"  switch texture colors (display) mean {np.round((ssum / stotal[:, None]).mean(0), 2).tolist()}")
    bpy.context.view_layer.objects.active = sw
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    sw.data.materials.clear()
    sw.data.materials.append(flat_material("SwitchPlastic", srgb_to_linear((0.62, 0.6, 0.55)), 0.6))
    for uvl in list(sme.uv_layers):
        sme.uv_layers.remove(uvl)
    slo, shi = bounds([sw])
    sme.transform(Matrix.Translation((-(slo.x + shi.x) / 2, -(slo.y + shi.y) / 2, -(slo.z + shi.z) / 2)))
    sme.transform(Matrix.Scale(SWITCH_SCALE, 4))
    sme.transform(Matrix.Rotation(math.radians(90), 4, "Z"))
    sme.shade_flat()
    sw.name = "LightSwitch"
    sw.location = SWITCH_AT
    outs.append(sw)

    # --- placeholders (no models supplied): a few cardboard boxes and a bin, plain primitives
    card = flat_material("Cardboard", srgb_to_linear((0.50, 0.38, 0.25)), 0.95)
    for k, (size, loc, rz) in enumerate(BOXES):
        outs.append(box_object(sc, f"Box_{k + 1}", size, loc, card, rz))
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=8, radius1=0.2, radius2=0.23, depth=0.62)
    me = bpy.data.meshes.new("Trashcan")
    bm.to_mesh(me)
    bm.free()
    me.materials.append(flat_material("BinGrey", srgb_to_linear((0.20, 0.21, 0.22)), 0.8))
    me.shade_flat()
    tc = bpy.data.objects.new("Trashcan", me)
    tc.location = (TRASH_AT[0], TRASH_AT[1], 0.31)
    sc.collection.objects.link(tc)
    outs.append(tc)

    for o in outs:
        print(f"  {o.name:18} tris {tri_count(o):5} at {tuple(round(v, 2) for v in o.location)}")
    export(OUT_PROPS, outs)
    cleanup(sc)


if "car" in STAGES:
    prep_car()
if "garage" in STAGES:
    prep_garage()
if "warehouse" in STAGES:
    prep_warehouse()
if "props" in STAGES:
    prep_props()
print("DONE", STAGES)
