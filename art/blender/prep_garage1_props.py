"""CONTRABAND96 Garage 1 PSX props: the furniture / tools / storage pack, prepared for Godot.

Raw sources (never modified): art/models/warehouse props/*.glb  (Sketchfab downloads; see docs/ASSET_PROVENANCE.md)
Game-ready outputs:           godot/assets/models/props/garage1/*.glb   (used by godot/home/garage1_props.tscn)

Run (headless, repeatable; Blender MCP is not required):
    blender -b --factory-startup --python art/blender/prep_garage1_props.py [-- name name ...]
With no names every asset is rebuilt. Each output is built in a throw-away scene.

PROP FRAME (every output): Blender Z up, origin at the middle of the footprint on the floor (z = 0),
the object's FRONT faces Blender -Y = Godot +Z (so a prop standing against the warehouse's long side wall,
which is at game z = -2.6, needs no rotation: it faces the room and the camera). Long furniture runs along X.
Tools (origin mode "wall") are rotated to hang flat on a wall: origin at the bottom-centre of their BACK.

LOOK: base-colour textures only (the downloads' normal / ORM / emissive maps are dropped), downsized,
desaturated and dusted, nearest-neighbour filtering, roughness ~0.9, no metal, flat shading. Geometry is only
reduced where a model is far heavier than the rest of the pack (the jack).
"""
import math
import os
import sys

import bpy
import bmesh
import numpy as np
from mathutils import Matrix, Vector

REPO = r"C:\Users\sam11\Downloads\dev\deadtildawn"
SRC = os.path.join(REPO, "art", "models", "warehouse props")
OUT = os.path.join(REPO, "godot", "assets", "models", "props", "garage1")

DUST = (1.0, 0.97, 0.9)      # a faint warm cast over everything: dust on old plastic and paint

# name -> config. pick: source object names (substring match; None = every mesh). rotz/rotx in degrees, applied
# in that order (rotx first), then scale (uniform, metres per source unit), then the origin.
# grade: per source material name (or "*") -> size px, saturation, gain, tint.
ASSETS = {
    "desk_table": dict(src="psx_table.glb", scale=0.9, rotz=0,
                       grade={"*": dict(size=256, sat=0.7, gain=0.8, tint=DUST)}),
    "crt_monitor": dict(src="low_poly_retro_pc.glb", pick=["Object_6"], scale=0.20, rotz=-90,
                        grade={"*": dict(size=256, sat=0.5, gain=0.6, tint=(1.0, 0.94, 0.82))}),
    "pc_tower": dict(src="low_poly_retro_pc.glb", pick=["Object_4"], scale=0.225, rotz=-90,
                     grade={"*": dict(size=256, sat=0.5, gain=0.6, tint=(1.0, 0.94, 0.82))}),
    "pc_keyboard": dict(src="low_poly_retro_pc.glb", pick=["Object_10"], scale=0.297, rotz=-90,
                        grade={"*": dict(size=256, sat=0.5, gain=0.6, tint=(1.0, 0.94, 0.82))}),
    "pc_mouse": dict(src="low_poly_retro_pc.glb", pick=["Object_8"], scale=0.29, rotz=-90,
                     grade={"*": dict(size=256, sat=0.5, gain=0.6, tint=(1.0, 0.94, 0.82))}),
    "folding_chair": dict(src="metal_folding_chair.glb", scale=1.0, rotz=-90,
                          grade={"*": dict(size=256, sat=0.6, gain=0.8, tint=DUST)}),
    "radio_base": dict(src="psx_style_satellite_radio.glb", scale=0.3, rotz=-90,
                       grade={"*": dict(size=256, sat=0.8, gain=1.25, tint=DUST)}),
    "toolbox_steel": dict(src="jagged_toolbox__game_ready.glb", scale=0.55 / 240.7, rotz=90,
                          grade={"*": dict(size=256, sat=0.85, gain=1.35, tint=DUST)}),
    "floor_jack": dict(src="car_jack.glb", scale=1.0, rotz=0, decimate=2800,
                       grade={"*": dict(size=512, sat=0.72, gain=0.95, tint=DUST)}),
    "hand_tools_a": dict(src="tools_pack.glb", scale=0.183, rotx=90, rotz=0, origin="wall", decimate=900,
                         grade={"*": dict(size=256, sat=0.75, gain=1.1, tint=DUST)}),
    "hand_tools_b": dict(src="tools_pack_2.glb", scale=0.12, rotx=90, rotz=0, origin="wall", decimate=1700,
                         grade={"*": dict(size=256, sat=0.75, gain=1.1, tint=DUST)}),
    "metal_shelf": dict(src="low-poly_metal_shelf.glb", scale=1.0, rotz=-90,
                        grade={"*": dict(size=512, sat=0.8, gain=3.3, tint=(1.0, 0.97, 0.9))}),
    "loose_wrench": dict(src="tools_pack_2.glb", pick=["Cube_Def_0"], scale=0.12, rotz=0,   # one wrench from the pack, lying flat
                         grade={"*": dict(size=256, sat=0.75, gain=1.1, tint=DUST)}),
    "trashcan": dict(src="trashcan.glb", scale=1.0, rotz=0,
                     grade={"*": dict(size=128, sat=0.9, gain=1.25, tint=DUST)}),
    "broom": dict(src="broom_psx.glb", scale=1.0, rotz=0,
                  grade={"*": dict(size=256, sat=0.85, gain=1.15, tint=DUST)}),
    "shop_rag": dict(src="dirty_rag.glb", scale=0.075, rotz=0,
                     grade={"*": dict(size=256, sat=0.9, gain=1.5, tint=DUST)}),
}
# the cardboard set: 4 distinct box shapes (the pack's 11 boxes are 4 sizes), each straightened, scaled x BOX_SCALE
BOX_SRC = "set_of_cardboard_boxes.glb"
BOX_SCALE = 1.4        # the pack's 29 cm "moving boxes" read small beside a 4 m car
BOXES = {"box_small": "290x170x190_1", "box_cube": "290x290x290_1", "box_long": "290x290x400_1", "box_med": "430x210x270_1"}


