"""Builds Faba's '96 Civic DX coupe (EJ6) shell in Blender and exports it to
godot/models/dx.glb (docs/MODELS.md).

Run it in Blender (open art/blender/dx.blend, Scripting tab > Open > Run
Script), or let Claude send it through the Blender MCP add-on. It wipes the
scene and rebuilds from these numbers, so change the numbers here, not the
mesh, and run it again.

How it's built (a loft, like a boat hull or a wing in CAD):
  - the body is a stack of cross-sections ("stations") along the car's length;
    each station's size comes from curves read off the side and top views:
    the bottom line yb(x), the beltline / hood / trunk line yt(x), and the half
    width w(x). Between the table points the curves are smooth (a monotone
    cubic spline, the same idea as a spline in CAD: no kinks, no overshoot).
  - each cross-section is a rounded box: a tucked-in rocker, the widest point
    a bit below the middle, the EJ's side crease, a round shoulder, a crowned
    top. Neighboring stations are joined with quads.
  - the greenhouse (cabin) is a second loft on top, from the windshield base
    to the trunk, its roof line yr(x), leaning in as it rises (tumblehome).
  - the wheel arches are cut with a boolean (cylinders): black wheel wells.
  - each face gets a material by where it is and which way it faces:
    Paint, Glass, Hood, Roof, Fender (the game colors these: the primer
    fender, the sun-faded hood and roof, a respray, the carbon hood, tint).
  - seams and moldings are thin ribbons laid ON the surface (they follow the
    curve instead of floating like boxes would).

Frame: car X forward = Blender +X; the car's right = Blender -Y; up = +Z.
The glTF exporter turns that into Godot's +X forward, +Z right, +Y up.
Origin on the ground at x = 0 of the game's frame (front axle +1.275,
rear -1.345), matching dx_model.gd.
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector


def find_repo():
    """The repo: set by whoever sends the script (DTD_REPO), else two folders up
    from this script or from the open dx.blend (both live in art/blender/)."""
    tries = [globals().get("DTD_REPO")]
    for base in (globals().get("__file__"), bpy.data.filepath):
        if base:
            tries.append(os.path.join(os.path.dirname(os.path.abspath(base)), "..", ".."))
    for t in tries:
        if t and os.path.exists(os.path.join(t, "godot", "project.godot")):
            return os.path.abspath(t)
    raise RuntimeError("Can't find the repo: open art/blender/dx.blend first, then run this script")


REPO = find_repo()
OUT_GLB = os.path.join(REPO, "godot", "models", "dx.glb")
OUT_BLEND = os.path.join(REPO, "art", "blender", "dx.blend")

FRONT_AXLE, REAR_AXLE = 1.275, -1.345
NOSE, TAIL = 2.225, -2.225
ARCH_R, ARCH_Z = 0.37, 0.28           # wheel arch radius and center height (tire r 0.297)
ARCH_FROM = 0.50                      # the wells go this far in from the side (|y|)

# The body curves, (x, value), rear to front (x ascending), meters.
# The tail is an upright panel (the lights sit on it) with a lip on the trunk's edge.
YB = [(TAIL, 0.36), (-2.20, 0.30), (-2.15, 0.28), (-2.0, 0.27), (2.0, 0.27),
      (2.15, 0.27), (2.20, 0.29), (NOSE, 0.33)]
# Measured off Spire's side photo (art/refs/perfectside.jpg: px -> m by the axles, the roof
# scaled to 1.335 m, the crown taken off): a wedge, a long hood dropping to a low nose.
YT = [(TAIL, 0.885), (-2.20, 0.935), (-2.16, 0.945), (-2.05, 0.945), (-1.80, 0.95),
      (-1.22, 0.925), (0.0, 0.895), (0.86, 0.85), (1.23, 0.78), (1.78, 0.68), (2.0, 0.61),
      (2.12, 0.565), (2.20, 0.515), (NOSE, 0.47)]
W = [(TAIL, 0.74), (-2.20, 0.80), (-2.15, 0.83), (-2.0, 0.845), (-1.6, 0.85),
     (1.4, 0.85), (1.85, 0.84), (2.05, 0.81), (2.15, 0.76), (2.20, 0.70), (NOSE, 0.60)]
# The roof line, center of the roof: rear glass, roof, the raked windshield
YR = [(-1.80, 0.985), (-1.74, 1.03), (-1.40, 1.17), (-1.06, 1.285), (-0.80, 1.325),
      (-0.55, 1.337), (-0.25, 1.322), (0.0, 1.278), (0.42, 1.08), (0.86, 0.872)]   # (the photo)
WINDSHIELD_X = 0.0                    # the windshield's top edge
REAR_GLASS = (-1.74, -1.08)           # the rear window, from x to x
SIDE_GLASS = (-1.22, 0.70)            # door + quarter glass, from x to x
B_PILLAR = (-0.56, -0.49)
CREASE = 0.64                         # the side crease, as a share of the body's height at that station

COLORS = {   # what the materials look like in Blender (the game overrides most)
    "Paint": (0.93, 0.93, 0.91, 1), "Hood": (0.93, 0.93, 0.91, 1), "Roof": (0.93, 0.93, 0.91, 1),
    "Fender": (0.93, 0.93, 0.91, 1), "Glass": (0.05, 0.06, 0.08, 0.6), "Trim": (0.06, 0.06, 0.065, 1),
    "Headlight": (0.72, 0.78, 0.84, 1), "Taillight": (0.6, 0.05, 0.05, 1), "Reverse": (0.80, 0.81, 0.83, 1),
    "Amber": (1.0, 0.55, 0.1, 1), "Plate": (0.85, 0.85, 0.82, 1), "Seam": (0.03, 0.03, 0.035, 1),
}


# ---------------------------------------------------------------- curves

def spline(table, x):
    """Monotone cubic (Fritsch-Carlson / PCHIP) through the table's points:
    smooth like a spline, but never overshoots between points (no bumps you
    didn't ask for)."""
    xs = [p[0] for p in table]
    ys = [p[1] for p in table]
    if x <= xs[0]:
        return ys[0]
    if x >= xs[-1]:
        return ys[-1]
    n = len(xs)
    h = [xs[k + 1] - xs[k] for k in range(n - 1)]
    d = [(ys[k + 1] - ys[k]) / h[k] for k in range(n - 1)]
    m = [d[0]] + [0.0] * (n - 2) + [d[-1]]
    for k in range(1, n - 1):
        if d[k - 1] * d[k] > 0:
            w1, w2 = 2 * h[k] + h[k - 1], h[k] + 2 * h[k - 1]
            m[k] = (w1 + w2) / (w1 / d[k - 1] + w2 / d[k])
    k = max(i for i in range(n - 1) if xs[i] <= x)
    t = (x - xs[k]) / h[k]
    h00, h10 = 2 * t ** 3 - 3 * t ** 2 + 1, t ** 3 - 2 * t ** 2 + t
    h01, h11 = -2 * t ** 3 + 3 * t ** 2, t ** 3 - t ** 2
    return h00 * ys[k] + h10 * h[k] * m[k] + h01 * ys[k + 1] + h11 * h[k] * m[k + 1]


def stations(x0, x1, step, extra=()):
    xs = set(round(x0 + i * step, 4) for i in range(int(round((x1 - x0) / step)) + 1))
    xs.update(e for e in extra)
    return sorted(x for x in xs if x0 <= x <= x1)


def to_blender(x, lat, h):
    """Car frame (x forward, lat = right side positive, h up) -> Blender."""
    return Vector((x, -lat, h))


# ---------------------------------------------------------------- materials

def material(name):
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.diffuse_color = COLORS[name]
    m.use_nodes = True
    bsdf = m.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = COLORS[name]
        bsdf.inputs["Roughness"].default_value = 0.08 if name == "Glass" else (0.6 if name in ("Trim", "Seam") else 0.35)
        if name == "Glass":
            bsdf.inputs["Alpha"].default_value = 0.6
            m.surface_render_method = "BLENDED"
    return m


# ---------------------------------------------------------------- the body

def body_half(x):
    """The right half of the body's cross-section at x, (lateral, height) from
    the rocker up to the crown: a rounded box with a crease."""
    yb, yt, w = spline(YB, x), spline(YT, x), spline(W, x)
    h = yt - yb
    rb = min(0.10, 0.25 * h)                   # the rocker's tuck-under radius
    rt = min(0.16, 0.30 * h)                   # the shoulder radius
    w_low, w_top = 0.975 * w, 0.975 * w
    pts = []
    for a in (-90, -60, -30, 0):               # the rocker, curving under
        r = math.radians(a)
        pts.append((w_low - rb + rb * math.cos(r), yb + rb + rb * math.sin(r)))
    pts.append((w, yb + 0.45 * h))             # the widest point
    hc = yb + CREASE * h                       # the crease: a little step in, catches the light
    pts += [(0.997 * w, hc - 0.004), (0.989 * w, hc + 0.004)]
    for a in (0, 22.5, 45, 67.5, 90):          # the shoulder, rolling over to the top
        r = math.radians(a)
        pts.append((w_top - rt + rt * math.cos(r), yt - rt + rt * math.sin(r)))
    pts.append((0.5 * (w_top - rt), yt + 0.025))   # the crown
    return pts, yb, yt


def body_ring(x):
    half, yb, yt = body_half(x)
    ring = [(0.0, yb)] + half + [(0.0, yt + 0.035)] + [(-l, hh) for l, hh in reversed(half)]
    return [to_blender(x, l, hh) for l, hh in ring]


def surface_lat(x, h):
    """How far out the body's side is at x, height h (for laying trim on it)."""
    half, _, _ = body_half(x)
    for (l0, h0), (l1, h1) in zip(half, half[1:]):
        if h0 <= h <= h1 and h1 > h0:
            return l0 + (l1 - l0) * (h - h0) / (h1 - h0)
    return half[-1][0] if h > half[-1][1] else half[0][0]


# ---------------------------------------------------------------- the greenhouse

def cabin_edge(x):
    """Where the side glass meets the roof rail: (lateral, height), and the base."""
    yt, w, yr = spline(YT, x), spline(W, x), spline(YR, x)
    base_l, base_h = 0.87 * w, yt - 0.01
    edge_h = max(yr - 0.05, base_h + 0.004)                # the roof edge sits a bit below the crown
    side_l = base_l - 0.30 * (edge_h - base_h)             # tumblehome: leans in as it rises
    return side_l, edge_h, base_l, base_h


def cabin_ring(x):
    yr = spline(YR, x)
    side_l, edge_h, base_l, base_h = cabin_edge(x)
    lift = max(yr - edge_h, 0.006)
    half = [(base_l, base_h), (side_l, edge_h),           # the side glass
            (side_l - 0.012, edge_h + 0.45 * lift),        # the rail, rounding over
            (side_l - 0.04, edge_h + 0.80 * lift),
            (0.62 * side_l, edge_h + 0.96 * lift),         # the roof's crown
            (0.30 * side_l, edge_h + 0.995 * lift)]
    ring = [(0.0, base_h - 0.02)] + half + [(0.0, edge_h + lift)] + [(-l, hh) for l, hh in reversed(half)]
    return [to_blender(x, l, hh) for l, hh in ring]


# ---------------------------------------------------------------- mesh helpers

def loft(bm, rings):
    """Join rings (same vertex count, closed loops) into quads; cap the two ends."""
    vrings = [[bm.verts.new(p) for p in ring] for ring in rings]
    for a, b in zip(vrings, vrings[1:]):
        n = len(a)
        for i in range(n):
            j = (i + 1) % n
            bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(vrings[0])))
    bm.faces.new(vrings[-1])


