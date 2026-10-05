"""The home screen's parking garage, LOW POLY (Spire: low-poly kanjo
everything): Spire's scanned underground garage (art/models/parking_garage.glb,
~680k triangles, a photo texture) turned into ~TARGET flat-shaded facets,
each one solid color, exported to godot/models/garage.glb.

    blender -b --factory-startup --python art/blender/prep_garage.py

How:
1. Bake the photo into the mesh: every face corner takes the texture's color
   at its UV (a "color attribute", like vertex paint). Done on the dense scan,
   so the colors are right before anything is simplified.
2. Decimate (collapse) down to TARGET triangles. The colors ride along with
   the vertices; the photo texture isn't needed any more, so its seams can't
   tear (the problem the textured version had).
3. One color per face: the average of its corners, a little quantized
   (POSTERIZE levels per channel) so the facets read as flat paint, and flat
   shading (no smoothing between faces).
4. Floor to height 0 (the scan's floor sat at -0.5 m), one material
   "LowPoly" that shows the face colors.

Stall used for Faba's car (this file's Blender frame): the right wing's
stalls run along +X to the back wall at x ~ 9.3, lines at y = -2.5 / -5.0 /
-7.5; the car backs into the one centered at y = -3.75.
"""
import os

import bpy
import numpy as np
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(REPO, "art", "models", "parking_garage.glb")
OUT = os.path.join(REPO, "godot", "models", "garage.glb")
TARGET = 40000           # triangles in the end
POSTERIZE = 24           # color levels per channel (flat paint, not a photo)
FLOOR_Z = -0.5


def image_of(material):
    for n in material.node_tree.nodes:
        if n.type == "TEX_IMAGE" and n.image is not None:
            return n.image
    return None


def bake_corner_colors(o):
    """Each face corner's color = the texture at its UV."""
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


def flatten_colors(o):
    """One color per face: its corners' average, posterized."""
    me = o.data
    attr = me.color_attributes["Col"]
    n = len(me.loops)
    cols = np.empty(n * 4, dtype=np.float32)
    attr.data.foreach_get("color", cols)
    cols = cols.reshape(-1, 4)
    start = np.empty(len(me.polygons), dtype=np.int32)
    total = np.empty(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("loop_start", start)
    me.polygons.foreach_get("loop_total", total)
    face_of_loop = np.repeat(np.arange(len(me.polygons)), total)
    sums = np.zeros((len(me.polygons), 4), dtype=np.float64)
    np.add.at(sums, face_of_loop, cols)
    face = sums / total[:, None]
    face[:, :3] = np.round(face[:, :3] * POSTERIZE) / POSTERIZE
    face[:, 3] = 1.0
    attr.data.foreach_set("color", face[face_of_loop].astype(np.float32).ravel())
    me.polygons.foreach_set("use_smooth", np.zeros(len(me.polygons), dtype=bool))


def lowpoly_material():
    m = bpy.data.materials.new("LowPoly")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    attr = nt.nodes.new("ShaderNodeVertexColor")
    attr.layer_name = "Col"
    nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    return m


for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
for o in meshes:                                   # bake transforms, then one mesh
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
for o in [o for o in bpy.data.objects if o.type != "MESH"]:
    bpy.data.objects.remove(o)
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in meshes:
    bake_corner_colors(o)
bpy.ops.object.join()
ob = bpy.context.view_layer.objects.active
tris0 = sum(len(p.vertices) - 2 for p in ob.data.polygons)
mod = ob.modifiers.new("lod", "DECIMATE")
mod.ratio = TARGET / tris0
bpy.ops.object.modifier_apply(modifier="lod")
ob.data.transform(Matrix.Translation((0, 0, -FLOOR_Z)))
flatten_colors(ob)
ob.data.materials.clear()
ob.data.materials.append(lowpoly_material())
for uvl in list(ob.data.uv_layers):
    ob.data.uv_layers.remove(uvl)
ob.name = "Garage"
tris1 = sum(len(p.vertices) - 2 for p in ob.data.polygons)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True)
print(f"GARAGE {tris0} -> {tris1} triangles (low poly), {os.path.getsize(OUT) / 1e6:.1f} MB -> {OUT}")