# ------------------------------------------------------------------ helpers
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def import_glb(name):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, name))
    return [o for o in bpy.data.objects if o not in before]


def bake_world(objs):
    """Meshes keep their place, lose their parents; empties go."""
    for o in objs:
        if o.type != "MESH":
            continue
        mw = o.matrix_world.copy()
        o.data.transform(mw)
        if mw.determinant() < 0:
            o.data.flip_normals()
        o.parent = None
        o.matrix_world = Matrix.Identity(4)
    meshes = [o for o in objs if o.type == "MESH"]
    for o in objs:
        if o.type != "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    return meshes


def bounds(objs):
    lo = Vector((1e9,) * 3)
    hi = Vector((-1e9,) * 3)
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
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def tri_count(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)


def base_color_source(m):
    """(image, None) or (None, rgba): what feeds the material's Base Color."""
    if m is None or not m.use_nodes:
        return None, (0.5, 0.5, 0.5, 1.0)
    bsdf = next((n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if bsdf is None:
        return None, (0.5, 0.5, 0.5, 1.0)
    sock = bsdf.inputs["Base Color"]
    seen, todo = set(), [sock]
    while todo:                                   # walk upstream to the first image texture
        s = todo.pop()
        for link in s.links:
            n = link.from_node
            if n.type == "TEX_IMAGE" and n.image is not None:
                return n.image, None
            if n.name not in seen:
                seen.add(n.name)
                todo.extend(i for i in n.inputs if i.links)
    return None, tuple(sock.default_value)


def graded_image(src, name, size, sat, gain, tint):
    """A small, desaturated, dusted copy of the source image, packed (sRGB values graded as stored)."""
    tmp = src.copy()
    w, h = tmp.size
    s = min(1.0, size / max(w, h))
    tw, th = max(1, round(w * s)), max(1, round(h * s))
    if (tw, th) != (w, h):
        tmp.scale(tw, th)
    px = np.empty(tw * th * 4, dtype=np.float32)
    tmp.pixels.foreach_get(px)
    px = px.reshape(-1, 4)
    rgb = px[:, :3]
    lum = rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
    rgb = lum[:, None] + (rgb - lum[:, None]) * sat
    rgb = np.clip(rgb * np.array(tint, dtype=np.float32) * gain, 0.0, 1.0)
    px[:, :3] = rgb
    px[:, 3] = 1.0
    out = bpy.data.images.new(name, tw, th, alpha=False)
    out.pixels.foreach_set(px.ravel())
    out.pack()
    bpy.data.images.remove(tmp)
    return out


def grade_color(rgba, sat, gain, tint):
    rgb = np.array(rgba[:3], dtype=np.float32)
    lum = float(rgb @ np.array([0.299, 0.587, 0.114]))
    rgb = lum + (rgb - lum) * sat
    return tuple(np.clip(rgb * np.array(tint) * gain, 0, 1).tolist()) + (1.0,)


def make_material(name, image=None, color=(0.5, 0.5, 0.5, 1.0), rough=0.92):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = 0.0
    if image is not None:
        tex = nt.nodes.new("ShaderNodeTexImage")
        tex.image = image
        tex.interpolation = "Closest"             # PSX: crisp texels (exported as a NEAREST sampler)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    else:
        bsdf.inputs["Base Color"].default_value = color
    mat.use_backface_culling = False
    return mat


def regrade_materials(ob, grade, tag):
    """Every material slot -> a fresh Base-Color-only material with a graded, downsized image."""
    cache = {}
    for i, m in enumerate(list(ob.data.materials)):
        key = m.name if m else "none"
        if key not in cache:
            g = grade.get(m.name if m else "", grade["*"])
            img, color = base_color_source(m)
            nm = f"{tag}_{key}".replace(" ", "_")
            if img is not None:
                cache[key] = make_material(nm, graded_image(img, nm, g["size"], g["sat"], g["gain"], g["tint"]))
            else:
                cache[key] = make_material(nm, color=grade_color(color, g["sat"], g["gain"], g["tint"]))
        ob.data.materials[i] = cache[key]


def decimate(ob, target):
    n = tri_count(ob)
    if n <= target:
        return
    bpy.context.view_layer.objects.active = ob
    mod = ob.modifiers.new("dec", "DECIMATE")
    mod.ratio = target / n
    bpy.ops.object.modifier_apply(modifier=mod.name)


def place(ob, scale, rotx, rotz, origin):
    me = ob.data
    me.transform(Matrix.Rotation(math.radians(rotx), 4, "X"))
    me.transform(Matrix.Rotation(math.radians(rotz), 4, "Z"))
    me.transform(Matrix.Scale(scale, 4))
    lo, hi = bounds([ob])
    if origin == "wall":      # back plane (y max) on y = 0, bottom-centre in x
        me.transform(Matrix.Translation((-(lo.x + hi.x) / 2, -hi.y, -lo.z)))
    else:                     # footprint centre, floor at z = 0
        me.transform(Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -lo.z)))


