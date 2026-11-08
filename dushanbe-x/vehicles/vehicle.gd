class_name Vehicle
extends VehicleBody3D
## Physics vehicle (player-drivable, also used by police AI and parked cars).
## Contract (docs/ARCHITECTURE.md): get_speed_kmh(), get_seat_transform(), get_door_position(),
## set_driver(node_or_null), is_player_controlled(). Group "vehicles". Forward = +Z.

signal driver_changed(driver: Node)

var car_type := "sedan"
var paint := Color.WHITE
var data: Dictionary = {}
var driver: Node = null
var player_controlled := false
## AI input (police): {"throttle": 0..1, "brake": 0..1, "steer": -1..1, "handbrake": bool}
var ai_enabled := false
var ai_input := {"throttle": 0.0, "brake": 0.0, "steer": 0.0, "handbrake": false}

var max_kmh := 160.0
var engine_per_wheel := 2000.0
var brake_per_wheel := 30.0
var max_steer := 0.6
var _steer := 0.0
var _flip_timer := 0.0
var _brake_mi: MeshInstance3D
var _siren_r: MeshInstance3D
var _siren_b: MeshInstance3D
var siren_on := false
var _siren_t := 0.0
var _headlight: SpotLight3D
var _horn: AudioStreamPlayer3D
var _engine: AudioStreamPlayer3D
var _engine_pb: AudioStreamGeneratorPlayback
var _engine_phase := 0.0
var _rpm := 800.0
var wheels: Array[VehicleWheel3D] = []
var _hit_cooldown := 0.0
var _parked_hold := true

static var _horn_stream: AudioStreamWAV


static func create(type: String, color := Color(0, 0, 0, 0)) -> Vehicle:
	var v := Vehicle.new()
	v.setup(type, color)
	return v


func setup(type: String, color := Color(0, 0, 0, 0)) -> void:
	car_type = type
	data = CarFactory.build(type, color)
	paint = data["color"]
	name = "Vehicle_" + type
	add_to_group("vehicles")
	mass = data["mass"]
	max_kmh = data["max_kmh"]
	collision_layer = 1 << (GameState.LAYER_VEHICLE - 1)
	collision_mask = 1 | 2 | 4 | 8 | 16
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, data["wheel_radius"] * 0.9, 0.05)
	angular_damp = 0.6
	linear_damp = 0.03
	contact_monitor = true
	max_contacts_reported = 4
	can_sleep = true
	body_entered.connect(_on_body_entered)

	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = data["body"]
	add_child(mi)
	_brake_mi = MeshInstance3D.new()
	_brake_mi.name = "BrakeLights"
	_brake_mi.mesh = data["brake"]
	add_child(_brake_mi)
	if data["siren_red"]:
		_siren_r = MeshInstance3D.new()
		_siren_r.mesh = data["siren_red"]
		add_child(_siren_r)
		_siren_b = MeshInstance3D.new()
		_siren_b.mesh = data["siren_blue"]
		add_child(_siren_b)
	if data["extras"].has("sign"):
		var lbl := Label3D.new()
		lbl.text = "ТАКСИ"
		lbl.font_size = 40
		lbl.pixel_size = 0.004
		lbl.modulate = Color(0.05, 0.05, 0.05)
		lbl.outline_size = 0
		lbl.position = data["extras"]["sign"] + Vector3(0, 0, 0.115)
		add_child(lbl)
		var lbl2: Label3D = lbl.duplicate()
		lbl2.position = data["extras"]["sign"] - Vector3(0, 0, 0.115)
		lbl2.rotation.y = PI
		add_child(lbl2)
	for s in data["shapes"]:
		var cs := CollisionShape3D.new()
		var b := BoxShape3D.new()
		b.size = s[1]
		cs.shape = b
		cs.position = s[0]
		add_child(cs)

	var n_drive := 0
	for d in data["drive"]:
		if d:
			n_drive += 1
	var heavy: bool = car_type in ["bus", "truck", "minibus"]
	engine_per_wheel = mass * (2.6 if heavy else 4.0) / maxf(1, n_drive)
	brake_per_wheel = mass * 0.022
	max_steer = 0.5 if heavy else 0.62
	var r: float = data["wheel_radius"]
	for i in data["wheels"].size():
		var w := VehicleWheel3D.new()
		w.name = "Wheel%d" % i
		var rest := 0.22 if not heavy else 0.26
		# wheel node sits at the suspension top; the wheel hangs rest_length below
		w.position = data["wheels"][i] + Vector3(0, rest * 0.75, 0)
		w.wheel_radius = r
		w.wheel_rest_length = rest
		w.suspension_travel = 0.22
		w.suspension_stiffness = 42.0 if not heavy else 55.0
		w.suspension_max_force = mass * 14.0
		w.damping_compression = 2.6
		w.damping_relaxation = 3.4
		w.wheel_friction_slip = 3.4 if data["steer"][i] else 3.1
		w.wheel_roll_influence = 0.08
		w.use_as_steering = data["steer"][i]
		w.use_as_traction = data["drive"][i]
		var wm := MeshInstance3D.new()
		wm.mesh = data["wheel"]
		w.add_child(wm)
		add_child(w)
		wheels.append(w)

	_horn = AudioStreamPlayer3D.new()
	_horn.stream = _get_horn_stream()
	_horn.unit_size = 12.0
	add_child(_horn)
	set_parked(true)


