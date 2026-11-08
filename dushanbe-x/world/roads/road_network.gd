class_name RoadNetwork
extends Node3D
## Streams road geometry per 500 m sector:
##  near (< NEAR_DIST): carriageway with markings, curbs + sidewalks, shoulders, bridges (deck, parapets, piers),
##                      tunnel tube + portals, guard rails, zebra crossings, collision near the player
##  far: simplified carriageway ribbons so roads stay visible from the mountains.

const NEAR_DIST := 800.0
const COLL_DIST := 300.0
const CURB := 0.15
const F_BRIDGE := 1
const F_TUNNEL := 2
const F_GAP := 4
const F_SWCUT := 8

var is_idle := false
var sectors: Dictionary = {}          # key -> state
var _flags: Array = []                # per road PackedByteArray
var _cross_by_sector: Dictionary = {}
var _results: Array = []
var _mutex := Mutex.new()
var _inflight := 0
var _timer := 0.0
var materials: Dictionary = {}
var view_distance := 7000.0
var near_dist := NEAR_DIST


func _ready() -> void:
	_make_materials()
	for ri in WorldData.roads.size():
		var f: PackedByteArray = WorldData.sample_flags(ri).duplicate()
		for run in WorldData.roads[ri].get("swcut", []):
			for i in range(int(run[0]), int(run[1]) + 1):
				f[i] |= F_SWCUT
		_flags.append(f)
	for cw in WorldData.world.get("crosswalks", []):
		var k := WorldData.sector_of(cw[0], cw[2])
		if not _cross_by_sector.has(k):
			_cross_by_sector[k] = []
		_cross_by_sector[k].append(cw)
	for key in WorldData.sector_index:
		if not WorldData.sector_index[key]["road_runs"].is_empty():
			sectors[key] = {"near": null, "far": null, "body": null, "near_pending": false, "far_pending": false,
				"faces": PackedVector3Array()}
	GameSettings.changed.connect(_apply_settings)
	_apply_settings()


func _apply_settings() -> void:
	view_distance = GameSettings.get_v("view_distance", 7000.0)
	near_dist = clampf(float(GameSettings.get_v("building_distance", 1100.0)) * 0.6, 350.0, NEAR_DIST)


func _make_materials() -> void:
	var base: ShaderMaterial = Mats.get_mat("road")
	for t in WorldData.world["road_types"]:
		var rt: Dictionary = WorldData.world["road_types"][t]
		var m: ShaderMaterial
		if t == "dirt":
			m = Mats.get_mat("road_dirt").duplicate()
		elif t == "rural":
			m = Mats.get_mat("road_old").duplicate()
		else:
			m = base.duplicate()
		m.set_shader_parameter("half_width", float(rt["half"]))
		m.set_shader_parameter("lanes", int(rt["lanes"]))
		m.set_shader_parameter("double_center", t == "highway")
		materials["road_" + t] = m


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
	_timer = 0.2
	var cam := GameState.view_position()
	var focus := GameState.focus_position()
	var todo: Array = []
	for key in sectors:
		var st: Dictionary = sectors[key]
		var d := _rect_dist(key, cam)
		var want_near := d < near_dist
		var want_far := d < view_distance
		if want_near and st["near"] == null and not st["near_pending"]:
			todo.append([d, key, true])
		elif not want_near and st["near"] != null and d > near_dist + 150.0:
			st["near"].queue_free()
			st["near"] = null
			st["faces"] = PackedVector3Array()
			if st["far"]:
				st["far"].visible = true
		if want_far and st["far"] == null and not st["far_pending"]:
			todo.append([d + 2000.0, key, false])
		elif st["far"] != null:
			st["far"].visible = want_far and st["near"] == null
		# collision
		var need_coll := _rect_dist(key, focus) < COLL_DIST
		if need_coll and st["body"] == null and st["near"] != null and not st["faces"].is_empty():
			var body := StaticBody3D.new()
			body.name = "RoadCol_%d_%d" % [key.x, key.y]
			var cs := CollisionShape3D.new()
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(st["faces"])
			cs.shape = shape
			body.add_child(cs)
			body.position = WorldData.sector_origin(key)
			add_child(body)
			st["body"] = body
		elif not need_coll and st["body"] != null:
			st["body"].queue_free()
			st["body"] = null
	todo.sort_custom(func(a, b): return a[0] < b[0])
	is_idle = todo.is_empty() and _inflight == 0
	for t in todo:
		if _inflight >= 3:
			break
		var key: Vector2i = t[1]
		var near: bool = t[2]
		sectors[key]["near_pending" if near else "far_pending"] = true
		_inflight += 1
		WorkerThreadPool.add_task(_task.bind(key, near))