def export(path, ob):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=False, export_cameras=False, export_lights=False,
                              export_image_format="AUTO")


def report(name, ob, path):
    lo, hi = bounds([ob])
    d = hi - lo
    print(f"  {name:14} tris {tri_count(ob):5}  mats {len(ob.data.materials)}  size X {d.x:.3f} Y {d.y:.3f} Z {d.z:.3f} m  "
          f"-> {os.path.getsize(path) / 1024:.0f} KB")


# ------------------------------------------------------------------ builders
def build(name, cfg):
    reset()
    objs = bake_world(import_glb(cfg["src"]))
    if cfg.get("pick"):
        keep = [o for o in objs if any(p == o.name for p in cfg["pick"])]
        for o in objs:
            if o not in keep:
                bpy.data.objects.remove(o, do_unlink=True)
        objs = keep
    ob = join(objs, name)
    for uvl in list(ob.data.uv_layers)[1:]:       # (the tool packs carry 3 UV sets; the first is the texture's)
        ob.data.uv_layers.remove(uvl)
    if cfg.get("decimate"):
        decimate(ob, cfg["decimate"])
    bpy.context.view_layer.objects.active = ob
    bpy.ops.mesh.customdata_custom_splitnormals_clear()
    regrade_materials(ob, cfg["grade"], name)
    place(ob, cfg["scale"], cfg.get("rotx", 0), cfg.get("rotz", 0), cfg.get("origin", "bottom"))
    ob.data.shade_flat()
    ob.data.validate()
    path = os.path.join(OUT, name + ".glb")
    export(path, ob)
    report(name, ob, path)


def cardboard_texture():
    """A 32 px cardboard swatch (the pack's own is printed with a 'MoveOn' logo, not a 1996 look)."""
    rng = np.random.default_rng(96)
    n = 32
    base = np.array([0.42, 0.33, 0.23])
    px = np.ones((n, n, 4), dtype=np.float32)
    noise = rng.normal(0, 0.03, (n, n, 1))
    streak = np.sin(np.arange(n) * 0.9)[None, :, None] * 0.015
    px[:, :, :3] = np.clip(base * (1.0 + noise + streak), 0, 1)
    img = bpy.data.images.new("cardboard", n, n, alpha=False)
    img.pixels.foreach_set(px.ravel())
    img.pack()
    return img


