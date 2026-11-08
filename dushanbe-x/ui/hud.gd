extends CanvasLayer
## DUSHANBE-X HUD: touch controls, minimap, status bar, notifications, map, menus, loading screen.

var touch: TouchControls
var minimap: Minimap
var map_screen: MapScreen
var menus: GameMenus
var root: Control

var _place: Label
var _sub: Label
var _time: Label
var _weather_icon: Control
var _money: Label
var _stars: Control
var _fps: Label
var _speed_panel: PanelContainer
var _speed: Label
var _health_bar: ProgressBar
var _toast: PanelContainer
var _toast_label: Label
var _toast_time := 0.0
var _banner: PanelContainer
var _banner_label: Label
var _banner_time := 0.0
var _loading: Control
var _loading_time := 0.0
var _info_timer := 0.0
var _discovered: Dictionary = {}
var _pause_center := Vector2.ZERO
var _font: Font


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UiTheme.get_theme()
	add_child(root)

	touch = TouchControls.new()
	touch.look_sensitivity = GameSettings.camera_sensitivity
	root.add_child(touch)
	touch.tap_region.connect(_on_region)

	_build_top_bar()
	minimap = Minimap.new()
	root.add_child(minimap)
	_build_right_column()
	_build_speedometer()
	_build_toasts()
	_build_pause_button()

	map_screen = MapScreen.new()
	map_screen.visible = false
	map_screen.theme = UiTheme.get_theme()
	root.add_child(map_screen)
	map_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_screen.closed.connect(close_overlays)
	map_screen.travel_requested.connect(_on_travel)

	menus = GameMenus.new()
	menus.visible = false
	root.add_child(menus)
	menus.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menus.resume_requested.connect(close_overlays)
	menus.map_requested.connect(open_map)

	_build_loading()
	GameState.notify.connect(show_toast)
	GameSettings.changed.connect(func(): touch.look_sensitivity = GameSettings.camera_sensitivity)
	get_viewport().size_changed.connect(_layout)
	_layout()


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------
func _build_top_bar() -> void:
	var pc := PanelContainer.new()
	pc.name = "PlacePanel"
	pc.position = Vector2(40, 28)
	pc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 0)
	pc.add_child(vb)
	_place = Label.new()
	_place.add_theme_font_size_override("font_size", 30)
	_place.text = "Душанбе"
	vb.add_child(_place)
	_sub = Label.new()
	_sub.add_theme_font_size_override("font_size", 21)
	_sub.add_theme_color_override("font_color", UiTheme.GOLD)
	vb.add_child(_sub)
	_health_bar = ProgressBar.new()
	_health_bar.custom_minimum_size = Vector2(300, 12)
	_health_bar.show_percentage = false
	_health_bar.max_value = 100
	_health_bar.value = 100
	var bg := UiTheme.box(Color(0, 0, 0, 0.5), 6, Color(0, 0, 0, 0), 0, 0)
	var fg := UiTheme.box(Color(0.2, 0.8, 0.3), 6, Color(0, 0, 0, 0), 0, 0)
	_health_bar.add_theme_stylebox_override("background", bg)
	_health_bar.add_theme_stylebox_override("fill", fg)
	_health_bar.visible = false
	vb.add_child(_health_bar)
	_fps = Label.new()
	_fps.position = Vector2(44, 0)
	_fps.add_theme_font_size_override("font_size", 18)
	_fps.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	root.add_child(_fps)
	# time & weather pill (top centre)
	var tp := PanelContainer.new()
	tp.name = "TimePanel"
	tp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(tp)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	tp.add_child(hb)
	_weather_icon = Control.new()
	_weather_icon.custom_minimum_size = Vector2(40, 40)
	_weather_icon.draw.connect(_draw_weather_icon)
	hb.add_child(_weather_icon)
	_time = Label.new()
	_time.add_theme_font_size_override("font_size", 28)
	hb.add_child(_time)


func _build_right_column() -> void:
	var vb := VBoxContainer.new()
	vb.name = "RightColumn"
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_BEGIN
	root.add_child(vb)
	_money = Label.new()
	_money.add_theme_font_size_override("font_size", 28)
	_money.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	vb.add_child(_money)
	_stars = Control.new()
	_stars.custom_minimum_size = Vector2(270, 36)
	_stars.draw.connect(_draw_stars)
	vb.add_child(_stars)


