class_name PropStreamer
extends Node3D
## Street furniture and roadside infrastructure per sector (near the camera only):
## street lamps, traffic lights, benches, bins, bus stops, billboards, street-name and direction signs,
## speed-limit signs, power lines along rural roads and highways, kilometre posts.
## At night a small pool of real OmniLights follows the closest lamps.

const ADS := ["ТОҶИКИСТОН — ДИЁРИ КӮҲҲО", "ДОБРО ПОЖАЛОВАТЬ В ДУШАНБЕ", "НОНИ ГАРМ — ҲАР РӮЗ", "ЧОЙИ КӮҲӢ",
	"БОНКИ МИЛЛӢ", "ВАРЗОБ — ИСТИРОҲАТ", "ПАХТА ВА ДЕҲҚОН", "МЕВАИ ТОҶИК", "ПАМИР ТЕЛЕКОМ", "СОМОНӢ-ТРАНС"]

var is_idle := false
var sectors: Dictionary = {}
var _results: Array = []
var _mutex := Mutex.new()
var _inflight := 0
var _timer := 0.0
var detail_dist := 450.0
var _lights: Array = []
var _light_timer := 0.0
var _tl_mat: ShaderMaterial
var _tl_by_sector: Dictionary = {}


func _ready() -> void:
	_tl_mat = ShaderMaterial.new()
	_tl_mat.shader = load("res://world/props/traffic_light.gdshader")
	for ri in WorldData.roads.size():
		WorldData.sample_flags(ri)
	for tl in WorldData.world.get("traffic_lights", []):
		var k := WorldData.sector_of(tl[0], tl[1])
		if not _tl_by_sector.has(k):
			_tl_by_sector[k] = []
		_tl_by_sector[k].append(tl)
	GameSettings.changed.connect(_apply_settings)
	_apply_settings()


func _apply_settings() -> void:
	detail_dist = float(GameSettings.get_v("detail_distance", 400.0)) + 100.0
	var n: int = GameSettings.get_v("street_lights", 8)
	while _lights.size() < n:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.82, 0.55)
		l.omni_range = 22.0
		l.light_energy = 2.2
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)
	while _lights.size() > n:
		_lights.pop_back().queue_free()


func _rect_dist(key: Vector2i, p: Vector3) -> float:
	var o := WorldData.sector_origin(key)
	var s := WorldData.SECTOR
	var dx := maxf(maxf(o.x - p.x, 0.0), p.x - (o.x + s))
	var dz := maxf(maxf(o.z - p.z, 0.0), p.z - (o.z + s))
	return sqrt(dx * dx + dz * dz)


func _process(delta: float) -> void:
	_apply_results()
	_update_lights(delta)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.3
	var cam := GameState.view_position()
	var todo: Array = []
	for key in WorldData.sector_index:
		var d := _rect_dist(key, cam)
		var st: Dictionary = sectors.get(key, {})
		if d < detail_dist:
			if st.is_empty():
				sectors[key] = {"node": null, "pending": true, "lamps": PackedVector3Array()}
				todo.append([d, key])
		elif not st.is_empty() and d > detail_dist + 100.0 and not st["pending"]:
			if st["node"]:
				st["node"].queue_free()
			sectors.erase(key)
	todo.sort_custom(func(a, b): return a[0] < b[0])
	is_idle = todo.is_empty() and _inflight == 0
	for t in todo:
		_inflight += 1
		WorkerThreadPool.add_task(_task.bind(t[1]))


func _task(key: Vector2i) -> void:
	var res := build_sector(key)
	_mutex.lock()
	_results.append([key, res])
	_mutex.unlock()


func _apply_results() -> void:
	_mutex.lock()
	var batch := _results.duplicate()
	_results.clear()
	_mutex.unlock()
	for r in batch:
		_inflight -= 1
		var key: Vector2i = r[0]
		if not sectors.has(key):
			continue
		var res: Dictionary = r[1]
		var root := Node3D.new()
		root.name = "Props_%d_%d" % [key.x, key.y]
		root.position = WorldData.sector_origin(key)
		var kit: MeshKit = res["kit"]
		if not kit.is_empty():
			var mi := MeshInstance3D.new()
			mi.mesh = kit.build({"traffic_light": _tl_mat})
			root.add_child(mi)
		for l in res["labels"]:
			var lb := Label3D.new()
			lb.text = l[2]
			lb.position = l[0]
			lb.rotation.y = l[1]
			lb.font_size = int(l[4]) if l.size() > 4 else 48
			lb.pixel_size = 0.01
			lb.modulate = l[3]
			lb.outline_size = 0
			lb.double_sided = false
			lb.visibility_range_end = 120.0
			root.add_child(lb)
		var body := StaticBody3D.new()
		body.collision_layer = 1 << (GameState.LAYER_PROP - 1)
		body.collision_mask = 0
		for c in res["colliders"]:
			var cs := CollisionShape3D.new()
			var shape := CylinderShape3D.new()
			shape.radius = c[1]
			shape.height = c[2]
			cs.shape = shape
			cs.position = c[0] + Vector3(0, c[2] * 0.5, 0)
			body.add_child(cs)
		root.add_child(body)
		add_child(root)
		sectors[key]["node"] = root
		sectors[key]["pending"] = false
		sectors[key]["lamps"] = res["lamps"]


