extends Node3D
## Faba's '96 Civic DX coupe (EJ6), built in code: a real side profile
## extruded to width (CSGPolygon3D), greenhouse, wheels, lights. The same
## model goes on the home overlook, the lift, the turnout and the replay.
##
## Day one it's mechanically stock and cosmetically rough (docs/ART_DIRECTION.md):
## Frost White with sun-faded roof and hood, a primer front fender, steelies,
## and one missing hubcap. build(ids) shows what's on it (Spire: "make the
## cars look better as we upgrade parts"):
##   PARTS (part ids): springs / coilovers drop it (coilovers with camber);
##   lightweight 7-spoke silvers or forged bronze mesh wheels; R-compound
##   sidewall letters; a header's bigger exhaust tip (the race header's
##   canister); buckets in place of the stock seats, no rear seat once the
##   interior's stripped (seen through the glass); the carbon hood.
##   LOOKS ("look:<id>", bodyshop.gd): a respray (fixes the primer and the
##   fade), banner, stripes, stickers, tint, lip, wing, rim color.
##
## A real model: put a glTF at MODEL_PATH (docs/MODELS.md) and it replaces the
## code-built shell; wheels, interior and the add-ons stay code-built on it.
##
## Axes: +x = forward, +y = up, +z = the car's right side (the side the
## cameras look at). Units: meters. Origin: on the ground, center of the car.

const BodyShop := preload("res://bodyshop.gd")
const Voice := preload("res://voice.gd")
const MODEL_PATH := "res://models/dx.glb"
const SHELL_INFO := "res://models/dx.json"  # a fitted model's nose, tail, taillights (art/blender/prep_cars.py)
const LOOK_DIR :="res://models/looks/"      # <body shop item id>.glb replaces its code-built version (in the car's frame)
const WHEEL_DIR := "res://models/wheels/"    # wheels_stock / wheels_light / wheels_forged .glb: a whole right-side wheel

const LENGTH := 4.45
const WIDTH := 1.70
const WHEELBASE := 2.62
const FRONT_AXLE := 1.275            # x; front overhang 0.95 m
const REAR_AXLE := FRONT_AXLE - WHEELBASE
const TRACK := 1.47
const TIRE_R := 0.297                # 185/65R14
const TIRE_W := 0.185
const EXHAUST_AT := Vector3(-2.2, 0.26, 0.42)   # the tip, rear right under the bumper

const FROST_WHITE := Color(0.93, 0.93, 0.91)
const FADED := Color(0.84, 0.82, 0.76)       # chalky, sun-killed clearcoat
const PRIMER := Color(0.47, 0.47, 0.45)
const GLASS := Color(0.05, 0.06, 0.08)
const TRIM := Color(0.06, 0.06, 0.065)
const TIRE := Color(0.04, 0.04, 0.045)
const STEELIE := Color(0.22, 0.22, 0.23)
const HUBCAP := Color(0.72, 0.73, 0.75)
const CARBON := Color(0.07, 0.07, 0.08)
const BRONZE := Color(0.55, 0.4, 0.2)
const SILVER := Color(0.78, 0.79, 0.81)
const CHROME := Color(0.9, 0.91, 0.93)
const P1_WHITE := Color(0.94, 0.94, 0.91)
const CLOTH := Color(0.2, 0.2, 0.22)         # stock seats
const BUCKET := Color(0.08, 0.08, 0.09)
const BUCKET_TRIM := Color(0.62, 0.08, 0.08)
const AMBER := Color(1.0, 0.55, 0.1)
const STICKERS := [Color(0.95, 0.85, 0.15), Color(0.9, 0.2, 0.2), Color(0.95, 0.95, 0.95)]

