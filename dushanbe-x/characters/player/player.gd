class_name Player
extends CharacterBody3D
## Third-person player: walk / run / sprint, jump, crouch, curb step-up, melee combat,
## interaction and entering / leaving vehicles (see docs/ARCHITECTURE.md for the vehicle contract).
## Builds its own children in _ready() (spawned via `load(...).new()` from scenes/main.gd).

signal health_changed(value: float)
signal died

const WALK := 1.6
const RUN := 4.3
const SPRINT := 6.9
const CROUCH := 1.4
const JUMP_V := 5.2
const STEP_H := 0.42
const HEIGHT := 1.75
const CROUCH_HEIGHT := 1.15

var appearance: Dictionary = {}
var model: Node3D
var animator: HumanoidAnimator
var rig: CameraRig
var shape: CollisionShape3D
var capsule: CapsuleShape3D

var health := 100.0
var crouching := false
var sprinting := false
var nearby_vehicle: Node3D = null
var nearby_interactable: Node3D = null
var vehicle: Node3D = null
var dead := false

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity", 9.8) * 1.25
var _scan_t := 0.0
var _combo := 0
var _combo_t := 0.0
var _hit_pending := -1.0
var _hit_force := 0.0
var _hit_range := 1.4
var _enter_t := -1.0
var _pending_vehicle: Node3D = null
var _safety_t := 0.0
var _jumped := false


func _ready() -> void:
	add_to_group("player")
	collision_layer = 1 << (GameState.LAYER_PLAYER - 1)
	collision_mask = (1 << (GameState.LAYER_WORLD - 1)) | (1 << (GameState.LAYER_VEHICLE - 1)) | \
		(1 << (GameState.LAYER_NPC - 1)) | (1 << (GameState.LAYER_PROP - 1))
	floor_max_angle = deg_to_rad(48.0)
	floor_snap_length = 0.45
	floor_constant_speed = true
	floor_block_on_wall = true
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = HEIGHT
	shape = CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = HEIGHT * 0.5
	add_child(shape)
	if appearance.is_empty():
		appearance = HumanoidBuilder.default_appearance()
		appearance["shirt"] = Color(0.88, 0.88, 0.86)
		appearance["pants"] = Color(0.14, 0.17, 0.27)
		appearance["jacket"] = true
		appearance["jacket_col"] = Color(0.2, 0.22, 0.26)
		appearance["hat"] = "none"
	model = HumanoidBuilder.create(appearance)
	add_child(model)
	animator = HumanoidAnimator.new()
	animator.name = "Animator"
	add_child(animator)
	animator.setup(model)
	animator.action_finished.connect(_on_action_finished)
	if not GameState.screenshot_mode:
		rig = CameraRig.new()
		rig.name = "CameraRig"
		rig.target = self
		add_child(rig)
	GameState.player = self


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------
func is_in_vehicle() -> bool:
	return vehicle != null


func enter_vehicle(v: Node3D) -> void:
	if v == null or vehicle != null or dead:
		return
	if v.has_method("get_driver") and v.get_driver() != null and v.get_driver() != self:
		var d: Node = v.get_driver()
		if d.has_method("eject_from_vehicle"):
			d.eject_from_vehicle()       # car-jacking an NPC driver
			GameState.add_crime(1)
	_pending_vehicle = v
	var door := _door_pos(v)
	global_position = Vector3(door.x, global_position.y, door.z)
	var to_car := v.global_position - global_position
	to_car.y = 0
	if to_car.length() > 0.1:
		rotation.y = atan2(-to_car.x, -to_car.z)
	velocity = Vector3.ZERO
	_enter_t = animator.play_action("enter_car", 1.4) * 0.85
	_set_collision(false)


