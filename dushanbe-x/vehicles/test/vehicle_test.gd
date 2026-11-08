extends Node3D
## Vehicle test harness.
##   Physics drive test (fast, headless):
##     godot --headless --path . res://vehicles/test/vehicle_test.tscn -- --mode=drive
##   Beauty / traffic screenshots:
##     xvfb-run -a godot --path . --rendering-driver vulkan --resolution 960x540 res://vehicles/test/vehicle_test.tscn -- --mode=shots --out=DIR

var terrain: Node
var mode := "drive"
var out_dir := "/tmp/claude-0/shots"
var cam: Camera3D


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mode="):
			mode = a.substr(7)
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out_dir)
	cam = Camera3D.new()
	cam.far = 9000.0
	add_child(cam)
	cam.make_current()
	GameState.camera = cam
	TimeWeather.paused = true
	TimeWeather.auto_weather = false
	TimeWeather.hour = 11.0
	if mode == "shots":
		_add_system("res://world/environment/day_night.gd", "Environment")
	terrain = _add_system("res://world/terrain/terrain_streamer.gd", "Terrain")
	for extra in [["res://world/roads/road_network.gd", "Roads"], ["res://world/city/city_streamer.gd", "City"],
			["res://world/landmarks/landmark_manager.gd", "Landmarks"]]:
		if mode == "shots" and ResourceLoader.exists(extra[0]):
			_add_system(extra[0], extra[1])
	if mode == "drive":
		_drive_test()
	else:
		_shots()


func _add_system(path: String, n: String) -> Node:
	if not ResourceLoader.exists(path):
		return null
	var node: Node = load(path).new()
	node.name = n
	add_child(node)
	return node


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _wait_collision(p: Vector3, timeout := 30.0) -> bool:
	var t := 0.0
	while t < timeout:
		var key := WorldData.sector_of(p.x, p.z)
		if terrain and terrain.chunks[key]["body"] != null:
			return true
		await _wait(0.25)
		t += 0.25
	return false


# ---------------------------------------------------------------------------
# Physics drive test with a simple road-following autopilot
# ---------------------------------------------------------------------------
func _find_road(name_part: String) -> int:
	for i in WorldData.roads.size():
		if str(WorldData.roads[i]["name"]).contains(name_part):
			return i
	return -1


func _drive_test() -> void:
	var results := []
	for test in [["проспект Рудаки", "sedan", 0.75, 26.0, 40.0], ["Серпантин", "suv", 0.05, 0.0, 70.0],
			["Трасса Душанбе — Варзоб", "minibus", 0.2, 0.0, 45.0], ["Серпантин", "bus", 0.05, 0.0, 40.0]]:
		var r: Dictionary = await _drive_one(test[0], test[1], test[2], 0.0, test[4])
		results.append(r)
	results.append(await _police_test())
	print("=== DRIVE RESULTS ===")
	for r in results:
		print(JSON.stringify(r))
	get_tree().quit()


