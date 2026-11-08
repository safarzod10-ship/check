class_name AICar
extends AnimatableBody3D
## Kinematic traffic car following road lanes (cheap: no wheel physics).
## Implements the Vehicle contract; set_driver()/make_drivable() convert it into a physics Vehicle
## (carjacking). Groups: "traffic", "vehicles".

const LANE_W := 3.5

var manager: Node = null
var car_type := "sedan"
var paint := Color.WHITE
var data: Dictionary = {}
var ri := 0
var s := 0.0
var dir := 1
var lane := 0
var speed := 0.0
var cruise := 13.0
var _lat := 0.0
var _lat_target := 0.0
var _stop_timer := 0.0
var _dist_since_stop := 0.0
var _next_stop := 400.0
var _turn_cool := 0.0
var _wheels: Array[MeshInstance3D] = []
var _brake_mi: MeshInstance3D
var _wheel_rot := 0.0
var _smooth_pos := Vector3.ZERO
var _blend := 0.0
var braking := false


func setup(type: String, color: Color, road: int, sample: float, direction: int, lane_idx: int) -> void:
	car_type = type
	data = CarFactory.build(type, color)
	paint = data["color"]
	ri = road
	s = sample
	dir = direction
	lane = lane_idx
	name = "AI_" + type
	add_to_group("traffic")
	add_to_group("vehicles")
	sync_to_physics = false
	collision_layer = 1 << (GameState.LAYER_VEHICLE - 1)
	collision_mask = 0
	var mi := MeshInstance3D.new()
	mi.mesh = data["body"]
	add_child(mi)
	_brake_mi = MeshInstance3D.new()
	_brake_mi.mesh = data["brake"]
	_brake_mi.visibility_range_end = 150.0
	_brake_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_brake_mi)
	if data["siren_red"]:
		var a := MeshInstance3D.new()
		a.mesh = data["siren_red"]
		add_child(a)
		var b := MeshInstance3D.new()
		b.mesh = data["siren_blue"]
		add_child(b)
	if data["extras"].has("sign"):
		var lbl := Label3D.new()
		lbl.text = "ТАКСИ"
		lbl.font_size = 40
		lbl.pixel_size = 0.004
		lbl.modulate = Color(0.05, 0.05, 0.05)
		lbl.position = data["extras"]["sign"] + Vector3(0, 0, 0.115)
		lbl.visibility_range_end = 80.0
		add_child(lbl)
	for wp in data["wheels"]:
		var w := MeshInstance3D.new()
		w.mesh = data["wheel"]
		w.position = wp
		w.visibility_range_end = 110.0   # perf: wheels are hidden by the body silhouette far away
		w.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(w)
		_wheels.append(w)
	for sh in data["shapes"]:
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = sh[1]
		cs.shape = bx
		cs.position = sh[0]
		add_child(cs)
	var rtype: String = WorldData.roads[ri]["type"]
	cruise = {"avenue": 16.5, "boulevard": 14.0, "street": 11.0, "highway": 20.0, "mountain": 11.0, "rural": 12.5, "dirt": 7.0}.get(rtype, 12.0)
	cruise *= randf_range(0.85, 1.12)
	if car_type in ["bus", "truck"]:
		cruise *= 0.8
	speed = cruise * 0.7
	_lat = _lane_offset()
	_lat_target = _lat
	_next_stop = randf_range(250.0, 450.0)
	var tf := _pose()
	global_transform = tf
	_smooth_pos = tf.origin


func _lanes_per_dir() -> int:
	var rt: Dictionary = WorldData.road_type(ri)
	return maxi(1, int(rt["lanes"]) / 2)


func _lane_offset() -> float:
	if int(WorldData.road_type(ri)["lanes"]) <= 1:
		return 0.0
	return (lane + 0.5) * LANE_W


func _curb_offset() -> float:
	var rt: Dictionary = WorldData.road_type(ri)
	return float(rt["half"]) - data["width"] * 0.5 - 0.4


