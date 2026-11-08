class_name TrafficManager
extends Node3D
## System "Traffic": spawns kinematic AI cars on road lanes around the player, police when wanted,
## and parked drivable cars. Density follows GameSettings "traffic_density".

const SPAWN_MIN := 110.0
const SPAWN_MAX := 360.0
const DESPAWN := 460.0

var cars: Array = []
var police: Array = []
var ped_positions: Array = []
var is_idle := false
var parked: ParkedCars
var max_cars := 24
var _spawn_timer := 0.0
var _ped_timer := 0.0
var _police_timer := 0.0
var _first_fill := true
var _age := 0.0
var _rng := RandomNumberGenerator.new()
## road -> Array of [sample_index, intersection_index]
var _road_inters: Dictionary = {}
## intersection_index -> {road: sample_index}
var _inter_samples: Dictionary = {}
## road -> {"start": Array, "end": Array} of [road, sample]
var _end_links: Dictionary = {}


func _ready() -> void:
	_rng.seed = 4242
	GameSettings.changed.connect(_apply_settings)
	_apply_settings()
	parked = ParkedCars.new()
	parked.name = "ParkedCars"
	add_child(parked)


func _apply_settings() -> void:
	max_cars = int(round(28.0 * float(GameSettings.get_v("traffic_density", 1.0))))


func _physics_process(delta: float) -> void:
	var focus := GameState.focus_position()
	_age += delta
	_ped_timer -= delta
	if _ped_timer <= 0.0:
		_ped_timer = 0.3
		ped_positions.clear()
		for p in get_tree().get_nodes_in_group("pedestrians"):
			if p is Node3D and p.global_position.distance_squared_to(focus) < 250000.0:
				ped_positions.append(p.global_position)
	# despawn far cars
	for c in cars.duplicate():
		if not is_instance_valid(c):
			cars.erase(c)
		elif c.global_position.distance_to(focus) > DESPAWN:
			cars.erase(c)
			c.queue_free()
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = 0.25 if _first_fill else 0.6
		var tries := 8 if _first_fill else 2
		for t in tries:
			if cars.size() >= max_cars:
				break
			_try_spawn(focus)
		if cars.size() >= max_cars or _age > 8.0:
			_first_fill = false
		is_idle = cars.size() >= max_cars * 0.6 or not _first_fill
	_police_timer -= delta
	if _police_timer <= 0.0:
		_police_timer = 1.0
		_update_police(focus)
	for p in police:
		if is_instance_valid(p):
			_drive_police(p, focus, delta)


# ---------------------------------------------------------------------------
# Spawning
# ---------------------------------------------------------------------------
func _try_spawn(focus: Vector3) -> void:
	var sec := WorldData.sector_of(focus.x, focus.z)
	var keys := []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector2i(sec.x + dx, sec.y + dz)
			if WorldData.sector_index.has(k):
				keys.append(k)
	if keys.is_empty():
		return
	var sd: Dictionary = WorldData.sector_index[keys[_rng.randi() % keys.size()]]
	var runs: Array = sd["road_runs"]
	if runs.is_empty():
		return
	var run: Array = runs[_rng.randi() % runs.size()]
	var road: int = run[0]
	var rtype: String = WorldData.roads[road]["type"]
	if rtype == "dirt":
		return
	var si := _rng.randi_range(int(run[1]), int(run[2]))
	var pts: Array = WorldData.roads[road]["pts"]
	if si < 2 or si > pts.size() - 3:
		return
	var flags := WorldData.sample_flags(road)
	if flags[si] & 4:
		return
	var p := WorldData.road_point(road, si)
	var d := p.distance_to(focus)
	var dmin := 30.0 if _first_fill else SPAWN_MIN
	if d < dmin or d > SPAWN_MAX:
		return
	for c in cars:
		if is_instance_valid(c) and c.global_position.distance_squared_to(p) < 400.0:
			return
	var rt: Dictionary = WorldData.road_type(road)
	var per_dir := maxi(1, int(rt["lanes"]) / 2)
	var lane_n := per_dir - 1 if per_dir >= 3 else per_dir
	var lane := _rng.randi_range(0, maxi(0, lane_n - 1))
	var direction := 1 if _rng.randf() < 0.5 else -1
	var type := _pick_type(rtype, lane, per_dir)
	var car := AICar.new()
	car.manager = self
	var col: Color = CarFactory.default_color(type) if type in ["taxi", "bus", "minibus", "police"] else CarFactory.random_paint(_rng)
	add_child(car)
	car.setup(type, col, road, float(si), direction, lane)
	cars.append(car)


