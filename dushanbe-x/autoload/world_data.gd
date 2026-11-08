extends Node
## Loads the generated world (heightmap, maps, world.json) and answers spatial queries.
## All game systems read terrain/road/building data through this singleton.

signal world_loaded

const DATA_DIR := "res://data/"
const SECTOR := 500.0            # streaming sector size in metres
## Road carriageway surface is drawn this far above the road profile height (pts[i].y).
const ROAD_LIFT := 0.12

var loaded := false
var world: Dictionary = {}
var n := 2001
var cell := 5.0
var origin := -5000.0
var size := 10000.0
var heights := PackedFloat32Array()
var holes := PackedByteArray()
var splat_img: Image
var veg_img: Image
var fields_img: Image
var minimap_img: Image
var splat_tex: ImageTexture
var fields_tex: ImageTexture

var sectors_n := 20
## sector key (Vector2i) -> Dictionary of index lists
var sector_index: Dictionary = {}
## spatial hash of road samples for nearest-road queries (cell 50 m)
var _road_hash: Dictionary = {}
const ROAD_HASH := 50.0

var roads: Array = []
var buildings: Array = []
var landmarks: Array = []
var pois: Array = []
var rivers: Array = []
var lakes: Array = []
var parcels: Array = []
var intersections: Array = []


func _ready() -> void:
	load_world()


func load_world() -> void:
	if loaded:
		return
	var t0 := Time.get_ticks_msec()
	var txt := FileAccess.get_file_as_string(DATA_DIR + "world.json")
	world = JSON.parse_string(txt)
	var meta: Dictionary = world["meta"]
	n = int(meta["n"])
	cell = float(meta["cell"])
	origin = float(meta["origin"])
	size = float(meta["size"])
	sectors_n = int(ceil(size / SECTOR))
	heights = FileAccess.get_file_as_bytes(DATA_DIR + "heightmap.f32").to_float32_array()
	holes = PackedByteArray()
	holes.resize(n * n)
	for h in world.get("holes", []):
		holes[int(h[1]) * n + int(h[0])] = 1
	splat_img = _load_png(DATA_DIR + "splat.pngdat")
	veg_img = _load_png(DATA_DIR + "veg.pngdat")
	fields_img = _load_png(DATA_DIR + "fields.pngdat")
	minimap_img = _load_png(DATA_DIR + "minimap.pngdat")
	splat_tex = ImageTexture.create_from_image(splat_img)
	fields_tex = ImageTexture.create_from_image(fields_img)
	roads = world["roads"]
	buildings = world["buildings"]
	landmarks = world["landmarks"]
	pois = world["pois"]
	rivers = world["rivers"]
	lakes = world["lakes"]
	parcels = world.get("parcels", [])
	intersections = world["intersections"]
	_build_indices()
	loaded = true
	print("[WorldData] loaded in %d ms: %d roads, %d buildings, heights %d" % [
		Time.get_ticks_msec() - t0, roads.size(), buildings.size(), heights.size()])
	world_loaded.emit()


func _load_png(path: String) -> Image:
	var img := Image.new()
	var err := img.load_png_from_buffer(FileAccess.get_file_as_bytes(path))
	if err != OK:
		push_error("WorldData: cannot load " + path)
	return img


# ---------------------------------------------------------------------------
# Terrain queries
# ---------------------------------------------------------------------------
func h_at_index(i: int, j: int) -> float:
	i = clampi(i, 0, n - 1)
	j = clampi(j, 0, n - 1)
	return heights[j * n + i]


func height_at(x: float, z: float) -> float:
	var fx := (x - origin) / cell
	var fz := (z - origin) / cell
	var i := clampi(int(floor(fx)), 0, n - 2)
	var j := clampi(int(floor(fz)), 0, n - 2)
	var tx := clampf(fx - i, 0.0, 1.0)
	var tz := clampf(fz - j, 0.0, 1.0)
	var k := j * n + i
	var h00 := heights[k]
	var h10 := heights[k + 1]
	var h01 := heights[k + n]
	var h11 := heights[k + n + 1]
	# match the triangle split used by the terrain mesh (diagonal 00-11)
	if tx >= tz:
		return h00 + (h10 - h00) * tx + (h11 - h10) * tz
	return h00 + (h11 - h01) * tx + (h01 - h00) * tz


