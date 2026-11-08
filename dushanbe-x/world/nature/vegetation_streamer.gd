class_name VegetationStreamer
extends Node3D
## Trees, bushes, rocks, street trees, orchards and vineyards per 500 m sector (MultiMesh),
## plus the grass field around the player (GrassField child).

const NEAR_DIST := 130.0
const RASTER := 2.5
const RN := 200                   # raster cells per sector side (500 / 2.5)

var is_idle := false
var sectors: Dictionary = {}       # key -> {data, near_nodes:[], far_nodes:[], pending}
var _results: Array = []
var _mutex := Mutex.new()
var _inflight := 0
var _timer := 0.0
var tree_distance := 1400.0
var _pads: Array = []
var grass: Node3D


func _ready() -> void:
	TreeLibrary.ensure()
	for ri in WorldData.roads.size():
		WorldData.sample_flags(ri)   # warm the cache on the main thread (read from workers later)
	for lm in WorldData.landmarks:
		_pads.append(Rect2(float(lm["x"]) - float(lm["pad"][0]), float(lm["z"]) - float(lm["pad"][1]),
			float(lm["pad"][0]) * 2.0, float(lm["pad"][1]) * 2.0))
	for p in WorldData.pois:
		_pads.append(Rect2(float(p["x"]) - 30.0, float(p["z"]) - 30.0, 60.0, 60.0))
	GameSettings.changed.connect(_apply_settings)
	_apply_settings()
	grass = load("res://world/nature/grass_field.gd").new()
	grass.name = "Grass"
	add_child(grass)


func _apply_settings() -> void:
	tree_distance = GameSettings.get_v("tree_distance", 1400.0)


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
	var todo: Array = []
	for j in WorldData.sectors_n:
		for i in WorldData.sectors_n:
			var key := Vector2i(i, j)
			var d := _rect_dist(key, cam)
			var st: Dictionary = sectors.get(key, {})
			if d < tree_distance:
				if st.is_empty():
					st = {"data": null, "near": [], "far": [], "pending": false}
					sectors[key] = st
				if st["data"] == null:
					if not st["pending"]:
						todo.append([d, key])
					continue
				var want_near := d < NEAR_DIST
				if want_near and st["near"].is_empty():
					st["near"] = _instantiate(key, st["data"], true)
				elif not want_near and not st["near"].is_empty() and d > NEAR_DIST + 60.0:
					for n in st["near"]:
						n.queue_free()
					st["near"] = []
				if st["far"].is_empty():
					st["far"] = _instantiate(key, st["data"], false)
				for n in st["far"]:
					n.visible = st["near"].is_empty()
			elif not st.is_empty() and d > tree_distance + 200.0 and not st["pending"]:
				for n in st["near"] + st["far"]:
					n.queue_free()
				sectors.erase(key)
	todo.sort_custom(func(a, b): return a[0] < b[0])
	is_idle = todo.is_empty() and _inflight == 0 and (grass == null or grass.is_idle)
	for t in todo:
		if _inflight >= 2:
			break
		sectors[t[1]]["pending"] = true
		_inflight += 1
		WorkerThreadPool.add_task(_task.bind(t[1]))


func _task(key: Vector2i) -> void:
	var data := place_sector(key)
	_mutex.lock()
	_results.append([key, data])
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
		sectors[key]["data"] = r[1]
		sectors[key]["pending"] = false


func _instantiate(key: Vector2i, data: Dictionary, near: bool) -> Array:
	var nodes: Array = []
	var org := WorldData.sector_origin(key)
	for sp in data["inst"]:
		var buf: PackedFloat32Array = data["inst"][sp]
		var count := buf.size() / 16
		if count == 0:
			continue
		if not near and (sp == "rock" or sp == "bush"):
			continue
		if not near:
			buf = _thin(buf, 2, 1.15)
			count = buf.size() / 16
			if count == 0:
				continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.mesh = TreeLibrary.near_meshes[sp] if near else TreeLibrary.far_meshes[sp]
		mm.instance_count = count
		mm.buffer = buf
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = org
		mmi.name = "%s_%s_%d_%d" % [sp, "n" if near else "f", key.x, key.y]
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if near else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)
		nodes.append(mmi)
	if near and data["kit"] != null and not data["kit"].is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = data["kit"].build()
		mi.position = org
		mi.name = "Rows_%d_%d" % [key.x, key.y]
		add_child(mi)
		nodes.append(mi)
	return nodes


