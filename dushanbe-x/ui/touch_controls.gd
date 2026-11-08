class_name TouchControls
extends Control
## Multi-touch gameplay controls drawn with _draw (no GUI nodes => cheap, never steal focus).
## * left 40 % of the screen: floating joystick -> move_* actions with analogue strength
## * right side: drag to look (adds pixels to GameState.look_delta)
## * round buttons press/release InputMap actions while held
## Mouse works through "emulate_touch_from_mouse"; right mouse drag also looks around.

signal tap_region(id: String)

const JOY_RADIUS := 110.0
const DEADZONE := 0.12

var vehicle_mode := false
var enabled := true
var show_enter := false
var look_sensitivity := 1.0
## extra tap regions (circles) handled as callbacks: id -> [center, radius]
var regions: Dictionary = {}

var _buttons: Array = []          # Array of Dictionary
var _touch_owner: Dictionary = {} # touch index -> "joy" | "look" | button id | region id
var _joy_center := Vector2.ZERO
var _joy_pos := Vector2.ZERO
var _joy_active := false
var _joy_index := -1
var _joy_vec := Vector2.ZERO
var _look_last: Dictionary = {}
var _font: Font


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_font = ThemeDB.fallback_font
	get_viewport().size_changed.connect(_layout)
	_layout()


func _btn(id: String, label: String, action: String, c: Vector2, r: float, col: Color, mode: String) -> Dictionary:
	return {"id": id, "label": label, "action": action, "c": c, "r": r, "col": col, "mode": mode, "touch": -1}


func _layout() -> void:
	var s := get_viewport_rect().size
	var m := 44.0
	var W := s.x
	var H := s.y
	var foot := [
		_btn("jump", "ПРЫЖОК", "jump", Vector2(W - m - 95, H - m - 95), 86, UiTheme.GREEN, "foot"),
		_btn("attack", "УДАР", "attack", Vector2(W - m - 290, H - m - 78), 76, UiTheme.RED, "foot"),
		_btn("sprint", "БЕГ", "sprint", Vector2(W - m - 95, H - m - 295), 64, Color(0.2, 0.35, 0.6), "foot"),
		_btn("crouch", "ПРИСЕСТЬ", "crouch", Vector2(W - m - 265, H - m - 262), 56, Color(0.3, 0.3, 0.36), "foot"),
		_btn("interact", "ДЕЙСТВИЕ", "interact", Vector2(W - m - 455, H - m - 66), 56, Color(0.3, 0.3, 0.36), "foot"),
		_btn("enter", "СЕСТЬ", "enter_vehicle", Vector2(W - m - 430, H - m - 245), 64, UiTheme.GOLD, "enter"),
	]
	var car := [
		_btn("left", "◀", "move_left", Vector2(m + 100, H - m - 100), 88, Color(0.25, 0.27, 0.33), "car"),
		_btn("right", "▶", "move_right", Vector2(m + 300, H - m - 100), 88, Color(0.25, 0.27, 0.33), "car"),
		_btn("gas", "ГАЗ", "move_forward", Vector2(W - m - 100, H - m - 120), 92, UiTheme.GREEN, "car"),
		_btn("brake", "ТОРМОЗ", "move_back", Vector2(W - m - 305, H - m - 95), 78, UiTheme.RED, "car"),
		_btn("handbrake", "РУЧНИК", "handbrake", Vector2(W - m - 110, H - m - 335), 60, Color(0.45, 0.32, 0.1), "car"),
		_btn("horn", "СИГНАЛ", "horn", Vector2(W - m - 480, H - m - 70), 52, Color(0.3, 0.3, 0.36), "car"),
		_btn("exit", "ВЫЙТИ", "enter_vehicle", Vector2(W - m - 300, H - m - 300), 58, UiTheme.GOLD, "car"),
	]
	release_all()
	_buttons = foot + car
	queue_redraw()


func _visible(b: Dictionary) -> bool:
	match b["mode"]:
		"foot":
			return not vehicle_mode
		"enter":
			return not vehicle_mode and show_enter
		"car":
			return vehicle_mode
	return false


func set_vehicle_mode(v: bool) -> void:
	if v != vehicle_mode:
		release_all()
		vehicle_mode = v
		queue_redraw()


func set_show_enter(v: bool) -> void:
	if v != show_enter:
		show_enter = v
		queue_redraw()


func release_all() -> void:
	for b in _buttons:
		if b["touch"] != -1:
			Input.action_release(b["action"])
			b["touch"] = -1
	_end_joy()
	_touch_owner.clear()
	_look_last.clear()


