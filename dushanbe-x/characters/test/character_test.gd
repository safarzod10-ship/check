extends Node3D
## Visual + functional test for the character module.
## xvfb-run -a godot --path . --rendering-driver vulkan --resolution 960x540 res://characters/test/character_test.tscn -- --out=/path/dir
## Writes character_*.png and prints controller checks.

var out_dir := "res://docs/screenshots"
var cam: Camera3D
var base := Vector3.ZERO
var player: Player


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	TimeWeather.paused = true
	TimeWeather.auto_weather = false
	TimeWeather.hour = 10.5
	var env: Node = load("res://world/environment/day_night.gd").new()
	add_child(env)
	var x := 470.0
	var z := 1760.0
	base = Vector3(x, WorldData.height_at(x, z), z)
	_make_ground()
	_run()


func _make_ground() -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(200, 1, 200)
	cs.shape = bs
	body.add_child(cs)
	body.position = base - Vector3(0, 0.5, 0)
	add_child(body)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(200, 200)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://textures/paving.png")
	m.uv1_scale = Vector3(50, 50, 1)
	pm.material = m
	mi.mesh = pm
	mi.position = base
	add_child(mi)
	# a 0.15 m curb to test step-up
	var curb := StaticBody3D.new()
	var cs2 := CollisionShape3D.new()
	var bs2 := BoxShape3D.new()
	bs2.size = Vector3(6, 0.15, 3)
	cs2.shape = bs2
	curb.add_child(cs2)
	var cm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs2.size
	cm.mesh = bm
	curb.add_child(cm)
	curb.position = base + Vector3(30, 0.075, -6)
	add_child(curb)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := out_dir.path_join("character_%s.png" % name)
	img.save_png(ProjectSettings.globalize_path(path) if path.begins_with("res://") else path)
	print("[CharTest] saved ", path)


func _look(from: Vector3, at: Vector3, fov := 45.0) -> void:
	cam.global_position = from
	cam.look_at(at)
	cam.fov = fov


func _posed(app: Dictionary, anim: String, t: float, pos: Vector3, yaw := 0.0) -> Node3D:
	var holder := Node3D.new()
	add_child(holder)
	holder.global_position = pos
	holder.rotation.y = yaw
	var model := HumanoidBuilder.create(app)
	holder.add_child(model)
	var an := HumanoidAnimator.new()
	holder.add_child(an)
	an.setup(model)
	an.ap.play(anim)
	an.ap.seek(t, true)
	an.ap.pause()
	return holder