## Keeps every `keep_every`-th instance and scales the kept ones (far LOD density reduction).
func _thin(buf: PackedFloat32Array, keep_every: int, scale: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := buf.size() / 16
	for i in range(0, n, keep_every):
		var o := i * 16
		for c in 12:
			var v := buf[o + c]
			if c != 3 and c != 7 and c != 11:
				v *= scale
			out.append(v)
		for c in range(12, 16):
			out.append(buf[o + c])
	return out


# ---------------------------------------------------------------------------
# Placement (worker thread)
# ---------------------------------------------------------------------------
func place_sector(key: Vector2i) -> Dictionary:
	var org := WorldData.sector_origin(key)
	var rng := RandomNumberGenerator.new()
	rng.seed = key.x * 7919 + key.y * 104729 + 11
	var blocked := _raster(key, org)
	var inst: Dictionary = {}
	for sp in TreeLibrary.SPECIES:
		inst[sp] = PackedFloat32Array()
	var step := 9.0
	var nstep := int(WorldData.SECTOR / step)
	for gj in nstep:
		for gi in nstep:
			var lx := (gi + rng.randf()) * step
			var lz := (gj + rng.randf()) * step
			var x := org.x + lx
			var z := org.z + lz
			var roll := rng.randf()
			var roll2 := rng.randf()
			if _is_blocked(blocked, lx, lz):
				continue
			var veg := WorldData.veg_at(x, z)
			var sp := WorldData.splat_at(x, z)
			var h := WorldData.height_at(x, z)
			var nrm := WorldData.normal_at(x, z)
			var slope := 1.0 - nrm.y
			var forest := veg.r
			var orchard := veg.g
			var species := ""
			var scale := rng.randf_range(0.75, 1.25)
			if roll < forest * 0.62 and slope < 0.55 and h < 1900.0:
				if h > 1100.0:
					species = "archa" if roll2 < 0.75 else "pine"
				elif h > 450.0:
					species = "archa" if roll2 < 0.4 else ("walnut" if roll2 < 0.7 else ("pine" if roll2 < 0.85 else "bush"))
				elif sp.a > 0.2:
					species = "willow" if roll2 < 0.45 else ("poplar" if roll2 < 0.8 else "bush")
				elif sp.b > 0.3:
					species = "chinar" if roll2 < 0.55 else ("poplar" if roll2 < 0.75 else "apricot")
				else:
					species = "walnut" if roll2 < 0.3 else ("chinar" if roll2 < 0.55 else ("poplar" if roll2 < 0.75 else ("apricot" if roll2 < 0.85 else "bush")))
			elif roll < orchard * 0.5 and slope < 0.3:
				species = "apricot" if roll2 < 0.8 else "walnut"
			elif roll < veg.a * 0.05 + forest * 0.15 and slope < 0.7:
				species = "bush"
				scale = rng.randf_range(0.6, 1.4)
			elif slope > 0.32 and roll < (slope - 0.3) * 0.5:
				species = "rock" if roll2 < 0.8 else "boulder"
				scale = rng.randf_range(0.6, 2.2)
			elif sp.a > 0.4 and roll < 0.12:
				species = "boulder" if roll2 < 0.3 else "rock"
				scale = rng.randf_range(0.4, 1.3)
			elif h > 250.0 and roll < 0.015:
				species = "boulder" if roll2 < 0.4 else "rock"
				scale = rng.randf_range(0.5, 2.5)
			if species == "":
				continue
			var y := h - org.y - (0.15 if species != "boulder" else 0.6 * scale)
			_push(inst[species], Vector3(lx, y, lz), rng.randf() * TAU, scale, rng.randf(),
				nrm if (species == "rock" or species == "boulder") else Vector3.UP)
	var kit := MeshKit.new()
	_street_trees(key, org, inst, rng)
	_parcels(key, org, inst, kit, rng)
	return {"inst": inst, "kit": kit}


func _push(buf: PackedFloat32Array, p: Vector3, yaw: float, s: float, tint: float, up := Vector3.UP) -> void:
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s))
	if up != Vector3.UP:
		var q := Quaternion(Vector3.UP, up.normalized())
		b = Basis(q) * b
	buf.append_array([b.x.x, b.y.x, b.z.x, p.x, b.x.y, b.y.y, b.z.y, p.y, b.x.z, b.y.z, b.z.z, p.z, tint, 0.0, 0.0, 0.0])


func _is_blocked(r: PackedByteArray, lx: float, lz: float) -> bool:
	var i := clampi(int(lx / RASTER), 0, RN - 1)
	var j := clampi(int(lz / RASTER), 0, RN - 1)
	return r[j * RN + i] != 0


