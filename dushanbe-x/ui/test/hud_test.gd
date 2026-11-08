extends Node
## Automated HUD screenshot test. Run:
## xvfb-run -a godot --path . --rendering-driver vulkan --resolution 1280x720 res://ui/test/hud_test.tscn
## Saves screenshots to OUT (user arg --out=dir, default docs/screenshots).

class FakeVehicle:
	extends Node3D
	func get_speed_kmh() -> float:
		return 87.0

var out_dir := "res://docs/screenshots"
var main: Node
var hud: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.substr(6)
	GameSettings.set_preset("low")
	# Minimal, self-contained world (independent of other modules under development):
	main = Node3D.new()
	main.name = "TestWorld"
	add_child(main)
	var env: Node = load("res://world/environment/day_night.gd").new()
	env.name = "Environment"
	main.add_child(env)
	var terrain: Node = load("res://world/terrain/terrain_streamer.gd").new()
	terrain.name = "Terrain"
	main.add_child(terrain)
	var sp: Dictionary = WorldData.world["spawn"]
	var cam := Camera3D.new()
	main.add_child(cam)
	cam.global_position = Vector3(sp["x"] + 40, WorldData.height_at(sp["x"], sp["z"]) + 25, sp["z"] + 90)
	cam.look_at(Vector3(sp["x"], WorldData.height_at(sp["x"], sp["z"]) + 5, sp["z"] - 200))
	cam.make_current()
	GameState.camera = cam
	var audio: Node = load("res://audio/ambience.gd").new()
	audio.name = "Audio"
	main.add_child(audio)
	main.add_child(load("res://ui/hud.tscn").instantiate())
	_run()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := ProjectSettings.globalize_path(out_dir + "/" + name + ".png") if out_dir.begins_with("res://") else out_dir + "/" + name + ".png"
	img.save_png(p)
	print("[hud_test] saved ", p)


func _run() -> void:
	await _frames(3)
	hud = main.get_node_or_null("HUD")
	if hud == null:
		push_error("HUD not found")
		get_tree().quit(1)
		return
	await _shot("ui_loading")
	var t0 := Time.get_ticks_msec()
	while hud._loading.visible and Time.get_ticks_msec() - t0 < 60000:
		await _frames(1)
	print("[hud_test] loading overlay hidden after %d ms" % (Time.get_ticks_msec() - t0))
	await _frames(4)
	GameState.wanted = 2
	GameState.message("Добро пожаловать в Душанбе!")
	await _frames(2)
	await _shot("ui_hud_foot")
	hud.open_map()
	await _frames(3)
	await _shot("ui_map")
	hud.map_screen.zoom = 3.0
	hud.map_screen.center_on_player()
	hud.map_screen._pick(hud.map_screen._to_screen(Vector2(380, 1800)))
	await _frames(2)
	await _shot("ui_map_zoom")
	hud.open_pause()
	await _frames(2)
	await _shot("ui_pause")
	hud.menus.show_page("settings")
	await _frames(2)
	await _shot("ui_settings")
	hud.menus.show_page("time")
	await _frames(2)
	await _shot("ui_time_weather")
	hud.close_overlays()
	var fv := FakeVehicle.new()
	main.add_child(fv)
	fv.global_position = GameState.focus_position()
	GameState.current_vehicle = fv
	TimeWeather.set_weather(TimeWeather.Weather.RAIN)
	await _frames(3)
	await _shot("ui_hud_vehicle")
	print("[hud_test] done")
	get_tree().quit()
