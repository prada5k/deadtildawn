"""The home screen's parking garage: Spire's scanned underground garage
(art/models/parking_garage.glb, ~680k triangles) cut down for a phone and
exported to godot/models/garage.glb.

    blender -b --factory-startup --python art/blender/prep_garage.py

- Decimates every piece to RATIO of its triangles. A photo scan's texture is
  cut into many small islands; collapsing an edge across an island's border
  smears the photo into black cracks. So every UV border is first marked a
  SEAM and its edges are locked (a vertex group the decimator must keep), and
  only the inside of each island gets simplified.
- Moves it so the floor is at height 0 (the scan's floor sat at -0.5 m).
- JPEG textures (photographic: plenty, and far smaller).

Stall used for Faba's car (in this file's Blender frame): the right wing's
stalls run along +X to the back wall at x ~ 9.3, lines at y = -2.5 / -5.0 /
-7.5; the car backs into the one centered at y = -3.75.
"""
import os

import bmesh
import bpy
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(REPO, "art", "models", "parking_garage.glb")
OUT = os.path.join(REPO, "godot", "models", "garage.glb")
RATIO = 0.3
FLOOR_Z = -0.5


def lock_uv_borders(o):
    """A vertex group of every vertex on a UV island border (weight 1), and
    the rest at 0: the decimator keeps the group's vertices where they are."""
    bm = bmesh.new()
    bm.from_mesh(o.data)
    uv = bm.loops.layers.uv.active
    border = set()
    for e in bm.edges:
        if len(e.link_faces) != 2:
            border.update(v.index for v in e.verts)
            continue
        f1, f2 = e.link_faces
        for v in e.verts:
            a = next(l for l in f1.loops if l.vert == v)[uv].uv
            b = next(l for l in f2.loops if l.vert == v)[uv].uv
            if (a - b).length > 1e-5:                  # the two faces disagree: a seam in the photo
                border.update(x.index for x in e.verts)
                break
    bm.free()
    g = o.vertex_groups.new(name="keep")
    g.add(list(border), 1.0, "REPLACE")
    return len(border)


for o in list(bpy.data.objects):
    bpy.data.objects.remove(o)
bpy.ops.import_scene.gltf(filepath=SRC)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
tris0 = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
for o in meshes:
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
    bpy.context.view_layer.objects.active = o
    lock_uv_borders(o)
    mod = o.modifiers.new("lod", "DECIMATE")
    mod.ratio = RATIO
    mod.vertex_group = "keep"
    mod.invert_vertex_group = True                   # weight 1 = keep
    mod.vertex_group_factor = 1000.0
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.ops.object.modifier_apply(modifier="lod")
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    o.data.transform(Matrix.Translation((0, 0, -FLOOR_Z)))
    o.vertex_groups.clear()
for o in [o for o in bpy.data.objects if o.type != "MESH"]:
    bpy.data.objects.remove(o)
tris1 = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True,
                          export_image_format="JPEG", export_jpeg_quality=85)
print(f"GARAGE {tris0} -> {tris1} triangles, {os.path.getsize(OUT) / 1e6:.1f} MB -> {OUT}")