func _build_speedometer() -> void:
	_speed_panel = PanelContainer.new()
	_speed_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_speed_panel.visible = false
	root.add_child(_speed_panel)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	_speed_panel.add_child(hb)
	_speed = Label.new()
	_speed.add_theme_font_size_override("font_size", 56)
	_speed.text = "0"
	hb.add_child(_speed)
	var u := Label.new()
	u.text = " км/ч"
	u.add_theme_font_size_override("font_size", 24)
	u.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	hb.add_child(u)


func _build_toasts() -> void:
	_toast = PanelContainer.new()
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	root.add_child(_toast)
	_toast_label = Label.new()
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_child(_toast_label)
	_banner = PanelContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	_banner.add_theme_stylebox_override("panel", UiTheme.box(Color(0.05, 0.06, 0.09, 0.85), 16, UiTheme.GOLD, 2, 26))
	root.add_child(_banner)
	var vb := VBoxContainer.new()
	_banner.add_child(vb)
	var cap := Label.new()
	cap.text = "ДОСТОПРИМЕЧАТЕЛЬНОСТЬ"
	cap.add_theme_font_size_override("font_size", 18)
	cap.add_theme_color_override("font_color", UiTheme.GOLD)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(cap)
	_banner_label = Label.new()
	_banner_label.add_theme_font_size_override("font_size", 38)
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_banner_label)
	vb.add_child(UiTheme.flag_stripe(4))


func _build_pause_button() -> void:
	var c := Control.new()
	c.name = "PauseButton"
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.custom_minimum_size = Vector2(72, 72)
	c.size = Vector2(72, 72)
	c.draw.connect(func():
		c.draw_circle(Vector2(36, 36), 34, Color(0.05, 0.06, 0.09, 0.75))
		c.draw_arc(Vector2(36, 36), 34, 0, TAU, 32, Color(1, 1, 1, 0.5), 2.0, true)
		c.draw_rect(Rect2(24, 22, 9, 28), Color.WHITE)
		c.draw_rect(Rect2(39, 22, 9, 28), Color.WHITE))
	root.add_child(c)


func _build_loading() -> void:
	_loading = Control.new()
	_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(_loading)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.add_child(bg)
	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_CENTER)
	vb.custom_minimum_size = Vector2(700, 0)
	vb.offset_left = -350
	vb.offset_right = 350
	vb.offset_top = -120
	vb.add_theme_constant_override("separation", 18)
	_loading.add_child(vb)
	var t := UiTheme.title("DUSHANBE-X", 84)
	vb.add_child(t)
	vb.add_child(UiTheme.flag_stripe(8))
	var l := Label.new()
	l.name = "Status"
	l.text = "Загрузка мира… Душанбе, Варзоб, Гиссар"
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	vb.add_child(l)
	var bar := ProgressBar.new()
	bar.name = "Bar"
	bar.custom_minimum_size = Vector2(0, 14)
	bar.show_percentage = false
	bar.add_theme_stylebox_override("background", UiTheme.box(Color(1, 1, 1, 0.12), 7, Color(0, 0, 0, 0), 0, 0))
	bar.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.GOLD, 7, Color(0, 0, 0, 0), 0, 0))
	vb.add_child(bar)


func _layout() -> void:
	var s := root.get_viewport_rect().size
	var m := 40.0
	# respect display cut-outs / rounded corners on phones
	var safe := DisplayServer.get_display_safe_area()
	var win := DisplayServer.window_get_size()
	if win.x > 0 and safe.size.x > 0:
		var sx := s.x / float(win.x)
		m = maxf(m, maxf(safe.position.x, win.x - safe.end.x) * sx + 16.0)
	root.get_node("PlacePanel").position = Vector2(m, 24)
	_fps.position = Vector2(m + 4, 150)
	minimap.position = Vector2(s.x - m - Minimap.D, 24)
	touch.regions["minimap"] = [minimap.position + Vector2(Minimap.D, Minimap.D) * 0.5, Minimap.D * 0.5]
	var rc: Control = root.get_node("RightColumn")
	rc.position = Vector2(s.x - m - 270, 24 + Minimap.D + 8)
	rc.size = Vector2(270, 80)
	var pb: Control = root.get_node("PauseButton")
	pb.position = Vector2(s.x - m - Minimap.D - 100, 30)
	_pause_center = pb.position + Vector2(36, 36)
	touch.regions["pause"] = [_pause_center, 40.0]
	var tp: Control = root.get_node("TimePanel")
	tp.position = Vector2(s.x * 0.5 - 120, 24)
	_speed_panel.position = Vector2(s.x * 0.5 - 130, s.y - 120)
	_speed_panel.custom_minimum_size = Vector2(260, 0)
	_toast.position = Vector2(s.x * 0.5 - 300, s.y * 0.2)
	_toast.custom_minimum_size = Vector2(600, 0)
	_banner.position = Vector2(s.x * 0.5 - 380, s.y * 0.3)
	_banner.custom_minimum_size = Vector2(760, 0)