func _update_lights(delta: float) -> void:
	_light_timer -= delta
	if _light_timer > 0.0:
		return
	_light_timer = 0.5
	var night := TimeWeather.night_factor > 0.3
	if not night or _lights.is_empty():
		for l in _lights:
			l.visible = false
		return
	var cam := GameState.view_position()
	var cand: Array = []
	for key in sectors:
		var st: Dictionary = sectors[key]
		var org := WorldData.sector_origin(key)
		for p in st["lamps"]:
			var wp: Vector3 = p + org
			var d := wp.distance_squared_to(cam)
			if d < 160.0 * 160.0:
				cand.append([d, wp])
	cand.sort_custom(func(a, b): return a[0] < b[0])
	for i in _lights.size():
		if i < cand.size():
			_lights[i].global_position = cand[i][1] - Vector3(0, 0.6, 0)
			_lights[i].visible = true
		else:
			_lights[i].visible = false


# ---------------------------------------------------------------------------
# Geometry (worker thread)
# ---------------------------------------------------------------------------
func build_sector(key: Vector2i) -> Dictionary:
	var kit := MeshKit.new()
	var labels: Array = []
	var colliders: Array = []
	var lamps := PackedVector3Array()
	var org := WorldData.sector_origin(key)
	var sd: Dictionary = WorldData.sector_index.get(key, {})
	var types: Dictionary = WorldData.world["road_types"]
	var rng := RandomNumberGenerator.new()
	rng.seed = key.x * 31337 + key.y * 7331
	for run in sd.get("road_runs", []):
		var ri: int = run[0]
		var road: Dictionary = WorldData.roads[ri]
		var t: String = road["type"]
		var rt: Dictionary = types[t]
		var pts: Array = road["pts"]
		var fl: PackedByteArray = WorldData.sample_flags(ri)
		var half: float = rt["half"]
		var sw: float = rt["sidewalk"]
		var swcut: Array = road.get("swcut", [])
		var city := sw > 0.0
		var a := int(run[1])
		var b := int(run[2])
		for si in range(a, b):
			if (fl[si] & 2) != 0:
				continue
			var p := Vector3(pts[si][0], float(pts[si][1]) + WorldData.ROAD_LIFT, pts[si][2])
			var tg := WorldData.road_tangent(ri, si)
			var right := tg.cross(Vector3.UP).normalized()
			var yaw := atan2(tg.x, tg.z)
			var near_cut := false
			for c in swcut:
				if si >= int(c[0]) - 1 and si <= int(c[1]) + 1:
					near_cut = true
					break
			if city:
				var curb_y := p.y + 0.15
				# street lamps every ~32 m, alternating sides
				if si % 8 == 0 and not near_cut and (fl[si] & 4) == 0:
					var side := 1.0 if (si / 8) % 2 == 0 else -1.0
					if t == "avenue":
						side = 1.0
					for s2 in ([side] if t != "avenue" else [-1.0, 1.0]):
						var lp: Vector3 = p + right * (half + 0.5) * s2
						lp.y = curb_y
						_lamp(kit, lp - org, yaw + (PI if s2 > 0 else 0.0), lamps, colliders)
				# bench + bin every ~60 m on wide sidewalks
				if si % 15 == 7 and sw >= 4.0 and not near_cut and (fl[si] & 5) == 0:
					var bp := p + right * (half + sw - 0.8)
					bp.y = curb_y
					_bench(kit, bp - org, yaw + PI * 0.5)
					var bp2 := p + right * (half + sw - 0.6) + tg * 2.0
					bp2.y = curb_y
					_bin(kit, bp2 - org)
				# bus stops on avenues / boulevards
				if (t == "avenue" or t == "boulevard") and si % 100 == 50 and not near_cut and fl[si] == 0:
					var sp := p + right * (half + sw - 1.2)
					sp.y = curb_y
					_bus_stop(kit, sp - org, yaw, labels, colliders)
				# street name plates near intersections
				if near_cut and si > 0 and (fl[si - 1] & 4) == 0:
					var is_first := true
					for c in swcut:
						if si == int(c[0]) - 1:
							is_first = true
					if is_first and rng.randf() < 0.5:
						var np := p + right * (half + 0.6)
						np.y = curb_y
						_street_sign(kit, np - org, yaw, str(road["name"]), labels)
			else:
				# rural roads & highways: power line, km posts, occasional billboard
				if (t == "highway" or t == "rural") and si % 12 == 0 and (fl[si] & 1) == 0:
					var pp := p + right * (half + 6.0)
					pp.y = WorldData.height_at(pp.x, pp.z)
					var prev_si := si - 12
					var pp_prev := Vector3.ZERO
					if prev_si >= a:
						var q := Vector3(pts[prev_si][0], 0, pts[prev_si][2])
						var r2 := WorldData.road_tangent(ri, prev_si).cross(Vector3.UP).normalized()
						pp_prev = q + r2 * (half + 6.0)
						pp_prev.y = WorldData.height_at(pp_prev.x, pp_prev.z)
					_power_pole(kit, pp - org, yaw, (pp_prev - org) if prev_si >= a else Vector3.INF, colliders)
				if t == "highway" and si % 250 == 125 and (fl[si] & 1) == 0:
					var bb := p + right * (half + 14.0) * (1.0 if rng.randf() < 0.5 else -1.0)
					bb.y = WorldData.height_at(bb.x, bb.z)
					_billboard(kit, bb - org, yaw, ADS[rng.randi() % ADS.size()], labels, colliders)
				if (t == "highway" or t == "mountain") and si % 250 == 0 and (fl[si] & 3) == 0:
					var kp := p + right * (half + 1.8)
					kp.y = WorldData.height_at(kp.x, kp.z)
					kit.box_yaw("plain", kp - org, yaw, Vector3(0.25, 1.0, 0.12), Color(0.95, 0.95, 0.95))
					kit.box_yaw("plain", kp - org + Vector3(0, 0.7, 0), yaw, Vector3(0.26, 0.2, 0.13), Color(0.1, 0.1, 0.1))
				# speed limit / curve warning signs on mountain roads
				if t == "mountain" and si % 60 == 30 and (fl[si] & 3) == 0:
					var sp2 := p + right * (half + 1.6)
					sp2.y = WorldData.height_at(sp2.x, sp2.z)
					_round_sign(kit, sp2 - org, yaw, "40", labels)
	# traffic lights at intersections in this sector
	for tl in _tl_by_sector.get(key, []):
		_traffic_light(kit, tl, org, colliders)
	# direction signs at highway starts
	for ri in range(WorldData.roads.size()):
		pass
	return {"kit": kit, "labels": labels, "colliders": colliders, "lamps": lamps}