func _drive_one(road_name: String, type: String, start_frac: float, _unused: float, seconds: float) -> Dictionary:
	var ri := _find_road(road_name)
	var pts: Array = WorldData.roads[ri]["pts"]
	var si := int(pts.size() * start_frac) + 2
	var dir := 1
	var f := WorldData.road_tangent(ri, si) * dir
	var right := Vector3(-f.z, 0, f.x)
	var lane_off := 1.75 if int(WorldData.road_type(ri)["lanes"]) > 1 else 0.0
	var p := WorldData.road_point(ri, si) + right * lane_off + Vector3(0, WorldData.ROAD_LIFT + 0.3, 0)
	var v := Vehicle.create(type)
	add_child(v)
	v.global_transform = Transform3D(Vehicle._basis_from_forward(f), p)
	GameState.current_vehicle = v
	cam.global_position = p + Vector3(0, 5, 0)
	var ok := await _wait_collision(p)
	v.set_parked(false)
	v.ai_enabled = true
	var t := 0.0
	var start := v.global_position
	var max_kmh := 0.0
	var min_up := 1.0
	var max_below := -99.0
	var log_t := 0.0
	var dist := 0.0
	var last := start
	var target_kmh := 60.0 if type != "bus" else 40.0
	if road_name.contains("Серпантин"):
		target_kmh = 35.0 if type != "bus" else 25.0
	while t < seconds:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		# autopilot: steer to a lane point ~16 m ahead
		var nr := WorldData.nearest_road(v.global_position.x, v.global_position.z, 40.0)
		var idx: int = si
		if not nr.is_empty() and nr["road"] == ri:
			idx = nr["index"]
		elif not nr.is_empty():
			# find on our road near position
			idx = si
		si = idx
		var ahead := clampi(idx + dir * (4 + int(v.get_speed_kmh() / 12.0)), 0, pts.size() - 1)
		var fa := WorldData.road_tangent(ri, ahead) * dir
		var ra := Vector3(-fa.z, 0, fa.x)
		var target := WorldData.road_point(ri, ahead) + ra * lane_off
		var local := v.to_local(target)
		var ang := atan2(local.x, local.z)
		var kmh := v.get_speed_kmh()
		var tk := target_kmh * (1.0 - clampf(absf(ang) * 1.5, 0.0, 0.6))
		v.ai_input = {"throttle": clampf((tk - kmh) / 10.0, 0.0, 1.0), "brake": clampf((kmh - tk - 5.0) / 10.0, 0.0, 1.0),
			"steer": clampf(ang * 2.2, -1.0, 1.0), "handbrake": false}
		if idx >= pts.size() - 6:
			break
		var gp := v.global_position
		dist += gp.distance_to(last)
		last = gp
		max_kmh = maxf(max_kmh, kmh)
		min_up = minf(min_up, v.global_transform.basis.y.y)
		max_below = maxf(max_below, WorldData.height_at(gp.x, gp.z) - gp.y)
		log_t += dt
		if log_t > 2.0:
			log_t = 0.0
			print("[%s %s] t=%.1f pos=(%.0f,%.1f,%.0f) kmh=%.1f up=%.2f off_road=%.1f" % [type, road_name, t, gp.x, gp.y, gp.z, kmh, v.global_transform.basis.y.y,
				0.0 if nr.is_empty() else nr["dist"]])
	var res := {"road": road_name, "type": type, "collision_ready": ok, "time": snappedf(t, 0.1), "distance_m": snappedf(dist, 0.1),
		"climb_m": snappedf(v.global_position.y - start.y, 0.1), "max_kmh": snappedf(max_kmh, 0.1), "min_up": snappedf(min_up, 0.01),
		"max_below_terrain": snappedf(max_below, 0.01)}
	v.queue_free()
	GameState.current_vehicle = null
	await _wait(0.2)
	return res


# ---------------------------------------------------------------------------
# Screenshots
# ---------------------------------------------------------------------------
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out_dir.path_join(name))
	print("saved ", name)


func _wait_terrain(max_t := 120.0) -> void:
	var t := 0.0
	while t < max_t:
		await _wait(0.5)
		t += 0.5
		var idle := true
		for c in get_children():
			if "is_idle" in c and not c.is_idle:
				idle = false
		if idle and t > 3.0:
			return