def new_object(name, bm, mats, fix_normals=True):
    # Every face must point OUT: Godot draws only a face's front side (Blender shows both)
    if fix_normals:
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for m in mats:
        ob.data.materials.append(bpy.data.materials[m])
    return ob


def classify(ob, rule):
    names = [m.name for m in ob.data.materials]
    for f in ob.data.polygons:
        c, n = f.center, f.normal
        f.material_index = names.index(rule(c.x, -c.y, c.z, n.x, -n.y, n.z, names[f.material_index]))


def body_material(x, lat, h, nx, nlat, nh, current):
    if current == "Trim":                         # the wheel wells (from the boolean)
        return current
    if nh > 0.6 and 0.86 < x < 2.15 and abs(lat) < 0.8 * spline(W, x):
        return "Hood"
    if lat > 0.3 and nlat > 0.4 and 0.74 < x < 1.84 and h > 0.30:
        return "Fender"                          # front right fender, the primer one on Faba's car
    return "Paint"


def cabin_material(x, lat, h, nx, nlat, nh, current):
    side_l, edge_h, _, _ = cabin_edge(x)
    if h < edge_h - 0.004 and abs(lat) > side_l - 0.004:   # the side band: door glass + quarter glass
        if B_PILLAR[0] < x < B_PILLAR[1]:
            return "Trim"                         # the black B pillar
        return "Glass" if SIDE_GLASS[0] < x < SIDE_GLASS[1] else "Roof"
    if abs(lat) > side_l - 0.04:
        return "Roof"                             # the pillars / roof rails
    if x > WINDSHIELD_X or REAR_GLASS[0] < x < REAR_GLASS[1]:
        return "Glass"                            # windshield, rear glass
    return "Roof"