func _task(key: Vector2i, near: bool) -> void:
	var res := build_sector(key, near)
	res["key"] = key
	res["near"] = near
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
		var st: Dictionary = sectors[key]
		var near: bool = res["near"]
		st["near_pending" if near else "far_pending"] = false
		var kit: MeshKit = res["kit"]
		if kit.is_empty():
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = kit.build(materials)
		mi.position = WorldData.sector_origin(key)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.name = ("RoadNear_%d_%d" if near else "RoadFar_%d_%d") % [key.x, key.y]
		add_child(mi)
		if near:
			st["near"] = mi
			st["faces"] = res["faces"]
			if st["far"]:
				st["far"].visible = false
		else:
			st["far"] = mi
			mi.visible = st["near"] == null


# ---------------------------------------------------------------------------
# Geometry (thread-safe: reads WorldData only)
# ---------------------------------------------------------------------------
func build_sector(key: Vector2i, near: bool) -> Dictionary:
	var kit := MeshKit.new()
	kit.slot_remap = {"gravel": "concrete", "lamp_always": "lamp_always"}
	var org := WorldData.sector_origin(key)
	var sd: Dictionary = WorldData.sector_index.get(key, {})
	var types: Dictionary = WorldData.world["road_types"]
	for run in sd.get("road_runs", []):
		var ri: int = run[0]
		var road: Dictionary = WorldData.roads[ri]
		var rt: Dictionary = types[road["type"]]
		_build_run(kit, ri, road, rt, int(run[1]), int(run[2]), org, near)
	if near:
		for cw in _cross_by_sector.get(key, []):
			_crosswalk(kit, cw, org)
	var faces := PackedVector3Array()
	if near:
		faces = kit.collision_faces(["road_avenue", "road_boulevard", "road_highway", "road_street", "road_mountain",
			"road_rural", "road_dirt", "paving", "concrete", "metal", "gravel"])
	return {"kit": kit, "faces": faces}


func _build_run(kit: MeshKit, ri: int, road: Dictionary, rt: Dictionary, a: int, b: int, org: Vector3, near: bool) -> void:
	var pts: Array = road["pts"]
	var fl: PackedByteArray = _flags[ri]
	var half: float = rt["half"]
	var sw: float = rt["sidewalk"]
	var slot: String = "road_" + str(road["type"])
	var step := 1 if near else 3
	var idxs := PackedInt32Array()
	var i := a
	while i < b:
		idxs.append(i)
		i += step
	idxs.append(b)
	var cnt := idxs.size()
	if cnt < 2:
		return
	var P := PackedVector3Array()
	var Rt := PackedVector3Array()
	var F := PackedByteArray()
	P.resize(cnt)
	Rt.resize(cnt)
	F.resize(cnt)
	var lift := WorldData.ROAD_LIFT
	for k in cnt:
		var si: int = idxs[k]
		var p: Array = pts[si]
		P[k] = Vector3(p[0], p[1] + lift, p[2]) - org
		var pa: Array = pts[maxi(0, si - 1)]
		var pb: Array = pts[mini(pts.size() - 1, si + 1)]
		var t := Vector3(pb[0] - pa[0], 0.0, pb[2] - pa[2]).normalized()
		Rt[k] = t.cross(Vector3.UP).normalized()
		F[k] = fl[si]
	var white := Color(1, 1, 1)
	# --- carriageway (split at intersection gaps) ---
	var L := PackedVector3Array()
	var Rr := PackedVector3Array()
	for k in cnt:
		var gap := (F[k] & F_GAP) != 0 and (k == 0 or (F[k - 1] & F_GAP) != 0)
		if gap:
			if L.size() > 1:
				kit.ribbon(slot, L, Rr, white)
			L = PackedVector3Array()
			Rr = PackedVector3Array()
			continue
		L.append(P[k] - Rt[k] * half)
		Rr.append(P[k] + Rt[k] * half)
	if L.size() > 1:
		kit.ribbon(slot, L, Rr, white)
	if not near:
		return
	# --- edges: sidewalks or shoulders, bridges, tunnels, guard rails ---
	for side in [-1.0, 1.0]:
		_edge_strips(kit, P, Rt, F, cnt, half, sw, side, org, rt)
	_bridges(kit, P, Rt, F, cnt, half + (sw if sw > 0.0 else 0.6), org)
	_tunnels(kit, P, Rt, F, cnt, half, org)