func _shots() -> void:
	# 1) line-up of all types on Dusti square
	var z0 := 1790.0
	var x := 318.0
	var paints := [Color(0.55, 0.06, 0.07), Color(0.07, 0.17, 0.42), Color(0.62, 0.64, 0.67), Color(0, 0, 0, 0),
		Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0.1, 0.3, 0.18)]
	var ti := 0
	var y0 := WorldData.height_at(380, z0)
	for type in CarFactory.TYPES:
		var d := CarFactory.build(type)
		x += d["width"] * 0.5 + 0.9
		var v := Vehicle.create(type, paints[ti])
		ti += 1
		add_child(v)
		var ang := deg_to_rad(-25.0)
		v.global_transform = Transform3D(Basis(Vector3.UP, ang), Vector3(x, WorldData.height_at(x, z0) + 0.02, z0 - d["length"] * 0.35))
		if type == "police":
			v.siren_on = true
		x += d["width"] * 0.5 + 0.9
	cam.fov = 55.0
	var mid := (318.0 + x) * 0.5
	cam.global_position = Vector3(mid - 6.0, y0 + 5.0, z0 + 21.0)
	cam.look_at(Vector3(mid - 2.0, y0 + 0.8, z0 - 2.0))
	await _wait_terrain()
	await _shot("vehicles_lineup.png")
	cam.global_position = Vector3(334, y0 + 2.0, z0 + 7.0)
	cam.look_at(Vector3(328, y0 + 0.9, z0 - 1.0))
	await _wait(1.0)
	await _shot("vehicles_closeup.png")
	# night
	TimeWeather.hour = 21.5
	cam.global_position = Vector3(mid - 6.0, y0 + 5.0, z0 + 21.0)
	cam.look_at(Vector3(mid - 2.0, y0 + 0.8, z0 - 2.0))
	await _wait(2.0)
	await _shot("vehicles_night.png")
	TimeWeather.hour = 11.0
	# 2) traffic on Rudaki avenue
	var tm := TrafficManager.new()
	tm.name = "Traffic"
	add_child(tm)
	cam.fov = 60.0
	cam.global_position = Vector3(522, WorldData.height_at(522, 2330) + 7.0, 2330)
	cam.look_at(Vector3(500, WorldData.height_at(500, 2250) + 1.0, 2250))
	var rud := _find_road("проспект Рудаки")
	var rpts: Array = WorldData.roads[rud]["pts"]
	var types := ["sedan", "taxi", "bus", "hatchback", "minibus", "suv", "old_sedan", "taxi", "sedan", "truck"]
	var q := 0
	for i in rpts.size():
		var zz: float = rpts[i][2]
		if zz > 2120.0 and zz < 2300.0 and i % 7 == 0 and q < types.size():
			tm.spawn_on(rud, i, 1 if q % 2 == 0 else -1, (q / 2) % 2, types[q])
			q += 1
	await _wait_terrain()
	await _wait(3.0)
	print("traffic cars: ", tm.cars.size(), " parked: ", tm.parked.spots.size())
	for c in tm.cars:
		if is_instance_valid(c) and c.global_position.distance_to(cam.global_position) < 150.0:
			print("  car ", c.car_type, " pos ", c.global_position, " kmh ", snappedf(c.get_speed_kmh(), 0.1), " ground ", snappedf(WorldData.height_at(c.global_position.x, c.global_position.z), 0.01))
	await _shot("vehicles_traffic.png")
	get_tree().quit()


func _police_test() -> Dictionary:
	var tm := TrafficManager.new()
	tm.name = "Traffic"
	add_child(tm)
	var rud := _find_road("проспект Рудаки")
	var p := WorldData.road_point(rud, 500) + Vector3(-8, WorldData.ROAD_LIFT + 0.3, 0)
	var target := Vehicle.create("sedan")
	add_child(target)
	target.global_transform = Transform3D(Basis.IDENTITY, p)
	GameState.current_vehicle = target
	await _wait_collision(p)
	target.set_parked(false)
	GameState.set_wanted(2)
	var t := 0.0
	var min_d := 9999.0
	var first_d := -1.0
	while t < 40.0:
		await _wait(1.0)
		t += 1.0
		for pc in tm.police:
			if is_instance_valid(pc):
				var d: float = pc.global_position.distance_to(target.global_position)
				if first_d < 0.0:
					first_d = d
				min_d = minf(min_d, d)
		if int(t) % 5 == 0:
			print("[police] t=%d count=%d min_dist=%.1f traffic=%d" % [t, tm.police.size(), min_d, tm.cars.size()])
	GameState.set_wanted(0)
	return {"test": "police", "police_count": tm.police.size(), "start_dist": snappedf(first_d, 0.1), "closest": snappedf(min_d, 0.1), "traffic_cars": tm.cars.size()}