## Spawn a specific AI car (used by tests / scripted scenes).
func spawn_on(road: int, si: int, direction: int, lane: int, type: String) -> AICar:
	var car := AICar.new()
	car.manager = self
	var col: Color = CarFactory.default_color(type) if type in ["taxi", "bus", "minibus", "police"] else CarFactory.random_paint(_rng)
	add_child(car)
	car.setup(type, col, road, float(si), direction, lane)
	cars.append(car)
	return car


func _pick_type(rtype: String, lane: int, per_dir: int) -> String:
	var r := _rng.randf()
	if rtype in ["avenue", "boulevard"]:
		if r < 0.1 and lane == 0:
			return "bus"
		if r < 0.2:
			return "minibus"
		if r < 0.42:
			return "taxi"
	elif rtype == "highway":
		if r < 0.2:
			return "truck"
		if r < 0.28:
			return "minibus"
	elif rtype in ["rural", "mountain"]:
		if r < 0.25:
			return "old_sedan"
		if r < 0.4:
			return "truck"
		if r < 0.55:
			return "suv"
	r = _rng.randf()
	if r < 0.35:
		return "sedan"
	if r < 0.55:
		return "hatchback"
	if r < 0.72:
		return "old_sedan"
	if r < 0.88:
		return "suv"
	return "taxi"


func on_car_converted(old: Node, _v: Vehicle) -> void:
	cars.erase(old)


# ---------------------------------------------------------------------------
# Road graph helpers (lazy)
# ---------------------------------------------------------------------------
func _nearest_sample(road: int, x: float, z: float) -> int:
	var pts: Array = WorldData.roads[road]["pts"]
	var best := 0
	var bd := INF
	for i in pts.size():
		var p: Array = pts[i]
		var d: float = (p[0] - x) * (p[0] - x) + (p[2] - z) * (p[2] - z)
		if d < bd:
			bd = d
			best = i
	return best


func _inter_sample(ii: int, road: int) -> int:
	if not _inter_samples.has(ii):
		_inter_samples[ii] = {}
	var m: Dictionary = _inter_samples[ii]
	if not m.has(road):
		var it: Array = WorldData.intersections[ii]
		m[road] = _nearest_sample(road, it[0], it[1])
	return m[road]


func _road_intersections(road: int) -> Array:
	if _road_inters.has(road):
		return _road_inters[road]
	var out := []
	for ii in WorldData.intersections.size():
		var it: Array = WorldData.intersections[ii]
		if (it[2] as Array).has(road):
			out.append([_inter_sample(ii, road), ii])
	_road_inters[road] = out
	return out


## If the car crossed an intersection between samples a and b, returns [new_road, new_sample].
func intersection_between(road: int, a: float, b: float) -> Array:
	var lo := minf(a, b)
	var hi := maxf(a, b)
	for e in _road_intersections(road):
		var si: int = e[0]
		if si > lo and si <= hi:
			var it: Array = WorldData.intersections[e[1]]
			var opts: Array = []
			for r2 in it[2]:
				if r2 != road and WorldData.roads[r2]["type"] != "dirt":
					opts.append(r2)
			if opts.is_empty():
				return []
			var r2: int = opts[_rng.randi() % opts.size()]
			return [r2, _inter_sample(e[1], r2)]
	return []


## Connection at the end of a road (or empty).
func connection_at_end(road: int, at_end: bool) -> Array:
	var key := "%d_%s" % [road, at_end]
	if not _end_links.has(key):
		var pts: Array = WorldData.roads[road]["pts"]
		var p: Array = pts[pts.size() - 1] if at_end else pts[0]
		var opts := []
		# 1) recorded intersections near the end
		for ii in WorldData.intersections.size():
			var it: Array = WorldData.intersections[ii]
			if absf(it[0] - p[0]) < 40.0 and absf(it[1] - p[2]) < 40.0:
				for r2 in it[2]:
					if r2 != road and WorldData.roads[r2]["type"] != "dirt":
						opts.append([r2, _inter_sample(ii, r2)])
		# 2) any other road passing close to the end point
		if opts.is_empty():
			var nr := _nearest_other_road(p[0], p[2], road, 30.0)
			if not nr.is_empty():
				opts.append(nr)
		_end_links[key] = opts
	var o: Array = _end_links[key]
	if o.is_empty():
		return []
	return o[_rng.randi() % o.size()]


