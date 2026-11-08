extends Node
## Global clock and weather state. Visual systems (sky, sun, rain, wet roads,
## street lights, lit windows) read from here and from the shader globals it sets.

signal weather_changed(state: String)
signal hour_changed(hour: int)

enum Weather { CLEAR, CLOUDY, FOG, RAIN, STORM }
const WEATHER_NAMES := ["Ясно", "Облачно", "Туман", "Дождь", "Гроза"]

## in-game hours per real second (24 game hours = 24 real minutes by default)
var time_scale := 1.0 / 60.0
var hour := 9.0
var day := 1
var paused := false

var weather: int = Weather.CLEAR
var _target_weather: int = Weather.CLEAR
var _weather_timer := 0.0
var auto_weather := true

## smoothed weather parameters (0..1)
var cloudiness := 0.1
var fog_amount := 0.0
var rain := 0.0
var wetness := 0.0
var night_factor := 0.0
var wind := 0.3

var _last_hour := -1


func _ready() -> void:
	_weather_timer = randf_range(240.0, 480.0)


func _process(delta: float) -> void:
	if not paused:
		hour += delta * time_scale
		if hour >= 24.0:
			hour -= 24.0
			day += 1
	if int(hour) != _last_hour:
		_last_hour = int(hour)
		hour_changed.emit(_last_hour)
	if auto_weather:
		_weather_timer -= delta
		if _weather_timer <= 0.0:
			_weather_timer = randf_range(300.0, 700.0)
			var r := randf()
			set_weather(Weather.CLEAR if r < 0.45 else Weather.CLOUDY if r < 0.7 else Weather.RAIN if r < 0.85 else Weather.FOG if r < 0.95 else Weather.STORM)
	var tc := 0.1
	var tf := 0.0
	var tr := 0.0
	var tw := 0.25
	match _target_weather:
		Weather.CLOUDY:
			tc = 0.65; tw = 0.45
		Weather.FOG:
			tc = 0.5; tf = 1.0; tw = 0.1
		Weather.RAIN:
			tc = 0.85; tr = 0.7; tw = 0.6
		Weather.STORM:
			tc = 1.0; tr = 1.0; tw = 1.0
	var k := clampf(delta * 0.12, 0.0, 1.0)
	cloudiness = lerpf(cloudiness, tc, k)
	fog_amount = lerpf(fog_amount, tf, k)
	rain = lerpf(rain, tr, k * 2.0)
	wind = lerpf(wind, tw, k)
	# roads get wet quickly in rain and dry slowly (faster in the sun)
	if rain > 0.2:
		wetness = minf(1.0, wetness + delta * 0.05 * rain)
	else:
		wetness = maxf(0.0, wetness - delta * (0.004 + 0.006 * (1.0 - night_factor)))
	night_factor = _night(hour)
	RenderingServer.global_shader_parameter_set("wetness", wetness)
	RenderingServer.global_shader_parameter_set("night_factor", night_factor)
	RenderingServer.global_shader_parameter_set("wind_strength", wind)


func _night(h: float) -> float:
	# 0 during the day, 1 at night with dusk/dawn ramps
	if h < 5.0 or h > 20.5:
		return 1.0
	if h < 7.0:
		return 1.0 - (h - 5.0) / 2.0
	if h > 18.5:
		return (h - 18.5) / 2.0
	return 0.0


func set_weather(w: int) -> void:
	_target_weather = w
	weather = w
	weather_changed.emit(WEATHER_NAMES[w])


func next_weather() -> void:
	set_weather((weather + 1) % WEATHER_NAMES.size())


func weather_name() -> String:
	return WEATHER_NAMES[weather]


func time_string() -> String:
	var h := int(hour)
	var m := int((hour - h) * 60.0)
	return "%02d:%02d" % [h, m]


## Sun direction (pointing from the sun towards the world)
func sun_elevation_deg() -> float:
	return sin((hour - 6.0) / 24.0 * TAU) * 62.0
