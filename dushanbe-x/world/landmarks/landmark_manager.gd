class_name LandmarkManager
extends Node3D
## Streams landmark and POI structures around the camera.
##
## Orientation convention (shared by every builder in builders/):
##   * builder local space: origin = landmark centre at pad ground height, Y up,
##     the MAIN FACADE FACES LOCAL +Z.
##   * the node is rotated by Basis(UP, deg_to_rad(yaw)), so yaw 0 => facade faces south (+Z world),
##     90 => east (+X), 180 => north (-Z), -90 => west (-X).
##   * POIs (world.json "pois") already store the yaw such that +Z faces their road.
##   * lm["hx"], lm["hz"] = local half extents of the pad (pad is world-axis aligned, swapped for ±90°).
## Small details (benches, lamps, flowers…) go to the detail kit lm["_detail"] which is only
## drawn within DETAIL_RANGE. Signage is returned as lm["_labels"] and becomes Label3D nodes.

const LOAD_RADIUS := 2500.0
const DETAIL_RANGE := 380.0
const LABEL_RANGE := 160.0
const RADIUS_OVERRIDE := {"flag_park": 5200.0, "somoni_monument": 3500.0, "palace_of_nations": 3200.0,
	"kohi_navruz": 3200.0, "vahdat_palace": 3000.0, "hisor_fortress": 3000.0, "safedi_viewpoint": 3000.0}
## Facade directions corrected to face the adjacent road / view (see layout.py positions).
const YAW_OVERRIDE := {"hisor_fortress": 0.0, "hisor_madrasa": 0.0, "safedi_viewpoint": -90.0}
const COLLIDE_SLOTS := ["stone", "marble", "concrete", "plain", "glossy", "metal", "gold", "glass", "paving",
	"tin", "wood", "dirt", "gravel", "bark", "chrome"]

var is_idle := false
var items: Array = []
var _builders: Dictionary = {}
var _poi_builder: GDScript
var _mats: Dictionary = {}
var _results: Array = []
var _mutex := Mutex.new()
var _inflight := 0
var _timer := 0.0
var max_inflight := 2


func _ready() -> void:
	for lm in WorldData.landmarks:
		var id: String = lm["id"]
		var p := "res://world/landmarks/builders/%s.gd" % id
		if ResourceLoader.exists(p):
			_builders[id] = load(p)
		else:
			push_warning("LandmarkManager: no builder for " + id)
	_poi_builder = load("res://world/landmarks/builders/pois.gd")
	_make_materials()
	for lm in WorldData.landmarks:
		var id: String = lm["id"]
		if not _builders.has(id):
			continue
		var yaw: float = YAW_OVERRIDE.get(id, float(lm["yaw"]))
		var y: float = float(lm.get("y", WorldData.height_at(lm["x"], lm["z"])))
		items.append({"kind": "lm", "id": id, "data": lm, "yaw": yaw,
			"pos": Vector3(lm["x"], y, lm["z"]), "radius": RADIUS_OVERRIDE.get(id, LOAD_RADIUS),
			"state": 0, "node": null})
	for poi in WorldData.pois:
		var x: float = poi["x"]
		var z: float = poi["z"]
		items.append({"kind": "poi", "id": poi["type"], "data": poi, "yaw": float(poi["yaw"]),
			"pos": Vector3(x, WorldData.height_at(x, z), z), "radius": 1500.0, "state": 0, "node": null})


func _make_materials() -> void:
	var water := ShaderMaterial.new()
	water.shader = load("res://world/landmarks/fountain_water.gdshader")
	_mats["lm_water"] = water
	var leaves := StandardMaterial3D.new()
	leaves.vertex_color_use_as_albedo = true
	leaves.vertex_color_is_srgb = true
	leaves.roughness = 0.92
	leaves.backlight_enabled = true
	leaves.backlight = Color(0.25, 0.35, 0.1)
	_mats["lm_leaves"] = leaves
	var flag := ShaderMaterial.new()
	flag.shader = load("res://util/shaders/flag.gdshader")
	flag.set_shader_parameter("flag_length", 50.0)
	_mats["flag"] = flag
	var awning := StandardMaterial3D.new()
	awning.vertex_color_use_as_albedo = true
	awning.vertex_color_is_srgb = true
	awning.cull_mode = BaseMaterial3D.CULL_DISABLED
	awning.roughness = 0.9
	_mats["awning"] = awning