## Builds runs of sidewalk (curb+top+outer face) or gravel shoulder on one side.
func _edge_strips(kit: MeshKit, P: PackedVector3Array, Rt: PackedVector3Array, F: PackedByteArray, cnt: int,
		half: float, sw: float, side: float, org: Vector3, rt: Dictionary) -> void:
	var runs: Array = []
	var cur: Array = []
	for k in cnt:
		var blocked := (F[k] & (F_GAP | F_TUNNEL)) != 0
		if sw > 0.0 and (F[k] & F_SWCUT) != 0:
			blocked = true
		if blocked:
			if cur.size() > 1:
				runs.append(cur)
			cur = []
		else:
			cur.append(k)
	if cur.size() > 1:
		runs.append(cur)
	for r in runs:
		var inner_b := PackedVector3Array()
		var inner_t := PackedVector3Array()
		var outer_t := PackedVector3Array()
		var outer_b := PackedVector3Array()
		var rail_lo := PackedVector3Array()
		var rail_hi := PackedVector3Array()
		var is_bridge_run := true
		for k in r:
			var e := P[k] + Rt[k] * half * side
			if (F[k] & F_BRIDGE) == 0:
				is_bridge_run = false
			if sw > 0.0:
				inner_b.append(e)
				inner_t.append(e + Vector3(0, CURB, 0))
				var o := P[k] + Rt[k] * (half + sw) * side + Vector3(0, CURB, 0)
				outer_t.append(o)
				outer_b.append(o - Vector3(0, 0.7, 0))
			else:
				inner_t.append(e)
				var o2 := P[k] + Rt[k] * (half + 1.4) * side - Vector3(0, 0.45, 0)
				outer_t.append(o2)
				outer_b.append(o2 - Vector3(0, 0.6, 0))
		if sw > 0.0:
			var curb_col := Color(0.82, 0.8, 0.76)
			var pav := Color(0.95, 0.93, 0.9)
			if side > 0.0:
				kit.ribbon("concrete", inner_b, inner_t, curb_col)
				kit.ribbon("paving", inner_t, outer_t, pav)
				kit.ribbon("concrete", outer_t, outer_b, curb_col)
			else:
				kit.ribbon("concrete", inner_t, inner_b, curb_col)
				kit.ribbon("paving", outer_t, inner_t, pav)
				kit.ribbon("concrete", outer_b, outer_t, curb_col)
		else:
			var gcol := Color(0.9, 0.86, 0.8)
			if side > 0.0:
				kit.ribbon("gravel", inner_t, outer_t, gcol)
				kit.ribbon("gravel", outer_t, outer_b, gcol)
			else:
				kit.ribbon("gravel", outer_t, inner_t, gcol)
				kit.ribbon("gravel", outer_b, outer_t, gcol)
		# guard rails above drops (mountain roads / highways), not on bridges (they have parapets)
		if rt["guard"] and not is_bridge_run:
			_guard_rails(kit, P, Rt, F, r, half + 0.9, side, org)