def apply_modifiers(ob):
    dg = bpy.context.evaluated_depsgraph_get()
    me = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    ob.modifiers.clear()
    old = ob.data
    ob.data = me
    bpy.data.meshes.remove(old)


def smooth_by_angle(ob, degrees=40):
    """Smooth shading, but keep edges sharper than `degrees` (the crease, the
    arches, the glass edges) and every edge where the material changes."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    for f in bm.faces:
        f.smooth = True
    for e in bm.edges:
        if len(e.link_faces) == 2:
            a, b = e.link_faces
            e.smooth = a.normal.angle(b.normal, 0) < math.radians(degrees) and a.material_index == b.material_index
        else:
            e.smooth = False
    bm.to_mesh(ob.data)
    bm.free()


def add_box(bm, center, size, rot_z=0.0, rot_y=0.0):
    """A box in car frame: center (x, lat, h), size (dx, dlat, dh). Returns its faces."""
    ret = bmesh.ops.create_cube(bm, size=1.0)
    verts = ret["verts"]
    m = (Matrix.Translation(to_blender(*center)) @ Matrix.Rotation(rot_z, 4, "Z")
         @ Matrix.Rotation(rot_y, 4, "Y") @ Matrix.Diagonal((size[0], size[1], size[2], 1.0)))
    bmesh.ops.transform(bm, matrix=m, verts=verts)
    return list({f for v in verts for f in v.link_faces})


def face_out(bm, verts, outward):
    f = bm.faces.new(verts)
    f.normal_update()
    if f.normal.dot(outward) < 0:
        f.normal_flip()
    return f


def ribbon_along(bm, x0, x1, h, tall, side, out=0.003, wrap_end=None):
    """A strip lying on the body's side at height h from x0 to x1 (side +1 =
    right, -1 = left). wrap_end = NOSE or TAIL also runs it across that end."""
    xs = stations(x0, x1, 0.04, extra=(x0, x1))
    pairs = []
    for x in xs:
        lat = surface_lat(x, h) + out
        pairs.append((bm.verts.new(to_blender(x, side * lat, h - tall / 2)),
                      bm.verts.new(to_blender(x, side * lat, h + tall / 2))))
    sideways = Vector((0, -side, 0))
    faces = [face_out(bm, (a[0], b[0], b[1], a[1]), sideways) for a, b in zip(pairs, pairs[1:])]
    if wrap_end is not None:                       # across the nose / tail panel, just proud of it
        xe = wrap_end + math.copysign(out, wrap_end)
        lat = surface_lat(wrap_end, h)
        a = (bm.verts.new(to_blender(xe, lat, h - tall / 2)), bm.verts.new(to_blender(xe, lat, h + tall / 2)))
        b = (bm.verts.new(to_blender(xe, -lat, h - tall / 2)), bm.verts.new(to_blender(xe, -lat, h + tall / 2)))
        faces.append(face_out(bm, (a[0], b[0], b[1], a[1]), Vector((math.copysign(1, wrap_end), 0, 0))))
    return faces


def ribbon_up(bm, x, h0, h1, wide, side, out=0.003):
    """A vertical strip on the body's side at x from h0 to h1 (a door seam)."""
    hs = [h0 + (h1 - h0) * i / 10 for i in range(11)]
    pairs = []
    for h in hs:
        lat = side * (surface_lat(x, h) + out)
        pairs.append((bm.verts.new(to_blender(x - wide / 2, lat, h)), bm.verts.new(to_blender(x + wide / 2, lat, h))))
    sideways = Vector((0, -side, 0))
    return [face_out(bm, (a[0], a[1], b[1], b[0]), sideways) for a, b in zip(pairs, pairs[1:])]