def box_uvs(ob, per_m=2.0):
    """Planar UVs per face along its dominant axis (the pack's UVs belong to its printed atlas)."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    uv = bm.loops.layers.uv.verify()
    for f in bm.faces:
        a = max(range(3), key=lambda i: abs(f.normal[i]))
        i, j = [k for k in range(3) if k != a]
        for loop in f.loops:
            loop[uv].uv = (loop.vert.co[i] * per_m, loop.vert.co[j] * per_m)
    bm.to_mesh(ob.data)
    bm.free()


def build_boxes():
    for out_name, key in BOXES.items():
        reset()
        objs = bake_world(import_glb(BOX_SRC))
        ob = next(o for o in objs if o.name.startswith(key))
        for o in objs:
            if o is not ob:
                bpy.data.objects.remove(o, do_unlink=True)
        ob.name = out_name
        ob.data.name = out_name
        me = ob.data
        xy = np.array([(v.co.x, v.co.y) for v in me.vertices])      # straighten: the yaw with the smallest footprint
        best = min(range(90), key=lambda d: np.ptp(xy @ _rot(d), axis=0).prod())
        me.transform(Matrix.Rotation(math.radians(-best), 4, "Z"))      # (_rot rotates by -deg)
        for uvl in list(me.uv_layers):
            me.uv_layers.remove(uvl)
        me.materials.clear()
        me.materials.append(make_material("Cardboard", cardboard_texture(), rough=0.95))
        box_uvs(ob)
        place(ob, BOX_SCALE, 0, 0, "bottom")
        me.shade_flat()
        path = os.path.join(OUT, out_name + ".glb")
        export(path, ob)
        report(out_name, ob, path)


def build_hanging_light():
    """A 4 ft hanging shop light: flat dark housing, emissive tubes (no real light: the lighting rig is untouched).
    Origin = the top of the rods centred over the fixture, so a node's y is the height it hangs from."""
    reset()
    objs = bake_world(import_glb("low_poly_hanging_light.glb"))
    tubes = [o for o in objs if o.name.startswith(("Cylinder.004", "Cylinder.005", "Cylinder.006"))]
    planes = [o for o in objs if o.name.startswith("Plane")]
    objs = [o for o in objs if o not in planes]
    for o in planes:
        bpy.data.objects.remove(o, do_unlink=True)          # the 2-triangle underside would hide the tubes from below
    housing = [o for o in objs if o not in tubes]
    for o in housing:
        o.data.materials.clear()
        o.data.materials.append(make_material("HangingLight_Housing", color=(0.045, 0.047, 0.05, 1.0), rough=0.8))
    on = make_material("HangingLight_Tube", color=(0.8, 0.88, 1.0, 1.0), rough=0.5)
    b = on.node_tree.nodes["Principled BSDF"]
    b.inputs["Emission Color"].default_value = (0.8, 0.9, 1.0, 1.0)
    b.inputs["Emission Strength"].default_value = 2.5
    for o in tubes:
        o.data.materials.clear()
        o.data.materials.append(on)
    ob = join(objs, "hanging_light")
    for uvl in list(ob.data.uv_layers):
        ob.data.uv_layers.remove(uvl)
    me = ob.data
    me.transform(Matrix.Scale(0.1, 4))
    lo, hi = bounds([ob])
    me.transform(Matrix.Translation((-(lo.x + hi.x) / 2, -(lo.y + hi.y) / 2, -hi.z)))
    me.shade_flat()
    path = os.path.join(OUT, "hanging_light.glb")
    export(path, ob)
    report("hanging_light", ob, path)


def _rot(deg):
    a = math.radians(deg)
    return np.array([[math.cos(a), math.sin(a)], [-math.sin(a), math.cos(a)]]).T


def main():
    names = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    print("== Garage 1 props ->", OUT)
    for name, cfg in ASSETS.items():
        if not names or name in names:
            build(name, cfg)
    if not names or any(n.startswith("box_") for n in names):
        build_boxes()
    if not names or "hanging_light" in names:
        build_hanging_light()
    print("DONE")


main()
