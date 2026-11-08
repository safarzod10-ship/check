extends Node3D
## DUSHANBE-X entry point. Builds the world systems, the player and the UI.
##
## Test / screenshot mode (used for automated visual checks):
##   godot --path . -- --shots=res://tools/shots.json
##   godot --path . -- --shot=out.png --cam=x,y,z,yaw,pitch --hour=10 --weather=0
## y may be written as g20 = 20 m above the ground.

const SYSTEMS := [
	["Environment", "res://world/environment/day_night.gd"],
	["Terrain", "res://world/terrain/terrain_streamer.gd"],
	["Water", "res://world/water/water_system.gd"],
	["Roads", "res://world/roads/road_network.gd"],
	["City", "res://world/city/city_streamer.gd"],
	["Landmarks", "res://world/landmarks/landmark_manager.gd"],
	["Nature", "res://world/nature/vegetation_streamer.gd"],
	["Props", "res://world/props/prop_streamer.gd"],
	["Traffic", "res://vehicles/traffic_manager.gd"],
	["Pedestrians", "res://characters/npc/pedestrian_manager.gd"],
	["Audio", "res://audio/ambience.gd"],
	["Events", "res://world/events/events.gd"],
]

var systems: Dictionary = {}
var _shots: Array = []
var _shot_cam: Camera3D
var _shot_wait := 0.0
var _shot_frames := 0
var _shot_index := -1
var _stats_out := ""


func _ready() -> void:
	var args := _parse_args()
	GameState.screenshot_mode = args.has("shot") or args.has("shots")
	if args.has("preset") and GameSettings.PRESETS.has(args["preset"]):
		# test runs: use a preset without overwriting the player's saved settings
		GameSettings.values = GameSettings.PRESETS[args["preset"]].duplicate()
		GameSettings.apply()
	var only: PackedStringArray = str(args.get("only", "")).split(",", false)
	for s in SYSTEMS:
		if not only.is_empty() and not only.has(s[0]):
			continue
		if ResourceLoader.exists(s[1]):
			var scr: Script = load(s[1])
			if scr == null or not scr.can_instantiate():
				push_error("[Main] system failed to compile: " + s[1])
				continue
			var node: Node = scr.new()
			node.name = s[0]
			add_child(node)
			systems[s[0]] = node
		else:
			print("[Main] system not present yet: ", s[1])
	_make_world_bounds()
	if GameState.screenshot_mode:
		_setup_shots(args)
	else:
		_spawn_player()
		if ResourceLoader.exists("res://ui/hud.tscn"):
			add_child(load("res://ui/hud.tscn").instantiate())
		if args.has("preset") and GameSettings.PRESETS.has(args["preset"]):
			pass
		if args.has("gameshots"):
			_run_gameshots(args)


## Rough per-system render budget: visible geometry instances, surfaces and triangles (no shadow passes).
func _profile() -> void:
	var cam := get_viewport().get_camera_3d()
	for k in systems.keys() + ["Player"]:
		var root: Node = systems.get(k, get_node_or_null(k))
		if root == null:
			continue
		var stats := [0, 0, 0]
		_profile_node(root, cam, stats)
		if stats[0] > 0:
			print("    %-12s inst=%4d surfaces=%4d tris=%8d" % [k, stats[0], stats[1], stats[2]])


