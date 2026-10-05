extends Node3D
## Opponents' cars, built in code from a few real proportions (like the DX in
## dx_model.gd, but parametric): a side profile generated from length,
## wheelbase, roof height, beltline, hood and roof length, and a body style
## (notch / fastback / hatch / mid / open), extruded to the car's width.
## Placeholder bodies until real models, but each reads as its own car.
##
## Axes like dx_model: +x forward, +y up, +z = the car's right side; meters;
## origin on the ground at the car's center. build_car(car_name) picks the
## profile by keyword (same keywords as widgets/car_sprite.gd).

const CarSprite := preload("res://widgets/car_sprite.gd")

const TIRE_R := 0.3
const ARCH_R := 0.37
const GLASS := Color(0.05, 0.06, 0.08)
const TRIM := Color(0.06, 0.06, 0.065)
const TIRE := Color(0.04, 0.04, 0.045)

# Proportions (m). style: notch = separate trunk; fastback = long sloping glass
# to the tail; hatch = roof runs back to a near-vertical hatch; mid = short
# roof, engine deck behind it; open = no roof (windshield frame only).
const DEFAULT := {"length": 4.4, "width": 1.7, "wheelbase": 2.5, "height": 1.32, "belt": 0.86,
	"nose": 0.62, "hood": 1.25, "windshield": 0.7, "roof": 1.0, "style": "notch",
	"rims": Color(0.7, 0.7, 0.72), "popups": false}
const PROFILES := {
	"280Z": {"length": 4.4, "width": 1.63, "wheelbase": 2.31, "height": 1.29, "belt": 0.8,
		"nose": 0.6, "hood": 1.72, "windshield": 0.62, "roof": 0.55, "style": "fastback",
		"rims": Color(0.2, 0.2, 0.22)},
	"CRX": {"length": 3.76, "width": 1.66, "wheelbase": 2.3, "height": 1.27, "belt": 0.8,
		"nose": 0.58, "hood": 0.95, "windshield": 0.75, "roof": 0.9, "style": "hatch"},
	"Miata": {"length": 3.95, "width": 1.68, "wheelbase": 2.27, "height": 1.15, "belt": 0.78,
		"nose": 0.55, "hood": 1.2, "windshield": 0.45, "roof": 0.0, "style": "open", "popups": true},
	"AE86": {"length": 4.2, "width": 1.63, "wheelbase": 2.4, "height": 1.34, "belt": 0.84,
		"nose": 0.6, "hood": 1.15, "windshield": 0.68, "roof": 1.05, "style": "hatch",
		"popups": true, "rims": Color(0.85, 0.85, 0.86)},
	"Integra": {"length": 4.38, "width": 1.71, "wheelbase": 2.57, "height": 1.34, "belt": 0.84,
		"nose": 0.58, "hood": 1.2, "windshield": 0.78, "roof": 0.95, "style": "hatch"},
	"Mustang": {"length": 4.56, "width": 1.74, "wheelbase": 2.55, "height": 1.32, "belt": 0.88,
		"nose": 0.66, "hood": 1.45, "windshield": 0.7, "roof": 1.0, "style": "notch"},
	"RSX": {"length": 4.37, "width": 1.73, "wheelbase": 2.57, "height": 1.4, "belt": 0.9,
		"nose": 0.62, "hood": 1.05, "windshield": 0.95, "roof": 0.9, "style": "hatch"},
	"Eclipse": {"length": 4.49, "width": 1.74, "wheelbase": 2.51, "height": 1.31, "belt": 0.86,
		"nose": 0.58, "hood": 1.2, "windshield": 0.85, "roof": 0.7, "style": "fastback"},
	"GTI": {"length": 4.15, "width": 1.73, "wheelbase": 2.51, "height": 1.44, "belt": 0.95,
		"nose": 0.68, "hood": 1.0, "windshield": 0.75, "roof": 1.35, "style": "hatch"},
	"MR2": {"length": 4.17, "width": 1.69, "wheelbase": 2.4, "height": 1.24, "belt": 0.8,
		"nose": 0.55, "hood": 1.05, "windshield": 0.8, "roof": 0.75, "style": "mid", "popups": true},
	"Mazdaspeed": {"length": 4.5, "width": 1.77, "wheelbase": 2.64, "height": 1.46, "belt": 0.96,
		"nose": 0.7, "hood": 1.05, "windshield": 0.95, "roof": 1.2, "style": "hatch"},
	"Prelude": {"length": 4.52, "width": 1.75, "wheelbase": 2.59, "height": 1.32, "belt": 0.86,
		"nose": 0.62, "hood": 1.3, "windshield": 0.75, "roof": 0.95, "style": "notch"},
	"2007 Honda Civic": {"length": 4.44, "width": 1.75, "wheelbase": 2.62, "height": 1.36, "belt": 0.9,
		"nose": 0.62, "hood": 0.95, "windshield": 1.1, "roof": 1.05, "style": "notch"},
	"Accord": {"length": 4.68, "width": 1.78, "wheelbase": 2.72, "height": 1.39, "belt": 0.9,
		"nose": 0.64, "hood": 1.2, "windshield": 0.8, "roof": 1.2, "style": "notch"},
	"FA5": {"length": 4.49, "width": 1.75, "wheelbase": 2.7, "height": 1.43, "belt": 0.92,
		"nose": 0.62, "hood": 1.0, "windshield": 1.1, "roof": 1.15, "style": "notch",
		"rims": Color(0.2, 0.2, 0.22)},
	"370Z": {"length": 4.25, "width": 1.85, "wheelbase": 2.55, "height": 1.32, "belt": 0.86,
		"nose": 0.62, "hood": 1.45, "windshield": 0.95, "roof": 0.5, "style": "fastback",
		"paint": Color(0.16, 0.16, 0.18), "rims": Color(0.12, 0.12, 0.13)},
	"Camaro": {"length": 4.9, "width": 1.88, "wheelbase": 2.57, "height": 1.3, "belt": 0.84,
		"nose": 0.58, "hood": 1.85, "windshield": 0.85, "roof": 0.6, "style": "fastback"},
}