func exit_vehicle() -> void:
	if vehicle == null:
		return
	var v := vehicle
	if v.has_method("set_driver"):
		v.set_driver(null)
	vehicle = null
	GameState.current_vehicle = null
	var door := _door_pos(v)
	var y := WorldData.height_at(door.x, door.z)
	var hit := _ray_down(door + Vector3(0, 3, 0), 8.0)
	if not hit.is_empty():
		y = hit.position.y
	global_position = Vector3(door.x, y + 0.05, door.z)
	var fwd := -v.global_basis.z
	rotation.y = atan2(-fwd.x, -fwd.z)
	_set_collision(true)
	velocity = Vector3.ZERO
	animator.set_state("normal")
	animator.play_action("exit_car", 1.4)


func take_hit(from: Vector3, force: float) -> void:
	if dead or vehicle:
		return
	health = maxf(0.0, health - force * 8.0)
	health_changed.emit(health)
	var away := global_position - from
	away.y = 0
	velocity += away.normalized() * force * 1.2 + Vector3(0, 1.5, 0)
	if health <= 0.0:
		_die()
	else:
		animator.play_action("hit_react")
		if rig:
			rig.add_shake(0.6)


func heal(amount: float) -> void:
	health = minf(100.0, health + amount)
	health_changed.emit(health)


# ---------------------------------------------------------------------------
# Update
# ---------------------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if vehicle:
		_follow_seat()
		if Input.is_action_just_pressed("enter_vehicle"):
			var spd := 0.0
			if vehicle.has_method("get_speed_kmh"):
				spd = vehicle.get_speed_kmh()
			if spd < 30.0:
				exit_vehicle()
		animator.tick(delta)
		return
	if _enter_t >= 0.0:
		_enter_t -= delta
		if _enter_t < 0.0:
			_finish_enter()
		animator.tick(delta)
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.2
		_scan_nearby()

	if dead:
		velocity.x = move_toward(velocity.x, 0, delta * 10)
		velocity.z = move_toward(velocity.z, 0, delta * 10)
		velocity.y -= _gravity * delta
		move_and_slide()
		animator.tick(delta, 0.0, false, is_on_floor(), velocity.y)
		return

	# --- input ---
	var inp := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var basis_y := rig.flat_basis() if rig else Basis(Vector3.UP, rotation.y)
	var dir := basis_y * Vector3(inp.x, 0, inp.y)
	dir.y = 0
	var mag := clampf(inp.length(), 0.0, 1.0)
	if Input.is_action_just_pressed("crouch"):
		_set_crouch(not crouching)
	sprinting = Input.is_action_pressed("sprint") and not crouching and mag > 0.5
	var busy := animator.is_busy() and animator.current_action() in ["punch_r", "punch_l", "kick", "interact", "exit_car", "get_up", "pickup"]
	var target_speed := 0.0
	if mag > 0.05 and not busy:
		if crouching:
			target_speed = CROUCH * mag
		elif sprinting:
			target_speed = SPRINT
		elif mag < 0.55:
			target_speed = WALK * (mag / 0.55)
		else:
			target_speed = lerpf(WALK, RUN, (mag - 0.55) / 0.45)
	var hv := Vector3(velocity.x, 0, velocity.z)
	var want := dir.normalized() * target_speed if dir.length() > 0.01 else Vector3.ZERO
	var accel := 22.0 if is_on_floor() else 4.0
	hv = hv.move_toward(want, accel * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if hv.length() > 0.3 and not busy:
		var face := atan2(-hv.x, -hv.z)
		rotation.y = lerp_angle(rotation.y, face, clampf(delta * 12.0, 0.0, 1.0))

	# --- jump / gravity ---
	if is_on_floor():
		if Input.is_action_just_pressed("jump") and not busy:
			if crouching:
				_set_crouch(false)
			else:
				velocity.y = JUMP_V
				_jumped = true
				animator.play_action("jump_up")
	else:
		velocity.y -= _gravity * delta
		velocity.y = maxf(velocity.y, -55.0)

	# --- combat / interaction / vehicles ---
	_combo_t -= delta
	if Input.is_action_just_pressed("attack"):
		_attack()
	if Input.is_action_just_pressed("interact"):
		_interact()
	if Input.is_action_just_pressed("enter_vehicle") and nearby_vehicle:
		enter_vehicle(nearby_vehicle)
		return
	if _hit_pending >= 0.0:
		_hit_pending -= delta
		if _hit_pending < 0.0:
			_resolve_hit()

	var was_air := not is_on_floor()
	var fall_speed := velocity.y
	_step_up(delta)
	move_and_slide()
	if was_air and is_on_floor():
		_jumped = false
		if fall_speed < -6.0 and not animator.is_busy():
			animator.play_action("land", 1.3)
		if fall_speed < -16.0:
			take_hit(global_position + Vector3(0, -1, 0), (-fall_speed - 16.0) * 1.2)
	_safety(delta)
	var speed := Vector2(velocity.x, velocity.z).length()
	animator.tick(delta, speed, crouching, is_on_floor() or _near_floor(), velocity.y)


func _near_floor() -> bool:
	# avoids "fall" flicker when stepping down curbs
	return velocity.y > -3.0 and not _jumped and not _ray_down(global_position + Vector3(0, 0.1, 0), 0.6).is_empty()


func _step_up(delta: float) -> void:
	if not is_on_floor():
		return
	var hv := Vector3(velocity.x, 0, velocity.z)
	if hv.length() < 0.3:
		return
	var motion := hv * delta + hv.normalized() * 0.08
	if not test_move(global_transform, motion):
		return
	var up := global_transform.translated(Vector3(0, STEP_H, 0))
	if test_move(global_transform, Vector3(0, STEP_H, 0)):
		return
	if test_move(up, motion):
		return
	# there is room above the obstacle: find the step top and lift onto it
	var probe := global_position + hv.normalized() * (capsule.radius + 0.12)
	var hit := _ray_down(probe + Vector3(0, STEP_H + 0.05, 0), STEP_H + 0.1)
	if hit.is_empty():
		return
	var rise: float = hit.position.y - global_position.y
	if rise > 0.02 and rise <= STEP_H and hit.normal.y > 0.7:
		global_position.y += rise + 0.01
		global_position += hv.normalized() * 0.05


func _safety(delta: float) -> void:
	# collision near the player streams in asynchronously: never fall through the world
	_safety_t -= delta
	if _safety_t > 0.0:
		return
	_safety_t = 0.25
	var ground := WorldData.height_at(global_position.x, global_position.z)
	if global_position.y < ground - 3.0 and _ray_down(global_position + Vector3(0, 2.0, 0), 4.0).is_empty():
		# below the terrain surface without any collider around (and not in a tunnel)
		global_position.y = ground + 0.3
		velocity.y = 0.0
	elif global_position.y < ground + 0.5 and velocity.y < -1.0 and _ray_down(global_position + Vector3(0, 1.0, 0), 3.0).is_empty():
		global_position.y = ground + 0.05
		velocity.y = 0.0


func _ray_down(from: Vector3, length: float) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -length, 0), 1 << (GameState.LAYER_WORLD - 1))
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)