# Side profile (x, y) of the body below the beltline, with wheel arches
const BODY_PROFILE := [
	Vector2(-2.18, 0.30), Vector2(-2.225, 0.42), Vector2(-2.21, 0.64), Vector2(-2.08, 0.85),
	Vector2(-1.55, 0.90), Vector2(0.55, 0.89), Vector2(1.95, 0.76), Vector2(2.19, 0.64),
	Vector2(2.225, 0.44), Vector2(2.15, 0.28),
	Vector2(1.70, 0.26), Vector2(1.62, 0.42), Vector2(1.45, 0.56), Vector2(1.275, 0.61),
	Vector2(1.10, 0.56), Vector2(0.93, 0.42), Vector2(0.85, 0.26),
	Vector2(-0.92, 0.26), Vector2(-1.00, 0.42), Vector2(-1.17, 0.56), Vector2(-1.345, 0.61),
	Vector2(-1.52, 0.56), Vector2(-1.69, 0.42), Vector2(-1.77, 0.28),
]
const GREENHOUSE := [
	Vector2(0.62, 0.87), Vector2(-0.08, 1.32), Vector2(-0.80, 1.34), Vector2(-1.50, 0.93),
	Vector2(-1.56, 0.87),
]
const FENDER := [                            # front right fender (the primer one)
	Vector2(0.62, 0.885), Vector2(1.84, 0.77), Vector2(1.84, 0.40), Vector2(1.62, 0.42),
	Vector2(1.45, 0.56), Vector2(1.275, 0.61), Vector2(1.10, 0.56), Vector2(0.93, 0.42),
	Vector2(0.62, 0.40),
]

var parts: Array = []        # what build() was given: part ids + "look:<id>" entries
var lights_on := true        # headlights/taillights glowing (off on the lift)
var rough := true            # Faba's DX: faded clearcoat, primer fender, missing hubcap
var paint_color := FROST_WHITE   # a clean car (rough = false) in another paint: opponents
var target: Node3D           # where extrude() and box() put things
var looks := {}              # slot -> body shop item (from the "look:" entries)


## Where the car's shell ends (Spire's EG6 from art/models/, fitted to the DX's
## axles): {front, rear, width, height, tails: [[x, y, z]...], ...}. Empty for the
## script-built EJ shell (its numbers are the constants above).
static func shell_info() -> Dictionary:
	if not FileAccess.file_exists(SHELL_INFO) or not ResourceLoader.exists(MODEL_PATH):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(SHELL_INFO))
	return d if d is Dictionary else {}


## The nose and tail (x) and the taillights, whichever shell is on.
static func front_x() -> float:
	return float(shell_info().get("front", LENGTH / 2.0))


static func rear_x() -> float:
	return float(shell_info().get("rear", -LENGTH / 2.0))


static func taillights() -> Array:
	var out := []
	for t in shell_info().get("tails", []):          # their height and side; at the very back (the brake glow)
		out.append(Vector3(rear_x() - 0.01, t[1], t[2]))
	return out if not out.is_empty() else [Vector3(-2.235, 0.74, -0.55), Vector3(-2.235, 0.74, 0.55)]