var spec := {}


static func profile_for(car_name: String) -> Dictionary:
	var p := DEFAULT.duplicate()
	for key in PROFILES:
		if car_name.contains(key):
			p.merge(PROFILES[key], true)
			break
	var look := CarSprite.profile_for(car_name)        # paint + livery shared with the replay
	if not p.has("paint"):
		p["paint"] = look.get("paint", Color(0.5, 0.5, 0.52))
	p["stripes"] = look.get("stripes", null)
	p["skirts"] = look.get("skirts", null)
	return p


func mat(color: Color, rough := 0.4, metal := 0.0, emit := Color.BLACK) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	if emit != Color.BLACK:
		m.emission_enabled = true
		m.emission = emit
		m.emission_energy_multiplier = 2.0
	return m


func extrude(points: PackedVector2Array, depth: float, material: Material) -> void:
	var c := CSGPolygon3D.new()
	c.polygon = points
	c.depth = depth
	c.position.z = depth / 2.0                     # CSGPolygon3D extrudes toward -z
	c.material = material
	add_child(c)


func box(size: Vector3, pos: Vector3, material: Material, rot := Vector3.ZERO) -> void:
	var m := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	m.mesh = b
	m.position = pos
	m.rotation = rot
	m.material_override = material
	add_child(m)


## Lower body: tail -> beltline -> hood -> nose -> bumper -> sills with both
## wheel arches cut out (half circles over each axle).
func body_profile(p: Dictionary) -> PackedVector2Array:
	var half: float = p["length"] / 2.0
	var xf: float = p["wheelbase"] / 2.0 + 0.05           # FR/FF cars sit a little nose-heavy
	var xr: float = xf - p["wheelbase"]
	var belt: float = p["belt"]
	var cowl: float = half - p["hood"]
	var tail_top: float = belt - (0.02 if p["style"] in ["notch", "mid"] else 0.0)
	var pts := PackedVector2Array([
		Vector2(-half + 0.06, 0.3), Vector2(-half, 0.45), Vector2(-half + 0.01, tail_top - 0.06),
		Vector2(-half + 0.1, tail_top), Vector2(cowl, belt),
		Vector2(half - 0.18, p["nose"]), Vector2(half, p["nose"] - 0.1), Vector2(half + 0.01, 0.42),
		Vector2(half - 0.06, 0.28),
	])
	for axle: float in [xf, xr]:
		pts.append(Vector2(axle + ARCH_R, 0.26))
		for i in range(1, 8):
			var a := PI * i / 8.0                        # over the top, front to back
			pts.append(Vector2(axle + cos(a) * ARCH_R, TIRE_R + sin(a) * ARCH_R * 0.95))
		pts.append(Vector2(axle - ARCH_R, 0.26))
	return pts