func _set_crouch(on: bool) -> void:
	if not on and crouching:
		# only stand up if there is room
		var q := PhysicsShapeQueryParameters3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.28
		cap.height = HEIGHT
		q.shape = cap
		q.transform = Transform3D(Basis(), global_position + Vector3(0, HEIGHT * 0.5 + 0.05, 0))
		q.collision_mask = 1
		q.exclude = [get_rid()]
		if not get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty():
			return
	crouching = on
	capsule.height = CROUCH_HEIGHT if on else HEIGHT
	shape.position.y = capsule.height * 0.5


func _set_collision(on: bool) -> void:
	shape.disabled = not on


# ---------------------------------------------------------------------------
# Combat
# ---------------------------------------------------------------------------
func _attack() -> void:
	if animator.is_busy() and animator.current_action() in ["punch_r", "punch_l", "kick"]:
		return
	if _combo_t <= 0.0:
		_combo = 0
	var anim: String = ["punch_r", "punch_l", "kick"][_combo % 3]
	var dur := animator.play_action(anim, 1.15)
	_hit_pending = dur * (0.42 if anim == "kick" else 0.33)
	_hit_force = 6.0 if anim == "kick" else 3.5
	_hit_range = 1.6 if anim == "kick" else 1.35
	_combo += 1
	_combo_t = dur + 0.45
	velocity.x *= 0.3
	velocity.z *= 0.3


