class_name GrassField
extends Node3D
## Grass and wild flowers around the camera focus: 16 m cells in a radius, MultiMesh per cell,
## density from the meadow map, no grass on roads/urban ground/fields/rock/snow.

const CELL := 16.0

var is_idle := true
var radius := 55.0
var density := 1.0
var _cells: Dictionary = {}
var _mesh: ArrayMesh
var _mat: ShaderMaterial
var _timer := 0.0


func _ready() -> void:
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://world/nature/grass.gdshader")
	_mat.set_shader_parameter("noise_tex", Mats.tex("noise"))
	_mesh = _make_clump()
	GameSettings.changed.connect(_apply)
	_apply()


func _apply() -> void:
	radius = GameSettings.get_v("grass_radius", 55.0)
	density = GameSettings.get_v("grass_density", 1.0)
	_mat.set_shader_parameter("fade_dist", radius)
	for k in _cells:
		_cells[k].queue_free()
	_cells.clear()


func _make_clump() -> ArrayMesh:
	var kit := MeshKit.new()
	var s: Dictionary = kit._s("grass")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for b in 7:
		var a := rng.randf() * TAU
		var off := Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
		var h := rng.randf_range(0.35, 0.75)
		var w := 0.05
		var dir := Vector3(cos(a), 0, sin(a))
		var lean := Vector3(rng.randf_range(-0.12, 0.12), 0, rng.randf_range(-0.12, 0.12))
		var base: int = s["v"].size()
		var nrm := dir.cross(Vector3.UP).normalized()
		s["v"].append_array([off - dir * w, off + dir * w, off + lean + Vector3(0, h, 0)])
		s["n"].append_array([Vector3.UP, Vector3.UP, Vector3.UP])
		var fl := Color(0, 0, 0, 0)
		s["c"].append_array([fl, fl, fl])
		s["uv"].append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		s["uv2"].append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		s["i"].append_array([base, base + 1, base + 2])
		var _n := nrm
	# a couple of flower heads (vertex alpha = 1 marks flower colour)
	var cols := [Color(0.95, 0.2, 0.15, 1), Color(1, 0.85, 0.2, 1), Color(0.95, 0.95, 1, 1), Color(0.65, 0.35, 0.9, 1)]
	for f in 2:
		var p := Vector3(rng.randf_range(-0.3, 0.3), rng.randf_range(0.45, 0.6), rng.randf_range(-0.3, 0.3))
		var c: Color = cols[f * 2 % 4]
		var base2: int = s["v"].size()
		s["v"].append_array([p + Vector3(-0.06, 0, 0), p + Vector3(0.06, 0, 0), p + Vector3(0, 0.08, 0), p + Vector3(0, 0, 0.06)])
		s["n"].append_array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
		s["c"].append_array([c, c, c, c])
		s["uv"].append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		s["uv2"].append_array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
		s["i"].append_array([base2, base2 + 1, base2 + 2, base2, base2 + 3, base2 + 2])
	return kit.build({"grass": _mat})


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or density <= 0.0 or radius <= 0.0:
		return
	_timer = 0.3
	var c := GameState.view_position()
	var ci := int(floor(c.x / CELL))
	var cj := int(floor(c.z / CELL))
	var r := int(ceil(radius / CELL))
	var want := {}
	var built := 0
	for dj in range(-r, r + 1):
		for di in range(-r, r + 1):
			var k := Vector2i(ci + di, cj + dj)
			var center := Vector2((k.x + 0.5) * CELL, (k.y + 0.5) * CELL)
			if center.distance_to(Vector2(c.x, c.z)) > radius + CELL:
				continue
			want[k] = true
			if not _cells.has(k) and built < 6:
				_cells[k] = _build_cell(k)
				built += 1
	for k in _cells.keys():
		if not want.has(k):
			_cells[k].queue_free()
			_cells.erase(k)
	is_idle = built == 0


func _build_cell(k: Vector2i) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = k.x * 92821 + k.y * 68917
	var ox := k.x * CELL
	var oz := k.y * CELL
	var buf := PackedFloat32Array()
	var n := int(70 * density)
	for q in n:
		var x := ox + rng.randf() * CELL
		var z := oz + rng.randf() * CELL
		if not WorldData.in_bounds(x, z, 5.0):
			continue
		var veg := WorldData.veg_at(x, z)
		var sp := WorldData.splat_at(x, z)
		var meadow := veg.a * (1.0 - sp.b) * (1.0 - sp.g * 0.85) * (1.0 - sp.r * 0.7) * (1.0 - sp.a)
		if rng.randf() > meadow:
			continue
		var h := WorldData.height_at(x, z)
		if h > 1500.0:
			continue
		var nrm := WorldData.normal_at(x, z)
		if nrm.y < 0.75:
			continue
		var s := rng.randf_range(0.7, 1.4)
		var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.3), s))
		buf.append_array([b.x.x, b.y.x, b.z.x, x - ox, b.x.y, b.y.y, b.z.y, h - 0.05, b.x.z, b.y.z, b.z.z, z - oz,
			clampf(sp.r + rng.randf() * 0.5, 0.0, 1.0), 0.0, 0.0, 0.0])
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _mesh
	mm.instance_count = buf.size() / 16
	if mm.instance_count > 0:
		mm.buffer = buf
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.position = Vector3(ox, 0, oz)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi
