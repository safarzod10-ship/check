class_name WaterSystem
extends Node3D
## Rivers, creeks, canals (flowing ribbons), lakes (discs with shore foam), waterfalls (steep segments
## with a faster foamy material + mist particles near the camera).

const MIST_DIST := 450.0

var is_idle := false
var _mist: Array = []        # [GPUParticles3D, position]
var _results: Array = []
var _mutex := Mutex.new()
var _pending := 0


func _ready() -> void:
	var lake_mat: ShaderMaterial = Mats.get_mat("water").duplicate()
	lake_mat.set_shader_parameter("is_lake", true)
	lake_mat.set_shader_parameter("deep_col", Color(0.08, 0.26, 0.32))
	lake_mat.set_shader_parameter("shallow_col", Color(0.25, 0.48, 0.5))
	var canal_mat: ShaderMaterial = Mats.get_mat("water").duplicate()
	canal_mat.set_shader_parameter("deep_col", Color(0.24, 0.3, 0.22))
	canal_mat.set_shader_parameter("shallow_col", Color(0.36, 0.42, 0.32))
	canal_mat.set_shader_parameter("flow_speed", 0.6)
	_mats = {"water": Mats.get_mat("water"), "waterfall": Mats.get_mat("waterfall"), "lake": lake_mat, "canal": canal_mat}
	for key in WorldData.sector_index:
		if not WorldData.sector_index[key]["river_runs"].is_empty():
			_pending += 1
			WorkerThreadPool.add_task(_task.bind(key))
	for lk in WorldData.lakes:
		_add_mesh(_lake_kit(lk), Vector3(lk["x"], 0, lk["z"]), "Lake")
	for wf in WorldData.world.get("waterfalls", []):
		_add_waterfall_fx(wf)


var _mats: Dictionary = {}


func _task(key: Vector2i) -> void:
	var kit := _river_kit(key)
	_mutex.lock()
	_results.append([key, kit])
	_mutex.unlock()


func _process(_delta: float) -> void:
	_mutex.lock()
	var batch := _results.duplicate()
	_results.clear()
	_mutex.unlock()
	for r in batch:
		_pending -= 1
		var kit: MeshKit = r[1]
		if not kit.is_empty():
			_add_mesh(kit, WorldData.sector_origin(r[0]), "River_%d_%d" % [r[0].x, r[0].y])
	is_idle = _pending == 0
	var cam := GameState.view_position()
	for m in _mist:
		var on: bool = cam.distance_to(m[1]) < MIST_DIST
		m[0].emitting = on
		m[0].visible = on


func _add_mesh(kit: MeshKit, origin: Vector3, nm: String) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = kit.build(_mats)
	mi.position = origin
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _river_kit(key: Vector2i) -> MeshKit:
	var kit := MeshKit.new()
	var org := WorldData.sector_origin(key)
	for run in WorldData.sector_index[key]["river_runs"]:
		var rv: Dictionary = WorldData.rivers[run[0]]
		var pts: Array = rv["pts"]
		var hw: float = float(rv["width"]) * 0.5 + 1.2
		var base_slot := "canal" if rv["kind"] == "canal" else "water"
		var L := PackedVector3Array()
		var R := PackedVector3Array()
		var cur_slot := ""
		var v0 := 0.0
		for i in range(int(run[1]), int(run[2]) + 1):
			var p: Array = pts[i]
			var pa: Array = pts[maxi(0, i - 1)]
			var pb: Array = pts[mini(pts.size() - 1, i + 1)]
			var t := Vector3(pb[0] - pa[0], 0, pb[2] - pa[2]).normalized()
			var right := t.cross(Vector3.UP).normalized()
			var c := Vector3(p[0], float(p[1]) + 0.05, p[2]) - org
			var drop: float = (float(pa[1]) - float(pb[1])) / maxf(0.1, Vector2(pb[0] - pa[0], pb[2] - pa[2]).length())
			var slot := "waterfall" if drop > 0.25 else base_slot
			if cur_slot != "" and slot != cur_slot:
				L.append(c - right * hw)
				R.append(c + right * hw)
				kit.ribbon(cur_slot, L, R, Color.WHITE, v0)
				v0 += 1.0
				L = PackedVector3Array()
				R = PackedVector3Array()
			cur_slot = slot
			L.append(c - right * hw)
			R.append(c + right * hw)
		if L.size() > 1:
			kit.ribbon(cur_slot, L, R, Color.WHITE, v0)
	return kit


func _lake_kit(lk: Dictionary) -> MeshKit:
	var kit := MeshKit.new()
	var s: Dictionary = kit._s("lake")
	var r: float = float(lk["r"]) + 4.0
	var y: float = float(lk["level"])
	var rings := 6
	var segs := 48
	s["v"].append(Vector3(0, y, 0))
	s["n"].append(Vector3.UP)
	s["c"].append(Color.WHITE)
	s["uv"].append(Vector2.ZERO)
	s["uv2"].append(Vector2(1, 0))
	for ri in range(1, rings + 1):
		var rr := r * float(ri) / rings
		for k in segs:
			var a := TAU * k / segs
			s["v"].append(Vector3(cos(a) * rr, y, sin(a) * rr))
			s["n"].append(Vector3.UP)
			s["c"].append(Color.WHITE)
			s["uv"].append(Vector2(cos(a), sin(a)) * rr)
			s["uv2"].append(Vector2(1.0 - float(ri) / rings, 0))
	for k in segs:
		s["i"].append_array([0, 1 + (k + 1) % segs, 1 + k])
	for ri in range(1, rings):
		var b0 := 1 + (ri - 1) * segs
		var b1 := 1 + ri * segs
		for k in segs:
			var k1 := (k + 1) % segs
			s["i"].append_array([b0 + k, b0 + k1, b1 + k, b1 + k, b0 + k1, b1 + k1])
	return kit


func _add_waterfall_fx(wf: Dictionary) -> void:
	var p := Vector3(wf["x1"], float(wf["y1"]) + 1.0, wf["z1"])
	var mist := GPUParticles3D.new()
	mist.name = "WaterfallMist"
	mist.amount = 60
	mist.lifetime = 2.5
	mist.position = p
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = float(wf["width"]) * 0.6 + 1.0
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.0
	pm.gravity = Vector3(0, -0.4, 0)
	pm.scale_min = 2.0
	pm.scale_max = 5.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.3))
	curve.add_point(Vector2(0.5, 1.0))
	curve.add_point(Vector2(1, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.alpha_curve = ct
	mist.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.95, 0.97, 1.0, 0.25)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	q.material = m
	mist.draw_pass_1 = q
	mist.emitting = false
	mist.visible = false
	add_child(mist)
	_mist.append([mist, p])