func set_parked(p: bool) -> void:
	_parked_hold = p
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = p


# ---------------------------------------------------------------------------
# Contract
# ---------------------------------------------------------------------------
func get_speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func forward_speed() -> float:
	return linear_velocity.dot(global_transform.basis.z)


func get_seat_transform() -> Transform3D:
	return global_transform * Transform3D(Basis.IDENTITY, data["seat"])


func get_door_position() -> Vector3:
	return global_transform * data["door"]


func is_player_controlled() -> bool:
	return player_controlled


func set_driver(node: Node) -> Vehicle:
	driver = node
	player_controlled = node != null and node == GameState.player
	if node != null:
		set_parked(false)
		sleeping = false
	if player_controlled:
		GameState.current_vehicle = self
		_ensure_player_fx()
	elif GameState.current_vehicle == self:
		GameState.current_vehicle = null
	if node == null:
		engine_force = 0.0
		brake = brake_per_wheel * 0.5
		if _engine:
			_engine.stop()
	driver_changed.emit(node)
	return self


func make_drivable() -> Vehicle:
	return self


# ---------------------------------------------------------------------------
# Physics / control
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if freeze:
		return
	var throttle := 0.0
	var brake_in := 0.0
	var steer_in := 0.0
	var hb := false
	if player_controlled:
		throttle = Input.get_action_strength("move_forward")
		brake_in = Input.get_action_strength("move_back")
		steer_in = Input.get_action_strength("move_left") - Input.get_action_strength("move_right")
		hb = Input.is_action_pressed("handbrake")
		if Input.is_action_just_pressed("horn"):
			_horn.play()
	elif ai_enabled:
		throttle = ai_input["throttle"]
		brake_in = ai_input["brake"]
		steer_in = ai_input["steer"]
		hb = ai_input["handbrake"]
	elif driver == null:
		brake_in = 1.0

	var kmh := get_speed_kmh()
	var fwd := forward_speed()
	var ef := 0.0
	var br := 0.0
	if throttle > 0.01:
		var limit := clampf(1.0 - kmh / max_kmh, 0.0, 1.0)
		ef = engine_per_wheel * throttle * (0.35 + 0.65 * limit)
		if fwd < -1.0:
			br = brake_per_wheel * throttle
			ef = 0.0
	if brake_in > 0.01:
		if fwd > 1.0:
			br = brake_per_wheel * brake_in
		else:
			# reverse
			ef = -engine_per_wheel * 0.55 * brake_in * clampf(1.0 - kmh / 28.0, 0.0, 1.0)
	if throttle < 0.01 and brake_in < 0.01 and driver != null:
		br = brake_per_wheel * 0.03    # engine braking / rolling resistance
	engine_force = ef
	brake = br
	var target_steer := steer_in * lerpf(max_steer, 0.1, clampf(kmh / 140.0, 0.0, 1.0))
	_steer = move_toward(_steer, target_steer, delta * (2.2 if absf(target_steer) > absf(_steer) else 3.5))
	steering = _steer
	for w in wheels:
		if not w.use_as_steering:
			w.wheel_friction_slip = 1.15 if hb else 3.1
			if hb:
				w.brake = brake_per_wheel * 1.2
	# stability aids: downforce and roll damping
	var v2 := linear_velocity.length_squared()
	apply_central_force(-global_transform.basis.y * v2 * mass * 0.00035)
	var fwd_axis := global_transform.basis.z
	var roll_rate := angular_velocity.dot(fwd_axis)
	var tilt := global_transform.basis.x.y
	apply_torque(-fwd_axis * (roll_rate * 1.8 + tilt * 3.0) * mass)

	_brake_mi.material_override = CarFactory.material("brake_on") if (br > brake_per_wheel * 0.2 or (brake_in > 0.01 and fwd > 1.0)) else null
	_update_flip(delta)
	_hit_cooldown = maxf(0.0, _hit_cooldown - delta)


func _process(delta: float) -> void:
	if _siren_r:
		_siren_t += delta
		var on := siren_on
		var phase := int(_siren_t * 6.0) % 2 == 0
		_siren_r.material_override = CarFactory.material("siren_on") if on and phase else null
		_siren_b.material_override = CarFactory.material("siren_on") if on and not phase else null
	if _headlight:
		_headlight.visible = player_controlled and TimeWeather.night_factor > 0.3
	if player_controlled and _engine:
		_feed_engine()