func _lamp(kit: MeshKit, p: Vector3, yaw: float, lamps: PackedVector3Array, colliders: Array) -> void:
	var pole := Color(0.32, 0.34, 0.36)
	kit.cylinder("metal", Transform3D(Basis(), p), 0.1, 0.07, 8.5, 6, pole)
	var arm_dir := Vector3(sin(yaw), 0, cos(yaw))
	var t := Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, 8.3, 0))
	kit.box("metal", t, Vector3(0, 0, 0.9), Vector3(0.08, 0.08, 1.8), pole)
	kit.box("metal", t, Vector3(0, -0.05, 1.8), Vector3(0.35, 0.18, 0.7), pole)
	kit.box("lamp", t, Vector3(0, -0.16, 1.8), Vector3(0.3, 0.05, 0.6), Color(1.0, 0.85, 0.6))
	lamps.append(p + Vector3(0, 8.2, 0) + arm_dir * 1.8)
	colliders.append([p, 0.12, 8.0])


func _bench(kit: MeshKit, p: Vector3, yaw: float) -> void:
	var t := Transform3D(Basis(Vector3.UP, yaw), p)
	var wood := Color(0.55, 0.38, 0.22)
	var iron := Color(0.2, 0.22, 0.2)
	kit.box("wood", t, Vector3(0, 0.45, 0), Vector3(1.8, 0.06, 0.45), wood)
	kit.box("wood", t, Vector3(0, 0.8, -0.22), Vector3(1.8, 0.35, 0.05), wood)
	kit.box("metal", t, Vector3(-0.8, 0.22, 0), Vector3(0.06, 0.45, 0.45), iron)
	kit.box("metal", t, Vector3(0.8, 0.22, 0), Vector3(0.06, 0.45, 0.45), iron)