func _profile_node(n: Node, cam: Camera3D, stats: Array) -> void:
	if n is Node3D and not (n as Node3D).is_visible_in_tree():
		return
	if n is GeometryInstance3D:
		var gi := n as GeometryInstance3D
		var d := cam.global_position.distance_to(gi.global_transform * gi.get_aabb().get_center()) if cam else 0.0
		if gi.visibility_range_end > 0.0 and d > gi.visibility_range_end:
			pass
		else:
			var mesh: Mesh = null
			var count := 1
			if n is MeshInstance3D:
				mesh = (n as MeshInstance3D).mesh
			elif n is MultiMeshInstance3D and (n as MultiMeshInstance3D).multimesh:
				mesh = (n as MultiMeshInstance3D).multimesh.mesh
				count = (n as MultiMeshInstance3D).multimesh.instance_count
			if mesh:
				stats[0] += 1
				stats[1] += mesh.get_surface_count()
				var tris := 0
				for si in mesh.get_surface_count():
					var arr := mesh.surface_get_arrays(si)
					var idx = arr[Mesh.ARRAY_INDEX]
					tris += (idx.size() / 3) if idx != null else (arr[Mesh.ARRAY_VERTEX].size() / 3)
				stats[2] += tris * count
	for c in n.get_children():
		_profile_node(c, cam, stats)