# ---------------------------------------------------------------------------
# Runtime
# ---------------------------------------------------------------------------
func _process(delta: float) -> void:
	_handle_actions()
	if _loading.visible:
		_update_loading(delta)
	var paused := get_tree().paused
	var player = GameState.player
	var veh = GameState.current_vehicle
	var in_vehicle: bool = veh != null and is_instance_valid(veh)
	touch.set_vehicle_mode(in_vehicle)
	var near_vehicle := false
	if player and is_instance_valid(player) and "nearby_vehicle" in player:
		near_vehicle = player.nearby_vehicle != null
	touch.set_show_enter(near_vehicle and not in_vehicle)
	_speed_panel.visible = in_vehicle and not paused
	if in_vehicle and veh.has_method("get_speed_kmh"):
		_speed.text = str(int(round(absf(veh.get_speed_kmh()))))
	if player and is_instance_valid(player) and "health" in player:
		_health_bar.visible = true
		_health_bar.value = float(player.health)
	var pp: Control = root.get_node("PlacePanel")
	_fps.position.y = pp.position.y + pp.size.y + 6.0
	_fps.visible = GameSettings.show_fps
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
	_time.text = TimeWeather.time_string() + "  " + TimeWeather.weather_name()
	_weather_icon.queue_redraw()
	_money.text = "%d смн" % GameState.money
	_stars.queue_redraw()
	_info_timer -= delta
	if _info_timer <= 0.0:
		_info_timer = 1.0
		_update_place()
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time, 0.0, 1.0)
		_toast.visible = _toast_time > 0.0
	if _banner_time > 0.0:
		_banner_time -= delta
		_banner.modulate.a = clampf(_banner_time, 0.0, 1.0)
		_banner.visible = _banner_time > 0.0


func _handle_actions() -> void:
	if Input.is_action_just_pressed("pause"):
		if menus.visible or map_screen.visible:
			close_overlays()
		else:
			open_pause()
	if Input.is_action_just_pressed("map"):
		if map_screen.visible:
			close_overlays()
		elif not menus.visible:
			open_map()


func _update_place() -> void:
	var p := GameState.focus_position()
	_place.text = WorldData.place_name(p.x, p.z)
	var lm := WorldData.nearest_landmark(p.x, p.z, 250.0)
	if not lm.is_empty():
		_sub.text = str(lm["name"])
	else:
		var r := WorldData.nearest_road(p.x, p.z, 60.0)
		_sub.text = str(WorldData.roads[r["road"]]["name"]) if not r.is_empty() else ""
	_sub.visible = _sub.text != ""
	# discovery banners
	for l in WorldData.landmarks:
		if _discovered.has(l["id"]):
			continue
		if Vector2(p.x, p.z).distance_to(Vector2(l["x"], l["z"])) < 120.0:
			_discovered[l["id"]] = true
			if l["id"] != "dusti_square" or not _discovered.has("somoni_monument"):
				show_banner(str(l["name"]))


func show_toast(text: String) -> void:
	_toast_label.text = text
	_toast.visible = true
	_toast_time = 3.5


func show_banner(text: String) -> void:
	_banner_label.text = text
	_banner.visible = true
	_banner_time = 4.5


func _update_loading(delta: float) -> void:
	if _loading_time == 0.0:
		_loading_time = Time.get_ticks_msec() / 1000.0
	var elapsed := Time.get_ticks_msec() / 1000.0 - _loading_time
	var terrain: Node = get_parent().get_node_or_null("Terrain") if get_parent() else null
	var ready: bool = terrain == null or ("is_idle" in terrain and terrain.is_idle)
	var bar: ProgressBar = _loading.find_child("Bar", true, false)
	bar.value = minf(95.0, elapsed / 20.0 * 100.0)
	if (ready and elapsed > 1.0) or elapsed > 20.0:
		_loading.visible = false
		var p := GameState.focus_position()
		show_banner(WorldData.place_name(p.x, p.z))
		_discovered["_start"] = true


func _on_region(id: String) -> void:
	if id == "minimap":
		open_map()
	elif id == "pause":
		open_pause()


