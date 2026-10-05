extends Node3D
## The parts pulls as boxes in a kei truck's flatbed (Spire, Oct 2026): a
## Honda Acty parked in the garage (widgets/garage_cam.gd puts it there) under
## a sodium lamp, one box per pull source with its price floating over it.
## The garage's camera picks a box (pick()); the shop shows its card.
## Spire's models: models/part scene/.
##
## Each model comes at its own scale and origin, so placed() normalizes it:
## scaled to a real size (its longest side), set on its bottom center.
## Local frame: the truck's cab toward -x, its bed toward +x.

const DIR := "res://models/part scene/"
const TRUCK := "simple_kei_truck.glb"
const TRUCK_LEN := 3.4                     # a kei truck's real length (m)
# One box per pull source: model, real size (longest side, m)
const BOXES := {
	"junkyard": ["closed_cardboard_greasy.glb", 0.62],     # greasy, ugly
	"swap_meet": ["taped_cardboard_clean.glb", 0.66],     # decent, loosely taped
	"crate": ["wood_box_closed.glb", 0.66],                # a wooden crate
	"import": ["open_closed_office_box.glb", 0.6],        # the JDM import box (a decal on it)
}
const SLOTS := {                           # (across the bed 0..1, tailgate 0 / cab 1)
	"junkyard": Vector2(0, 0), "import": Vector2(1, 0), "swap_meet": Vector2(1, 1), "crate": Vector2(0, 1),
}
const DRESSING := [                                        # opened boxes on the ground by the truck
	["open_cardboard_greasy.glb", 0.6, Vector3(2.5, 0, 1.2), 0.6],
	["open_cardboard_clean.glb", 0.65, Vector3(-0.4, 0, 1.45), -0.4],
]
const SODIUM := Color(1.0, 0.62, 0.28)
const MONEY := Color(0.35, 0.9, 0.45)
const LOCKED := Color(0.95, 0.25, 0.2)

var boxes := {}          # id -> Node3D (normalized box)
var labels := {}         # id -> Label3D
var bed_floor := 0.62    # the flatbed's floor height (m), set by the truck's measure
var bed_rect := Rect2()  # the flatbed (x, z) where the boxes go
var selected := ""
var t := 0.0


func _ready() -> void:
	var lamp := SpotLight3D.new()                  # the sodium lamp over the bed
	lamp.light_color = SODIUM
	lamp.light_energy = 7.0
	lamp.spot_range = 7.0
	lamp.spot_angle = 40.0
	lamp.shadow_enabled = true
	add_child(lamp)
	lamp.position = Vector3(0.6, 3.1, 0.3)
	lamp.rotation = Vector3(-PI / 2.0, 0, 0)
	var truck := placed(TRUCK, TRUCK_LEN)
	if truck != null:
		# Spire's Acty comes with its length on z: turned so the cab is at -x, the bed toward +x
		truck.rotation.y = -PI / 2.0
		add_child(truck)
		var half_w: float = truck.get_meta("half_x")
		bed_rect = Rect2(-TRUCK_LEN / 2.0 + 1.4, -half_w + 0.12, TRUCK_LEN - 1.55, half_w * 2.0 - 0.24)
		bed_floor = truck.get_meta("height") * 0.39
	for d: Array in DRESSING:
		var b := placed(d[0], d[1])
		if b != null:
			b.position = d[2]
			b.rotation.y = d[3]
			add_child(b)