func _end_joy() -> void:
	if _joy_active:
		for a in ["move_forward", "move_back", "move_left", "move_right"]:
			Input.action_release(a)
	_joy_active = false
	_joy_index = -1
	_joy_vec = Vector2.ZERO
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not enabled or not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_down(event.index, event.position)
		else:
			_touch_up(event.index)
	elif event is InputEventScreenDrag:
		_touch_move(event.index, event.position, event.relative)
	elif event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_RIGHT) or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			GameState.look_delta += event.relative * look_sensitivity


func _touch_down(idx: int, p: Vector2) -> void:
	for id in regions:
		var rg: Array = regions[id]
		if p.distance_to(rg[0]) <= rg[1]:
			_touch_owner[idx] = "region:" + id
			return
	for b in _buttons:
		if _visible(b) and p.distance_to(b["c"]) <= b["r"] * 1.12:
			b["touch"] = idx
			_touch_owner[idx] = b["id"]
			Input.action_press(b["action"])
			queue_redraw()
			get_viewport().set_input_as_handled()
			return
	var s := get_viewport_rect().size
	if p.x < s.x * 0.4 and not _joy_active and p.y > s.y * 0.25:
		_joy_active = true
		_joy_index = idx
		_joy_center = p
		_joy_pos = p
		_touch_owner[idx] = "joy"
		queue_redraw()
	else:
		_touch_owner[idx] = "look"
		_look_last[idx] = p


func _touch_move(idx: int, p: Vector2, rel: Vector2) -> void:
	var owner: String = _touch_owner.get(idx, "")
	if owner == "joy":
		_joy_pos = p
		var v := (p - _joy_center) / JOY_RADIUS
		if v.length() > 1.0:
			# drag the base along so the thumb never "falls off" the stick
			_joy_center = p - v.normalized() * JOY_RADIUS
			v = v.normalized()
		_joy_vec = v
		_apply_joy()
		queue_redraw()
	elif owner == "look":
		GameState.look_delta += rel * look_sensitivity


func _touch_up(idx: int) -> void:
	var owner: String = _touch_owner.get(idx, "")
	_touch_owner.erase(idx)
	_look_last.erase(idx)
	if owner == "joy":
		_end_joy()
	elif owner.begins_with("region:"):
		tap_region.emit(owner.substr(7))
	else:
		for b in _buttons:
			if b["touch"] == idx:
				b["touch"] = -1
				Input.action_release(b["action"])
				queue_redraw()


func _apply_joy() -> void:
	var v := _joy_vec
	if v.length() < DEADZONE:
		v = Vector2.ZERO
	_axis("move_right", "move_left", v.x)
	_axis("move_back", "move_forward", v.y)


func _axis(pos_action: String, neg_action: String, val: float) -> void:
	if val > 0.0:
		Input.action_press(pos_action, clampf(val, 0.0, 1.0))
		Input.action_release(neg_action)
	elif val < 0.0:
		Input.action_press(neg_action, clampf(-val, 0.0, 1.0))
		Input.action_release(pos_action)
	else:
		Input.action_release(pos_action)
		Input.action_release(neg_action)


func _draw() -> void:
	if not enabled:
		return
	# joystick hint / active joystick
	var s := get_viewport_rect().size
	if _joy_active:
		draw_circle(_joy_center, JOY_RADIUS, Color(0, 0, 0, 0.28))
		draw_arc(_joy_center, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.45), 3.0, true)
		draw_circle(_joy_center + _joy_vec * JOY_RADIUS, 46, Color(1, 1, 1, 0.55))
	elif not vehicle_mode:
		var hint := Vector2(s.x * 0.13, s.y - 190)
		draw_arc(hint, JOY_RADIUS, 0, TAU, 48, Color(1, 1, 1, 0.18), 3.0, true)
		draw_circle(hint, 40, Color(1, 1, 1, 0.14))
	for b in _buttons:
		if not _visible(b):
			continue
		var c: Vector2 = b["c"]
		var r: float = b["r"]
		var col: Color = b["col"]
		var pressed: bool = b["touch"] != -1
		var fill := col
		fill.a = 0.75 if pressed else 0.45
		draw_circle(c, r, fill)
		draw_arc(c, r, 0, TAU, 48, Color(1, 1, 1, 0.85 if pressed else 0.5), 3.0, true)
		var label: String = b["label"]
		if label == "◀" or label == "▶":
			var d := -1.0 if label == "◀" else 1.0
			draw_colored_polygon(PackedVector2Array([c + Vector2(d * 34, 0), c + Vector2(-d * 22, -32), c + Vector2(-d * 22, 32)]), Color(1, 1, 1, 0.92))
			continue
		var fs := 22 if label.length() > 6 else 26
		if label.length() <= 1:
			fs = 44
		var ts := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		var tc := Color(0.1, 0.08, 0.0) if col == UiTheme.GOLD else Color(1, 1, 1)
		draw_string(_font, c + Vector2(-ts.x * 0.5, fs * 0.35), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, tc)