func normal_at(x: float, z: float) -> Vector3:
	var e := cell
	var hl := height_at(x - e, z)
	var hr := height_at(x + e, z)
	var hd := height_at(x, z - e)
	var hu := height_at(x, z + e)
	return Vector3(hl - hr, 2.0 * e, hd - hu).normalized()


func is_hole(i: int, j: int) -> bool:
	if i < 0 or j < 0 or i >= n or j >= n:
		return false
	return holes[j * n + i] != 0


func in_bounds(x: float, z: float, margin := 0.0) -> bool:
	return x > origin + margin and z > origin + margin and x < origin + size - margin and z < origin + size - margin


func uv_of(x: float, z: float) -> Vector2:
	return Vector2((x - origin) / size, (z - origin) / size)


func splat_at(x: float, z: float) -> Color:
	var uv := uv_of(x, z)
	return splat_img.get_pixel(clampi(int(uv.x * splat_img.get_width()), 0, splat_img.get_width() - 1),
		clampi(int(uv.y * splat_img.get_height()), 0, splat_img.get_height() - 1))


func veg_at(x: float, z: float) -> Color:
	var uv := uv_of(x, z)
	return veg_img.get_pixel(clampi(int(uv.x * veg_img.get_width()), 0, veg_img.get_width() - 1),
		clampi(int(uv.y * veg_img.get_height()), 0, veg_img.get_height() - 1))


func field_code_at(x: float, z: float) -> int:
	var uv := uv_of(x, z)
	var c := fields_img.get_pixel(clampi(int(uv.x * fields_img.get_width()), 0, fields_img.get_width() - 1),
		clampi(int(uv.y * fields_img.get_height()), 0, fields_img.get_height() - 1))
	return int(round(c.r * 255.0 / 30.0))


# ---------------------------------------------------------------------------
# Sectors
# ---------------------------------------------------------------------------
func sector_of(x: float, z: float) -> Vector2i:
	return Vector2i(clampi(int((x - origin) / SECTOR), 0, sectors_n - 1), clampi(int((z - origin) / SECTOR), 0, sectors_n - 1))


func sector_origin(s: Vector2i) -> Vector3:
	return Vector3(origin + s.x * SECTOR, 0.0, origin + s.y * SECTOR)


func sector_center(s: Vector2i) -> Vector3:
	return sector_origin(s) + Vector3(SECTOR * 0.5, 0.0, SECTOR * 0.5)


func sector_data(s: Vector2i) -> Dictionary:
	if not sector_index.has(s):
		sector_index[s] = {"buildings": [], "road_runs": [], "pois": [], "landmarks": [], "parcels": [],
			"intersections": [], "river_runs": []}
	return sector_index[s]


func _build_indices() -> void:
	sector_index.clear()
	_road_hash.clear()
	for bi in buildings.size():
		var b: Array = buildings[bi]
		sector_data(sector_of(b[0], b[1]))["buildings"].append(bi)
	# road samples are split into contiguous runs per sector (+1 sample overlap for continuity)
	for ri in roads.size():
		var pts: Array = roads[ri]["pts"]
		var cur := Vector2i(-1, -1)
		var start := 0
		for si in pts.size():
			var p: Array = pts[si]
			var s := sector_of(p[0], p[2])
			if s != cur:
				if cur.x >= 0:
					sector_data(cur)["road_runs"].append([ri, start, si])
				cur = s
				start = maxi(0, si - 1)
			var hk := Vector2i(int(floor(p[0] / ROAD_HASH)), int(floor(p[2] / ROAD_HASH)))
			if not _road_hash.has(hk):
				_road_hash[hk] = PackedInt32Array()
			var arr: PackedInt32Array = _road_hash[hk]
			arr.append(ri)
			arr.append(si)
			_road_hash[hk] = arr
		if cur.x >= 0:
			sector_data(cur)["road_runs"].append([ri, start, pts.size() - 1])
	for i in pois.size():
		sector_data(sector_of(pois[i]["x"], pois[i]["z"]))["pois"].append(i)
	for i in landmarks.size():
		sector_data(sector_of(landmarks[i]["x"], landmarks[i]["z"]))["landmarks"].append(i)
	for i in parcels.size():
		sector_data(sector_of(parcels[i][0], parcels[i][1]))["parcels"].append(i)
	for i in intersections.size():
		sector_data(sector_of(intersections[i][0], intersections[i][1]))["intersections"].append(i)
	for ri in rivers.size():
		var pts: Array = rivers[ri]["pts"]
		var cur := Vector2i(-1, -1)
		var start := 0
		for si in pts.size():
			var s := sector_of(pts[si][0], pts[si][2])
			if s != cur:
				if cur.x >= 0:
					sector_data(cur)["river_runs"].append([ri, start, si])
				cur = s
				start = maxi(0, si - 1)
		if cur.x >= 0:
			sector_data(cur)["river_runs"].append([ri, start, pts.size() - 1])


