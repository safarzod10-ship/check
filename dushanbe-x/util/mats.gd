class_name Mats
extends RefCounted
## Shared material library (one instance per material name => few draw-call states).

static var _cache: Dictionary = {}
static var _tex_cache: Dictionary = {}


static func tex(name: String) -> Texture2D:
	if not _tex_cache.has(name):
		_tex_cache[name] = load("res://textures/%s.png" % name)
	return _tex_cache[name]


static func get_mat(name: String) -> Material:
	if _cache.has(name):
		return _cache[name]
	var m: Material = _make(name)
	_cache[name] = m
	return m


static func _std(rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = rough
	m.metallic = metal
	return m


static func _shader(path: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


static func _make(name: String) -> Material:
	match name:
		"plain":
			return _std(0.85)
		"plain2":   # double sided (thin parts: flags, leaves cards, awnings)
			var m := _std(0.8)
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
			return m
		"glossy":
			return _std(0.35)
		"metal":
			return _std(0.35, 0.75)
		"gold":
			var m := _std(0.22, 1.0)
			m.vertex_color_use_as_albedo = false
			m.albedo_color = Color(1.0, 0.78, 0.34)
			return m
		"glass":
			var m := _std(0.06, 0.55)
			m.specular = 0.9
			return m
		"chrome":
			var m := _std(0.12, 1.0)
			return m
		"rubber":
			return _std(0.95)
		"lamp":
			return _shader("res://util/shaders/lamp.gdshader")
		"lamp_always":
			return _shader("res://util/shaders/lamp.gdshader", {"always_on": true})
		"facade":
			return _shader("res://world/city/building.gdshader", {"noise_tex": tex("noise")})
		"stone":
			return _shader("res://util/shaders/world_textured.gdshader", {"albedo_tex": tex("masonry"), "scale": 0.35, "rough": 0.7})
		"marble":
			return _shader("res://util/shaders/world_textured.gdshader", {"albedo_tex": tex("concrete"), "scale": 0.2, "rough": 0.3, "tex_amount": 0.35})
		"concrete":
			return _shader("res://util/shaders/world_textured.gdshader", {"albedo_tex": tex("concrete"), "scale": 0.25, "rough": 0.9})
		"paving":
			return _shader("res://util/shaders/world_textured.gdshader", {"albedo_tex": tex("paving"), "scale": 0.25, "rough": 0.8, "wet_reflect": 1.0})
		"dirt":
			return _shader("res://util/shaders/world_textured.gdshader", {"albedo_tex": tex("dirt"), "scale": 0.2, "rough": 0.95})
		"gravel":
			return _shader("res://util/shaders/world_textured.gdshader", {"albedo_tex": tex("gravel"), "scale": 0.25, "rough": 0.95})
		"rock":
			return _shader("res://util/shaders/world_textured.gdshader", {"albedo_tex": tex("rock"), "scale": 0.12, "rough": 0.85})
		"tin":
			return _shader("res://util/shaders/world_textured.gdshader", {"albedo_tex": tex("tin"), "scale": 0.4, "rough": 0.45, "metal": 0.5})
		"bark":
			return _shader("res://util/shaders/world_textured.gdshader", {"albedo_tex": tex("bark"), "scale": 0.8, "rough": 0.95})
		"wood":
			return _shader("res://util/shaders/world_textured.gdshader", {"albedo_tex": tex("bark"), "scale": 0.5, "rough": 0.8, "tex_amount": 0.5})
		"foliage":
			return _shader("res://world/nature/foliage.gdshader", {"noise_tex": tex("noise")})
		"flag":
			return _shader("res://util/shaders/flag.gdshader")
		"water":
			return _shader("res://world/water/water.gdshader", {"normal_tex": tex("water_normal")})
		"waterfall":
			return _shader("res://world/water/water.gdshader", {"normal_tex": tex("water_normal"), "flow_speed": 6.0, "foam": 0.8})
		"road":
			return _shader("res://world/roads/road.gdshader", {"asphalt_tex": tex("asphalt"), "noise_tex": tex("noise")})
		"road_dirt":
			return _shader("res://world/roads/road.gdshader", {"asphalt_tex": tex("dirt"), "noise_tex": tex("noise"), "markings": false, "dirt_road": true})
		"road_old":
			return _shader("res://world/roads/road.gdshader", {"asphalt_tex": tex("asphalt"), "noise_tex": tex("noise"), "markings": false, "patchy": true})
		"crosswalk":
			return _shader("res://world/roads/crosswalk.gdshader")
	push_warning("Mats: unknown material " + name)
	return _std()