func _set_overlay(on: bool) -> void:
	touch.release_all()
	touch.enabled = not on
	touch.visible = not on
	get_tree().paused = on
	if on:
		_toast_time = 0.0
		_banner_time = 0.0
		_toast.visible = false
		_banner.visible = false


func open_pause() -> void:
	map_screen.visible = false
	menus.visible = true
	menus.show_page("pause")
	_set_overlay(true)


func open_map() -> void:
	menus.visible = false
	map_screen.visible = true
	_set_overlay(true)


func close_overlays() -> void:
	menus.visible = false
	map_screen.visible = false
	_set_overlay(false)


func _on_travel(x: float, z: float, label: String) -> void:
	# land next to the closest road so the player never spawns inside a building
	var target := Vector3(x, 0, z)
	var r := WorldData.nearest_road(x, z, 400.0)
	if not r.is_empty():
		target = r["pos"]
	target.y = WorldData.height_at(target.x, target.z) + 1.5
	if not r.is_empty():
		target.y = maxf(target.y, r["pos"].y + WorldData.ROAD_LIFT + 1.5)
	var veh = GameState.current_vehicle
	var who: Node3D = null
	if veh and is_instance_valid(veh):
		who = veh
	elif GameState.player and is_instance_valid(GameState.player):
		who = GameState.player
	elif GameState.camera:
		who = GameState.camera
		target.y += 30.0
	if who:
		who.global_position = target
		if "linear_velocity" in who:
			who.linear_velocity = Vector3.ZERO
			who.angular_velocity = Vector3.ZERO
		if "velocity" in who:
			who.velocity = Vector3.ZERO
	close_overlays()
	show_toast("Вы прибыли: " + label)


# ---------------------------------------------------------------------------
# Small vector icons
# ---------------------------------------------------------------------------
func _draw_weather_icon() -> void:
	var c := Vector2(20, 20)
	var w := TimeWeather.weather
	var night := TimeWeather.night_factor > 0.5
	if w == TimeWeather.Weather.CLEAR:
		if night:
			_weather_icon.draw_circle(c, 13, Color(0.9, 0.92, 1.0))
			_weather_icon.draw_circle(c + Vector2(6, -5), 11, Color(0.08, 0.09, 0.13))
		else:
			for k in 8:
				var a := TAU * k / 8.0
				_weather_icon.draw_line(c + Vector2(cos(a), sin(a)) * 13, c + Vector2(cos(a), sin(a)) * 19, UiTheme.GOLD, 3.0)
			_weather_icon.draw_circle(c, 10, UiTheme.GOLD)
		return
	var cloud := Color(0.85, 0.87, 0.92) if w != TimeWeather.Weather.STORM else Color(0.5, 0.52, 0.6)
	_weather_icon.draw_circle(c + Vector2(-7, 2), 9, cloud)
	_weather_icon.draw_circle(c + Vector2(3, -3), 11, cloud)
	_weather_icon.draw_circle(c + Vector2(11, 3), 8, cloud)
	_weather_icon.draw_rect(Rect2(c + Vector2(-7, 2), Vector2(18, 9)), cloud)
	if w == TimeWeather.Weather.RAIN or w == TimeWeather.Weather.STORM:
		for k in 3:
			var x := 10.0 + k * 9.0
			_weather_icon.draw_line(Vector2(x, 33), Vector2(x - 3, 40), Color(0.5, 0.75, 1.0), 2.5)
	if w == TimeWeather.Weather.STORM:
		_weather_icon.draw_colored_polygon(PackedVector2Array([Vector2(22, 26), Vector2(16, 36), Vector2(21, 35), Vector2(18, 42), Vector2(27, 31), Vector2(22, 32)]), UiTheme.GOLD)
	if w == TimeWeather.Weather.FOG:
		for k in 3:
			_weather_icon.draw_line(Vector2(4, 30 + k * 4), Vector2(36, 30 + k * 4), Color(0.8, 0.8, 0.85, 0.8), 2.0)


func _draw_stars() -> void:
	var n := 5
	for i in n:
		var c := Vector2(270 - 18 - i * 34, 18)
		var pts := PackedVector2Array()
		for k in 10:
			var a := -PI / 2 + k * PI / 5
			var r := 15.0 if k % 2 == 0 else 6.5
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		var on := (n - i) <= GameState.wanted
		if GameState.wanted == 0:
			continue
		_stars.draw_colored_polygon(pts, UiTheme.GOLD if on else Color(1, 1, 1, 0.18))
