extends Node3D
## Faba's '96 Civic DX coupe (EJ6), built in code: a real side profile
## extruded to width (CSGPolygon3D), greenhouse, wheels, lights. Placeholder
## until a real .glb; the same model goes on the home overlook and the lift.
##
## Day one it's mechanically stock and cosmetically rough (docs/ART_DIRECTION.md):
## Frost White with sun-faded roof and hood, a primer front fender, steelies,
## and one missing hubcap. build(parts) shows installed parts that change the
## look (carbon hood, aftermarket wheels, lowering springs).
##
## Axes: +x = forward, +y = up, +z = the car's right side (the side the
## cameras look at). Units: meters. Origin: on the ground, center of the car.

const LENGTH := 4.45
const WIDTH := 1.70
const WHEELBASE := 2.62
const FRONT_AXLE := 1.275            # x; front overhang 0.95 m
const REAR_AXLE := FRONT_AXLE - WHEELBASE
const TRACK := 1.47
const TIRE_R := 0.297                # 185/65R14
const TIRE_W := 0.185

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

var parts: Array = []        # installed part ids
var lights_on := true        # headlights/taillights glowing (off on the lift)
var rough := true            # Faba's DX: faded clearcoat, primer fender, missing hubcap
var paint_color := FROST_WHITE   # a clean car (rough = false) in another paint: opponents
var target: Node3D           # where extrude() and box() put things


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


func has_part(prefix: String) -> bool:
	for p in parts:
		if str(p).begins_with(prefix):
			return true
	return false


func build(installed: Array = []) -> void:
	parts = installed
	for c in get_children():
		c.queue_free()
	var drop := 0.04 if has_part("springs") else 0.0     # lowering springs
	var body := Node3D.new()
	body.position.y = -drop
	add_child(body)
	target = body

	var paint := mat(paint_color, 0.35)
	var faded := mat(FADED, 0.95) if rough else paint
	extrude(BODY_PROFILE, WIDTH, 0.0, paint)
	extrude(GREENHOUSE, WIDTH * 0.84, 0.0, mat(GLASS, 0.08, 0.4))

	# Roof and hood: sun-faded clearcoat (or a carbon hood once you buy one)
	box(Vector3(0.70, 0.02, WIDTH * 0.78), Vector3(-0.44, 1.335, 0), faded)
	var hood_mat := mat(CARBON, 0.3, 0.2) if has_part("hood") else faded
	var hood_angle := atan2(0.89 - 0.77, 1.90 - 0.62)
	box(Vector3(1.30, 0.02, WIDTH * 0.86), Vector3(1.26, 0.84, 0), hood_mat, Vector3(0, 0, -hood_angle))
	# Primer fender on the right side
	if rough:
		extrude(FENDER, 0.006, WIDTH / 2.0 + 0.004, mat(PRIMER, 1.0))
	# Rub strip, mirrors
	for side: float in [-1.0, 1.0]:
		box(Vector3(3.2, 0.06, 0.02), Vector3(-0.1, 0.52, side * (WIDTH / 2.0 + 0.01)), mat(TRIM, 0.6))
		box(Vector3(0.14, 0.09, 0.12), Vector3(0.45, 0.98, side * (WIDTH / 2.0 + 0.04)), paint)
	# Lights: headlights (warm) and taillights, glowing when lights_on
	for side: float in [-1.0, 1.0]:
		box(Vector3(0.06, 0.12, 0.42), Vector3(2.19, 0.64, side * 0.56),
			mat(Color(1, 0.96, 0.85), 0.2, 0.0, Color(1.0, 0.92, 0.72) if lights_on else Color.BLACK))
		box(Vector3(0.05, 0.14, 0.40), Vector3(-2.21, 0.74, side * 0.55),
			mat(Color(0.6, 0.05, 0.05), 0.3, 0.0, Color(0.9, 0.05, 0.03) if lights_on else Color.BLACK))
	# Black grille slot, plate
	box(Vector3(0.04, 0.06, 0.6), Vector3(2.215, 0.55, 0), mat(TRIM))
	box(Vector3(0.03, 0.12, 0.30), Vector3(-2.22, 0.52, 0), mat(Color(0.85, 0.85, 0.82), 0.6))

	# Wheels: steelies with hubcaps, except the front right (lost on the 5)
	var aftermarket := has_part("wheels")
	for axle: float in [FRONT_AXLE, REAR_AXLE]:
		for side: float in [-1.0, 1.0]:
			var w := Node3D.new()
			w.position = Vector3(axle, TIRE_R, side * (TRACK / 2.0))
			add_child(w)
			var tire := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = TIRE_R
			cyl.bottom_radius = TIRE_R
			cyl.height = TIRE_W
			tire.mesh = cyl
			tire.rotation.x = PI / 2.0
			tire.material_override = mat(TIRE, 0.9)
			w.add_child(tire)
			var rim := MeshInstance3D.new()
			var rc := CylinderMesh.new()
			rc.top_radius = 0.18
			rc.bottom_radius = 0.18
			rc.height = TIRE_W + 0.01
			rim.mesh = rc
			rim.rotation.x = PI / 2.0
			rim.material_override = mat(BRONZE if aftermarket else STEELIE, 0.45, 0.6)
			w.add_child(rim)
			var missing_cap := rough and axle == FRONT_AXLE and side > 0.0
			if not aftermarket and not missing_cap:
				var cap := MeshInstance3D.new()
				var cc := CylinderMesh.new()
				cc.top_radius = 0.19
				cc.bottom_radius = 0.19
				cc.height = 0.02
				cap.mesh = cc
				cap.rotation.x = PI / 2.0
				cap.position.z = side * (TIRE_W / 2.0 + 0.01)
				cap.material_override = mat(HUBCAP, 0.35, 0.8)
				w.add_child(cap)