func _resolve_hit() -> void:
	var fwd := -global_basis.z
	var hit_any := false
	for group in ["pedestrians", "police"]:
		for n in get_tree().get_nodes_in_group(group):
			if not (n is Node3D) or n == self:
				continue
			var to: Vector3 = n.global_position - global_position
			to.y = 0
			if to.length() < _hit_range and (to.length() < 0.4 or fwd.dot(to.normalized()) > 0.45):
				if n.has_method("take_hit"):
					n.take_hit(global_position, _hit_force)
					hit_any = true
	if hit_any:
		GameState.add_crime(1)
		if rig:
			rig.add_shake(0.25)


func _interact() -> void:
	if animator.is_busy():
		return
	if nearby_interactable and nearby_interactable.has_method("interact"):
		var tgt := nearby_interactable.global_position - global_position
		tgt.y = 0
		if tgt.length() > 0.1:
			rotation.y = atan2(-tgt.x, -tgt.z)
		animator.play_action("interact")
		nearby_interactable.interact(self)
	else:
		animator.play_action("interact")


func _die() -> void:
	dead = true
	animator.set_state("down")
	died.emit()
	GameState.message("Вы потеряли сознание…")
	get_tree().create_timer(4.0).timeout.connect(_respawn)


func _respawn() -> void:
	var sp: Dictionary = WorldData.world["spawn"]
	global_position = Vector3(sp["x"], WorldData.height_at(sp["x"], sp["z"]) + 0.5, sp["z"])
	velocity = Vector3.ZERO
	health = 100.0
	health_changed.emit(health)
	dead = false
	GameState.set_wanted(0)
	GameState.add_money(-mini(100, GameState.money))
	animator.set_state("normal")
	animator.play_action("get_up")


func _on_action_finished(_name: String) -> void:
	pass


# ---------------------------------------------------------------------------
# Vehicles & interactables
# ---------------------------------------------------------------------------
func _scan_nearby() -> void:
	var best: Node3D = null
	var bd := 4.0
	for v in get_tree().get_nodes_in_group("vehicles"):
		if not (v is Node3D):
			continue
		var d := global_position.distance_to(v.global_position)
		if v.has_method("get_door_position"):
			d = minf(d, global_position.distance_to(v.get_door_position()) * 0.8)
		if d < bd:
			bd = d
			best = v
	nearby_vehicle = best
	var bi: Node3D = null
	var bdi := 2.5
	for it in get_tree().get_nodes_in_group("interactable"):
		if it is Node3D:
			var d := global_position.distance_to(it.global_position)
			if d < bdi:
				bdi = d
				bi = it
	nearby_interactable = bi


func _door_pos(v: Node3D) -> Vector3:
	if v.has_method("get_door_position"):
		return v.get_door_position()
	return v.global_position - v.global_basis.x * 1.4


func _finish_enter() -> void:
	var v := _pending_vehicle
	_pending_vehicle = null
	if v == null or not is_instance_valid(v):
		_set_collision(true)
		return
	vehicle = v
	GameState.current_vehicle = v
	if v.has_method("set_driver"):
		v.set_driver(self)
	animator.set_state("drive")
	nearby_vehicle = null
	_follow_seat()


func _follow_seat() -> void:
	if not is_instance_valid(vehicle):
		vehicle = null
		GameState.current_vehicle = null
		_set_collision(true)
		animator.set_state("normal")
		return
	var seat: Transform3D
	if vehicle.has_method("get_seat_transform"):
		seat = vehicle.get_seat_transform()
	else:
		seat = vehicle.global_transform.translated_local(Vector3(-0.4, 0.5, 0))
	# seat transform marks the seat surface; hips sit 0.1 m above it
	var hips_h := 0.95 * model.scale.y
	global_transform = Transform3D(seat.basis.orthonormalized(), seat.origin - seat.basis.y.normalized() * (hips_h - 0.1))
	velocity = Vector3.ZERO