func _sample(sv: float) -> Vector3:
	var pts: Array = WorldData.roads[ri]["pts"]
	var n := pts.size()
	sv = clampf(sv, 0.0, n - 1.001)
	var i0 := int(sv)
	var t := sv - i0
	var a: Array = pts[i0]
	var b: Array = pts[i0 + 1]
	return Vector3(lerpf(a[0], b[0], t), lerpf(a[1], b[1], t), lerpf(a[2], b[2], t))


func _pose() -> Transform3D:
	var p := _sample(s)
	var ahead := _sample(s + dir * 1.5)
	var behind := _sample(s - dir * 1.5)
	var f := ahead - behind
	if f.length() < 0.01:
		f = Vector3.BACK
	f = f.normalized()
	var flat := Vector3(f.x, 0, f.z).normalized()
	var right := Vector3(-flat.z, 0, flat.x)
	var pos := p + right * _lat + Vector3(0, WorldData.ROAD_LIFT, 0)
	var x := Vector3.UP.cross(f).normalized()
	var y := f.cross(x).normalized()
	return Transform3D(Basis(x, y, f), pos)


func _physics_process(delta: float) -> void:
	var pts: Array = WorldData.roads[ri]["pts"]
	var n := pts.size()
	_turn_cool = maxf(0.0, _turn_cool - delta)
	# --- desired speed
	var target := cruise
	# curvature ahead
	var f0 := (_sample(s + dir * 2.0) - _sample(s)).normalized()
	var f1 := (_sample(s + dir * 8.0) - _sample(s + dir * 6.0)).normalized()
	var bend := 1.0 - clampf(f0.dot(f1), -1.0, 1.0)
	target = minf(target, lerpf(cruise, 5.0, clampf(bend * 6.0, 0.0, 1.0)))
	if _stop_timer > 0.0:
		_stop_timer -= delta
		target = 0.0
		if _stop_timer <= 0.0:
			_lat_target = _lane_offset()
	var obstacle := _obstacle_distance()
	if obstacle < 40.0:
		target = minf(target, maxf(0.0, (obstacle - 7.0) * 0.6))
	braking = target < speed - 0.5
	speed = move_toward(speed, target, delta * (6.0 if braking else 2.2))
	# --- advance along the road
	var i0 := clampi(int(s), 0, n - 2)
	var seg := Vector2(pts[i0 + 1][0] - pts[i0][0], pts[i0 + 1][2] - pts[i0][2]).length()
	var ds := speed * delta / maxf(seg, 0.5)
	var old_s := s
	s += ds * dir
	_dist_since_stop += speed * delta
	_lat = move_toward(_lat, _lat_target, delta * 1.5)
	# bus / taxi stops
	if car_type in ["bus", "minibus", "taxi"] and _dist_since_stop > _next_stop and _stop_timer <= 0.0:
		var rtype: String = WorldData.roads[ri]["type"]
		if rtype in ["avenue", "boulevard", "street"] and (car_type != "taxi" or randf() < 0.4):
			_stop_timer = randf_range(4.0, 8.0)
			_lat_target = _curb_offset()
		_dist_since_stop = 0.0
		_next_stop = randf_range(320.0, 480.0) if car_type != "taxi" else randf_range(400.0, 900.0)
	# intersections: maybe turn
	if manager and _turn_cool <= 0.0:
		var turn: Array = manager.intersection_between(ri, old_s, s)
		if not turn.is_empty() and randf() < 0.35:
			_switch_road(turn[0], turn[1])
	# road end
	if s >= n - 1.05 or s <= 0.05:
		var done := false
		if manager:
			var nxt: Array = manager.connection_at_end(ri, dir > 0)
			if not nxt.is_empty():
				_switch_road(nxt[0], nxt[1])
				done = true
		if not done:
			dir = -dir
			s = clampf(s, 0.1, n - 1.1)
			_blend = 1.0
	var tf := _pose()
	if _blend > 0.0:
		_blend = maxf(0.0, _blend - delta * 1.2)
		tf.origin = _smooth_pos.lerp(tf.origin, clampf(delta * 5.0, 0.0, 1.0))
	_smooth_pos = tf.origin
	global_transform = tf
	# wheels
	_wheel_rot += speed * delta / data["wheel_radius"]
	for w in _wheels:
		w.rotation.x = _wheel_rot
	_brake_mi.material_override = CarFactory.material("brake_on") if braking or speed < 0.3 else null