# ---------------------------------------------------------------- the front (Spire's photos)
# Things on the nose are laid ON its surface: for a point (lateral l, height h),
# find how far forward the body reaches there (x_front) and put it just proud.

HEAD_L = (0.31, 0.72)           # the headlights from their inner edge (by the grille) out round the corner
GRILLE_L = 0.27                 # the grille's half width
BUMPER_H = 0.53                 # the bumper's top seam, just under the lights


def head_lo(l):                 # the headlight's bottom edge: low by the grille, rising as it wraps
    t = min(max((abs(l) - HEAD_L[0]) / (HEAD_L[1] - HEAD_L[0]), 0.0), 1.0)
    return 0.545 + 0.055 * t ** 1.4


def head_hi(l):                 # its top edge: under the hood line
    return hood_line(l) - 0.006


def hood_line(l):               # the hood's front edge: a shallow dip in the middle
    t = min(abs(l) / HEAD_L[1], 1.0)
    return 0.65 + 0.012 * t


def inside(x, l, h):
    half, yb, yt = body_half(x)
    return yb <= h <= top_h(x, l) and abs(l) <= surface_lat(x, h)


def x_front(l, h):
    lo, hi = 1.2, NOSE + 0.001
    for _ in range(26):
        mid = (lo + hi) / 2
        if inside(mid, l, h):
            lo = mid
        else:
            hi = mid
    return lo


def front_point(l, h, off):
    """The nose's surface at (l, h), `off` out along its normal: (Blender point, Blender normal)."""
    e = 0.004
    x = x_front(l, h)
    dxdl = (x_front(l + e, h) - x_front(l - e, h)) / (2 * e)
    dxdh = (x_front(l, h + e) - x_front(l, h - e)) / (2 * e)
    n = Vector((1.0, -dxdl, -dxdh)).normalized()                 # (x, l, h)
    p = Vector((x, l, h)) + n * off
    return to_blender(p.x, p.y, p.z), Vector((n.x, -n.y, n.z))