func _bin(kit: MeshKit, p: Vector3) -> void:
	kit.cylinder("metal", Transform3D(Basis(), p), 0.25, 0.28, 0.85, 8, Color(0.25, 0.45, 0.3), true, false)


func _bus_stop(kit: MeshKit, p: Vector3, yaw: float, labels: Array, colliders: Array) -> void:
	var t := Transform3D(Basis(Vector3.UP, yaw), p)
	var frame := Color(0.3, 0.4, 0.55)
	kit.box("metal", t, Vector3(0, 2.6, 0), Vector3(1.8, 0.12, 5.0), frame)
	for z in [-2.3, 2.3]:
		kit.box("metal", t, Vector3(0.75, 1.3, z), Vector3(0.1, 2.6, 0.1), frame)
		kit.box("metal", t, Vector3(-0.75, 1.3, z), Vector3(0.1, 2.6, 0.1), frame)
	kit.box("glass", t, Vector3(0.78, 1.4, 0), Vector3(0.04, 2.2, 4.6), Color(0.6, 0.7, 0.75))
	kit.box("wood", t, Vector3(0.4, 0.45, 0), Vector3(0.45, 0.06, 3.5), Color(0.55, 0.38, 0.22))
	kit.box("plain", t, Vector3(0, 2.85, 0), Vector3(0.3, 0.4, 2.0), Color(0.15, 0.4, 0.75))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	labels.append([p + Vector3(0, 2.85, 0) - right * 0.16, yaw - PI * 0.5, "ИСТГОҲ • ОСТАНОВКА", Color(1, 1, 1), 40])
	colliders.append([p + right * 0.75, 0.15, 2.6])


func _street_sign(kit: MeshKit, p: Vector3, yaw: float, name: String, labels: Array) -> void:
	kit.cylinder("metal", Transform3D(Basis(), p), 0.05, 0.05, 2.9, 5, Color(0.5, 0.5, 0.5))
	var t := Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), p + Vector3(0, 2.7, 0))
	var w := clampf(name.length() * 0.13 + 0.4, 1.2, 3.6)
	kit.box("plain", t, Vector3(w * 0.5, 0, 0), Vector3(w, 0.35, 0.04), Color(0.1, 0.35, 0.65))
	var tt := Basis(Vector3.UP, yaw + PI * 0.5)
	labels.append([p + Vector3(0, 2.7, 0) + tt.x * w * 0.5 + tt.z * 0.03, yaw + PI * 0.5, name, Color(1, 1, 1), 30])
	labels.append([p + Vector3(0, 2.7, 0) + tt.x * w * 0.5 - tt.z * 0.03, yaw - PI * 0.5, name, Color(1, 1, 1), 30])


func _round_sign(kit: MeshKit, p: Vector3, yaw: float, text: String, labels: Array) -> void:
	kit.cylinder("metal", Transform3D(Basis(), p), 0.04, 0.04, 2.3, 5, Color(0.6, 0.6, 0.6))
	var t := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, PI * 0.5), p + Vector3(0, 2.3, 0))
	kit.cylinder("plain", t, 0.35, 0.35, 0.03, 12, Color(0.85, 0.1, 0.1), true, true)
	kit.cylinder("plain", t * Transform3D(Basis(), Vector3(0, -0.01, 0)), 0.27, 0.27, 0.05, 12, Color(1, 1, 1), true, true)
	labels.append([p + Vector3(0, 2.3, 0) - Vector3(sin(yaw), 0, cos(yaw)) * 0.05, yaw + PI, text, Color(0, 0, 0), 40])


func _billboard(kit: MeshKit, p: Vector3, yaw: float, text: String, labels: Array, colliders: Array) -> void:
	var t := Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), p)
	var steel := Color(0.4, 0.42, 0.44)
	kit.cylinder("metal", Transform3D(Basis(), p + t.basis.x * -3.0), 0.2, 0.2, 7.0, 6, steel)
	kit.cylinder("metal", Transform3D(Basis(), p + t.basis.x * 3.0), 0.2, 0.2, 7.0, 6, steel)
	kit.box("plain", t, Vector3(0, 8.5, 0), Vector3(12.0, 4.0, 0.3), Color(0.95, 0.95, 0.92))
	kit.box("plain", t, Vector3(0, 8.5, 0.16), Vector3(11.4, 3.4, 0.02), Color.from_hsv(randf(), 0.6, 0.85))
	labels.append([p + Vector3(0, 8.5, 0) + t.basis.z * 0.2, yaw + PI * 0.5, text, Color(1, 1, 1), 96])
	labels.append([p + Vector3(0, 8.5, 0) - t.basis.z * 0.2, yaw - PI * 0.5, text, Color(0.2, 0.2, 0.2), 96])
	colliders.append([p + t.basis.x * -3.0, 0.25, 7.0])
	colliders.append([p + t.basis.x * 3.0, 0.25, 7.0])