func mat(color: Color, rough := 0.5, metal := 0.0, emit := Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emit != Color.BLACK:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = 2.0
	return m


## A 2D profile extruded across z, centered on z = center (depth along z).
func extrude(points: Array, depth: float, center: float, material: Material) -> CSGPolygon3D:
	var c := CSGPolygon3D.new()
	c.polygon = PackedVector2Array(points)
	c.depth = depth
	c.position.z = center + depth / 2.0        # CSGPolygon3D extrudes toward -z
	c.material = material
	target.add_child(c)
	return c


func box(size: Vector3, pos: Vector3, material: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.rotation = rot
	m.material_override = material
	target.add_child(m)
	return m


func cyl(r: float, h: float, pos: Vector3, material: Material, rot := Vector3.ZERO, parent: Node3D = null) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	m.mesh = c
	m.position = pos
	m.rotation = rot
	m.material_override = material
	(parent if parent != null else target).add_child(m)
	return m


func has_part(prefix: String) -> bool:
	for p in parts:
		if str(p).begins_with(prefix):
			return true
	return false


func look(slot: String) -> Dictionary:
	return looks.get(slot, {})


func build(installed: Array = []) -> void:
	parts = installed
	looks = {}
	for p in installed:
		var s := str(p)
		if s.begins_with("look:") and BodyShop.ITEMS.has(s.substr(5)):
			var item: Dictionary = BodyShop.ITEMS[s.substr(5)]
			looks[item["slot"]] = item.merged({"id": s.substr(5)})
	for c in get_children():
		c.queue_free()
	# Stance: lowering springs 35 mm, coilovers 60 mm (and a touch of camber)
	var drop := 0.06 if has_part("coilovers") else (0.035 if has_part("springs") else 0.0)
	var body := Node3D.new()
	body.position.y = -drop
	add_child(body)
	target = body

	var resprayed := not look("paint").is_empty()
	var worn := rough and not resprayed               # the primer and the fade, until a respray
	var color: Color = look("paint").get("color", paint_color)
	var paint := mat(color, 0.3 if resprayed else 0.35, 0.05 if resprayed else 0.0)
	var faded := mat(FADED, 0.95) if worn else paint
	var glass := mat(GLASS, 0.08, 0.4)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color.a = 0.93 if not look("tint").is_empty() else 0.62   # see the seats (unless tinted)

	var hood_mat := mat(CARBON, 0.3, 0.2) if has_part("hood") else faded
	if ResourceLoader.exists(MODEL_PATH):
		build_shell_model(paint, faded, hood_mat, mat(PRIMER, 1.0) if worn else paint, glass)
	else:
		extrude(BODY_PROFILE, WIDTH, 0.0, paint)
		extrude(GREENHOUSE, WIDTH * 0.84, 0.0, glass)
		# Roof and hood: sun-faded clearcoat (or a carbon hood once you buy one)
		box(Vector3(0.70, 0.02, WIDTH * 0.78), Vector3(-0.44, 1.335, 0), faded)
		var hood_angle := atan2(0.89 - 0.77, 1.90 - 0.62)
		box(Vector3(1.30, 0.02, WIDTH * 0.86), Vector3(1.26, 0.84, 0), hood_mat, Vector3(0, 0, -hood_angle))
		if worn:                                      # primer fender on the right side
			extrude(FENDER, 0.006, WIDTH / 2.0 + 0.004, mat(PRIMER, 1.0))
		build_details(paint)
	build_interior()
	build_exhaust()
	build_looks(color)
	build_wheels(drop)


## The trim that makes it read as a real car: door seams, the window line,
## side markers, rub strips, mirrors, lights, grille, plates.
func build_details(paint: Material) -> void:
	var seam := mat(Color(0.02, 0.02, 0.025), 0.9)
	for side: float in [-1.0, 1.0]:
		var z := side * (WIDTH / 2.0 + 0.004)
		box(Vector3(0.012, 0.6, 0.008), Vector3(0.6, 0.6, z), seam)              # door, front edge
		box(Vector3(0.012, 0.55, 0.008), Vector3(-0.62, 0.62, z), seam)          # door, rear edge
		box(Vector3(0.1, 0.012, 0.008), Vector3(-0.42, 0.78, z), seam)           # door handle
		box(Vector3(2.2, 0.02, 0.01), Vector3(-0.45, 0.885, z), mat(TRIM, 0.6))  # the window line
		box(Vector3(3.2, 0.06, 0.02), Vector3(-0.1, 0.52, side * (WIDTH / 2.0 + 0.01)), mat(TRIM, 0.6))
		box(Vector3(0.14, 0.09, 0.12), Vector3(0.45, 0.98, side * (WIDTH / 2.0 + 0.04)), paint)
		box(Vector3(0.08, 0.04, 0.01), Vector3(2.05, 0.6, z), mat(AMBER, 0.3, 0.0,
			AMBER * 0.6 if lights_on else Color.BLACK))                          # side marker
	for side: float in [-1.0, 1.0]:
		box(Vector3(0.06, 0.12, 0.42), Vector3(2.19, 0.64, side * 0.56),
			mat(Color(1, 0.96, 0.85), 0.2, 0.0, Color(1.0, 0.92, 0.72) if lights_on else Color.BLACK))
		box(Vector3(0.05, 0.14, 0.40), Vector3(-2.21, 0.74, side * 0.55),
			mat(Color(0.6, 0.05, 0.05), 0.3, 0.0, Color(0.9, 0.05, 0.03) if lights_on else Color.BLACK))
	box(Vector3(0.04, 0.06, 0.6), Vector3(2.215, 0.55, 0), mat(TRIM))             # grille slot
	box(Vector3(0.03, 0.12, 0.30), Vector3(-2.22, 0.52, 0), mat(Color(0.85, 0.85, 0.82), 0.6))   # plates
	box(Vector3(0.03, 0.1, 0.28), Vector3(2.23, 0.4, 0), mat(Color(0.85, 0.85, 0.82), 0.6))


## A real model (docs/MODELS.md, art/blender/build_dx.py): the game swaps its
## materials by name (Paint, Roof, Hood, Fender, Glass, lights); the rest is
## as modeled.
func build_shell_model(paint: Material, faded: Material, hood: Material, fender: Material, glass: Material) -> void:
	var shell: Node3D = (load(MODEL_PATH) as PackedScene).instantiate()
	target.add_child(shell)
	swap_materials(shell, {
		"Paint": paint, "Roof": faded, "Hood": hood, "Fender": fender, "Glass": glass,
		"Headlight": mat(Color(0.72, 0.78, 0.84), 0.15, 0.2, Color(1.0, 0.92, 0.72) if lights_on else Color.BLACK),   # glassy blue-gray lens
		"Taillight": mat(Color(0.6, 0.05, 0.05), 0.3, 0.0, Color(0.9, 0.05, 0.03) if lights_on else Color.BLACK),
		"Amber": mat(AMBER, 0.3, 0.0, AMBER * 0.6 if lights_on else Color.BLACK),
	})


## Seats and dash, seen through the glass: stock cloth seats and a rear
## bench; fixed-back buckets (red bolsters) once they're in; no rear seat
## once the interior's stripped.
func build_interior() -> void:
	var dash := mat(TRIM, 0.8)
	if shell_info().is_empty():                        # (a fitted model brings its own dash)
		box(Vector3(0.35, 0.16, WIDTH * 0.78), Vector3(0.42, 0.9, 0), dash)
		box(Vector3(0.05, 0.05, 0.3), Vector3(0.28, 0.98, -0.36), dash, Vector3(0, 0, 0.4))   # the wheel
	for side: float in [-1.0, 1.0]:
		var z := side * 0.36
		if has_part("seats"):
			var shell := mat(BUCKET, 0.7)
			box(Vector3(0.1, 0.62, 0.48), Vector3(-0.38, 0.92, z), shell, Vector3(0, 0, 0.12))
			for e: float in [-0.21, 0.21]:
				box(Vector3(0.12, 0.42, 0.06), Vector3(-0.33, 0.86, z + e), mat(BUCKET_TRIM, 0.6), Vector3(0, 0, 0.12))
			box(Vector3(0.11, 0.08, 0.2), Vector3(-0.42, 1.12, z), mat(Color(0.3, 0.3, 0.32)))   # harness slot
		else:
			var cloth := mat(CLOTH, 0.95)
			box(Vector3(0.12, 0.5, 0.44), Vector3(-0.36, 0.86, z), cloth, Vector3(0, 0, 0.2))
			box(Vector3(0.09, 0.14, 0.24), Vector3(-0.42, 1.18, z), cloth, Vector3(0, 0, 0.15))   # headrest
	if not has_part("interior"):
		box(Vector3(0.14, 0.4, WIDTH * 0.72), Vector3(-1.2, 0.86, 0), mat(CLOTH, 0.95), Vector3(0, 0, 0.35))


## The exhaust tip: a stock pea-shooter turned down, a header's bigger tip,
## the race header's big burnt canister.
func build_exhaust() -> void:
	var steel := mat(SILVER, 0.3, 0.8)
	var r := 0.024
	var length := 0.1
	if has_part("header_41"):
		r = 0.055
		length = 0.22
		steel = mat(Color(0.5, 0.42, 0.36), 0.35, 0.8)        # heat-blued
	elif has_part("header"):
		r = 0.038
		length = 0.16
	var at := EXHAUST_AT if shell_info().is_empty() else Vector3(rear_x() + 0.025, EXHAUST_AT.y, EXHAUST_AT.z)
	cyl(r, length, at, steel, Vector3(0, 0, PI / 2.0 + (0.25 if r < 0.03 else 0.0)))
	cyl(r * 0.7, length + 0.005, at, mat(Color(0.02, 0.02, 0.02), 1.0), Vector3(0, 0, PI / 2.0))


## The body shop's add-ons (bodyshop.gd), on the paint `color`.
## A model file for a body shop item (LOOK_DIR, built in Blender, in the car's
## frame): placed on the body; its "Paint" material takes the car's color, a
## "Contrast" material the stripe color. Returns whether there was one.
func look_model(slot: String, color: Color, contrast: Color) -> bool:
	var id: String = look(slot).get("id", "")
	var path := LOOK_DIR + id + ".glb"
	if id == "" or not ResourceLoader.exists(path) or not shell_info().is_empty():   # (built on the EJ's surface)
		return false
	var m: Node3D = (load(path) as PackedScene).instantiate()
	target.add_child(m)
	swap_materials(m, {"Paint": mat(color, 0.35), "Contrast": mat(contrast, 0.4)})
	return true


## Replace a model's materials by name (the names given in Blender).
func swap_materials(root: Node, swaps: Dictionary) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.mesh.get_surface_count():
			var sm := m.mesh.surface_get_material(i)
			if sm != null and swaps.has(sm.resource_name):
				m.set_surface_override_material(i, swaps[sm.resource_name])


func build_looks(color: Color) -> void:
	var contrast := Color(0.06, 0.06, 0.07) if color.get_luminance() > 0.5 else Color(0.95, 0.95, 0.93)
	var modeled := {}
	for slot in ["stripes", "lip", "wing"]:            # the shaped ones: a model when there is one
		if look_model(slot, color, contrast):
			modeled[slot] = true
	if not look("banner").is_empty():
		# Across the top of the windshield, its letters facing forward and up
		var d := Vector2(-0.70, 0.45).normalized()             # up the windshield
		var n := Vector3(-d.y, d.x, 0.0) * -1.0                 # out of it, forward-up
		var at := Vector3(0.62, 0.87, 0) + Vector3(d.x, d.y, 0) * 0.74 + n * 0.008
		box(Vector3(0.012, 0.15, WIDTH * 0.78), at, mat(Color(0.04, 0.04, 0.05), 0.6),
			Vector3(0, 0, atan2(d.y, d.x) - PI / 2.0))
		var label := Label3D.new()
		label.text = Voice.BANNER_TEXT
		label.font = preload("res://fonts/RacingSansOne-Regular.ttf")
		label.font_size = 72
		label.pixel_size = 0.0014
		label.outline_size = 0
		label.modulate = Color(0.97, 0.97, 0.95)
		label.basis = Basis(Vector3(0, 0, -1), Vector3(d.x, d.y, 0), Vector3(-d.y, d.x, 0) * -1.0)
		label.position = at + Vector3(-d.y, d.x, 0) * -0.012
		target.add_child(label)
	match "" if modeled.has("stripes") else look("stripes").get("name", ""):
		"Side stripe":
			for side: float in [-1.0, 1.0]:
				box(Vector3(3.6, 0.05, 0.006), Vector3(-0.1, 0.72, side * (WIDTH / 2.0 + 0.006)), mat(contrast, 0.4))
		"Twin racing stripes":
			var hood_angle := atan2(0.89 - 0.77, 1.90 - 0.62)
			for z: float in [-0.13, 0.13]:
				box(Vector3(1.3, 0.008, 0.16), Vector3(1.26, 0.852, z), mat(contrast, 0.4), Vector3(0, 0, -hood_angle))
				box(Vector3(0.72, 0.008, 0.16), Vector3(-0.44, 1.348, z), mat(contrast, 0.4))
				box(Vector3(0.5, 0.008, 0.16), Vector3(-1.82, 0.9, z), mat(contrast, 0.4), Vector3(0, 0, 0.09))
	if look("stickers").get("name", "").begins_with("Crew decal"):
		# The crew's name across the top of the rear window, reading from behind
		var u := Vector2(0.70, 0.41).normalized()                # up the rear glass
		var at := Vector3(-0.80, 1.34, 0) + Vector3(-u.x, -u.y, 0) * 0.12
		var decal := Label3D.new()
		decal.text = Voice.CREW_NAME
		decal.font = preload("res://fonts/DelaGothicOne-Regular.ttf")
		decal.font_size = 72
		decal.pixel_size = 0.0019
		decal.outline_size = 0
		decal.modulate = Color(0.97, 0.96, 0.93)
		decal.basis = Basis(Vector3(0, 0, 1), Vector3(u.x, u.y, 0), Vector3(-u.y, u.x, 0))
		decal.position = at + Vector3(-u.y, u.x, 0) * 0.012
		target.add_child(decal)
	elif not look("stickers").is_empty():
		for side: float in [-1.0, 1.0]:                        # on the rear quarter glass
			for k in 3:
				box(Vector3(0.16, 0.05, 0.004), Vector3(-1.22 + k * 0.03, 1.08 - k * 0.07, side * (WIDTH * 0.42 + 0.004)),
					mat(STICKERS[k], 0.5))
	if not look("lip").is_empty() and not modeled.has("lip"):
		box(Vector3(0.16, 0.025, WIDTH * 0.95), Vector3(2.16, 0.265, 0), mat(Color(0.05, 0.05, 0.06), 0.5))
	match "" if modeled.has("wing") else look("wing").get("name", ""):
		"Ducktail spoiler":
			box(Vector3(0.12, 0.05, WIDTH * 0.86), Vector3(-2.05, 0.9, 0), mat(color, 0.35), Vector3(0, 0, 0.3))
		"GT wing":
			for z: float in [-0.5, 0.5]:
				box(Vector3(0.05, 0.2, 0.03), Vector3(-1.98, 0.99, z), mat(Color(0.08, 0.08, 0.09), 0.5))
			box(Vector3(0.3, 0.03, WIDTH * 0.92), Vector3(-1.99, 1.1, 0), mat(Color(0.08, 0.08, 0.09), 0.4), Vector3(0, 0, 0.12))
			for z: float in [-0.78, 0.78]:
				box(Vector3(0.32, 0.1, 0.01), Vector3(-1.99, 1.09, z), mat(Color(0.08, 0.08, 0.09), 0.4))
	if not look("tape").is_empty():                            # silver duct tape across the front corner
		var tape := mat(Color(0.72, 0.73, 0.74), 0.45, 0.3)
		for k in 3:
			box(Vector3(0.09, 0.05, 0.005), Vector3(2.0 - k * 0.07, 0.5 + k * 0.06, -(WIDTH / 2.0 + 0.006)),
				tape, Vector3(0, 0, 0.5 - k * 0.3))
			box(Vector3(0.005, 0.05, 0.12), Vector3(2.226, 0.46 + k * 0.06, -0.62 + k * 0.03), tape, Vector3(0.4 * k, 0, 0))


## Wheels: steelies with hubcaps (the front right lost on the 5), or the
## aftermarket ones with their spokes; R-compound letters on the tire; the
## body shop's rim color over any of them. Coilovers tuck them in at the top.
func build_wheels(drop: float) -> void:
	var forged := has_part("wheels_forged")
	var light := has_part("wheels_light")
	# Spire's picks: lightweight = chrome Konig Countergrams (9 spokes), forged = white Buddy Club P1s (6)
	var rim_col: Color = P1_WHITE if forged else (CHROME if light else STEELIE)
	rim_col = look("rims").get("color", rim_col)
	var chrome := light and look("rims").is_empty()
	var camber := 0.035 if has_part("coilovers") else 0.0
	var spokes := 6 if forged else 9
	var model_path := WHEEL_DIR + ("wheels_forged" if forged else ("wheels_light" if light else "wheels_stock")) + ".glb"
	var wheel_model: PackedScene = load(model_path) if ResourceLoader.exists(model_path) else null
	for axle: float in [FRONT_AXLE, REAR_AXLE]:
		for side: float in [-1.0, 1.0]:
			var w := Node3D.new()
			w.position = Vector3(axle, TIRE_R, side * (TRACK / 2.0 + (0.015 if drop > 0.0 else 0.0)))
			w.rotation.x = -side * camber
			add_child(w)
			var face := side * (TIRE_W / 2.0 + 0.006)
			var hubcap_gone := rough and look("paint").is_empty() and axle == FRONT_AXLE and side > 0.0   # lost on the 5
			if wheel_model != null:                  # the Blender wheel (art/blender/build_wheels.py)
				var wm: Node3D = wheel_model.instantiate()
				if side < 0.0:
					wm.rotation.y = PI               # modeled as a right-side wheel: turn it to face out on the left
				w.add_child(wm)
				# Low metal values: a fully metallic surface only mirrors its surroundings, and
				# the night / garage scenes are dark, so real "chrome" renders near black
				var rim_mat := mat(rim_col, 0.15, 0.45) if chrome else mat(rim_col, 0.4, 0.15 if forged else 0.3)
				var cap_mat := mat(HUBCAP if look("rims").is_empty() else rim_col, 0.3, 0.3)
				for m: StandardMaterial3D in [rim_mat, cap_mat]:
					m.cull_mode = BaseMaterial3D.CULL_DISABLED     # two-sided, like the model's (the barrel's seen from inside)
				swap_materials(wm, {"Rim": rim_mat, "Hubcap": cap_mat})
				var cap := wm.find_child("Hubcap", true, false)
				if cap != null:
					cap.visible = not hubcap_gone
				add_tire_letters(w, face)
				continue
			cyl(TIRE_R, TIRE_W, Vector3.ZERO, mat(TIRE, 0.9), Vector3(PI / 2.0, 0, 0), w)
			cyl(0.18, TIRE_W + 0.01, Vector3.ZERO, mat(rim_col, 0.45, 0.6), Vector3(PI / 2.0, 0, 0), w)
			if light or forged:
				cyl(0.17, 0.012, Vector3(0, 0, face), mat(Color(0.03, 0.03, 0.03), 0.9), Vector3(PI / 2.0, 0, 0), w)
				var spoke := mat(rim_col, 0.35, 0.7)
				for k in spokes:
					var a := TAU * k / spokes
					var s := MeshInstance3D.new()
					var b := BoxMesh.new()
					b.size = Vector3(0.028 if light else 0.018, 0.15, 0.014)
					s.mesh = b
					s.position = Vector3(cos(a), sin(a), 0) * 0.09 + Vector3(0, 0, face)
					s.rotation.z = a - PI / 2.0
					s.material_override = spoke
					w.add_child(s)
				cyl(0.035, 0.02, Vector3(0, 0, face), mat(rim_col.darkened(0.2), 0.4, 0.7), Vector3(PI / 2.0, 0, 0), w)
			elif not hubcap_gone:
				cyl(0.19, 0.02, Vector3(0, 0, face), mat(HUBCAP if look("rims").is_empty() else rim_col, 0.35, 0.8),
					Vector3(PI / 2.0, 0, 0), w)
			add_tire_letters(w, face)


## R-compound tires: yellow letters around the sidewall.
func add_tire_letters(w: Node3D, face: float) -> void:
	if not has_part("tires_r_comp"):
		return
	var letter := mat(Color(0.98, 0.85, 0.1), 0.6)
	for k in 8:
		var a := TAU * k / 8.0
		var l := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.07, 0.02, 0.004)
		l.mesh = lb
		l.position = Vector3(cos(a), sin(a), 0) * 0.245 + Vector3(0, 0, face)
		l.rotation.z = a + PI / 2.0
		l.material_override = letter
		w.add_child(l)
