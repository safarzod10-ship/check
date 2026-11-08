class_name TerrainStreamer
extends Node3D
## Streams the 10x10 km terrain as 500 m chunks with distance based LOD.
## Mesh data is generated on WorkerThreadPool threads; nodes are created on the main thread.
## Collision (trimesh, with tunnel-portal holes) only exists close to the player.

signal idle_changed(is_idle: bool)

const STEPS := [1, 2, 4, 10, 20]          # heightmap cells per vertex for each LOD
const COLLISION_RADIUS := 180.0

var material: ShaderMaterial
var chunks: Dictionary = {}               # Vector2i -> Dictionary
var _results: Array = []
var _mutex := Mutex.new()
var _inflight := 0
var max_inflight := 3
var _timer := 0.0
var lod_dist: Array = [500.0, 1200.0, 2500.0, 4500.0]
var view_distance := 7000.0
var is_idle := false


func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = load("res://world/terrain/terrain.gdshader")
	material.set_shader_parameter("splat_map", WorldData.splat_tex)
	material.set_shader_parameter("field_map", WorldData.fields_tex)
	for p in [["tex_grass", "grass"], ["tex_dry", "grass_dry"], ["tex_rock", "rock"], ["tex_snow", "snow"],
			["tex_dirt", "dirt"], ["tex_gravel", "gravel"], ["tex_paving", "paving"], ["tex_soil", "soil"],
			["tex_rows", "crop_rows"], ["tex_noise", "noise"]]:
		material.set_shader_parameter(p[0], Mats.tex(p[1]))
	for j in WorldData.sectors_n:
		for i in WorldData.sectors_n:
			chunks[Vector2i(i, j)] = {"mesh": null, "lod": -1, "pending": -1, "body": null, "coll_pending": false}
	GameSettings.changed.connect(_apply_settings)
	_apply_settings()
	_build_horizon()


func _apply_settings() -> void:
	var bias: float = GameSettings.get_v("terrain_lod_bias", 1.0)
	lod_dist = [500.0 * bias, 1200.0 * bias, 2500.0 * bias, 4500.0 * bias]
	view_distance = GameSettings.get_v("view_distance", 7000.0)


func _process(delta: float) -> void:
	_apply_results()
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.15
	_update_lods()


func _rect_dist(key: Vector2i, p: Vector3) -> float:
	var o := WorldData.sector_origin(key)
	var s := WorldData.SECTOR
	var dx := maxf(maxf(o.x - p.x, 0.0), p.x - (o.x + s))
	var dz := maxf(maxf(o.z - p.z, 0.0), p.z - (o.z + s))
	return sqrt(dx * dx + dz * dz)


func desired_lod(d: float) -> int:
	if d > view_distance:
		return 4 if d < view_distance + 3000.0 else -1
	for k in lod_dist.size():
		if d < lod_dist[k]:
			return k
	return 4


func _update_lods() -> void:
	var cam := GameState.view_position()
	var focus := GameState.focus_position()
	var todo: Array = []
	for key in chunks:
		var c: Dictionary = chunks[key]
		var d := _rect_dist(key, cam)
		var want := desired_lod(d)
		if want != c["lod"] and c["pending"] != want:
			todo.append([d, key, want])
		var need_coll := _rect_dist(key, focus) < COLLISION_RADIUS
		if need_coll and c["body"] == null and not c["coll_pending"]:
			todo.append([-1.0, key, 100])
		elif not need_coll and c["body"] != null:
			c["body"].queue_free()
			c["body"] = null
	todo.sort_custom(func(a, b): return a[0] < b[0])
	var was_idle := is_idle
	is_idle = todo.is_empty() and _inflight == 0
	if is_idle != was_idle:
		idle_changed.emit(is_idle)
	for t in todo:
		if _inflight >= max_inflight:
			break
		var key: Vector2i = t[1]
		var want: int = t[2]
		var c: Dictionary = chunks[key]
		if want == 100:
			c["coll_pending"] = true
		else:
			if want == -1:
				if c["mesh"]:
					c["mesh"].visible = false
				c["lod"] = -1
				continue
			c["pending"] = want
		_inflight += 1
		WorkerThreadPool.add_task(_build_task.bind(key, want))


func _build_task(key: Vector2i, lod: int) -> void:
	var res: Dictionary
	if lod == 100:
		res = build_chunk_arrays(key, 1, true)
	else:
		res = build_chunk_arrays(key, STEPS[lod], false)
	res["key"] = key
	res["lod"] = lod
	_mutex.lock()
	_results.append(res)
	_mutex.unlock()


func _apply_results() -> void:
	_mutex.lock()
	var batch := _results.duplicate()
	_results.clear()
	_mutex.unlock()
	for res in batch:
		_inflight -= 1
		var key: Vector2i = res["key"]
		var c: Dictionary = chunks[key]
		var lod: int = res["lod"]
		if lod == 100:
			c["coll_pending"] = false
			if _rect_dist(key, GameState.focus_position()) > COLLISION_RADIUS + 60.0:
				continue
			var body := StaticBody3D.new()
			body.name = "TerrainCol_%d_%d" % [key.x, key.y]
			body.collision_layer = 1
			var cs := CollisionShape3D.new()
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(res["faces"])
			cs.shape = shape
			body.add_child(cs)
			body.position = WorldData.sector_origin(key)
			add_child(body)
			c["body"] = body
			continue
		if c["pending"] != lod:
			continue
		c["pending"] = -1
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, res["arrays"])
		mesh.surface_set_material(0, material)
		if c["mesh"] == null:
			var mi := MeshInstance3D.new()
			mi.name = "Terrain_%d_%d" % [key.x, key.y]
			mi.position = WorldData.sector_origin(key)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mi)
			c["mesh"] = mi
		c["mesh"].mesh = mesh
		c["mesh"].visible = true
		# far LODs don't need to cast shadows
		c["mesh"].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if lod <= 1 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		c["lod"] = lod


