class_name CameraRig
extends Node3D
## Third-person orbit camera. Follows the player, or the vehicle when GameState.current_vehicle is set.
## Look input: GameState.look_delta (touch drag from the HUD, pixels) + right-mouse drag / captured mouse.

const FOOT_DIST := [3.4, 4.6, 6.5]
const CAR_DIST := [6.5, 8.5, 11.0]

var target: Node3D
var yaw := 0.0
var pitch := deg_to_rad(-12.0)
var distance := 4.6
var mode := 1
var camera: Camera3D
var arm: SpringArm3D
var _pivot: Node3D
var _idle_look := 10.0
var _smoothed := Vector3.ZERO
var _shake := 0.0


func _ready() -> void:
	top_level = true
	_pivot = Node3D.new()
	add_child(_pivot)
	arm = SpringArm3D.new()
	arm.collision_mask = 1
	arm.margin = 0.25
	var sphere := SphereShape3D.new()
	sphere.radius = 0.22
	arm.shape = sphere
	arm.spring_length = distance
	_pivot.add_child(arm)
	camera = Camera3D.new()
	camera.near = 0.2
	camera.fov = 70.0
	arm.add_child(camera)
	camera.make_current()
	GameState.camera = camera
	GameSettings.changed.connect(_apply_settings)
	_apply_settings()
	if target is CollisionObject3D:
		arm.add_excluded_object(target.get_rid())
	if target:
		_smoothed = target.global_position
		yaw = target.global_rotation.y


func _apply_settings() -> void:
	if camera:
		camera.far = float(GameSettings.get_v("view_distance", 7000.0)) + 12000.0


func add_shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
			GameState.look_delta += event.relative
	elif event.is_action_pressed("camera_mode"):
		mode = (mode + 1) % 3


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var veh: Node3D = GameState.current_vehicle if is_instance_valid(GameState.current_vehicle) else null
	var sens := 0.0045 * GameSettings.camera_sensitivity
	var ld := GameState.look_delta
	GameState.look_delta = Vector2.ZERO
	if ld.length_squared() > 0.0:
		_idle_look = 0.0
	else:
		_idle_look += delta
	yaw -= ld.x * sens
	pitch -= ld.y * sens * (-1.0 if GameSettings.invert_y else 1.0)
	pitch = clampf(pitch, deg_to_rad(-70.0), deg_to_rad(35.0))

	var focus: Vector3
	var want_dist: float
	var speed_kmh := 0.0
	if veh:
		focus = veh.global_position + Vector3(0, 1.6, 0)
		want_dist = CAR_DIST[mode]
		if veh.has_method("get_speed_kmh"):
			speed_kmh = veh.get_speed_kmh()
		# auto-align behind the car when the player isn't looking around
		if _idle_look > 1.2 and speed_kmh > 8.0:
			var fwd := _vehicle_forward(veh)
			if fwd.length_squared() > 0.01:
				var target_yaw := atan2(-fwd.x, -fwd.z)
				yaw = lerp_angle(yaw, target_yaw, clampf(delta * 2.0, 0.0, 1.0))
				pitch = lerpf(pitch, deg_to_rad(-10.0), clampf(delta * 1.5, 0.0, 1.0))
	else:
		var crouch: bool = target.get("crouching") == true
		focus = target.global_position + Vector3(0, 1.25 if crouch else 1.6, 0)
		want_dist = FOOT_DIST[mode]
		# gentle auto-follow while running if no look input
		if _idle_look > 2.5 and target is CharacterBody3D:
			var hv: Vector3 = target.velocity
			hv.y = 0
			if hv.length() > 3.0:
				yaw = lerp_angle(yaw, atan2(-hv.x, -hv.z), clampf(delta * 0.8, 0.0, 1.0))
	_smoothed = _smoothed.lerp(focus, clampf(delta * (14.0 if veh == null else 9.0), 0.0, 1.0))
	if _smoothed.distance_to(focus) > 20.0:
		_smoothed = focus
	global_position = _smoothed
	distance = lerpf(distance, want_dist + speed_kmh * 0.012, clampf(delta * 3.0, 0.0, 1.0))
	arm.spring_length = distance
	_pivot.rotation = Vector3(pitch, yaw, 0.0)
	# camera sits at the end of the arm, looking along -Z of the pivot
	camera.fov = lerpf(camera.fov, clampf(70.0 + speed_kmh * 0.12, 70.0, 92.0), clampf(delta * 2.0, 0.0, 1.0))
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 2.5)
		camera.h_offset = randf_range(-1, 1) * _shake * 0.15
		camera.v_offset = randf_range(-1, 1) * _shake * 0.15
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


func _vehicle_forward(veh: Node3D) -> Vector3:
	if veh.has_method("get_forward"):
		return veh.get_forward()
	var v := Vector3.ZERO
	if veh is RigidBody3D:
		v = veh.linear_velocity
	v.y = 0
	if v.length() > 1.0:
		return v.normalized()
	var f := -veh.global_basis.z
	f.y = 0
	return f.normalized()


## Horizontal camera basis used by the player for camera-relative movement.
func flat_basis() -> Basis:
	return Basis(Vector3.UP, yaw)