def front_patch(bm, l0, l1, h_lo, h_hi, off, nl=14, nh=3):
    """A patch on the nose from lateral l0 to l1, between heights h_lo(l) and h_hi(l)."""
    grid = []
    for i in range(nl + 1):
        l = l0 + (l1 - l0) * i / nl
        lo, hi = h_lo(l), h_hi(l)
        grid.append([front_point(l, lo + (hi - lo) * j / nh, off) for j in range(nh + 1)])
    verts = [[bm.verts.new(p) for p, _ in col] for col in grid]
    faces = []
    for i in range(nl):
        for j in range(nh):
            out = grid[i][j][1]
            faces.append(face_out(bm, (verts[i][j], verts[i + 1][j], verts[i + 1][j + 1], verts[i][j + 1]), out))
    return faces


LAMP_IN = 0.235                 # the taillights' inboard edge (lateral)
LAMP_WRAP = 0.11                # how far they wrap forward round the corner (m along x)


def lamp_patch(bm, side, h0, h1, off, grow=0.0, rows=4):
    """A taillight lens lying on the tail: across the flat tail panel from
    LAMP_IN out to its edge, then round the corner along the side, between
    heights h0 and h1, `off` proud of the paint. grow: a bigger copy (the bezel)."""
    def path(h):
        edge = surface_lat(TAIL, h) - 0.004
        pts = []
        l_in = LAMP_IN - grow
        for i in range(7):                                     # the flat panel: facing straight back
            pts.append((TAIL - off, l_in + (edge - l_in) * i / 6, Vector((-1, 0))))
        xs = [TAIL + 0.004 + (LAMP_WRAP + grow) * (i / 6) ** 1.3 for i in range(7)]
        for x in xs:                                           # round the corner and along the side
            lat = surface_lat(x, h)
            slope = (surface_lat(x + 0.003, h) - surface_lat(x - 0.003, h)) / 0.006
            n = Vector((-slope, 1)).normalized()               # outward from the outline
            pts.append((x + n.x * off, lat + n.y * off, n))
        return pts
    hs = [h0 - grow + (h1 - h0 + 2 * grow) * i / rows for i in range(rows + 1)]
    grid = []
    for h in hs:
        grid.append([(bm.verts.new(to_blender(x, side * lat, h)), n) for x, lat, n in path(h)])
    faces = []
    for a, b in zip(grid, grid[1:]):
        for k in range(len(a) - 1):
            n = a[k][1]
            out = Vector((n.x, -side * n.y, 0))                 # car frame -> Blender (right = -Y)
            faces.append(face_out(bm, (a[k][0], a[k + 1][0], b[k + 1][0], b[k][0]), out))
    return faces


# ---------------------------------------------------------------- build