func _guard_rails(kit: MeshKit, P: PackedVector3Array, Rt: PackedVector3Array, F: PackedByteArray, r: Array,
		off: float, side: float, org: Vector3) -> void:
	var seg_lo := PackedVector3Array()
	var seg_hi := PackedVector3Array()
	var metal := Color(0.72, 0.74, 0.76)
	var post_col := Color(0.55, 0.56, 0.58)
	for k in r:
		var base := P[k] + Rt[k] * off * side
		var w := base + org
		var drop := P[k].y + org.y - WorldData.height_at(w.x + Rt[k].x * 3.0 * side, w.z + Rt[k].z * 3.0 * side)
		if drop > 1.6 and (F[k] & F_BRIDGE) == 0:
			seg_lo.append(base + Vector3(0, 0.45, 0))
			seg_hi.append(base + Vector3(0, 0.8, 0))
			if k % 2 == 0:
				kit.box_yaw("metal", base - Vector3(0, 0.3, 0), 0.0, Vector3(0.12, 1.1, 0.12), post_col)
		else:
			if seg_lo.size() > 1:
				kit.ribbon("metal", seg_lo, seg_hi, metal)
				kit.ribbon("metal", seg_hi, seg_lo, metal)
			seg_lo = PackedVector3Array()
			seg_hi = PackedVector3Array()
	if seg_lo.size() > 1:
		kit.ribbon("metal", seg_lo, seg_hi, metal)
		kit.ribbon("metal", seg_hi, seg_lo, metal)


func _bridges(kit: MeshKit, P: PackedVector3Array, Rt: PackedVector3Array, F: PackedByteArray, cnt: int,
		hw: float, org: Vector3) -> void:
	var k := 0
	var concrete := Color(0.78, 0.76, 0.72)
	while k < cnt:
		if (F[k] & F_BRIDGE) == 0:
			k += 1
			continue
		var s := k
		while k < cnt and (F[k] & F_BRIDGE) != 0:
			k += 1
		var e := mini(k, cnt - 1)
		var top_l := PackedVector3Array()
		var top_r := PackedVector3Array()
		var bot_l := PackedVector3Array()
		var bot_r := PackedVector3Array()
		var par_l_in := PackedVector3Array()
		var par_l_top := PackedVector3Array()
		var par_r_in := PackedVector3Array()
		var par_r_top := PackedVector3Array()
		var par_l_out := PackedVector3Array()
		var par_r_out := PackedVector3Array()
		for q in range(s, e + 1):
			var lft := P[q] - Rt[q] * (hw + 0.4)
			var rgt := P[q] + Rt[q] * (hw + 0.4)
			top_l.append(lft)
			top_r.append(rgt)
			bot_l.append(lft - Vector3(0, 1.4, 0))
			bot_r.append(rgt - Vector3(0, 1.4, 0))
			par_l_in.append(lft + Rt[q] * 0.4 + Vector3(0, 0.15, 0))
			par_l_top.append(lft + Rt[q] * 0.2 + Vector3(0, 1.05, 0))
			par_l_out.append(lft + Vector3(0, 0.15, 0))
			par_r_in.append(rgt - Rt[q] * 0.4 + Vector3(0, 0.15, 0))
			par_r_top.append(rgt - Rt[q] * 0.2 + Vector3(0, 1.05, 0))
			par_r_out.append(rgt + Vector3(0, 0.15, 0))
		kit.ribbon("concrete", bot_r, bot_l, concrete)      # underside (faces down)
		kit.ribbon("concrete", bot_l, top_l, concrete)      # left side
		kit.ribbon("concrete", top_r, bot_r, concrete)      # right side
		# parapets
		kit.ribbon("concrete", par_l_top, par_l_in, concrete)
		kit.ribbon("concrete", par_l_out, par_l_top, concrete)
		kit.ribbon("concrete", par_r_in, par_r_top, concrete)
		kit.ribbon("concrete", par_r_top, par_r_out, concrete)
		# piers every ~20 m where the deck is high above ground
		for q in range(s, e + 1, 5):
			var w := P[q] + org
			var g := WorldData.height_at(w.x, w.z)
			var hgt := P[q].y - 1.4 - g + 1.0
			if hgt > 1.5:
				var yaw := atan2(Rt[q].x, Rt[q].z)
				kit.box_yaw("concrete", Vector3(P[q].x, g - 1.0 - org.y, P[q].z), yaw,
					Vector3(1.6, hgt, (hw + 0.4) * 1.5), concrete)
		# abutments at both ends
		for q in [s, e]:
			var yaw2 := atan2(Rt[q].x, Rt[q].z)
			var w2 := P[q] + org
			var g2 := WorldData.height_at(w2.x, w2.z)
			kit.box_yaw("concrete", Vector3(P[q].x, g2 - 2.0 - org.y, P[q].z), yaw2,
				Vector3((hw + 0.6) * 2.0, P[q].y + org.y - g2 + 1.9, 3.0), concrete)


