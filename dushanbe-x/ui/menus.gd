class_name GameMenus
extends Control
## Pause menu, settings screen and time/weather screen (one overlay, swappable pages).

signal resume_requested
signal map_requested

var _pages: Dictionary = {}
var _settings_widgets: Dictionary = {}
var _hour_slider: HSlider
var _hour_label: Label
var _preset_buttons: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiTheme.get_theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_pages["pause"] = _make_pause()
	_pages["settings"] = _make_settings()
	_pages["time"] = _make_time()
	show_page("pause")


func show_page(p: String) -> void:
	for k in _pages:
		_pages[k].visible = k == p
	if p == "settings":
		_refresh_settings()
	if p == "time":
		_hour_slider.set_value_no_signal(TimeWeather.hour)
		_hour_label.text = "Время: " + TimeWeather.time_string()


func _panel(width: float, height: float) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.custom_minimum_size = Vector2(width, height)
	pc.offset_left = -width * 0.5
	pc.offset_right = width * 0.5
	pc.offset_top = -height * 0.5
	pc.offset_bottom = height * 0.5
	add_child(pc)
	return pc


func _button(text: String, cb: Callable, h := 76.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	b.pressed.connect(func(): Ambience.play_ui(); cb.call())
	return b


func _make_pause() -> Control:
	var pc := _panel(560, 580)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	pc.add_child(vb)
	vb.add_child(UiTheme.title("DUSHANBE-X", 48))
	vb.add_child(UiTheme.flag_stripe(6))
	var sp := Control.new()
	sp.custom_minimum_size.y = 8
	vb.add_child(sp)
	vb.add_child(_button("Продолжить", func(): resume_requested.emit()))
	vb.add_child(_button("Карта", func(): map_requested.emit()))
	vb.add_child(_button("Настройки", func(): show_page("settings")))
	vb.add_child(_button("Время и погода", func(): show_page("time")))
	vb.add_child(_button("Выход", func(): get_tree().quit()))
	return pc


func _row(grid: GridContainer, label: String, ctrl: Control) -> void:
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 330
	grid.add_child(l)
	ctrl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl.custom_minimum_size.y = 56
	grid.add_child(ctrl)


func _slider(key: String, lo: float, hi: float, step: float, is_setting := true) -> HSlider:
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.custom_minimum_size.x = 420
	s.value_changed.connect(func(v): _on_slider(key, v, is_setting))
	_settings_widgets[key] = s
	return s


func _on_slider(key: String, v: float, is_setting: bool) -> void:
	if is_setting:
		GameSettings.set_value(key, v)
		_highlight_preset()
	else:
		GameSettings.set(key, v)
		GameSettings.apply()
		GameSettings.save_settings()
	var vl: Label = _settings_widgets.get(key + "_val")
	if vl:
		vl.text = _fmt(key, v)


func _fmt(key: String, v) -> String:
	match key:
		"render_scale", "grass_density", "traffic_density", "pedestrian_density", "sound_volume", "camera_sensitivity":
			return "%d%%" % int(round(float(v) * 100.0))
		"view_distance":
			return "%.1f км" % (float(v) / 1000.0)
		"shadow_distance":
			return "%d м" % int(v)
	return str(v)


func _slider_row(grid: GridContainer, label: String, key: String, lo: float, hi: float, step: float, is_setting := true) -> void:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var s := _slider(key, lo, hi, step, is_setting)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(s)
	var vl := Label.new()
	vl.custom_minimum_size.x = 110
	vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(vl)
	_settings_widgets[key + "_val"] = vl
	_row(grid, label, hb)


func _check(key: String, is_setting := true) -> CheckButton:
	var c := CheckButton.new()
	c.toggled.connect(func(on):
		if is_setting:
			GameSettings.set_value(key, on)
			_highlight_preset()
		else:
			GameSettings.set(key, on)
			GameSettings.apply()
			GameSettings.save_settings())
	_settings_widgets[key] = c
	return c


func _make_settings() -> Control:
	var pc := _panel(1180, 800)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	vb.add_child(UiTheme.title("НАСТРОЙКИ", 40))
	vb.add_child(UiTheme.flag_stripe(4))
	var presets := HBoxContainer.new()
	presets.add_theme_constant_override("separation", 12)
	vb.add_child(presets)
	var pl := Label.new()
	pl.text = "Графика:"
	presets.add_child(pl)
	for p in [["low", "Низкие"], ["medium", "Средние"], ["high", "Высокие"], ["ultra", "Ультра"]]:
		var b := _button(p[1], func(): GameSettings.set_preset(p[0]); _refresh_settings(), 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.toggle_mode = true
		presets.add_child(b)
		_preset_buttons[p[0]] = b
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	scroll.add_child(grid)
	_slider_row(grid, "Масштаб рендера", "render_scale", 0.5, 1.0, 0.05)
	_slider_row(grid, "Дальность прорисовки", "view_distance", 1500, 10000, 250)
	_row(grid, "Тени", _check("shadows"))
	_slider_row(grid, "Дальность теней", "shadow_distance", 30, 300, 10)
	_slider_row(grid, "Плотность травы", "grass_density", 0.0, 2.0, 0.1)
	_slider_row(grid, "Плотность трафика", "traffic_density", 0.0, 1.5, 0.1)
	_slider_row(grid, "Пешеходы", "pedestrian_density", 0.0, 1.5, 0.1)
	var fps := OptionButton.new()
	fps.add_item("30 FPS", 30)
	fps.add_item("60 FPS", 60)
	fps.item_selected.connect(func(i): GameSettings.set_value("fps_cap", fps.get_item_id(i)); _highlight_preset())
	_settings_widgets["fps_cap"] = fps
	_row(grid, "Ограничение кадров", fps)
	_slider_row(grid, "Громкость", "sound_volume", 0.0, 1.0, 0.05, false)
	_slider_row(grid, "Чувствительность камеры", "camera_sensitivity", 0.3, 2.5, 0.05, false)
	_row(grid, "Инверсия оси Y", _check("invert_y", false))
	_row(grid, "Показывать FPS", _check("show_fps", false))
	vb.add_child(_button("Назад", func(): show_page("pause"), 66))
	return pc


func _refresh_settings() -> void:
	for key in ["render_scale", "view_distance", "shadow_distance", "grass_density", "traffic_density", "pedestrian_density"]:
		var s: HSlider = _settings_widgets[key]
		var v = GameSettings.get_v(key, s.min_value)
		s.set_value_no_signal(float(v))
		_settings_widgets[key + "_val"].text = _fmt(key, v)
	for key in ["sound_volume", "camera_sensitivity"]:
		var s: HSlider = _settings_widgets[key]
		s.set_value_no_signal(float(GameSettings.get(key)))
		_settings_widgets[key + "_val"].text = _fmt(key, GameSettings.get(key))
	_settings_widgets["shadows"].set_pressed_no_signal(bool(GameSettings.get_v("shadows", true)))
	_settings_widgets["invert_y"].set_pressed_no_signal(bool(GameSettings.invert_y))
	_settings_widgets["show_fps"].set_pressed_no_signal(bool(GameSettings.show_fps))
	var fps: OptionButton = _settings_widgets["fps_cap"]
	fps.select(0 if int(GameSettings.get_v("fps_cap", 30)) <= 30 else 1)
	_highlight_preset()


func _highlight_preset() -> void:
	for k in _preset_buttons:
		_preset_buttons[k].set_pressed_no_signal(k == GameSettings.preset)


func _make_time() -> Control:
	var pc := _panel(900, 600)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	pc.add_child(vb)
	vb.add_child(UiTheme.title("ВРЕМЯ И ПОГОДА", 40))
	vb.add_child(UiTheme.flag_stripe(4))
	_hour_label = Label.new()
	_hour_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_hour_label)
	_hour_slider = HSlider.new()
	_hour_slider.min_value = 0.0
	_hour_slider.max_value = 23.99
	_hour_slider.step = 0.25
	_hour_slider.custom_minimum_size.y = 56
	_hour_slider.value_changed.connect(func(v):
		TimeWeather.hour = v
		_hour_label.text = "Время: " + TimeWeather.time_string())
	vb.add_child(_hour_slider)
	var quick := HBoxContainer.new()
	quick.add_theme_constant_override("separation", 10)
	vb.add_child(quick)
	for q in [["Рассвет", 6.0], ["День", 12.0], ["Закат", 19.0], ["Ночь", 23.0]]:
		var b := _button(q[0], func(): TimeWeather.hour = q[1]; show_page("time"), 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		quick.add_child(b)
	var wl := Label.new()
	wl.text = "Погода:"
	vb.add_child(wl)
	var wb := HBoxContainer.new()
	wb.add_theme_constant_override("separation", 10)
	vb.add_child(wb)
	for i in TimeWeather.WEATHER_NAMES.size():
		var b := _button(TimeWeather.WEATHER_NAMES[i], func(): TimeWeather.auto_weather = false; TimeWeather.set_weather(i), 64)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wb.add_child(b)
	var auto := CheckButton.new()
	auto.text = "Автоматическая смена погоды"
	auto.button_pressed = TimeWeather.auto_weather
	auto.toggled.connect(func(on): TimeWeather.auto_weather = on)
	vb.add_child(auto)
	vb.add_child(_button("Назад", func(): show_page("pause"), 66))
	return pc