func _nearest_other_road(x: float, z: float, exclude: int, maxd: float) -> Array:
	var best := []
	var bd := maxd * maxd
	var sec := WorldData.sector_of(x, z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector2i(sec.x + dx, sec.y + dz)
			if not WorldData.sector_index.has(k):
				continue
			for run in WorldData.sector_index[k]["road_runs"]:
				var r2: int = run[0]
				if r2 == exclude or WorldData.roads[r2]["type"] == "dirt":
					continue
				var pts: Array = WorldData.roads[r2]["pts"]
				for i in range(int(run[1]), int(run[2]) + 1):
					var p: Array = pts[i]
					var d: float = (p[0] - x) * (p[0] - x) + (p[2] - z) * (p[2] - z)
					if d < bd:
						bd = d
						best = [r2, i]
	return best


# ---------------------------------------------------------------------------
# Police
# ---------------------------------------------------------------------------
func _update_police(focus: Vector3) -> void:
	for p in police.duplicate():
		if not is_instance_valid(p):
			police.erase(p)
			continue
		var far: bool = p.global_position.distance_to(focus) > 420.0
		if far or (GameState.wanted == 0 and p.global_position.distance_to(focus) > 120.0):
			police.erase(p)
			p.queue_free()
	if GameState.wanted <= 0:
		for p in police:
			p.siren_on = false
		return
	var want := clampi(GameState.wanted, 1, 3)
	if police.size() < want:
		_spawn_police(focus)


func _spawn_police(focus: Vector3) -> void:
	# a road sample 120-200 m away
	for attempt in 30:
		var ang := _rng.randf() * TAU
		var dist := _rng.randf_range(110.0, 180.0)
		var q := focus + Vector3(cos(ang), 0, sin(ang)) * dist
		var nr := WorldData.nearest_road(q.x, q.z, 60.0)
		if nr.is_empty():
			continue
		var flags := WorldData.sample_flags(nr["road"])
		if flags[nr["index"]] & 6:
			continue
		var p: Vector3 = nr["pos"]
		var v := Vehicle.create("police")
		add_child(v)
		var f := WorldData.road_tangent(nr["road"], nr["index"])
		var to_player := (focus - p)
		if f.dot(to_player) < 0.0:
			f = -f
		v.global_transform = Transform3D(Vehicle._basis_from_forward(f), p + Vector3(0, WorldData.ROAD_LIFT + 0.15, 0))
		v.add_to_group("police")
		v.set_parked(false)
		v.ai_enabled = true
		v.siren_on = true
		v.set_meta("stuck", 0.0)
		police.append(v)
		return


func _drive_police(v: Vehicle, focus: Vector3, delta: float) -> void:
	if GameState.wanted <= 0:
		# drive away calmly
		v.ai_input = {"throttle": 0.4, "brake": 0.0, "steer": 0.0, "handbrake": false}
		v.siren_on = false
		return
	v.siren_on = true
	var local := v.to_local(focus)
	var ang := atan2(local.x, local.z)          # + = target on the left
	var dist := local.length()
	var steer := clampf(ang * 1.6, -1.0, 1.0)
	var throttle := clampf(dist / 30.0, 0.2, 1.0) * (1.0 - clampf(absf(ang) - 1.2, 0.0, 0.7))
	var brk := 0.0
	if dist < 9.0:
		throttle = 0.0
		brk = 1.0
	var stuck: float = v.get_meta("stuck", 0.0)
	if v.get_speed_kmh() < 3.0 and throttle > 0.3:
		stuck += delta
	else:
		stuck = maxf(0.0, stuck - delta * 0.5)
	if stuck > 2.5:
		# reverse out while steering the other way
		throttle = 0.0
		brk = 1.0
		steer = -steer
		if stuck > 4.5:
			stuck = 0.0
	v.set_meta("stuck", stuck)
	v.ai_input = {"throttle": throttle, "brake": brk, "steer": steer, "handbrake": absf(ang) > 1.4 and v.get_speed_kmh() > 30.0}