func _power_pole(kit: MeshKit, p: Vector3, yaw: float, prev: Vector3, colliders: Array) -> void:
	var wood := Color(0.42, 0.34, 0.26)
	kit.cylinder("concrete", Transform3D(Basis(), p), 0.16, 0.11, 9.0, 6, Color(0.75, 0.74, 0.7))
	var t := Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), p + Vector3(0, 8.6, 0))
	kit.box("wood", t, Vector3(0, 0, 0), Vector3(2.4, 0.12, 0.12), wood)
	colliders.append([p, 0.18, 9.0])
	if prev == Vector3.INF:
		return
	# three sagging wires to the previous pole
	for off in [-1.1, 0.0, 1.1]:
		var a: Vector3 = p + Vector3(0, 8.7, 0) + t.basis.x * off
		var tp := Transform3D(Basis(Vector3.UP, yaw + PI * 0.5), prev + Vector3(0, 8.7, 0))
		var b: Vector3 = prev + Vector3(0, 8.7, 0) + tp.basis.x * off
		var seg := 6
		var L := PackedVector3Array()
		var R := PackedVector3Array()
		for k in seg + 1:
			var f := float(k) / seg
			var q: Vector3 = a.lerp(b, f) - Vector3(0, sin(f * PI) * 0.9, 0)
			L.append(q)
			R.append(q + Vector3(0, 0.03, 0))
		kit.ribbon("metal", L, R, Color(0.15, 0.15, 0.15))
		kit.ribbon("metal", R, L, Color(0.15, 0.15, 0.15))


func _traffic_light(kit: MeshKit, tl: Array, org: Vector3, colliders: Array) -> void:
	var c := Vector3(tl[0], 0, tl[1])
	var nr := WorldData.nearest_road(c.x, c.z, 40.0)
	if nr.is_empty():
		return
	var ri: int = nr["road"]
	var rt: Dictionary = WorldData.road_type(ri)
	var tg := WorldData.road_tangent(ri, nr["index"])
	var right := tg.cross(Vector3.UP).normalized()
	var y: float = nr["pos"].y + WorldData.ROAD_LIFT + 0.15
	var off: float = float(rt["half"]) + 1.0
	var corners := [c + right * off + tg * (off + 2.0), c - right * off - tg * (off + 2.0)]
	var phase := 0
	for p in corners:
		p.y = y
		var yaw := atan2(tg.x, tg.z) + (0.0 if phase == 0 else PI)
		var lp: Vector3 = p - org
		var pole := Color(0.25, 0.27, 0.28)
		kit.cylinder("metal", Transform3D(Basis(), lp), 0.09, 0.09, 6.0, 6, pole)
		var t := Transform3D(Basis(Vector3.UP, yaw), lp + Vector3(0, 5.8, 0))
		var reach: float = off * 0.8
		kit.box("metal", t, Vector3(-reach * 0.5 * (1.0 if phase == 0 else 1.0), 0, 0), Vector3(reach, 0.12, 0.12), pole)
		var head := t * Transform3D(Basis(), Vector3(-reach + 0.3, -0.7, 0))
		kit.box("metal", head, Vector3(0, 0, 0), Vector3(0.38, 1.1, 0.3), Color(0.12, 0.12, 0.12))
		for li in 3:
			var col: Color = [Color(1, 0.1, 0.05, 0.0), Color(1, 0.75, 0.05, 0.5), Color(0.1, 1, 0.3, 1.0)][li]
			kit.uv2 = Vector2(float(phase) * 0.5, 0)
			kit.sphere("traffic_light", head * Transform3D(Basis(), Vector3(0, 0.33 - li * 0.33, 0.16)), 0.1, 3, 6, col)
			kit.sphere("traffic_light", head * Transform3D(Basis(), Vector3(0, 0.33 - li * 0.33, -0.16)), 0.1, 3, 6, col)
			kit.uv2 = Vector2.ZERO
		colliders.append([lp, 0.12, 6.0])
		phase += 1
