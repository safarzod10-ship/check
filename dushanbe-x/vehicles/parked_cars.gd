class_name ParkedCars
extends Node3D
## Drivable parked cars near the player: kerbside on city streets, at parking lots / gas stations,
## and one guaranteed car next to the player spawn (Dusti square, Rudaki avenue).
## Cars stay frozen (static) until the player comes close, then become physics bodies.

const RADIUS := 230.0
const KEEP := 330.0
const WAKE := 45.0
const MAX_PARKED := 16

var spots: Dictionary = {}     # key -> Vehicle
var _timer := 0.0
var _spawn_car_done := false


func _physics_process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 1.0
	var focus := GameState.focus_position()
	if not _spawn_car_done and WorldData.loaded:
		_spawn_car_done = true
		_spawn_start_car()
	# cleanup / wake
	for k in spots.keys():
		var v: Vehicle = spots[k]
		if not is_instance_valid(v):
			spots.erase(k)
			continue
		var d := v.global_position.distance_to(focus)
		if v.is_player_controlled() or v.driver != null:
			continue
		if d > KEEP and k != "start":
			spots.erase(k)
			v.queue_free()
		elif d < WAKE and v.freeze:
			v.set_parked(false)
	if spots.size() >= MAX_PARKED:
		return
	_fill_pois(focus)
	_fill_kerbs(focus)


func _add(key: String, type: String, pos: Vector3, forward: Vector3) -> void:
	if spots.has(key) or spots.size() >= MAX_PARKED:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var col: Color = CarFactory.default_color(type) if type == "taxi" else CarFactory.PAINTS[rng.randi() % CarFactory.PAINTS.size()]
	var v := Vehicle.create(type, col)
	add_child(v)
	v.global_transform = Transform3D(Vehicle._basis_from_forward(forward.normalized()), pos)
	v.set_parked(true)
	spots[key] = v


func _surface_y(x: float, z: float) -> float:
	var nr := WorldData.nearest_road(x, z, 14.0)
	var g := WorldData.height_at(x, z)
	if not nr.is_empty():
		return maxf(g, nr["pos"].y + WorldData.ROAD_LIFT)
	return g


func _spawn_start_car() -> void:
	var sp: Dictionary = WorldData.world.get("spawn", {"x": 470, "z": 1760})
	# west kerb of Rudaki avenue (southbound side), facing south (+Z)
	var x := 489.6
	var z := float(sp["z"]) + 10.0
	var nr := WorldData.nearest_road(500.0, z, 30.0)
	var fwd := Vector3.BACK
	if not nr.is_empty():
		fwd = WorldData.road_tangent(nr["road"], nr["index"])
		if fwd.z < 0.0:
			fwd = -fwd
		var right := Vector3(-fwd.z, 0, fwd.x)
		var half: float = WorldData.road_type(nr["road"])["half"]
		var p: Vector3 = nr["pos"] + right * (half - 1.3)
		x = p.x
		z = p.z
	_add("start", "sedan", Vector3(x, _surface_y(x, z), z), fwd)
	var v: Vehicle = spots.get("start")
	if v:
		v.name = "StartCar"


func _fill_pois(focus: Vector3) -> void:
	for i in WorldData.pois.size():
		var poi: Dictionary = WorldData.pois[i]
		if poi["type"] not in ["parking", "gas_station"]:
			continue
		var c := Vector3(poi["x"], poi["y"], poi["z"])
		if c.distance_to(focus) > RADIUS:
			continue
		var yaw := deg_to_rad(float(poi["yaw"]))
		var basis := Basis(Vector3.UP, yaw)
		var count := 4 if poi["type"] == "parking" else 2
		for q in count:
			var key := "poi%d_%d" % [i, q]
			var local := Vector3(-6.0 + q * 3.2, 0, 4.0) if poi["type"] == "parking" else Vector3(-4.0 + q * 8.0, 0, 9.0)
			var p := c + basis * local
			var types := ["sedan", "hatchback", "suv", "old_sedan", "taxi"]
			_add(key, types[(i * 3 + q) % types.size()], Vector3(p.x, WorldData.height_at(p.x, p.z), p.z), basis.z)


func _fill_kerbs(focus: Vector3) -> void:
	var sec := WorldData.sector_of(focus.x, focus.z)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector2i(sec.x + dx, sec.y + dz)
			if not WorldData.sector_index.has(k):
				continue
			for run in WorldData.sector_index[k]["road_runs"]:
				var road: int = run[0]
				var rtype: String = WorldData.roads[road]["type"]
				if rtype not in ["street", "boulevard"]:
					continue
				var flags := WorldData.sample_flags(road)
				var start: int = int(run[1]) - int(run[1]) % 37 + 37
				for si in range(start, int(run[2]), 37):
					if hash(road * 7919 + si) % 3 != 0:
						continue
					if si < 6 or si > WorldData.roads[road]["pts"].size() - 7:
						continue
					var bad := false
					for o in range(-6, 7):
						if flags[clampi(si + o, 0, flags.size() - 1)] != 0:
							bad = true
							break
					if bad:
						continue
					var p := WorldData.road_point(road, si)
					if p.distance_to(focus) > RADIUS:
						continue
					var f := WorldData.road_tangent(road, si)
					if hash(si) % 2 == 0:
						f = -f
					var right := Vector3(-f.z, 0, f.x)
					var half: float = WorldData.road_type(road)["half"]
					var pos := p + right * (half - 1.1) + Vector3(0, WorldData.ROAD_LIFT, 0)
					var types := ["sedan", "hatchback", "old_sedan", "suv", "sedan", "minibus"]
					_add("k%d_%d" % [road, si], types[hash(si * 31 + road) % types.size()], pos, f)
					if spots.size() >= MAX_PARKED:
						return