def build():
    for ob in list(bpy.data.objects):
        bpy.data.objects.remove(ob)
    for name in COLORS:
        material(name)

    # ---- body: the loft, then the wheel arches
    bm = bmesh.new()
    ends = [TAIL + d for d in (0, 0.005, 0.015, 0.03, 0.05, 0.075)] + [NOSE - d for d in (0, 0.005, 0.015, 0.03, 0.05, 0.075)]
    loft(bm, [body_ring(x) for x in stations(TAIL, NOSE, 0.05, extra=ends)])
    body = new_object("Body", bm, ["Paint", "Trim", "Hood", "Fender"])
    for ax in (FRONT_AXLE, REAR_AXLE):
        for side in (-1, 1):
            depth = 1.0
            bpy.ops.mesh.primitive_cylinder_add(vertices=48, radius=ARCH_R, depth=depth,
                                                location=to_blender(ax, side * (ARCH_FROM + depth / 2), ARCH_Z),
                                                rotation=(math.pi / 2, 0, 0))
            cutter = bpy.context.active_object
            cutter.data.materials.append(bpy.data.materials["Trim"])
            mod = body.modifiers.new("arch", "BOOLEAN")
            mod.operation = "DIFFERENCE"
            mod.solver = "EXACT"
            mod.material_mode = "TRANSFER"
            mod.object = cutter
            apply_modifiers(body)
            bpy.data.objects.remove(cutter)
    classify(body, body_material)

    # ---- greenhouse
    bm = bmesh.new()
    edges = (WINDSHIELD_X, *REAR_GLASS, *SIDE_GLASS, *B_PILLAR)     # stations where the glass starts / stops
    loft(bm, [cabin_ring(x) for x in stations(YR[0][0], YR[-1][0], 0.04, extra=edges)])
    cabin = new_object("Greenhouse", bm, ["Roof", "Glass", "Trim"])
    classify(cabin, cabin_material)

    # ---- details: lights, seams, moldings, grille, plates, mirrors, wipers
    names = ["Paint", "Trim", "Headlight", "Taillight", "Reverse", "Amber", "Plate", "Seam"]
    bm = bmesh.new()
    parts = []                                   # (faces, material)
    tail_h = 0.74                                # the taillights' center height on the tail panel
    for s in (-1, 1):
        parts += [
            # headlights (Spire's front photos): almonds tucked under the hood's edge, tall by
            # the grille, narrowing as they wrap round the corner; a black bezel behind
            (front_patch(bm, s * HEAD_L[0], s * HEAD_L[1], head_lo, head_hi, 0.006), "Headlight"),
            (front_patch(bm, s * (HEAD_L[0] - 0.018), s * (HEAD_L[1] + 0.012),
                         lambda l: head_lo(l) - 0.016, lambda l: head_hi(l) + 0.010, 0.003), "Trim"),
            # the reflector bowl inside, by the grille: the "eye"
            (front_patch(bm, s * 0.35, s * 0.50, lambda l: 0.568, lambda l: 0.626, 0.0075, nl=6, nh=2), "Seam"),
            # taillights (Spire): two colors stacked, red over white (the reverse light), lenses
            # that follow the tail panel and wrap round the corner, in a black bezel
            (lamp_patch(bm, s, tail_h, tail_h + 0.075, 0.006), "Taillight"),
            (lamp_patch(bm, s, tail_h - 0.07, tail_h, 0.006), "Reverse"),
            (lamp_patch(bm, s, tail_h - 0.085, tail_h + 0.09, 0.003, grow=0.014), "Trim"),
            (add_box(bm, (2.03, s * (surface_lat(2.03, 0.58) + 0.002), 0.58), (0.09, 0.01, 0.04)), "Amber"),
            (add_box(bm, (-2.05, s * (surface_lat(-2.05, 0.66) + 0.002), 0.66), (0.08, 0.01, 0.035)), "Taillight"),
            (ribbon_along(bm, -0.95, 0.88, 0.50, 0.045, s, out=0.010), "Trim"),          # the side molding
            (ribbon_along(bm, 1.60, 2.0, BUMPER_H, 0.007, s), "Seam"),                     # front bumper line: the side...
            (ribbon_along(bm, TAIL, -1.58, 0.60, 0.007, s, wrap_end=TAIL if s > 0 else None), "Seam"),  # rear bumper line
            (ribbon_up(bm, 0.74, 0.33, spline(YT, 0.74) - 0.02, 0.007, s), "Seam"),       # door: front edge
            (ribbon_up(bm, -0.55, 0.33, spline(YT, -0.55) - 0.02, 0.007, s), "Seam"),     # door: rear edge
            (add_box(bm, (-0.32, s * (surface_lat(-0.32, 0.73) + 0.004), 0.73), (0.11, 0.012, 0.016)), "Trim"),  # handle
            (add_box(bm, (0.56, s * 0.79, 0.89), (0.10, 0.10, 0.05)), "Trim"),           # mirror base
            (add_box(bm, (0.54, s * 0.90, 0.935), (0.13, 0.12, 0.09)), "Paint"),          # mirror
            (add_box(bm, (0.90, s * 0.22, 0.87), (0.025, 0.44, 0.012), rot_z=s * 0.05), "Trim"),   # wipers
        ]
    parts += [
        # ...and across the front, under the lights
        (front_patch(bm, -surface_lat(2.0, BUMPER_H) + 0.01, surface_lat(2.0, BUMPER_H) - 0.01,
                     lambda l: BUMPER_H - 0.0035, lambda l: BUMPER_H + 0.0035, 0.003, nh=1), "Seam"),
        # the grille: a wide, low black opening between the lights
        (front_patch(bm, -GRILLE_L, GRILLE_L, lambda l: 0.548, lambda l: 0.638 - 0.02 * (l / GRILLE_L) ** 2, 0.004), "Trim"),
        # the hood's shut line across the top of the lights and the grille
        (front_patch(bm, -HEAD_L[1], HEAD_L[1], lambda l: hood_line(l) - 0.003, lambda l: hood_line(l) + 0.003,
                     0.004, nh=1), "Seam"),
        # the bumper: a long thin intake low down, the plate above it
        (front_patch(bm, -0.56, 0.56, lambda l: 0.355, lambda l: 0.392, 0.004), "Trim"),
        (front_patch(bm, -0.15, 0.15, lambda l: 0.415, lambda l: 0.51, 0.009, nl=2, nh=1), "Plate"),
        (add_box(bm, (TAIL - 0.008, 0.0, 0.52), (0.012, 0.30, 0.15)), "Plate"),
        (add_box(bm, (TAIL - 0.003, 0.0, tail_h), (0.010, 0.44, 0.05)), "Trim"),                 # garnish between the lights
    ]
    for faces, m in parts:
        for f in faces:
            f.material_index = names.index(m)
    details = new_object("Details", bm, names, fix_normals=False)

    for ob in (body, cabin, details):
        smooth_by_angle(ob)
    return [body, cabin, details]