func _switch_road(new_ri: int, new_s: int) -> void:
	var npts: Array = WorldData.roads[new_ri]["pts"]
	var rt: String = WorldData.roads[new_ri]["type"]
	if rt == "dirt" and car_type in ["bus", "truck", "minibus"]:
		return
	ri = new_ri
	s = float(new_s)
	if new_s < 3:
		dir = 1
	elif new_s > npts.size() - 4:
		dir = -1
	else:
		dir = 1 if randf() < 0.5 else -1
	lane = mini(lane, _lanes_per_dir() - 1)
	if _lanes_per_dir() >= 3:
		lane = mini(lane, _lanes_per_dir() - 2)
	_lat_target = _lane_offset()
	_lat = _lat_target
	_blend = 1.0
	_turn_cool = 3.0
	cruise = {"avenue": 16.5, "boulevard": 14.0, "street": 11.0, "highway": 20.0, "mountain": 11.0, "rural": 12.5, "dirt": 7.0}.get(rt, 12.0) * randf_range(0.85, 1.1)


## distance to the nearest obstacle in our lane ahead
func _obstacle_distance() -> float:
	var best := 999.0
	var fwd := global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var p := global_position
	if manager:
		for other in manager.cars:
			if other == self or not is_instance_valid(other):
				continue
			var d: Vector3 = other.global_position - p
			var along := d.dot(fwd)
			if along > 0.0 and along < best:
				var lat := absf(d.x * fwd.z - d.z * fwd.x)
				if lat < 2.2 and absf(d.y) < 4.0:
					best = along - other.data["length"] * 0.5 + 2.0
		for q in manager.ped_positions:
			var d2: Vector3 = q - p
			var al := d2.dot(fwd)
			if al > 0.0 and al < best and absf(d2.x * fwd.z - d2.z * fwd.x) < 2.0 and absf(d2.y) < 3.0:
				best = al
	var targets := []
	if GameState.current_vehicle and is_instance_valid(GameState.current_vehicle):
		targets.append(GameState.current_vehicle.global_position)
	elif GameState.player and is_instance_valid(GameState.player):
		targets.append(GameState.player.global_position)
	for tp in targets:
		var d3: Vector3 = tp - p
		var a3 := d3.dot(fwd)
		if a3 > 0.0 and a3 < best and absf(d3.x * fwd.z - d3.z * fwd.x) < 2.6 and absf(d3.y) < 4.0:
			best = a3 - 1.0
	return best


# ---------------------------------------------------------------------------
# Vehicle contract / carjacking
# ---------------------------------------------------------------------------
func get_speed_kmh() -> float:
	return speed * 3.6


func get_seat_transform() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, data["seat"])


func get_door_position() -> Vector3:
	return global_transform * data["door"]


func is_player_controlled() -> bool:
	return false


## Replace this kinematic car with a physics Vehicle at the same transform.
func make_drivable() -> Vehicle:
	var v := Vehicle.create(car_type, paint)
	var parent := get_parent()
	parent.add_child(v)
	v.global_transform = global_transform
	v.global_position += Vector3(0, 0.05, 0)
	v.set_parked(false)
	v.linear_velocity = global_transform.basis.z * speed
	if manager:
		manager.on_car_converted(self, v)
	remove_from_group("vehicles")
	remove_from_group("traffic")
	queue_free()
	return v


## Carjack: returns the new physics Vehicle (callers should use the return value).
func set_driver(node: Node) -> Vehicle:
	var v := make_drivable()
	v.set_driver(node)
	return v


func on_bumped(_by: Node, _kmh: float) -> void:
	var v := make_drivable()
	v.set_driver(null)
	v.brake = 0.0