## Glass above the beltline, shaped by the body style.
func greenhouse(p: Dictionary) -> PackedVector2Array:
	var half: float = p["length"] / 2.0
	var belt: float = p["belt"]
	var h: float = p["height"]
	var base_front: float = half - p["hood"]
	var roof_front: float = base_front - p["windshield"]
	var roof_rear: float = roof_front - p["roof"]
	var back: float
	match p["style"]:
		"fastback":
			back = -half + 0.25                          # long glass down to the tail
		"hatch":
			back = maxf(roof_rear - 0.35, -half + 0.08)  # near-vertical hatch
		"mid":
			back = roof_rear - 0.45                      # engine deck behind
		_:
			back = roof_rear - 0.6                       # notchback: trunk behind
	return PackedVector2Array([Vector2(base_front, belt - 0.01), Vector2(roof_front, h),
		Vector2(roof_rear, h), Vector2(back, belt - 0.01)])


## A real model (Spire's low-poly cars, prepped by art/blender/prep_cars.py:
## nose +x, on the ground, centered, real length) for a car's keyword. The
## first key the car's name contains wins. Looks only: the race is the sim's.
const MODELS := {
	"280Z": "240z",          # the 240Z's body = the 280Z's
	"370Z": "370z",
	"AE86": "ae86",
	"Accord": "accord94",
	"FA5": "fd2",            # the story's FA5 Civic Si sedan: the FD2's body (Spire). Brandon's R18 Civic: TODO
	"Celica": "celica6",
	"Lancer": "evo3",
	"Evo": "evo3",
}
const MODEL_DIR := "res://models/cars/"
## Cars shown as another car (looks only; the race is still the sim's car).
## Spire, Oct 2026: Zed in the 370Z to see how it looks. Delete the line to
## put him back in his 280Z.
const LOOKS_AS := {"280Z": "370Z"}


static func model_path(car_name: String) -> String:
	for key in MODELS:
		if car_name.contains(key):
			var path: String = MODEL_DIR + MODELS[key] + ".glb"
			return path if ResourceLoader.exists(path) else ""
	return ""


