class_name Minimap
extends Control
## Circular minimap: rotates with the camera, zooms out with vehicle speed,
## shows the player arrow, north marker and nearby landmark icons.

const D := 270.0

var map_tex: Texture2D
var _rect: ColorRect
var _overlay: Control
var _mat: ShaderMaterial
var radius_m := 230.0
var _fwd := Vector2(0, -1)
var _pos := Vector2.ZERO
var _font: Font


func _ready() -> void:
	custom_minimum_size = Vector2(D, D)
	size = Vector2(D, D)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = ThemeDB.fallback_font
	map_tex = ImageTexture.create_from_image(WorldData.minimap_img) if WorldData.minimap_img else null
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://ui/minimap.gdshader")
	_mat.set_shader_parameter("map_tex", map_tex)
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.size = Vector2(D, D)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_overlay = Control.new()
	_overlay.size = Vector2(D, D)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	add_child(_overlay)


func _process(delta: float) -> void:
	var p := GameState.focus_position()
	_pos = Vector2(p.x, p.z)
	var cam := get_viewport().get_camera_3d()
	if cam:
		var f := -cam.global_basis.z
		var f2 := Vector2(f.x, f.z)
		if f2.length() > 0.01:
			_fwd = f2.normalized()
	var speed := 0.0
	var v = GameState.current_vehicle
	if v and is_instance_valid(v) and v.has_method("get_speed_kmh"):
		speed = v.get_speed_kmh()
	var target := 230.0 + clampf(speed, 0.0, 140.0) * 3.2
	radius_m = lerpf(radius_m, target, clampf(delta * 1.5, 0.0, 1.0))
	var size_w: float = WorldData.size
	_mat.set_shader_parameter("center_uv", Vector2((_pos.x - WorldData.origin) / size_w, (_pos.y - WorldData.origin) / size_w))
	_mat.set_shader_parameter("fwd", _fwd)
	_mat.set_shader_parameter("radius_uv", radius_m / size_w)
	_overlay.queue_redraw()


func _to_screen(w: Vector2) -> Vector2:
	var d := w - _pos
	var right := Vector2(-_fwd.y, _fwd.x)
	var s := Vector2(d.dot(right), -d.dot(_fwd)) / radius_m
	return Vector2(D, D) * 0.5 + s * D * 0.5


func _draw_overlay() -> void:
	var c := Vector2(D, D) * 0.5
	var R := D * 0.5
	# landmarks inside the circle
	for lm in WorldData.landmarks:
		if lm["id"] == "dusti_square":
			continue
		var sp := _to_screen(Vector2(lm["x"], lm["z"]))
		var off := sp - c
		if off.length() > R - 14:
			continue
		_overlay.draw_circle(sp, 7, UiTheme.RED)
		_overlay.draw_arc(sp, 7, 0, TAU, 16, Color.WHITE, 2.0, true)
	# north marker on the rim
	var n := _to_screen(_pos + Vector2(0, -1) * radius_m * 10.0)
	var nd := (n - c).normalized()
	var np := c + nd * (R - 18)
	_overlay.draw_circle(np, 15, Color(0.05, 0.06, 0.09, 0.9))
	_overlay.draw_string(_font, np + Vector2(-8, 8), "С", HORIZONTAL_ALIGNMENT_CENTER, -1, 22, UiTheme.GOLD)
	# player arrow (always points up = camera forward; rotate by player heading relative to camera)
	var heading := 0.0
	var pl = GameState.current_vehicle if GameState.current_vehicle else GameState.player
	if pl and is_instance_valid(pl) and pl is Node3D:
		var pf: Vector3 = -pl.global_basis.z
		var pf2 := Vector2(pf.x, pf.z)
		if pf2.length() > 0.01:
			pf2 = pf2.normalized()
			var right := Vector2(-_fwd.y, _fwd.x)
			heading = atan2(pf2.dot(right), pf2.dot(_fwd))
	var pts := PackedVector2Array([Vector2(0, -16), Vector2(11, 12), Vector2(0, 6), Vector2(-11, 12)])
	var tr := Transform2D(heading, c)
	var poly := tr * pts
	_overlay.draw_colored_polygon(poly, UiTheme.GOLD)
	poly.append(poly[0])
	_overlay.draw_polyline(poly, Color(0, 0, 0, 0.8), 2.0, true)