func _mark(r: PackedByteArray, lx: float, lz: float, rad: float) -> void:
	var c := int(ceil(rad / RASTER))
	var ci := int(lx / RASTER)
	var cj := int(lz / RASTER)
	for dj in range(-c, c + 1):
		var j := cj + dj
		if j < 0 or j >= RN:
			continue
		for di in range(-c, c + 1):
			var i := ci + di
			if i < 0 or i >= RN:
				continue
			if (di * di + dj * dj) * RASTER * RASTER <= rad * rad:
				r[j * RN + i] = 1


## Occupancy raster of roads, buildings, pads (2.5 m cells) for this sector.
func _raster(key: Vector2i, org: Vector3) -> PackedByteArray:
	var r := PackedByteArray()
	r.resize(RN * RN)
	var types: Dictionary = WorldData.world["road_types"]
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var k := Vector2i(key.x + di, key.y + dj)
			var sd: Dictionary = WorldData.sector_index.get(k, {})
			if sd.is_empty():
				continue
			for run in sd["road_runs"]:
				var road: Dictionary = WorldData.roads[run[0]]
				var rt: Dictionary = types[road["type"]]
				var rad: float = float(rt["half"]) + float(rt["sidewalk"]) + 2.0
				var pts: Array = road["pts"]
				for si in range(int(run[1]), int(run[2]) + 1):
					var lx: float = float(pts[si][0]) - org.x
					var lz: float = float(pts[si][2]) - org.z
					if lx < -rad or lz < -rad or lx > 500.0 + rad or lz > 500.0 + rad:
						continue
					_mark(r, lx, lz, rad)
			for bi in sd["buildings"]:
				var b: Array = WorldData.buildings[bi]
				var lx2: float = float(b[0]) - org.x
				var lz2: float = float(b[1]) - org.z
				var w: float = b[3]
				var d: float = b[4]
				var rad2 := sqrt(w * w + d * d) * 0.5 + 2.0
				if lx2 < -rad2 or lz2 < -rad2 or lx2 > 500.0 + rad2 or lz2 > 500.0 + rad2:
					continue
				var a := -deg_to_rad(float(b[2]))
				var ax := Vector2(cos(a), -sin(a))     # local X in world (x,z)
				var az := Vector2(sin(a), cos(a))      # local Z in world (x,z)
				var c := int(ceil(rad2 / RASTER))
				var ci := int(lx2 / RASTER)
				var cj := int(lz2 / RASTER)
				var shrink := 0.0 if (b[6] != 5 and b[6] != 7) else 0.0
				for jj in range(-c, c + 1):
					var j := cj + jj
					if j < 0 or j >= RN:
						continue
					for ii in range(-c, c + 1):
						var i := ci + ii
						if i < 0 or i >= RN:
							continue
						var rel := Vector2((i + 0.5) * RASTER - lx2, (j + 0.5) * RASTER - lz2)
						if absf(rel.dot(ax)) < w * 0.5 + 1.5 - shrink and absf(rel.dot(az)) < d * 0.5 + 1.5:
							r[j * RN + i] = 1
	var sector_rect := Rect2(org.x, org.z, WorldData.SECTOR, WorldData.SECTOR)
	for pad in _pads:
		if not sector_rect.intersects(pad):
			continue
		var ri: Rect2 = pad.intersection(sector_rect)
		for j in range(int((ri.position.y - org.z) / RASTER), mini(RN, int((ri.end.y - org.z) / RASTER) + 1)):
			for i in range(int((ri.position.x - org.x) / RASTER), mini(RN, int((ri.end.x - org.x) / RASTER) + 1)):
				r[j * RN + i] = 1
	return r


