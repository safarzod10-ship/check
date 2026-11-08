class_name MapScreen
extends Control
## Full-screen world map: pan (drag), zoom (wheel / pinch / buttons), labels for regions,
## districts, villages and landmarks; tap a landmark to fast-travel there.

signal closed
signal travel_requested(x: float, z: float, label: String)

const MAP_UNITS := 1000.0          # map drawn as MAP_UNITS x MAP_UNITS virtual px at zoom 1

var map_tex: Texture2D
var zoom := 0.8
var offset := Vector2.ZERO
var _font: Font
var _dragging := false
var _drag_moved := 0.0
var _touches: Dictionary = {}
var _pinch_dist := 0.0
var _selected: Dictionary = {}
var _panel: PanelContainer
var _sel_label: Label
var _canvas: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	map_tex = ImageTexture.create_from_image(WorldData.minimap_img) if WorldData.minimap_img else null
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.04, 0.06, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_map)
	add_child(_canvas)
	# top bar
	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 40
	top.offset_right = -40
	top.offset_top = 24
	top.add_theme_constant_override("separation", 16)
	add_child(top)
	var title := UiTheme.title("КАРТА DUSHANBE-X", 36)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	top.add_child(title)
	for b in [["-", func(): _zoom_at(get_viewport_rect().size * 0.5, 1.0 / 1.4)],
			["+", func(): _zoom_at(get_viewport_rect().size * 0.5, 1.4)],
			["Я здесь", center_on_player], ["Закрыть", func(): closed.emit()]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(90, 70)
		btn.pressed.connect(b[1])
		top.add_child(btn)
	# selection panel
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_top = -170
	_panel.offset_bottom = -30
	_panel.offset_left = -360
	_panel.offset_right = 360
	_panel.visible = false
	add_child(_panel)
	var vb := VBoxContainer.new()
	_panel.add_child(vb)
	_sel_label = Label.new()
	_sel_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sel_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(_sel_label)
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 20)
	vb.add_child(hb)
	var go := Button.new()
	go.text = "Отправиться"
	go.custom_minimum_size = Vector2(260, 64)
	go.pressed.connect(_travel)
	hb.add_child(go)
	var cancel := Button.new()
	cancel.text = "Отмена"
	cancel.custom_minimum_size = Vector2(200, 64)
	cancel.pressed.connect(func(): _selected = {}; _panel.visible = false; _canvas.queue_redraw())
	hb.add_child(cancel)
	visibility_changed.connect(func(): if visible: center_on_player())


func center_on_player() -> void:
	var s := get_viewport_rect().size
	zoom = maxf(zoom, s.y / MAP_UNITS)
	var p := GameState.focus_position()
	offset = s * 0.5 - _world_to_map(Vector2(p.x, p.z)) * zoom
	_canvas.queue_redraw()


func _world_to_map(w: Vector2) -> Vector2:
	return (w - Vector2(WorldData.origin, WorldData.origin)) / WorldData.size * MAP_UNITS


func _to_screen(w: Vector2) -> Vector2:
	return offset + _world_to_map(w) * zoom


func _zoom_at(screen_p: Vector2, factor: float) -> void:
	var nz := clampf(zoom * factor, 0.5, 12.0)
	var f := nz / zoom
	offset = screen_p - (screen_p - offset) * f
	zoom = nz
	_canvas.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, 1.15)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, 1.0 / 1.15)
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_dragging = true
				_drag_moved = 0.0
			else:
				_dragging = false
				if _drag_moved < 12.0:
					_pick(event.position)
	elif event is InputEventMouseMotion and _dragging and _touches.size() < 2:
		offset += event.relative
		_drag_moved += event.relative.length()
		_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	# pinch zoom with two fingers
	if event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = event.position
		else:
			_touches.erase(event.index)
		_pinch_dist = 0.0
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index] = event.position
		if _touches.size() >= 2:
			var k := _touches.keys()
			var a: Vector2 = _touches[k[0]]
			var b: Vector2 = _touches[k[1]]
			var d := a.distance_to(b)
			if _pinch_dist > 0.0:
				_zoom_at((a + b) * 0.5, d / _pinch_dist)
			_pinch_dist = d
			_drag_moved = 100.0