func _update_flip(delta: float) -> void:
	var up := global_transform.basis.y.dot(Vector3.UP)
	if up < 0.35 and get_speed_kmh() < 6.0:
		_flip_timer += delta
		if _flip_timer > 3.0:
			_flip_timer = 0.0
			var f := global_transform.basis.z
			f.y = 0.0
			if f.length() < 0.1:
				f = Vector3.BACK
			var p := global_position
			var gy := WorldData.height_at(p.x, p.z)
			global_transform = Transform3D(_basis_from_forward(f.normalized()), Vector3(p.x, maxf(p.y, gy) + 1.2, p.z))
			linear_velocity = Vector3.ZERO
			angular_velocity = Vector3.ZERO
	else:
		_flip_timer = 0.0
	# fell through the world: put back on the ground
	var gp := global_position
	if gp.y < WorldData.height_at(gp.x, gp.z) - 6.0:
		global_position = Vector3(gp.x, WorldData.height_at(gp.x, gp.z) + 1.5, gp.z)
		linear_velocity = Vector3.ZERO


static func _basis_from_forward(f: Vector3) -> Basis:
	var x := Vector3.UP.cross(f).normalized()
	var y := f.cross(x).normalized()
	return Basis(x, y, f)


func _on_body_entered(body: Node) -> void:
	if _hit_cooldown > 0.0:
		return
	var kmh := get_speed_kmh()
	if body.is_in_group("pedestrians") and kmh > 10.0 and body.has_method("take_hit"):
		body.take_hit(global_position, kmh)
		_hit_cooldown = 0.5
		if player_controlled:
			GameState.add_crime(1)
	elif body.is_in_group("traffic") and kmh > 25.0 and player_controlled:
		if body.has_method("on_bumped"):
			body.on_bumped(self, kmh)
		_hit_cooldown = 0.5


# ---------------------------------------------------------------------------
# Effects (player car only)
# ---------------------------------------------------------------------------
func _ensure_player_fx() -> void:
	if _headlight == null:
		_headlight = SpotLight3D.new()
		_headlight.spot_range = 45.0
		_headlight.spot_angle = 32.0
		_headlight.light_energy = 4.0
		_headlight.light_color = Color(1.0, 0.95, 0.85)
		_headlight.shadow_enabled = false
		_headlight.position = Vector3(0, 0.8, data["length"] * 0.5 + 0.2)
		_headlight.rotation = Vector3(deg_to_rad(-8.0), PI, 0)   # SpotLight shines along -Z, car forward is +Z
		add_child(_headlight)
	if _engine == null:
		_engine = AudioStreamPlayer3D.new()
		var gen := AudioStreamGenerator.new()
		gen.mix_rate = 22050.0
		gen.buffer_length = 0.12
		_engine.stream = gen
		_engine.unit_size = 8.0
		_engine.volume_db = -8.0
		add_child(_engine)
	if not _engine.playing:
		_engine.play()
		_engine_pb = _engine.get_stream_playback() as AudioStreamGeneratorPlayback


func _feed_engine() -> void:
	if _engine_pb == null:
		return
	var thr := Input.get_action_strength("move_forward")
	var target := 800.0 + absf(forward_speed()) * 95.0 * (1.0 if car_type not in ["bus", "truck"] else 0.6) + thr * 900.0
	# fake gear changes
	target = 800.0 + fmod(target - 800.0, 3600.0)
	_rpm = lerpf(_rpm, target, 0.08)
	var freq := _rpm / 60.0 * 2.0
	var frames := _engine_pb.get_frames_available()
	var inc := freq / 22050.0
	for i in frames:
		_engine_phase = fmod(_engine_phase + inc, 1.0)
		var s := (_engine_phase * 2.0 - 1.0) * 0.35 + sin(_engine_phase * TAU * 2.0) * 0.2 + (randf() - 0.5) * 0.08 * (0.3 + thr)
		_engine_pb.push_frame(Vector2(s, s) * (0.4 + thr * 0.3))


static func _get_horn_stream() -> AudioStreamWAV:
	if _horn_stream:
		return _horn_stream
	var rate := 22050
	var n := int(rate * 0.45)
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		var t := float(i) / rate
		var env := clampf(t * 40.0, 0.0, 1.0) * clampf((0.45 - t) * 30.0, 0.0, 1.0)
		var s := (signf(sin(TAU * 415.0 * t)) * 0.5 + signf(sin(TAU * 520.0 * t)) * 0.5) * 0.35 * env
		bytes.encode_s16(i * 2, int(s * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = bytes
	_horn_stream = w
	return w