# ---------------------------------------------------------------------------
# Roads
# ---------------------------------------------------------------------------
func road_type(ri: int) -> Dictionary:
	return world["road_types"][roads[ri]["type"]]


## Returns {road, index, dist, pos} of the closest road sample (or empty dict).
func nearest_road(x: float, z: float, max_dist := 120.0) -> Dictionary:
	var best := {}
	var bd := max_dist * max_dist
	var r := int(ceil(max_dist / ROAD_HASH))
	var cx := int(floor(x / ROAD_HASH))
	var cz := int(floor(z / ROAD_HASH))
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := Vector2i(cx + dx, cz + dz)
			if not _road_hash.has(k):
				continue
			var arr: PackedInt32Array = _road_hash[k]
			for q in range(0, arr.size(), 2):
				var p: Array = roads[arr[q]]["pts"][arr[q + 1]]
				var d: float = (p[0] - x) * (p[0] - x) + (p[2] - z) * (p[2] - z)
				if d < bd:
					bd = d
					best = {"road": arr[q], "index": arr[q + 1], "dist": sqrt(d), "pos": Vector3(p[0], p[1], p[2])}
	return best


func road_point(ri: int, si: int) -> Vector3:
	var p: Array = roads[ri]["pts"][clampi(si, 0, roads[ri]["pts"].size() - 1)]
	return Vector3(p[0], p[1], p[2])


func road_tangent(ri: int, si: int) -> Vector3:
	var pts: Array = roads[ri]["pts"]
	var a := road_point(ri, maxi(0, si - 1))
	var b := road_point(ri, mini(pts.size() - 1, si + 1))
	var t := b - a
	t.y = 0.0
	return t.normalized() if t.length() > 0.001 else Vector3.FORWARD


func sample_flags(ri: int) -> PackedByteArray:
	## 0 = normal, 1 = bridge, 2 = tunnel, 4 = gap (inside a bigger road at an intersection)
	var r: Dictionary = roads[ri]
	if r.has("_flags"):
		return r["_flags"]
	var f := PackedByteArray()
	f.resize(r["pts"].size())
	for run in r.get("bridges", []):
		for i in range(int(run[0]), int(run[1]) + 1):
			f[i] |= 1
	for run in r.get("tunnels", []):
		for i in range(int(run[0]), int(run[1]) + 1):
			f[i] |= 2
	for run in r.get("gaps", []):
		for i in range(int(run[0]), int(run[1]) + 1):
			f[i] |= 4
	r["_flags"] = f
	return f


# ---------------------------------------------------------------------------
# Place names
# ---------------------------------------------------------------------------
func place_name(x: float, z: float) -> String:
	var p := Vector2(x, z)
	for d in world["districts"]:
		if Geometry2D.is_point_in_polygon(p, _poly(d["poly"])):
			return "Душанбе, " + str(d["name"])
	for v in world["villages"]:
		if p.distance_to(Vector2(v["x"], v["z"])) < float(v["r"]) * 1.3:
			return str(v["name"])
	for rg in world["regions"]:
		if Geometry2D.is_point_in_polygon(p, _poly(rg["poly"])):
			return str(rg["name"])
	return "Таджикистан"


func nearest_landmark(x: float, z: float, max_dist := 250.0) -> Dictionary:
	var best := {}
	var bd := max_dist
	for lm in landmarks:
		var d := Vector2(x, z).distance_to(Vector2(lm["x"], lm["z"]))
		if d < bd:
			bd = d
			best = lm
	return best


var _poly_cache: Dictionary = {}


func _poly(arr: Array) -> PackedVector2Array:
	var key := str(arr)
	if _poly_cache.has(key):
		return _poly_cache[key]
	var out := PackedVector2Array()
	for q in arr:
		out.append(Vector2(q[0], q[1]))
	_poly_cache[key] = out
	return out