## info per source: {id: {price, locked (rep), rep_required}}
func setup(sources: Dictionary) -> void:
	for id in boxes:
		boxes[id].queue_free()
		labels[id].queue_free()
	boxes.clear()
	labels.clear()
	var ids := []
	for id in BOXES:
		if sources.has(id):
			ids.append(id)
	# Two rows of two across the bed: the low ones at the tailgate, the tall
	# crate against the cab, so every box shows
	for k in ids.size():
		var id: String = ids[k]
		var spec: Array = BOXES[id]
		var b := placed(spec[0], spec[1])
		if b == null:
			continue
		var slot: Vector2 = SLOTS.get(id, Vector2(k % 2, k / 2))
		b.position = Vector3(lerpf(bed_rect.end.x - 0.42, bed_rect.position.x + 0.42, slot.y),
			bed_floor, lerpf(bed_rect.position.y + 0.38, bed_rect.end.y - 0.38, slot.x))
		b.set_meta("tag_up", 0.32 + slot.y * 0.38)        # the back row's tags float higher
		b.rotation.y = [0.12, -0.2, 0.05, -0.1][k % 4]
		add_child(b)
		boxes[id] = b
		if id == "import":                        # the import box: a JDM decal on its side
			var decal := Label3D.new()
			decal.text = "JDM 輸入"
			decal.font = preload("res://fonts/DelaGothicOne-Regular.ttf")
			decal.font_size = 64
			decal.pixel_size = 0.0018
			decal.modulate = Color(0.85, 0.1, 0.1)
			decal.outline_size = 0
			decal.position = Vector3(0, b.get_meta("height") * 0.5, b.get_meta("half_z") + 0.004)
			b.add_child(decal)
		var src: Dictionary = sources[id]
		var l := Label3D.new()
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.font = preload("res://fonts/VT323-Regular.ttf")
		l.font_size = 80
		l.pixel_size = 0.0026
		l.outline_size = 16
		l.outline_modulate = Color(0.02, 0.02, 0.03)
		l.no_depth_test = true
		l.text = ("NEEDS %d REP" % int(src["rep_required"])) if src["locked"] else "$%d" % int(src["price"])
		l.modulate = LOCKED if src["locked"] else MONEY
		l.position = b.position + Vector3(0, b.get_meta("height") + b.get_meta("tag_up"), 0)
		add_child(l)
		labels[id] = l
	select(ids[0] if not ids.is_empty() else "")


func select(id: String) -> void:
	selected = id
	for k in labels:
		labels[k].scale = Vector3.ONE * (1.3 if k == id else 1.0)


## Which box (or its price) is nearest a tap on screen, through `cam`; "" = none.
func pick(cam: Camera3D, pos: Vector2) -> String:
	var best := ""
	var best_d := 90.0
	for id in boxes:
		var b: Node3D = boxes[id]
		for at: Vector3 in [b.global_position + Vector3(0, b.get_meta("height") * 0.5, 0), labels[id].global_position]:
			if cam.is_position_behind(at):
				continue
			var d := cam.unproject_position(at).distance_to(pos)
			if d < best_d:
				best_d = d
				best = id
	if best != "":
		select(best)
	return best


## A model scaled to `size` (its longest side) on its bottom center, wrapped.
static func placed(file: String, size: float) -> Node3D:
	var path := DIR + file
	if not ResourceLoader.exists(path):
		return null
	var m: Node3D = (load(path) as PackedScene).instantiate()
	var box := AABB()
	var first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var mesh_i := mi as MeshInstance3D
		var a := local_xform(mesh_i, m) * mesh_i.get_aabb()
		box = a if first else box.merge(a)
		first = false
	var k := size / maxf(box.size.x, maxf(box.size.y, box.size.z))
	var holder := Node3D.new()
	holder.add_child(m)
	m.scale = Vector3.ONE * k
	m.position = -Vector3(box.get_center().x, box.position.y, box.get_center().z) * k
	holder.set_meta("height", box.size.y * k)
	holder.set_meta("half_z", box.size.z * k / 2.0)
	holder.set_meta("half_x", box.size.x * k / 2.0)
	return holder


## A node's transform relative to an ancestor (works before it's in the tree).
static func local_xform(n: Node3D, root: Node3D) -> Transform3D:
	var x := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			x = (cur as Node3D).transform * x
		cur = cur.get_parent()
	return x


func _process(delta: float) -> void:
	t += delta
	for id in labels:                                   # the picked one bobs
		var l: Label3D = labels[id]
		var b: Node3D = boxes[id]
		var bob := sin(t * 3.0) * 0.04 if id == selected else 0.0
		l.position.y = b.position.y + b.get_meta("height") + b.get_meta("tag_up") + bob