## Gameplay capture for testing: real player, HUD, traffic. Steps (JSON list):
## {"wait": s} | {"hour": h} | {"weather": n} | {"teleport": "x,z,yaw"} | {"press": action, "time": s}
## | {"enter_car": true} | {"look": "dx,dy"} | {"shot": path}
func _run_gameshots(args: Dictionary) -> void:
	var steps: Array = JSON.parse_string(FileAccess.get_file_as_string(args["gameshots"]))
	TimeWeather.auto_weather = false
	for st in steps:
		if st.has("hour"):
			TimeWeather.hour = float(st["hour"])
		if st.has("weather"):
			TimeWeather.set_weather(int(st["weather"]))
		if st.has("teleport"):
			var c: PackedStringArray = str(st["teleport"]).split(",")
			var x := float(c[0])
			var z := float(c[1])
			var target: Node3D = GameState.current_vehicle if GameState.current_vehicle else GameState.player
			target.global_position = Vector3(x, WorldData.height_at(x, z) + 1.5, z)
			target.rotation = Vector3(0, deg_to_rad(float(c[2])) if c.size() > 2 else 0.0, 0)
			if target is RigidBody3D:
				target.linear_velocity = Vector3.ZERO
			if target is CharacterBody3D:
				target.velocity = Vector3.ZERO
		if st.has("look"):
			var l: PackedStringArray = str(st["look"]).split(",")
			GameState.look_delta += Vector2(float(l[0]), float(l[1]))
		if st.has("enter_car"):
			var best: Node3D = null
			var bd := 1e9
			for v in get_tree().get_nodes_in_group("vehicles"):
				var d: float = v.global_position.distance_to(GameState.player.global_position)
				if d < bd:
					bd = d
					best = v
			if best and GameState.player.has_method("enter_vehicle"):
				GameState.player.global_position = best.global_position + Vector3(2, 0.5, 0)
				GameState.player.enter_vehicle(best)
		if st.has("press"):
			Input.action_press(st["press"], 1.0)
			await get_tree().create_timer(float(st.get("time", 1.0))).timeout
			Input.action_release(st["press"])
		if st.has("wait"):
			var t_end := Time.get_ticks_msec() + int(float(st["wait"]) * 1000.0)
			while Time.get_ticks_msec() < t_end:
				await get_tree().process_frame
		if st.has("shot"):
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(str(st["shot"]))
			_profile()
			print("[Main] gameshot ", st["shot"], " fps=", Engine.get_frames_per_second(),
				" draw_calls=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				" prims=", RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	get_tree().quit()


func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	return out


func _spawn_player() -> void:
	var sp: Dictionary = WorldData.world["spawn"]
	var pos := Vector3(sp["x"], WorldData.height_at(sp["x"], sp["z"]) + 1.2, sp["z"])
	if ResourceLoader.exists("res://characters/player/player.gd"):
		var player: Node3D = load("res://characters/player/player.gd").new()
		player.name = "Player"
		add_child(player)
		player.global_position = pos
		player.rotation.y = deg_to_rad(float(sp["yaw"]))
		GameState.player = player
	else:
		# no player yet: free camera
		var cam := Camera3D.new()
		add_child(cam)
		cam.global_position = pos + Vector3(0, 30, 60)
		cam.look_at(pos)
		GameState.camera = cam


func _make_world_bounds() -> void:
	var body := StaticBody3D.new()
	body.name = "WorldBounds"
	add_child(body)
	var half := WorldData.size * 0.5
	for d in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(10 if d.x != 0 else WorldData.size, 6000, 10 if d.z != 0 else WorldData.size)
		cs.shape = shape
		cs.position = d * (half - 20.0) + Vector3(0, 1500, 0)
		body.add_child(cs)


# ---------------------------------------------------------------------------
# Screenshot / test mode
# ---------------------------------------------------------------------------
func _setup_shots(args: Dictionary) -> void:
	if args.has("shots"):
		var f := FileAccess.get_file_as_string(args["shots"])
		_shots = JSON.parse_string(f)
	else:
		_shots = [{"out": args["shot"], "cam": args.get("cam", "470,g40,1900,0,-15"),
			"hour": float(args.get("hour", "10")), "weather": int(args.get("weather", "0"))}]
	_stats_out = args.get("stats", "")
	_shot_cam = Camera3D.new()
	_shot_cam.fov = 70.0
	add_child(_shot_cam)
	_shot_cam.make_current()
	GameState.camera = _shot_cam
	TimeWeather.paused = true
	TimeWeather.auto_weather = false
	_next_shot()


func _next_shot() -> void:
	_shot_index += 1
	if _shot_index >= _shots.size():
		print("[Main] all screenshots done")
		get_tree().quit()
		return
	var s: Dictionary = _shots[_shot_index]
	var c: PackedStringArray = str(s["cam"]).split(",")
	var x := float(c[0])
	var z := float(c[2])
	var y: float
	if c[1].begins_with("g"):
		y = WorldData.height_at(x, z) + float(c[1].substr(1))
	else:
		y = float(c[1])
	_shot_cam.global_position = Vector3(x, y, z)
	_shot_cam.rotation = Vector3(deg_to_rad(float(c[4])), deg_to_rad(float(c[3])), 0.0)
	_shot_cam.fov = float(s.get("fov", 70.0))
	TimeWeather.hour = float(s.get("hour", 10.0))
	TimeWeather.set_weather(int(s.get("weather", 0)))
	var w := int(s.get("weather", 0))
	TimeWeather.cloudiness = [0.1, 0.65, 0.5, 0.85, 1.0][w]
	TimeWeather.fog_amount = 1.0 if w == 2 else 0.0
	TimeWeather.rain = [0.0, 0.0, 0.0, 0.7, 1.0][w]
	TimeWeather.wetness = 1.0 if w >= 3 else float(s.get("wet", 0.0))
	_shot_wait = 0.0
	_shot_frames = 0


func _process(delta: float) -> void:
	if not GameState.screenshot_mode or _shot_index < 0 or _shot_index >= _shots.size():
		return
	_shot_wait += delta
	_shot_frames += 1
	var idle := true
	for k in systems:
		var sys: Node = systems[k]
		if "is_idle" in sys and not sys.is_idle:
			idle = false
	if (_shot_frames > 12 and idle and _shot_wait > 1.0) or _shot_wait > 90.0:
		var s: Dictionary = _shots[_shot_index]
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		var out := str(s["out"])
		img.save_png(out)
		print("[Main] saved ", out, " (waited %.1fs, idle=%s, fps=%d)" % [_shot_wait, idle, Engine.get_frames_per_second()])
		if _stats_out != "":
			_write_stats()
		_next_shot()


func _write_stats() -> void:
	var f := FileAccess.open(_stats_out, FileAccess.WRITE)
	var d := {
		"fps": Engine.get_frames_per_second(),
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"video_mem_mb": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
		"static_mem_mb": OS.get_static_memory_usage() / 1048576.0,
		"nodes": get_tree().get_node_count(),
	}
	f.store_string(JSON.stringify(d))