func build_car(car_name: String, lights_on := true) -> void:
	for c in get_children():
		c.queue_free()
	for key in LOOKS_AS:
		if car_name.contains(key):
			car_name = LOOKS_AS[key]
	var p := profile_for(car_name)
	spec = p
	var model := model_path(car_name)
	if model != "":
		add_child((load(model) as PackedScene).instantiate())
		return
	var w: float = p["width"]
	var paint := mat(p["paint"], 0.32, 0.1)
	extrude(body_profile(p), w, paint)
	var half: float = p["length"] / 2.0
	var roof_front: float = half - p["hood"] - p["windshield"]
	if p["style"] == "open":
		# Windshield frame only; seats and roll hoops show over the doors
		box(Vector3(0.05, 0.36, w * 0.86), Vector3(half - p["hood"] - 0.12, p["belt"] + 0.16, 0),
			mat(GLASS, 0.08, 0.4), Vector3(0, 0, 0.5))
		box(Vector3(0.9, 0.12, w * 0.7), Vector3(roof_front - 0.45, p["belt"] + 0.05, 0), mat(TRIM, 0.8))
	else:
		# Painted cabin with the window shape cut out (pillars + roof frame),
		# glass set just inside it
		var cabin := greenhouse(p)
		var glass := Geometry2D.offset_polygon(cabin, -0.02)    # just inside the paint: no z-fighting
		extrude(glass[0] if not glass.is_empty() else cabin, w * 0.82, mat(GLASS, 0.08, 0.4))
		var frame := CSGCombiner3D.new()
		add_child(frame)
		var shell := CSGPolygon3D.new()
		shell.polygon = cabin
		shell.depth = w * 0.86
		shell.position.z = w * 0.43
		shell.material = paint
		frame.add_child(shell)
		var windows := Geometry2D.offset_polygon(cabin, -0.07)
		if not windows.is_empty():
			var cut := CSGPolygon3D.new()
			cut.polygon = windows[0]
			cut.depth = w
			cut.position.z = w / 2.0
			cut.operation = CSGShape3D.OPERATION_SUBTRACTION
			frame.add_child(cut)
	# Livery: twin stripes over hood and roof, dark side skirts
	if p["stripes"] != null and p["style"] != "open":
		var hood_tilt := atan2(p["belt"] - p["nose"], p["hood"])
		for side: float in [-1.0, 1.0]:
			box(Vector3(p["roof"] + 0.1, 0.012, 0.16), Vector3(roof_front - p["roof"] / 2.0, p["height"] + 0.02,
				side * 0.14), mat(p["stripes"], 0.4))
			box(Vector3(p["hood"], 0.012, 0.16), Vector3(half - p["hood"] / 2.0, (p["belt"] + p["nose"]) / 2.0 + 0.01,
				side * 0.14), mat(p["stripes"], 0.4), Vector3(0, 0, -hood_tilt))
	if p["skirts"] != null:
		for side: float in [-1.0, 1.0]:
			box(Vector3(p["wheelbase"] - 0.75, 0.1, 0.02), Vector3(0, 0.32, side * (w / 2.0 + 0.005)),
				mat(p["skirts"], 0.6))
	# Rub strip, lights, grille
	for side: float in [-1.0, 1.0]:
		box(Vector3(p["length"] * 0.7, 0.05, 0.02), Vector3(0, 0.5, side * (w / 2.0 + 0.01)), mat(TRIM, 0.6))
		var lamp_h: float = p["nose"] - 0.06
		if p["popups"]:
			box(Vector3(0.3, 0.12, 0.34), Vector3(half - 0.35, p["nose"] + 0.08, side * 0.5), paint)   # popped up
			lamp_h = p["nose"] + 0.08
		box(Vector3(0.06, 0.1, 0.36), Vector3(half - (0.21 if p["popups"] else 0.0), lamp_h, side * 0.5),
			mat(Color(1, 0.96, 0.85), 0.2, 0.0, Color(1.0, 0.92, 0.72) if lights_on else Color.BLACK))
		box(Vector3(0.05, 0.12, 0.42), Vector3(-half, p["belt"] - 0.12, side * 0.52),
			mat(Color(0.6, 0.05, 0.05), 0.3, 0.0, Color(0.9, 0.05, 0.03) if lights_on else Color.BLACK))
	box(Vector3(0.04, 0.07, w * 0.4), Vector3(half + 0.01, 0.5, 0), mat(TRIM))
	# Wheels
	var xf: float = p["wheelbase"] / 2.0 + 0.05
	for axle: float in [xf, xf - p["wheelbase"]]:
		for side: float in [-1.0, 1.0]:
			var wheel := Node3D.new()
			wheel.position = Vector3(axle, TIRE_R, side * (w / 2.0 - 0.13))
			add_child(wheel)
			for part in [[TIRE_R, 0.2, mat(TIRE, 0.9)], [0.19, 0.21, mat(p["rims"], 0.35, 0.7)]]:
				var m := MeshInstance3D.new()
				var cyl := CylinderMesh.new()
				cyl.top_radius = part[0]
				cyl.bottom_radius = part[0]
				cyl.height = part[1]
				m.mesh = cyl
				m.rotation.x = PI / 2.0
				m.material_override = part[2]
				wheel.add_child(m)


## Where the headlights sit (for spotlights), in the car's own space.
func headlight_positions() -> Array:
	var half: float = spec["length"] / 2.0
	var h: float = spec["nose"] + (0.08 if spec["popups"] else -0.06)
	return [Vector3(half + 0.05, h, -0.5), Vector3(half + 0.05, h, 0.5)]