## Pure function (thread safe): vertex arrays for a chunk at a given step.
static func build_chunk_arrays(key: Vector2i, step: int, faces_only: bool) -> Dictionary:
	var n: int = WorldData.n
	var cell: float = WorldData.cell
	var hts: PackedFloat32Array = WorldData.heights
	var holes: PackedByteArray = WorldData.holes
	var per := int(WorldData.SECTOR / cell)
	var i0 := key.x * per
	var j0 := key.y * per
	var cnt := per / step + 1
	var verts := PackedVector3Array()
	verts.resize(cnt * cnt)
	var normals := PackedVector3Array()
	if not faces_only:
		normals.resize(cnt * cnt)
	var ns := maxi(1, step)
	for jj in cnt:
		var gj := mini(j0 + jj * step, n - 1)
		for ii in cnt:
			var gi := mini(i0 + ii * step, n - 1)
			var k := jj * cnt + ii
			var h := hts[gj * n + gi]
			verts[k] = Vector3((gi - i0) * cell, h, (gj - j0) * cell)
			if not faces_only:
				var hl := hts[gj * n + maxi(gi - ns, 0)]
				var hr := hts[gj * n + mini(gi + ns, n - 1)]
				var hd := hts[maxi(gj - ns, 0) * n + gi]
				var hu := hts[mini(gj + ns, n - 1) * n + gi]
				normals[k] = Vector3(hl - hr, 2.0 * ns * cell, hd - hu).normalized()
	var idx := PackedInt32Array()
	var faces := PackedVector3Array()
	for jj in cnt - 1:
		for ii in cnt - 1:
			if step == 1 and holes[mini(j0 + jj, n - 1) * n + mini(i0 + ii, n - 1)] != 0:
				continue
			var a := jj * cnt + ii
			var b := a + 1
			var c := a + cnt
			var d := c + 1
			if faces_only:
				faces.append_array([verts[a], verts[b], verts[d], verts[a], verts[d], verts[c]])
			else:
				idx.append_array([a, b, d, a, d, c])
	if faces_only:
		return {"faces": faces}
	# skirts to hide cracks between different LODs
	var skirt := 10.0 + step * cell * 2.0
	var edges := [[], [], [], []]
	for q in cnt:
		edges[0].append(q)                          # z = 0 edge
		edges[1].append((cnt - 1) * cnt + q)        # z = max
		edges[2].append(q * cnt)                    # x = 0
		edges[3].append(q * cnt + cnt - 1)          # x = max
	for e in edges:
		var base: int = verts.size()
		for vi in e:
			verts.append(verts[vi] - Vector3(0, skirt, 0))
			normals.append(normals[vi])
		for q in e.size() - 1:
			var t0: int = e[q]
			var t1: int = e[q + 1]
			var b0: int = base + q
			var b1: int = base + q + 1
			# both windings so the skirt is visible from either side
			idx.append_array([t0, t1, b1, t0, b1, b0, t0, b1, t1, t0, b0, b1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	return {"arrays": arr}


## Low-poly ring of mountains beyond the map edge so the horizon never ends in the void.
func _build_horizon() -> void:
	var rings := [5000.0, 5600.0, 7000.0, 9500.0, 13000.0, 18000.0]
	var segs := 160
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var noise := FastNoiseLite.new()
	noise.seed = 77
	noise.frequency = 0.00025
	noise.fractal_octaves = 5
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	for ri in rings.size():
		for k in segs:
			var a := TAU * k / segs
			var dir := Vector2(cos(a), sin(a))
			# square-ish inner ring that matches the map border
			var inner := 5000.0 / maxf(absf(dir.x), absf(dir.y))
			var r: float = inner + (rings[ri] - 5000.0)
			var p := dir * r
			var h: float
			if ri == 0:
				h = WorldData.height_at(clampf(p.x, -4999.0, 4999.0), clampf(p.y, -4999.0, 4999.0)) - 2.0
			else:
				var north := clampf(-p.y / 9000.0 + 0.4, 0.15, 1.3)
				h = (400.0 + 1900.0 * north) * (0.55 + 0.45 * noise.get_noise_2d(p.x, p.y)) * minf(1.0, ri / 2.0)
				h += 30.0 * ri
			verts.append(Vector3(p.x, h, p.y))
	var nv := verts.size()
	var normals := PackedVector3Array()
	normals.resize(nv)
	for ri in rings.size() - 1:
		for k in segs:
			var a := ri * segs + k
			var b := ri * segs + (k + 1) % segs
			var c := (ri + 1) * segs + k
			var d := (ri + 1) * segs + (k + 1) % segs
			idx.append_array([a, c, b, b, c, d])
	for q in range(0, idx.size(), 3):
		var n := (verts[idx[q + 1]] - verts[idx[q]]).cross(verts[idx[q + 2]] - verts[idx[q]])
		if n.y < 0:
			n = -n
		for o in 3:
			normals[idx[q + o]] += n
	for q in nv:
		normals[q] = normals[q].normalized()
	# make sure triangles face up (clockwise from above in Godot)
	for q in range(0, idx.size(), 3):
		var n2 := (verts[idx[q + 1]] - verts[idx[q]]).cross(verts[idx[q + 2]] - verts[idx[q]])
		if n2.y > 0:
			var tmp := idx[q + 1]
			idx[q + 1] = idx[q + 2]
			idx[q + 2] = tmp
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = normals
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, material)
	var mi := MeshInstance3D.new()
	mi.name = "HorizonMountains"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