func _process(delta: float) -> void:
	_apply_results()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.3
	var cam := GameState.view_position()
	var pending := false
	var order: Array = []
	for i in items.size():
		var it: Dictionary = items[i]
		var p: Vector3 = it["pos"]
		var d := Vector2(p.x - cam.x, p.z - cam.z).length()
		if d < it["radius"]:
			if it["state"] == 0:
				order.append([d, i])
				pending = true
			elif it["state"] == 1:
				pending = true
		elif d > it["radius"] + 300.0 and it["state"] == 2:
			if is_instance_valid(it["node"]):
				it["node"].queue_free()
			it["node"] = null
			it["state"] = 0
	order.sort_custom(func(a, b): return a[0] < b[0])
	for o in order:
		if _inflight >= max_inflight:
			break
		var it: Dictionary = items[o[1]]
		it["state"] = 1
		_inflight += 1
		WorkerThreadPool.add_task(_task.bind(o[1]))
	is_idle = not pending and _inflight == 0


func _task(idx: int) -> void:
	var it: Dictionary = items[idx]
	var k := MeshKit.new()
	var det := MeshKit.new()
	var lm: Dictionary = it["data"].duplicate()
	lm["_detail"] = det
	var yaw: float = it["yaw"]
	var swap := absf(sin(deg_to_rad(yaw))) > 0.7
	if it["kind"] == "lm":
		var pad: Array = lm["pad"]
		lm["hx"] = float(pad[1]) if swap else float(pad[0])
		lm["hz"] = float(pad[0]) if swap else float(pad[1])
		var b: GDScript = _builders[it["id"]]
		b.build(k, lm)
	else:
		_poi_builder.build_poi(k, lm)
	_linearize(k)
	_linearize(det)
	var faces := k.collision_faces(COLLIDE_SLOTS)
	_mutex.lock()
	_results.append({"idx": idx, "kit": k, "detail": det, "faces": faces, "labels": lm.get("_labels", [])})
	_mutex.unlock()


## Textured world-space shaders use COLOR as linear; builders author colours in sRGB.
const LINEAR_SLOTS := ["stone", "marble", "concrete", "paving", "dirt", "gravel", "wood", "tin", "bark", "lm_water"]


static func _linearize(k: MeshKit) -> void:
	for slot in LINEAR_SLOTS:
		if not k.surfaces.has(slot):
			continue
		var c: PackedColorArray = k.surfaces[slot]["c"]
		for i in c.size():
			c[i] = c[i].srgb_to_linear()
		k.surfaces[slot]["c"] = c


func _apply_results() -> void:
	_mutex.lock()
	var batch := _results.duplicate()
	_results.clear()
	_mutex.unlock()
	for r in batch:
		_inflight -= 1
		var it: Dictionary = items[r["idx"]]
		var node := Node3D.new()
		node.name = "%s_%d" % [it["id"], r["idx"]]
		add_child(node)
		node.global_position = it["pos"]
		node.rotation.y = deg_to_rad(it["yaw"])
		var kit: MeshKit = r["kit"]
		if not kit.is_empty():
			var mi := MeshInstance3D.new()
			mi.mesh = kit.build(_mats)
			mi.visibility_range_end = it["radius"] + 250.0
			mi.visibility_range_end_margin = 50.0
			node.add_child(mi)
		var det: MeshKit = r["detail"]
		if not det.is_empty():
			var md := MeshInstance3D.new()
			md.mesh = det.build(_mats)
			md.visibility_range_end = DETAIL_RANGE
			md.visibility_range_end_margin = 30.0
			md.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			md.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			node.add_child(md)
		var faces: PackedVector3Array = r["faces"]
		if faces.size() > 0:
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			var cs := CollisionShape3D.new()
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			cs.shape = shape
			body.add_child(cs)
			node.add_child(body)
		for l in r["labels"]:
			var lab := Label3D.new()
			lab.text = l[1]
			lab.font_size = l[2]
			lab.pixel_size = 0.02
			lab.modulate = l[3]
			lab.outline_size = 10
			lab.outline_modulate = Color(0, 0, 0, 0.8)
			lab.position = l[0]
			lab.rotation.y = l[4]
			lab.visibility_range_end = LABEL_RANGE
			lab.double_sided = false
			node.add_child(lab)
		it["node"] = node
		it["state"] = 2
