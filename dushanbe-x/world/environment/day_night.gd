class_name DayNight
extends Node3D
## Sun / moon, sky, fog, ambient light and rain driven by TimeWeather.

var env: Environment
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var moon: DirectionalLight3D
var sky_mat: ShaderMaterial
var rain: GPUParticles3D
var _lightning := 0.0
var _lightning_timer := 5.0


func _ready() -> void:
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://world/environment/sky.gdshader")
	sky_mat.set_shader_parameter("cloud_noise", Mats.tex("noise"))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 0.85
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 1.2
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_density = 0.00012
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.25
	env.fog_height = 900.0
	env.fog_height_density = 0.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.08
	env.adjustment_contrast = 1.04
	world_env = WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 150.0
	sun.directional_shadow_fade_start = 0.8
	sun.shadow_blur = 1.2
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.5
	sun.light_angular_distance = 0.5
	add_child(sun)
	moon = DirectionalLight3D.new()
	moon.name = "Moon"
	moon.light_color = Color(0.55, 0.65, 0.95)
	moon.light_energy = 0.12
	moon.shadow_enabled = false
	add_child(moon)

	_make_rain()
	GameSettings.changed.connect(_apply_settings)
	_apply_settings()
	_update(0.0)


func _apply_settings() -> void:
	sun.shadow_enabled = GameSettings.get_v("shadows", true)
	sun.directional_shadow_max_distance = maxf(30.0, GameSettings.get_v("shadow_distance", 150.0))
	rain.amount = int(GameSettings.get_v("rain_particles", 2000))
	var vd: float = GameSettings.get_v("view_distance", 7000.0)
	var cam := get_viewport().get_camera_3d()
	if cam:
		cam.far = vd + 12000.0


func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	var h := TimeWeather.hour
	# sun moves east (+X) -> south (+Z) -> west (-X); north is -Z
	var day_angle := (h - 6.0) / 24.0 * TAU              # 0 at 6:00 (sunrise), PI/2 at noon
	var elev := sin(day_angle) * deg_to_rad(64.0)
	var azim := day_angle                                  # 0 east, PI/2 south, PI west
	var sun_dir := Vector3(cos(azim) * cos(elev), sin(elev), sin(azim) * cos(elev) * 0.85 + 0.25).normalized()
	sun.look_at_from_position(Vector3.ZERO, -sun_dir, Vector3.UP if absf(sun_dir.y) < 0.99 else Vector3.FORWARD)
	var moon_dir := -sun_dir
	moon_dir.y = absf(moon_dir.y) * 0.8 + 0.2
	moon_dir = moon_dir.normalized()
	moon.look_at_from_position(Vector3.ZERO, -moon_dir, Vector3.UP)

	var day := clampf(smoothstep(-0.12, 0.25, sun_dir.y), 0.0, 1.0)
	var sunset := clampf(1.0 - absf(sun_dir.y) / 0.35, 0.0, 1.0) * clampf(sun_dir.y * 4.0 + 1.0, 0.0, 1.0)
	var cl := TimeWeather.cloudiness
	var rainv := TimeWeather.rain
	var fog := TimeWeather.fog_amount
	var dark := clampf(rainv * 1.2, 0.0, 1.0)

	sky_mat.set_shader_parameter("sun_dir", sun_dir)
	sky_mat.set_shader_parameter("moon_dir", moon_dir)
	sky_mat.set_shader_parameter("day_amount", day)
	sky_mat.set_shader_parameter("sunset_amount", sunset)
	sky_mat.set_shader_parameter("cloudiness", cl)
	sky_mat.set_shader_parameter("overcast_dark", dark)

	var warm := Color(1.0, 0.62, 0.38).lerp(Color(1.0, 0.96, 0.9), clampf(sun_dir.y * 2.5, 0.0, 1.0))
	sun.light_color = warm
	sun.light_energy = clampf(sun_dir.y * 4.0, 0.0, 1.0) * lerpf(1.25, 0.35, clampf(cl * 1.1 - 0.1, 0.0, 1.0))
	sun.visible = sun_dir.y > -0.05
	moon.visible = not sun.visible or day < 0.3
	moon.light_energy = 0.14 * (1.0 - cl * 0.7)

	env.ambient_light_energy = lerpf(0.25, 1.0, day) * lerpf(1.0, 0.8, cl)
	env.background_energy_multiplier = lerpf(0.6, 1.0, day)
	var fog_day := Color(0.72, 0.8, 0.9).lerp(Color(0.62, 0.64, 0.68), cl)
	var fog_night := Color(0.05, 0.06, 0.09)
	var fog_col := fog_night.lerp(fog_day, day).lerp(Color(1.0, 0.6, 0.4), sunset * 0.35)
	env.fog_light_color = fog_col
	env.fog_density = 0.00010 + cl * 0.00008 + rainv * 0.0006 + fog * 0.0055
	env.fog_aerial_perspective = lerpf(0.55, 0.05, fog)
	env.fog_sky_affect = lerpf(0.2, 1.0, maxf(fog, rainv * 0.6))
	env.tonemap_exposure = lerpf(1.25, 1.0, day)

	# rain particles follow the camera
	var cam := get_viewport().get_camera_3d()
	if cam:
		rain.global_position = cam.global_position + Vector3(0, 12, 0)
	rain.emitting = rainv > 0.08
	rain.amount_ratio = clampf(rainv, 0.05, 1.0)

	# lightning in storms
	if TimeWeather.weather == TimeWeather.Weather.STORM:
		_lightning_timer -= delta
		if _lightning_timer <= 0.0:
			_lightning = 1.0
			_lightning_timer = randf_range(4.0, 14.0)
	_lightning = maxf(0.0, _lightning - delta * 4.0)
	if _lightning > 0.0:
		env.ambient_light_energy += _lightning * 2.5
		env.background_energy_multiplier += _lightning * 2.0


func _make_rain() -> void:
	rain = GPUParticles3D.new()
	rain.name = "Rain"
	rain.amount = 2000
	rain.lifetime = 1.2
	rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 50, 60))
	rain.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(28, 2, 28)
	pm.direction = Vector3(0.08, -1, 0.04)
	pm.spread = 3.0
	pm.initial_velocity_min = 22.0
	pm.initial_velocity_max = 28.0
	pm.gravity = Vector3(0, -9.8, 0)
	rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.025, 0.7)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	q.material = m
	rain.draw_pass_1 = q
	rain.emitting = false
	add_child(rain)