func _street_trees(key: Vector2i, org: Vector3, inst: Dictionary, rng: RandomNumberGenerator) -> void:
	var types: Dictionary = WorldData.world["road_types"]
	var runs: Array = []
	for dj in range(-1, 2):
		for di in range(-1, 2):
			runs.append_array(WorldData.sector_index.get(Vector2i(key.x + di, key.y + dj), {}).get("road_runs", []))
	for run in runs:
		var road: Dictionary = WorldData.roads[run[0]]
		var t: String = road["type"]
		if not (t == "avenue" or t == "boulevard" or t == "street"):
			continue
		var rt: Dictionary = types[t]
		var off: float = float(rt["half"]) + float(rt["sidewalk"]) - 0.9
		var pts: Array = road["pts"]
		var fl: PackedByteArray = WorldData.sample_flags(run[0])
		var swcut: Array = road.get("swcut", [])
		var spacing := 3 if t == "avenue" else 4
		for si in range(int(run[1]) + 1, int(run[2]), spacing):
			if fl[si] != 0:
				continue
			var cut := false
			for c in swcut:
				if si >= int(c[0]) - 2 and si <= int(c[1]) + 2:
					cut = true
					break
			if cut:
				continue
			var tg := WorldData.road_tangent(run[0], si)
			var right := tg.cross(Vector3.UP).normalized()
			for side in [-1.0, 1.0]:
				var keep := rng.randf() >= 0.15
				var sp_roll := rng.randf()
				var sc_roll := rng.randf()
				var yaw_roll := rng.randf()
				if not keep:
					continue
				var p: Vector3 = Vector3(pts[si][0], float(pts[si][1]) + WorldData.ROAD_LIFT + 0.1, pts[si][2]) + right * off * side - org
				if p.x < 0 or p.z < 0 or p.x >= 500.0 or p.z >= 500.0:
					continue
				var sp := "chinar" if t == "avenue" else ("poplar" if sp_roll < 0.35 else "chinar")
				var sc := lerpf(0.65, 1.0, sc_roll) if sp == "chinar" else lerpf(0.8, 1.1, sc_roll)
				_push(inst[sp], p, yaw_roll * TAU, sc, sc_roll * 0.5)


func _parcels(key: Vector2i, org: Vector3, inst: Dictionary, kit: MeshKit, rng: RandomNumberGenerator) -> void:
	var sd: Dictionary = WorldData.sector_index.get(key, {})
	for pi in sd.get("parcels", []):
		var pc: Array = WorldData.parcels[pi]
		var cx: float = pc[0]
		var cz: float = pc[1]
		var a := deg_to_rad(float(pc[2]))
		var w: float = pc[3]
		var d: float = pc[4]
		var code: int = pc[5]
		var ax := Vector3(cos(a), 0, sin(a))
		var az := Vector3(-sin(a), 0, cos(a))
		var row_sp := 6.0 if code == 6 else 3.0
		var rows := int(d / row_sp)
		for ri in rows:
			var v := -d * 0.5 + row_sp * (ri + 0.5)
			if code == 6:
				var n := int(w / 6.0)
				for ti in n:
					var u := -w * 0.5 + 6.0 * (ti + 0.5)
					var wp := Vector3(cx, 0, cz) + ax * u + az * v
					var p := Vector3(wp.x, WorldData.height_at(wp.x, wp.z) - 0.1, wp.z) - org
					_push(inst["apricot"], p, rng.randf() * TAU, rng.randf_range(0.8, 1.15), rng.randf())
			else:
				# vineyard row: posts every 6 m + a continuous leafy band on a wire
				var a0 := Vector3(cx, 0, cz) + ax * (-w * 0.5 + 1.0) + az * v
				var a1 := Vector3(cx, 0, cz) + ax * (w * 0.5 - 1.0) + az * v
				var seg := int((w - 2.0) / 6.0)
				for si in seg:
					var p0 := a0.lerp(a1, float(si) / seg)
					var p1 := a0.lerp(a1, float(si + 1) / seg)
					var h0 := WorldData.height_at(p0.x, p0.z)
					var h1 := WorldData.height_at(p1.x, p1.z)
					var q0 := Vector3(p0.x, h0, p0.z) - org
					var q1 := Vector3(p1.x, h1, p1.z) - org
					kit.box_yaw("wood", q0 - Vector3(0, 0.2, 0), -a, Vector3(0.1, 1.9, 0.1), Color(0.5, 0.4, 0.3))
					var side := az * 0.35
					var g := Color(0.3, 0.48, 0.18).lightened(rng.randf() * 0.1)
					kit.quad("foliage", q0 - side + Vector3(0, 0.6, 0), q1 - side + Vector3(0, 0.6, 0), q1 - side * 0.2 + Vector3(0, 1.7, 0), q0 - side * 0.2 + Vector3(0, 1.7, 0), g)
					kit.quad("foliage", q1 + side + Vector3(0, 0.6, 0), q0 + side + Vector3(0, 0.6, 0), q0 + side * 0.2 + Vector3(0, 1.7, 0), q1 + side * 0.2 + Vector3(0, 1.7, 0), g)
					kit.quad("foliage", q0 - side * 0.2 + Vector3(0, 1.7, 0), q1 - side * 0.2 + Vector3(0, 1.7, 0), q1 + side * 0.2 + Vector3(0, 1.7, 0), q0 + side * 0.2 + Vector3(0, 1.7, 0), g.lightened(0.05))