# ---------------------------------------------------------------- body shop looks
# Each is its own .glb in godot/models/looks/<item id>.glb, in the car's frame,
# built ON this body's surface (dx_model.gd uses it instead of its code-built
# box). Materials: Paint (the car's color), Contrast (the stripe color), Trim.

def top_h(x, l):
    """The height of the body's top (hood / trunk) at x, lateral l."""
    half, _, yt = body_half(x)
    top = half[-6:] + [(0.0, yt + 0.035)]          # shoulder -> crown -> center: lateral shrinking
    for (l0, h0), (l1, h1) in zip(top, top[1:]):
        if l1 <= abs(l) <= l0:
            return h0 + (h1 - h0) * (l0 - abs(l)) / (l0 - l1)
    return top[-1][1]


def roof_h(x, l):
    """The height of the cabin's roof at x, lateral l."""
    ring = cabin_ring(x)
    pts = sorted({(abs(v.y), v.z) for v in ring if v.z >= spline(YR, x) - 0.06}, reverse=True)
    for (l0, h0), (l1, h1) in zip(pts, pts[1:]):
        if l1 <= abs(l) <= l0:
            return h0 + (h1 - h0) * (l0 - abs(l)) / (l0 - l1)
    return pts[-1][1]


def band_on_top(bm, x0, x1, l_center, width, height_at, lift=0.004):
    """A flat band (a stripe) lying on a top surface from x0 to x1."""
    xs = stations(x0, x1, 0.04, extra=(x0, x1))
    ls = [l_center - width / 2, l_center, l_center + width / 2]
    rows = [[bm.verts.new(to_blender(x, l, height_at(x, l) + lift)) for l in ls] for x in xs]
    faces = []
    for a, b in zip(rows, rows[1:]):
        for k in range(len(ls) - 1):
            faces.append(face_out(bm, (a[k], a[k + 1], b[k + 1], b[k]), Vector((0, 0, 1))))
    return faces


def look_object(name, mats, fill):
    bm = bmesh.new()
    fill(bm)
    ob = new_object(name, bm, mats, fix_normals=False)
    smooth_by_angle(ob)
    return ob


