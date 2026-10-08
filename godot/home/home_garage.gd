extends Node3D
## Permanent HOME 3D boundary. Prepared game assets are optional children of
## GarageVisual and VehicleVisual; the source GLBs under ../art are never read.

const GAME_CAR_ID := "eg6_sir_ii_1995"
const GAME_CAR_SCENE := "res://assets/models/cars/eg6_game.glb"
const GARAGE_SCENE := "res://assets/models/scenes/warehouse1_game.glb"
const GARAGE_PROPS_SCENE := "res://assets/models/scenes/warehouse_props_game.glb"

## The camera is stationary: close, a little above the roofline (about 1.9 m, looking down ~10 degrees),
## front three-quarter, the Civic nose toward it (+x is the nose), the car centered and ~89% of the frame
## width (the whole car, mirrors included, stays inside). Camera position + fov are on GarageCamera in
## home_garage.tscn; this is the point it looks at.
## The prepared models share one origin (art/blender/prep_home.py): where the Civic parks, floor at y = 0,
## the warehouse's long side wall 2.6 m behind it (z = -2.6).
const CAMERA_TARGET := Vector3(-0.15, 0.35, -0.4)

## The car's paint and glass are glossy in the pack: under a bright tube light that is a hot white blob on the
## hood and windshield. Rougher / less specular, same colors (looks only).
const PAINT_ROUGHNESS := 0.62
const PAINT_SPECULAR := 0.3
const GLASS_ROUGHNESS := 0.5
const GLASS_SPECULAR := 0.2
const CONTACT_SHADOW_SIZE := Vector2(5.0, 2.5)    # the soft dark blot under the car (wheels read as grounded)
const CONTACT_SHADOW_ALPHA := 0.6

const BODY := Color(0.62, 0.07, 0.09)
const GLASS := Color(0.06, 0.07, 0.09)
const TIRE := Color(0.05, 0.05, 0.05)
const RIM := Color(0.55, 0.56, 0.6)

var _civic_state := {}

@onready var civic_anchor: Node3D = %CivicAnchor
@onready var vehicle_visual: Node3D = %VehicleVisual
@onready var garage_visual: Node3D = %GarageVisual
@onready var garage_camera: Camera3D = %GarageCamera


func _ready() -> void:
	configure_environment()
	garage_camera.look_at(CAMERA_TARGET, Vector3.UP)
	var built := load_optional_scene(GARAGE_SCENE, garage_visual)
	built = load_optional_scene(GARAGE_PROPS_SCENE, garage_visual) or built
	if built:
		use_vertex_colors(garage_visual)
	add_contact_shadow()
	refresh_vehicle_visual()


## The whole transient view is copied so future appearance, damage, wheels,
## work-in-progress, and other visual fields can cross this same boundary.
## civic.installed in game.gd remains the sole persistent installation authority.
func apply_civic_state(civic_view: Dictionary) -> void:
	_civic_state = civic_view.duplicate(true)
	_civic_state["chassis_id"] = str(civic_view.get("chassis_id", ""))
	_civic_state["base_car_id"] = str(civic_view.get("base_car_id", ""))
	_civic_state["installed"] = civic_view.get("installed", {}).duplicate(true)
	civic_anchor.set_meta("chassis_id", _civic_state["chassis_id"])
	civic_anchor.set_meta("base_car_id", _civic_state["base_car_id"])
	civic_anchor.set_meta("installed", _civic_state["installed"].duplicate(true))
	if is_node_ready():
		refresh_vehicle_visual()


func current_civic_state() -> Dictionary:
	return _civic_state.duplicate(true)


func current_vehicle_visual_state() -> Dictionary:
	return vehicle_visual.get_meta("civic_view", {}).duplicate(true)


func configure_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.02, 0.022, 0.026)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.36, 0.4, 0.46)
	environment.ambient_light_energy = 0.55
	environment.fog_enabled = true                      # the far end of the garage falls into the dark
	environment.fog_light_color = Color(0.03, 0.034, 0.04)
	environment.fog_density = 0.035
	%Environment.environment = environment