func _run() -> void:
	# --- controller test with the real Player ---
	player = Player.new()
	add_child(player)
	player.global_position = base + Vector3(20, 0.1, 0)
	await _frames(5)
	var p0 := player.global_position
	Input.action_press("move_forward")
	for i in 60:
		await get_tree().physics_frame
	var anim1 := player.animator.ap.current_animation
	Input.action_press("sprint")
	for i in 40:
		await get_tree().physics_frame
	var anim2 := player.animator.ap.current_animation
	Input.action_release("sprint")
	Input.action_release("move_forward")
	var p1 := player.global_position
	print("[CharTest] moved %.2f m, anim walking/running: %s, sprint: %s, on_floor=%s" % [p0.distance_to(p1), anim1, anim2, player.is_on_floor()])
	# curb step-up: walk towards the curb (+X direction relative)
	player.global_position = base + Vector3(30, 0.05, -1.0)
	player.rig.yaw = PI    # camera looks +Z ... move_forward goes towards -Z (curb at z-6)
	player.rig.yaw = 0.0
	await _frames(2)
	Input.action_press("move_forward")
	var curb_max := 0.0
	for i in 90:
		await get_tree().physics_frame
		curb_max = maxf(curb_max, player.global_position.y - base.y)
	Input.action_release("move_forward")
	print("[CharTest] curb test: max y on curb %.3f (expect ~0.15), end z=%.2f" % [curb_max, player.global_position.z - base.z])
	player.global_position = base + Vector3(20, 0.05, 0)
	await _frames(2)
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	var maxy := 0.0
	for i in 50:
		await get_tree().physics_frame
		maxy = maxf(maxy, player.global_position.y - base.y)
	print("[CharTest] jump height %.2f m, back on floor=%s" % [maxy, player.is_on_floor()])
	Input.action_press("attack")
	await get_tree().physics_frame
	Input.action_release("attack")
	await _frames(3)
	print("[CharTest] attack anim: ", player.animator.ap.current_animation)
	Input.action_press("crouch")
	await get_tree().physics_frame
	Input.action_release("crouch")
	await _frames(10)
	print("[CharTest] crouch: ", player.crouching, " anim ", player.animator.ap.current_animation)
	# --- pedestrian system ---
	var pm := PedestrianManager.new()
	add_child(pm)
	for i in 120:
		await get_tree().process_frame
	print("[CharTest] pedestrians spawned: %d (max %d)" % [pm.peds.size(), pm.max_count()])
	if pm.peds.size() > 0:
		var ped: Pedestrian = pm.peds[0]
		var p_before := ped.global_position
		for i in 30:
			await get_tree().process_frame
		print("[CharTest] ped walked %.2f m on road '%s'" % [p_before.distance_to(ped.global_position), WorldData.roads[ped.road]["name"]])
		ped.take_hit(ped.global_position + Vector3(1, 0, 0), 4.0)
		var fleeing := 0
		for q in pm.peds:
			if q.state == Pedestrian.S.FLEE:
				fleeing += 1
		print("[CharTest] hit ped state=%d (DOWN=%d), fleeing nearby=%d" % [ped.state, Pedestrian.S.DOWN, fleeing])
	pm.queue_free()
	player.queue_free()

	cam = Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.far = 3000
	# --- close-up idle (front) ---
	var hero := HumanoidBuilder.default_appearance()
	hero["jacket"] = true
	hero["jacket_col"] = Color(0.2, 0.22, 0.26)
	var h := _posed(hero, "idle", 0.5, base)
	_look(base + Vector3(0.9, 1.45, -2.4), base + Vector3(0, 1.05, 0), 40)
	await _shot("idle")
	_look(base + Vector3(-0.3, 1.62, -0.75), base + Vector3(0, 1.62, 0), 40)
	await _shot("face")
	h.queue_free()
	# --- pose lineup ---
	var poses := [["idle", 0.4], ["walk", 0.0], ["run", 0.0], ["sprint", 0.0], ["crouch_idle", 0.2],
		["punch_r", 0.2], ["kick", 0.4], ["jump_up", 0.2], ["sit_drive", 0.2], ["knocked_down", 1.1]]
	var holders: Array = []
	for i in poses.size():
		holders.append(_posed(hero, poses[i][0], poses[i][1], base + Vector3((i - 4.5) * 1.3, 0, 0), PI * 0.5))
	_look(base + Vector3(0, 2.2, -9.5), base + Vector3(0, 0.8, 0), 55)
	await _shot("poses")
	for x in holders:
		x.queue_free()
	# --- walk & punch 3/4 view ---
	h = _posed(hero, "walk", 0.0, base, 0.0)
	_look(base + Vector3(2.4, 1.3, -2.0), base + Vector3(0, 0.95, 0), 45)
	await _shot("walk")
	h.queue_free()
	h = _posed(hero, "punch_r", 0.2, base, 0.0)
	var target := _posed(HumanoidBuilder.random_appearance(RandomNumberGenerator.new()), "hit_react", 0.12, base + Vector3(0, 0, -1.2), PI)
	_look(base + Vector3(2.6, 1.4, -0.6), base + Vector3(0, 1.0, -0.6), 45)
	await _shot("punch")
	h.queue_free()
	target.queue_free()
	h = _posed(hero, "crouch_walk", 0.1, base, 0.6)
	_look(base + Vector3(2.0, 1.2, -2.0), base + Vector3(0, 0.6, 0), 45)
	await _shot("crouch")
	h.queue_free()
	# --- NPC variety ---
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var anims := ["idle", "talk", "walk", "wave", "idle", "talk", "walk", "idle", "idle", "talk"]
	for i in 10:
		holders.append(_posed(HumanoidBuilder.random_appearance(rng), anims[i], rng.randf() * 0.9,
			base + Vector3((i % 5 - 2) * 1.2, 0, (i / 5) * 1.6), rng.randf_range(-0.4, 0.4)))
	_look(base + Vector3(0, 1.9, -6.5), base + Vector3(0, 0.9, 0.8), 50)
	await _shot("npcs")
	print("[CharTest] done")
	get_tree().quit()