func _pick(p: Vector2) -> void:
	var best := {}
	var bd := 34.0
	for lm in WorldData.landmarks:
		if lm["id"] == "dusti_square":
			continue
		var d := _to_screen(Vector2(lm["x"], lm["z"])).distance_to(p)
		if d < bd:
			bd = d
			best = {"x": lm["x"], "z": lm["z"], "name": lm["name"]}
	for v in WorldData.world.get("villages", []):
		var d := _to_screen(Vector2(v["x"], v["z"])).distance_to(p)
		if d < bd:
			bd = d
			best = {"x": v["x"], "z": v["z"], "name": v["name"]}
	_selected = best
	_panel.visible = not best.is_empty()
	if not best.is_empty():
		_sel_label.text = str(best["name"]) + "\n" + WorldData.place_name(best["x"], best["z"])
	_canvas.queue_redraw()


func _travel() -> void:
	if _selected.is_empty():
		return
	travel_requested.emit(float(_selected["x"]), float(_selected["z"]), str(_selected["name"]))
	_selected = {}
	_panel.visible = false


var _placed: Array[Rect2] = []


func _label(p: Vector2, text: String, fs: int, col: Color, outline := 6, avoid := false) -> void:
	var ts := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	var pos := p - Vector2(ts.x * 0.5, -fs * 0.35)
	var r := Rect2(pos - Vector2(0, fs), Vector2(ts.x, fs * 1.2))
	if avoid:
		for q in _placed:
			if q.intersects(r):
				return
	_placed.append(r)
	_canvas.draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, outline, Color(0, 0, 0, 0.85))
	_canvas.draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


func _centroid(poly: Array) -> Vector2:
	var c := Vector2.ZERO
	for q in poly:
		c += Vector2(q[0], q[1])
	return c / maxf(1.0, poly.size())


func _draw_map() -> void:
	_placed.clear()
	if map_tex:
		_canvas.draw_texture_rect(map_tex, Rect2(offset, Vector2(MAP_UNITS, MAP_UNITS) * zoom), false)
	_canvas.draw_rect(Rect2(offset, Vector2(MAP_UNITS, MAP_UNITS) * zoom), Color(1, 1, 1, 0.3), false, 2.0)
	for rg in WorldData.world.get("regions", []):
		_label(_to_screen(_centroid(rg["poly"])), str(rg["name"]).to_upper(), int(clampf(18 * zoom, 16, 34)), Color(1, 1, 1, 0.9))
	if zoom > 1.1:
		for d in WorldData.world.get("districts", []):
			_label(_to_screen(_centroid(d["poly"])), str(d["name"]), 20, Color(1.0, 0.92, 0.7))
	for v in WorldData.world.get("villages", []):
		var sp := _to_screen(Vector2(v["x"], v["z"]))
		_canvas.draw_circle(sp, 5, Color(0.95, 0.75, 0.45))
		_label(sp + Vector2(0, -16), str(v["name"]), 19, Color(1.0, 0.85, 0.6))
	if zoom > 1.6:
		for poi in WorldData.pois:
			if poi["type"] == "gas_station":
				var sp := _to_screen(Vector2(poi["x"], poi["z"]))
				_canvas.draw_rect(Rect2(sp - Vector2(7, 7), Vector2(14, 14)), Color(0.1, 0.5, 0.9))
	for lm in WorldData.landmarks:
		if lm["id"] == "dusti_square":
			continue
		var sp := _to_screen(Vector2(lm["x"], lm["z"]))
		var sel: bool = not _selected.is_empty() and _selected["name"] == lm["name"]
		_canvas.draw_circle(sp, 12 if sel else 8, Color.WHITE if sel else UiTheme.RED)
		_canvas.draw_arc(sp, 12 if sel else 8, 0, TAU, 20, UiTheme.RED if sel else Color.WHITE, 3.0 if sel else 2.0, true)
		if zoom > 1.3 or sel:
			_label(sp + Vector2(0, 26), str(lm["name"]), 17, Color.WHITE, 5, not sel)
	# player
	var p := GameState.focus_position()
	var pp := _to_screen(Vector2(p.x, p.z))
	_canvas.draw_circle(pp, 14, Color(0, 0, 0, 0.6))
	_canvas.draw_circle(pp, 10, UiTheme.GOLD)
	# scale bar (1 km)
	var s := get_viewport_rect().size
	var km := MAP_UNITS / WorldData.size * 1000.0 * zoom
	var y := s.y - 40
	_canvas.draw_line(Vector2(40, y), Vector2(40 + km, y), Color.WHITE, 5.0)
	_label(Vector2(40 + km * 0.5, y - 22), "1 км", 20, Color.WHITE)