## The garage's colors are baked into its vertices (one color per facet, no textures): the
## material has to read them as albedo.
func use_vertex_colors(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null:
				continue
			var colored := source.duplicate() as StandardMaterial3D
			colored.vertex_color_use_as_albedo = true
			mesh_instance.set_surface_override_material(surface, colored)


func load_optional_scene(path: String, anchor: Node3D) -> bool:
	if not ResourceLoader.exists(path):
		return false
	var resource := load(path)
	if resource is not PackedScene:
		push_warning("HOME asset is not a scene: %s" % path)
		return false
	anchor.add_child((resource as PackedScene).instantiate())
	return true


func refresh_vehicle_visual() -> void:
	for child in vehicle_visual.get_children():
		vehicle_visual.remove_child(child)
		child.queue_free()
	apply_vehicle_visual_state(_civic_state)
	if _civic_state.get("base_car_id", "") == GAME_CAR_ID and load_optional_scene(GAME_CAR_SCENE, vehicle_visual):
		soften_car_highlights(vehicle_visual)
		return
	build_eg6_development_fallback()


## Paint and glass by material name (the prepared EG6 names them Paint / Glass).
func soften_car_highlights(root: Node) -> void:
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for surface in mesh_instance.mesh.get_surface_count():
			var source := mesh_instance.mesh.surface_get_material(surface) as StandardMaterial3D
			if source == null or not source.resource_name in ["Paint", "Glass"]:
				continue
			var softer := source.duplicate() as StandardMaterial3D
			var is_paint := source.resource_name == "Paint"
			softer.roughness = PAINT_ROUGHNESS if is_paint else GLASS_ROUGHNESS
			softer.metallic_specular = PAINT_SPECULAR if is_paint else GLASS_SPECULAR
			mesh_instance.set_surface_override_material(surface, softer)


## A cheap soft shadow blot under the car: a transparent quad with a radial gradient, so the tires read as
## sitting on the floor even where the real shadow is faint. It lives on the anchor (the car's own
## nodes are rebuilt when the Civic state changes).
func add_contact_shadow() -> void:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray([Color(0, 0, 0, CONTACT_SHADOW_ALPHA), Color(0, 0, 0, CONTACT_SHADOW_ALPHA * 0.5), Color(0, 0, 0, 0)])
	gradient.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	var quad := QuadMesh.new()
	quad.size = Vector2(CONTACT_SHADOW_SIZE.x, CONTACT_SHADOW_SIZE.y)
	var blot := StandardMaterial3D.new()
	blot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blot.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blot.albedo_texture = texture
	blot.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shadow := MeshInstance3D.new()
	shadow.name = "ContactShadow"
	shadow.mesh = quad
	shadow.material_override = blot
	shadow.rotation_degrees = Vector3(-90, 0, 0)
	shadow.position = Vector3(0, 0.008, 0)
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	civic_anchor.add_child(shadow)


## Single visual customization hook. It intentionally records the authoritative
## view without interpreting fields that do not exist yet.
func apply_vehicle_visual_state(civic_view: Dictionary) -> void:
	vehicle_visual.set_meta("civic_view", civic_view.duplicate(true))


func material(color: Color, emissive := false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.7
	if emissive:
		result.emission_enabled = true
		result.emission = color
		result.emission_energy_multiplier = 1.0
	return result


func add_part(parent: Node3D, mesh: Mesh, color: Color, position: Vector3,
		rotation_degrees := Vector3.ZERO, emissive := false) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.material_override = material(color, emissive)
	part.position = position
	part.rotation_degrees = rotation_degrees
	parent.add_child(part)


func box(size: Vector3) -> BoxMesh:
	var result := BoxMesh.new()
	result.size = size
	return result


## Unchanged in purpose from the old pedestal car: this is only a visible
## development fallback until the prepared EG6 scene occupies VehicleVisual.
func build_eg6_development_fallback() -> void:
	var fallback := Node3D.new()
	fallback.name = "EG6DevelopmentFallback"
	vehicle_visual.add_child(fallback)
	# x = length (front is +x), z = width, y = up
	add_part(fallback, box(Vector3(4.070, 0.5, 1.695)), BODY, Vector3(0, 0.55, 0))
	add_part(fallback, box(Vector3(1.1, 0.12, 1.62)), BODY, Vector3(1.42, 0.86, 0), Vector3(0, 0, -4))
	add_part(fallback, box(Vector3(0.32, 0.1, 1.62)), BODY, Vector3(-1.87, 0.84, 0))
	add_part(fallback, box(Vector3(2.25, 0.46, 1.48)), GLASS, Vector3(-0.3, 1.02, 0))
	add_part(fallback, box(Vector3(1.5, 0.06, 1.46)), BODY, Vector3(-0.36, 1.27, 0))
	add_part(fallback, box(Vector3(0.08, 0.44, 1.5)), BODY, Vector3(-1.52, 1.03, 0))
	add_part(fallback, box(Vector3(0.06, 0.12, 0.42)), Color(1, 0.96, 0.88), Vector3(2.01, 0.68, 0.55), Vector3.ZERO, true)
	add_part(fallback, box(Vector3(0.06, 0.12, 0.42)), Color(1, 0.96, 0.88), Vector3(2.01, 0.68, -0.55), Vector3.ZERO, true)
	add_part(fallback, box(Vector3(0.06, 0.1, 0.5)), Color(0.9, 0.08, 0.08), Vector3(-2.01, 0.7, 0.52), Vector3.ZERO, true)
	add_part(fallback, box(Vector3(0.06, 0.1, 0.5)), Color(0.9, 0.08, 0.08), Vector3(-2.01, 0.7, -0.52), Vector3.ZERO, true)
	for x in [1.285, -1.285]:
		for z in [0.76, -0.76]:
			var tire := CylinderMesh.new()
			tire.top_radius = 0.3
			tire.bottom_radius = 0.3
			tire.height = 0.2
			tire.radial_segments = 12
			add_part(fallback, tire, TIRE, Vector3(x, 0.3, z), Vector3(90, 0, 0))
			var rim := CylinderMesh.new()
			rim.top_radius = 0.18
			rim.bottom_radius = 0.18
			rim.height = 0.21
			rim.radial_segments = 12
			add_part(fallback, rim, RIM, Vector3(x, 0.3, z), Vector3(90, 0, 0))
