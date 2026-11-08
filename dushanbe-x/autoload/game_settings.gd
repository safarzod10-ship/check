extends Node
## Graphics / gameplay settings with presets for different Android devices.
## Saved to user://settings.cfg. Systems listen to `changed` and re-read values.

signal changed

const PATH := "user://settings.cfg"

const PRESETS := {
	"low": {
		"render_scale": 0.6, "msaa": 0, "shadows": false, "shadow_distance": 0.0,
		"view_distance": 2500.0, "terrain_lod_bias": 0.6, "building_distance": 700.0,
		"tree_distance": 600.0, "grass_density": 0.0, "grass_radius": 0.0, "detail_distance": 180.0,
		"traffic_density": 0.4, "pedestrian_density": 0.4, "fps_cap": 30, "rain_particles": 600,
		"fog": true, "street_lights": 4, "water_quality": 0,
	},
	"medium": {
		"render_scale": 0.75, "msaa": 0, "shadows": true, "shadow_distance": 80.0,
		"view_distance": 4500.0, "terrain_lod_bias": 0.85, "building_distance": 1100.0,
		"tree_distance": 900.0, "grass_density": 0.5, "grass_radius": 35.0, "detail_distance": 280.0,
		"traffic_density": 0.7, "pedestrian_density": 0.7, "fps_cap": 30, "rain_particles": 1500,
		"fog": true, "street_lights": 8, "water_quality": 1,
	},
	"high": {
		"render_scale": 1.0, "msaa": 1, "shadows": true, "shadow_distance": 150.0,
		"view_distance": 7000.0, "terrain_lod_bias": 1.0, "building_distance": 1600.0,
		"tree_distance": 1400.0, "grass_density": 1.0, "grass_radius": 55.0, "detail_distance": 400.0,
		"traffic_density": 1.0, "pedestrian_density": 1.0, "fps_cap": 60, "rain_particles": 3000,
		"fog": true, "street_lights": 12, "water_quality": 2,
	},
	"ultra": {
		"render_scale": 1.0, "msaa": 2, "shadows": true, "shadow_distance": 260.0,
		"view_distance": 10000.0, "terrain_lod_bias": 1.4, "building_distance": 2400.0,
		"tree_distance": 2000.0, "grass_density": 1.6, "grass_radius": 75.0, "detail_distance": 600.0,
		"traffic_density": 1.3, "pedestrian_density": 1.3, "fps_cap": 60, "rain_particles": 5000,
		"fog": true, "street_lights": 16, "water_quality": 2,
	},
}

var preset := "medium"
var values: Dictionary = {}
var sound_volume := 0.8
var music_volume := 0.5
var camera_sensitivity := 1.0
var invert_y := false
var show_fps := true


func _ready() -> void:
	_setup_input()
	preset = "medium" if OS.has_feature("mobile") else "high"
	values = PRESETS[preset].duplicate()
	load_settings()
	apply.call_deferred()


func get_v(key: String, default_value = null):
	return values.get(key, default_value)


func set_preset(p: String) -> void:
	if not PRESETS.has(p):
		return
	preset = p
	values = PRESETS[p].duplicate()
	apply()
	save_settings()


func set_value(key: String, v) -> void:
	values[key] = v
	preset = "custom"
	apply()
	save_settings()


func apply() -> void:
	var vp := get_viewport()
	if vp:
		vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		vp.scaling_3d_scale = float(values["render_scale"])
		vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X][int(values["msaa"])]
	Engine.max_fps = int(values["fps_cap"])
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(sound_volume, 0.001)))
	changed.emit()


func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("graphics", "preset", preset)
	for k in values:
		cf.set_value("graphics", k, values[k])
	cf.set_value("game", "sound_volume", sound_volume)
	cf.set_value("game", "camera_sensitivity", camera_sensitivity)
	cf.set_value("game", "invert_y", invert_y)
	cf.set_value("game", "show_fps", show_fps)
	cf.save(PATH)


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	preset = cf.get_value("graphics", "preset", preset)
	if PRESETS.has(preset):
		values = PRESETS[preset].duplicate()
	for k in values.keys():
		values[k] = cf.get_value("graphics", k, values[k])
	sound_volume = cf.get_value("game", "sound_volume", sound_volume)
	camera_sensitivity = cf.get_value("game", "camera_sensitivity", camera_sensitivity)
	invert_y = cf.get_value("game", "invert_y", invert_y)
	show_fps = cf.get_value("game", "show_fps", show_fps)


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "sprint": [KEY_SHIFT], "crouch": [KEY_C], "attack": [KEY_F],
		"interact": [KEY_E], "enter_vehicle": [KEY_G, KEY_ENTER], "handbrake": [KEY_SPACE],
		"horn": [KEY_H], "pause": [KEY_ESCAPE], "map": [KEY_M], "camera_mode": [KEY_V],
		"time_skip": [KEY_T], "weather_next": [KEY_Y],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var pad := {"jump": JOY_BUTTON_A, "attack": JOY_BUTTON_X, "enter_vehicle": JOY_BUTTON_Y,
		"crouch": JOY_BUTTON_B, "sprint": JOY_BUTTON_LEFT_STICK, "pause": JOY_BUTTON_START}
	for action in pad:
		var ev := InputEventJoypadButton.new()
		ev.button_index = pad[action]
		InputMap.action_add_event(action, ev)
