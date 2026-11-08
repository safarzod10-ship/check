class_name CityStreamer
extends Node3D
## Streams the ~5800 generated buildings per 500 m sector:
##   detailed meshes near the camera, facade-shaded boxes far away, box collisions near the player.

const COLL_DIST := 260.0

var is_idle := false
var sectors: Dictionary = {}
var _results: Array = []
var _mutex := Mutex.new()
var _inflight := 0
var _timer := 0.0
var detail_dist := 600.0
var far_dist := 4000.0


func _ready() -> void:
	for key in WorldData.sector_index:
		if not WorldData.sector_index[key]["buildings"].is_empty():
			sectors[key] = {"near": null, "far": null, "body": null, "labels": null, "near_pending": false, "far_pending": false}
	GameSettings.changed.connect(_apply_settings)
	_apply_settings()


func _apply_settings() -> void:
	detail_dist = float(GameSettings.get_v("building_distance", 1100.0)) * 0.5
	far_dist = maxf(1500.0, float(GameSettings.get_v("view_distance", 7000.0)) * 0.75)


func _rect_dist(key: Vector2i, p: Vector3) -> float:
	var o := WorldData.sector_origin(key)
	var s := WorldData.SECTOR
	var dx := maxf(maxf(o.x - p.x, 0.0), p.x - (o.x + s))
	var dz := maxf(maxf(o.z - p.z, 0.0), p.z - (o.z + s))
	return sqrt(dx * dx + dz * dz)


func _process(delta: float) -> void:
	_apply_results()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.25
	var cam := GameState.view_position()
	var focus := GameState.focus_position()
	var todo: Array = []
	for key in sectors:
		var st: Dictionary = sectors[key]
		var d := _rect_dist(key, cam)
		var want_near := d < detail_dist
		if want_near and st["near"] == null and not st["near_pending"]:
			todo.append([d, key, true])
		elif not want_near and st["near"] != null and d > detail_dist + 120.0:
			st["near"].queue_free()
			st["near"] = null
			if st["labels"]:
				st["labels"].queue_free()
				st["labels"] = null
		var want_far := d < far_dist
		if want_far and st["far"] == null and not st["far_pending"]:
			todo.append([d + 1500.0, key, false])
		elif not want_far and st["far"] != null:
			st["far"].queue_free()
			st["far"] = null
		if st["far"] != null:
			st["far"].visible = st["near"] == null
		var need_coll := _rect_dist(key, focus) < COLL_DIST
		if need_coll and st["body"] == null:
			st["body"] = _make_collision(key)
		elif not need_coll and st["body"] != null:
			st["body"].queue_free()
			st["body"] = null
	todo.sort_custom(func(a, b): return a[0] < b[0])
	is_idle = todo.is_empty() and _inflight == 0
	for t in todo:
		if _inflight >= 3:
			break
		sectors[t[1]]["near_pending" if t[2] else "far_pending"] = true
		_inflight += 1
		WorkerThreadPool.add_task(_task.bind(t[1], t[2]))


func _task(key: Vector2i, near: bool) -> void:
	var kit := MeshKit.new()
	var labels: Array = []
	var org := WorldData.sector_origin(key)
	for bi in WorldData.sector_index[key]["buildings"]:
		var b: Array = WorldData.buildings[bi]
		if near:
			BuildingFactory.build_near(kit, b, org, labels)
		else:
			BuildingFactory.build_far(kit, b, org)
	_mutex.lock()
	_results.append({"key": key, "near": near, "kit": kit, "labels": labels})
	_mutex.unlock()


func _apply_results() -> void:
	_mutex.lock()
	var batch := _results.duplicate()
	_results.clear()
	_mutex.unlock()
	for res in batch:
		_inflight -= 1
		var key: Vector2i = res["key"]
		var st: Dictionary = sectors[key]
		var near: bool = res["near"]
		st["near_pending" if near else "far_pending"] = false
		var kit: MeshKit = res["kit"]
		if kit.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.name = ("CityNear_%d_%d" if near else "CityFar_%d_%d") % [key.x, key.y]
		mi.mesh = kit.build()
		mi.position = WorldData.sector_origin(key)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		if near:
			if st["near"]:
				st["near"].queue_free()
			st["near"] = mi
			if st["far"]:
				st["far"].visible = false
			st["labels"] = _make_labels(res["labels"], key)
		else:
			if st["far"]:
				st["far"].queue_free()
			st["far"] = mi
			mi.visible = st["near"] == null


func _make_labels(labels: Array, key: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.name = "Signs_%d_%d" % [key.x, key.y]
	root.position = WorldData.sector_origin(key)
	add_child(root)
	for l in labels:
		var lb := Label3D.new()
		lb.text = l[2]
		lb.position = l[0]
		lb.rotation.y = l[1]
		lb.font_size = 64
		lb.pixel_size = 0.012
		lb.modulate = l[3]
		lb.outline_size = 8
		lb.outline_modulate = Color(0, 0, 0, 0.6)
		lb.visibility_range_end = 140.0
		lb.double_sided = false
		root.add_child(lb)
	return root


func _make_collision(key: Vector2i) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "CityCol_%d_%d" % [key.x, key.y]
	body.collision_layer = 1
	body.collision_mask = 0
	var org := WorldData.sector_origin(key)
	body.position = org
	for bi in WorldData.sector_index[key]["buildings"]:
		var b: Array = WorldData.buildings[bi]
		var t := BuildingFactory.transform_of(b, org)
		var st: int = b[6]
		var w: float = b[3]
		var d: float = b[4]
		var h := BuildingFactory.height_of(b)
		if st == 5 or (st == 7 and w >= 15.0):
			# yard walls (gate left open) + house
			var wh := 3.0
			_box(body, t, Vector3(0, wh / 2 - 0.5, -d / 2), Vector3(w, wh, 0.5))
			_box(body, t, Vector3(w / 2, wh / 2 - 0.5, 0), Vector3(0.5, wh, d))
			_box(body, t, Vector3(-w / 2, wh / 2 - 0.5, 0), Vector3(0.5, wh, d))
			var side := (w / 2 - 1.8) * 0.5
			_box(body, t, Vector3(-(w / 2 + 1.8) / 2, wh / 2 - 0.5, d / 2), Vector3(side * 2.0 - 1.8 + 1.8, wh, 0.5))
			_box(body, t, Vector3((w / 2 + 1.8) / 2, wh / 2 - 0.5, d / 2), Vector3(side * 2.0, wh, 0.5))
			var hw := w * (0.62 if st == 5 else 0.7)
			var hd := minf(9.0, d * 0.42) if st == 5 else 6.5
			var hz := -d / 2 + hd / 2 + (1.0 if st == 5 else 0.8)
			_box(body, t, Vector3(0, h / 2, hz), Vector3(hw, h + 1.0, hd))
		else:
			_box(body, t, Vector3(0, h / 2 - 1.0, 0), Vector3(w, h + 2.0, d))
	add_child(body)
	return body


func _box(body: StaticBody3D, t: Transform3D, c: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.transform = t * Transform3D(Basis(), c)
	body.add_child(cs)