def build_looks():
    for name in ("Contrast",):
        COLORS.setdefault(name, (0.06, 0.06, 0.07, 1))
        material(name)
    looks = {}

    def side_stripe(bm):
        for s in (-1, 1):
            ribbon_along(bm, TAIL + 0.08, 1.55, 0.70, 0.05, s, out=0.004)
    looks["stripes_side"] = look_object("stripes_side", ["Contrast"], side_stripe)

    def twin_stripes(bm):
        for lc in (-0.13, 0.13):
            band_on_top(bm, 0.90, NOSE - 0.06, lc, 0.16, top_h)                    # hood
            band_on_top(bm, REAR_GLASS[1] + 0.02, WINDSHIELD_X - 0.02, lc, 0.16, roof_h)   # roof
            band_on_top(bm, TAIL + 0.02, REAR_GLASS[0] - 0.08, lc, 0.16, top_h)    # trunk
    looks["stripes_twin"] = look_object("stripes_twin", ["Contrast"], twin_stripes)

    def ducktail(bm):
        # A wedge along the trunk's back edge, kicking up and back
        ls = [i / 10 * 0.72 for i in range(-10, 11)]
        rows = []
        for l in ls:
            edge = 1.0 - (abs(l) / (0.72 * 1.02)) ** 6                  # rounds off at the corners
            rows.append([bm.verts.new(to_blender(x, l, h)) for x, h in (
                (-1.98, top_h(-1.98, l) - 0.004),
                (-2.19, top_h(-2.19, l) + 0.06 * edge),
                (-2.215, top_h(-2.215, l) + 0.045 * edge),
                (-2.215, top_h(-2.215, l) - 0.01))])
        for a, b in zip(rows, rows[1:]):
            for k in range(3):
                face_out(bm, (a[k], b[k], b[k + 1], a[k + 1]), Vector((-0.5, 0, 1)) if k < 2 else Vector((-1, 0, 0)))
        face_out(bm, rows[0], Vector((0, 1, 0)))
        face_out(bm, rows[-1], Vector((0, -1, 0)))
    looks["wing_duck"] = look_object("wing_duck", ["Paint"], ducktail)

    def front_lip(bm):
        # A thin black splitter under the bumper, following the nose's curve in plan view
        ls = [i / 12 * 0.80 for i in range(-12, 13)]
        rows = []
        for l in ls:
            front = NOSE + 0.035 - 0.30 * (abs(l) / 0.80) ** 3
            back = 1.92
            rows.append([bm.verts.new(to_blender(x, l, h)) for x, h in (
                (back, 0.27), (front, 0.255), (front, 0.235), (back, 0.25))])
        for a, b in zip(rows, rows[1:]):
            for k in range(4):
                j = (k + 1) % 4
                face_out(bm, (a[k], b[k], b[j], a[j]), Vector((0, 0, 1 if k == 0 else -1)) if k in (0, 2)
                         else Vector((1 if k == 1 else -1, 0, 0)))
        face_out(bm, rows[0], Vector((0, 1, 0)))
        face_out(bm, rows[-1], Vector((0, -1, 0)))
    looks["lip"] = look_object("lip", ["Trim"], front_lip)

    def pedestal_wing(bm):
        # Spire's picture (art/looks/wing_gt.png): a body-colored pedestal wing. Two
        # pedestals flared at the foot, a gently arched blade between their tops.
        ped_l, ped_x = 0.60, -1.98                  # where the pedestals stand (lateral, x of the middle)
        rise = 0.15                                 # how high the blade sits over the trunk
        for s in (-1, 1):
            l = s * ped_l
            base = top_h(ped_x, l)
            # Sections up the pedestal: (height over the trunk, length along x, width across)
            secs = [(-0.01, 0.30, 0.10), (0.012, 0.26, 0.075), (0.05, 0.20, 0.055), (rise, 0.15, 0.048)]
            rings = []
            for dh, ln, wd in secs:
                h = base + dh
                rings.append([bm.verts.new(to_blender(ped_x + dx, l + dl, h)) for dx, dl in (
                    (-ln / 2, -wd / 2), (ln / 2, -wd / 2), (ln / 2, wd / 2), (-ln / 2, wd / 2))])
            for a, b in zip(rings, rings[1:]):
                for k in range(4):
                    j = (k + 1) % 4
                    face_out(bm, (a[k], a[j], b[j], b[k]), (sum((v.co for v in a[k:k + 1] + a[j:j + 1]), Vector())
                                                            / 2 - to_blender(ped_x, l, a[0].co.z)).normalized())
            face_out(bm, rings[-1], Vector((0, 0, 1)))
            face_out(bm, rings[0], Vector((0, 0, -1)))
        # The blade: an airfoil, chord 0.21 m, arched up 2 cm in the middle, overlapping the pedestal tops
        top = top_h(ped_x, ped_l) + rise
        foil = [(0.105, 0.0), (0.06, 0.012), (0.0, 0.018), (-0.07, 0.012), (-0.105, 0.002),
                (-0.07, -0.004), (0.0, -0.006), (0.06, -0.004)]                     # (x along the chord, up)
        span = [i / 16 * (ped_l + 0.03) for i in range(-16, 17)]
        rings = []
        for l in span:
            arch = 0.02 * (1 - (l / (ped_l + 0.03)) ** 2)
            tilt = 0.08                                                            # trailing edge up a touch
            rings.append([bm.verts.new(to_blender(ped_x + cx, l, top + arch + cz - cx * tilt)) for cx, cz in foil])
        for a, b in zip(rings, rings[1:]):
            for k in range(len(foil)):
                j = (k + 1) % len(foil)
                up = Vector((0, 0, 1)) if k < 4 else Vector((0, 0, -1))
                face_out(bm, (a[k], b[k], b[j], a[j]), up)
        face_out(bm, rings[0], Vector((0, 1, 0)))
        face_out(bm, rings[-1], Vector((0, -1, 0)))
    looks["wing_gt"] = look_object("wing_gt", ["Paint"], pedestal_wing)
    return looks


def export_one(ob, path):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True)


def export(objs):
    os.makedirs(os.path.dirname(OUT_GLB), exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    for ob in objs:
        ob.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.export_scene.gltf(filepath=OUT_GLB, export_format="GLB", use_selection=True,
                              export_yup=True, export_apply=True)
    bpy.ops.wm.save_as_mainfile(filepath=OUT_BLEND, copy=True)


objs = build()
looks = build_looks()
for _ob in looks.values():
    _ob.hide_set(True)                 # in the .blend but out of the way (unhide to look at one)
export(objs)
os.makedirs(os.path.join(REPO, "godot", "models", "looks"), exist_ok=True)
for _id, _ob in looks.items():
    _ob.hide_set(False)
    export_one(_ob, os.path.join(REPO, "godot", "models", "looks", _id + ".glb"))
    _ob.hide_set(True)
tris = sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in objs)
print("built", [o.name for o in objs], "triangles:", tris, "->", OUT_GLB, "| looks:", list(looks))