func _tunnels(kit: MeshKit, P: PackedVector3Array, Rt: PackedVector3Array, F: PackedByteArray, cnt: int,
		half: float, org: Vector3) -> void:
	var k := 0
	var wall := Color(0.7, 0.69, 0.66)
	var hw := half + 1.6
	var arc := 8
	while k < cnt:
		if (F[k] & F_TUNNEL) == 0:
			k += 1
			continue
		var s := k
		while k < cnt and (F[k] & F_TUNNEL) != 0:
			k += 1
		var e := mini(k, cnt - 1)
		# tube cross-section: walking along the arc from right wall bottom to left wall bottom
		var prof: Array = []
		prof.append(Vector2(hw, -0.2))
		prof.append(Vector2(hw, 4.2))
		for q in range(1, arc):
			var ang := PI * float(q) / arc
			prof.append(Vector2(cos(ang) * hw, 4.2 + sin(ang) * 3.2))
		prof.append(Vector2(-hw, 4.2))
		prof.append(Vector2(-hw, -0.2))
		for pi in prof.size() - 1:
			var la := PackedVector3Array()
			var lb := PackedVector3Array()
			for q in range(s, e + 1):
				var a2: Vector2 = prof[pi]
				var b2: Vector2 = prof[pi + 1]
				la.append(P[q] + Rt[q] * a2.x + Vector3(0, a2.y, 0))
				lb.append(P[q] + Rt[q] * b2.x + Vector3(0, b2.y, 0))
			# inward facing
			kit.ribbon("concrete", la, lb, wall)
		# lighting strip on the ceiling + curbs
		var l1 := PackedVector3Array()
		var l2 := PackedVector3Array()
		for q in range(s, e + 1):
			l1.append(P[q] + Rt[q] * 0.4 + Vector3(0, 7.25, 0))
			l2.append(P[q] - Rt[q] * 0.4 + Vector3(0, 7.25, 0))
		kit.ribbon("lamp_always", l1, l2, Color(1.0, 0.85, 0.55))
		# portals
		for q in [s, e]:
			var yaw := atan2(Rt[q].x, Rt[q].z)
			var t := Transform3D(Basis(Vector3.UP, yaw), P[q] - Vector3(0, 0.5, 0))
			var pc := Color(0.62, 0.6, 0.57)
			kit.box("concrete", t, Vector3(-(hw + 4.0), 6.5, 0), Vector3(8.0, 14.0, 1.5), pc)
			kit.box("concrete", t, Vector3(hw + 4.0, 6.5, 0), Vector3(8.0, 14.0, 1.5), pc)
			kit.box("concrete", t, Vector3(0, 11.5, 0), Vector3(hw * 2.0, 4.0, 1.5), pc)
			kit.box("concrete", t, Vector3(0, 14.0, 0), Vector3(hw * 2.0 + 17.0, 1.2, 2.0), Color(0.5, 0.48, 0.46))


func _crosswalk(kit: MeshKit, cw: Array, org: Vector3) -> void:
	var yaw := deg_to_rad(float(cw[3]))
	var w: float = cw[4]
	var c := Vector3(cw[0], float(cw[1]) + WorldData.ROAD_LIFT + 0.03, cw[2]) - org
	var fwd := Vector3(sin(yaw), 0, cos(yaw))
	var right := fwd.cross(Vector3.UP).normalized()
	var hw := w * 0.5 - 0.6
	var d := 1.8
	var a := c - right * hw - fwd * d
	var b := c + right * hw - fwd * d
	var cc := c + right * hw + fwd * d
	var dd := c - right * hw + fwd * d
	# quad must face up: a,b,c,d counter-clockwise from above => order a, dd, cc, b? check normal
	var n := (b - a).cross(dd - a)
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(hw * 2.0, 0), Vector2(hw * 2.0, d * 2.0), Vector2(0, d * 2.0)])
	if n.y > 0:
		kit.quad("crosswalk", a, b, cc, dd, Color.WHITE, uvs)
	else:
		kit.quad("crosswalk", b, a, dd, cc, Color.WHITE, PackedVector2Array([uvs[1], uvs[0], uvs[3], uvs[2]]))
