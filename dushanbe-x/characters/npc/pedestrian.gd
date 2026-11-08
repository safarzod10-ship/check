class_name Pedestrian
extends CharacterBody3D
## Ambient pedestrian. Moves kinematically along a road's sidewalk (or the edge of a village lane),
## idles, chats, occasionally crosses the road at intersections, reacts to hits and flees.
## No navmesh and no physics simulation: position is set directly every update (cheap).

enum S { WALK, IDLE, CHAT, CROSS, FLEE, DOWN, GETUP }

var appearance: Dictionary = {}
var road := -1            # index into WorldData.roads
var si := 0.0             # current (fractional) sample index along the road
var dir := 1              # +1 / -1 along the samples
var side := 1             # +1 right side of the road direction, -1 left
var speed := 1.3
var state := S.WALK
var manager: Node = null

var model: Node3D
var animator: HumanoidAnimator
var _timer := 0.0
var _flee_from := Vector3.ZERO
var _cross_t := 0.0
var _cross_from := Vector3.ZERO
var _cross_to := Vector3.ZERO
var _acc := 0.0
var _frame := 0
var _hits := 0
var _cur_speed := 0.0
var _avoid := 0.0
var _rng := RandomNumberGenerator.new()


func setup(p_road: int, p_index: int, p_side: int, p_dir: int, p_app: Dictionary, seed_v: int) -> void:
	road = p_road
	si = p_index
	side = p_side
	dir = p_dir
	appearance = p_app
	_rng.seed = seed_v


func _ready() -> void:
	add_to_group("pedestrians")
	collision_layer = 1 << (GameState.LAYER_NPC - 1)
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.28
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)
	model = HumanoidBuilder.create(appearance)
	add_child(model)
	animator = HumanoidAnimator.new()
	add_child(animator)
	animator.setup(model, true)
	speed = _rng.randf_range(1.05, 1.55)
	_timer = _rng.randf_range(6.0, 25.0)
	global_position = _path_point(si)
	_face(_path_point(si + dir * 2.0) - global_position)


func _road_pts() -> Array:
	return WorldData.roads[road]["pts"]


func _offset() -> float:
	var rt: Dictionary = WorldData.road_type(road)
	var sw: float = rt["sidewalk"]
	if sw > 0.0:
		return float(rt["half"]) + sw * 0.5
	return float(rt["half"]) + 0.9


func _path_point(f: float) -> Vector3:
	var pts := _road_pts()
	var i := clampi(int(f), 0, pts.size() - 1)
	var p := WorldData.road_point(road, i)
	var t := WorldData.road_tangent(road, i)
	var nrm := Vector3(-t.z, 0, t.x)      # right of the sample direction
	var q := p + nrm * (_offset() * side)
	var rt: Dictionary = WorldData.road_type(road)
	if float(rt["sidewalk"]) > 0.0:
		q.y = p.y + WorldData.ROAD_LIFT + 0.15
	else:
		q.y = WorldData.height_at(q.x, q.z)
	return q


func _face(v: Vector3) -> void:
	v.y = 0
	if v.length() > 0.01:
		rotation.y = lerp_angle(rotation.y, atan2(-v.x, -v.z), 0.35)


## Called by the manager with a distance-based frame skip.
func step(delta: float, dist_to_player: float) -> void:
	_frame += 1
	_acc += delta
	var skip := 1 if dist_to_player < 35.0 else (2 if dist_to_player < 70.0 else 4)
	if _frame % skip != 0:
		return
	var dt := _acc
	_acc = 0.0
	_update(dt)
	animator.tick(dt, _cur_speed, false, true, 0.0)


func _update(dt: float) -> void:
	_timer -= dt
	_cur_speed = 0.0
	match state:
		S.WALK, S.FLEE:
			var spd := speed * (3.2 if state == S.FLEE else 1.0)
			# keep away from the player
			var pl := GameState.player
			if pl and is_instance_valid(pl) and state == S.WALK:
				var to := pl.global_position - global_position
				to.y = 0
				if to.length() < 1.3 and (-global_basis.z).dot(to) > 0.0:
					_avoid = 1.0
			_avoid = maxf(0.0, _avoid - dt)
			var step_len := spd * dt / 4.0     # road samples are 4 m apart
			si += step_len * dir
			var n: int = _road_pts().size()
			if si <= 1.0 or si >= n - 2:
				si = clampf(si, 1.0, n - 2.0)
				dir = -dir
			var target := _path_point(si)
			if _avoid > 0.0:
				var t := WorldData.road_tangent(road, int(si))
				target += Vector3(-t.z, 0, t.x) * side * 0.9 * _avoid
			var mv := target - global_position
			_face(mv)
			global_position = target
			_cur_speed = spd
			if state == S.FLEE and _timer <= 0.0:
				state = S.WALK
				_timer = _rng.randf_range(10.0, 30.0)
			elif state == S.WALK and _timer <= 0.0:
				_pick_activity()
			elif state == S.WALK and _at_gap() and _rng.randf() < 0.02:
				_start_cross()
		S.IDLE:
			if _timer <= 0.0:
				state = S.WALK
				_timer = _rng.randf_range(8.0, 30.0)
		S.CHAT:
			if _timer <= 0.0:
				state = S.WALK
				_timer = _rng.randf_range(10.0, 30.0)
		S.CROSS:
			_cross_t += dt * speed / maxf(_cross_from.distance_to(_cross_to), 0.1)
			var p := _cross_from.lerp(_cross_to, clampf(_cross_t, 0.0, 1.0))
			p.y = maxf(_cross_from.y, _cross_to.y) - 0.15 if _cross_t > 0.15 and _cross_t < 0.85 else p.y
			_face(_cross_to - _cross_from)
			global_position = p
			_cur_speed = speed
			if _cross_t >= 1.0:
				side = -side
				dir = -dir
				state = S.WALK
				_timer = _rng.randf_range(8.0, 25.0)
		S.DOWN:
			if _timer <= 0.0:
				state = S.GETUP
				animator.set_state("normal")
				_timer = animator.play_action("get_up")
		S.GETUP:
			if _timer <= 0.0:
				_flee(_flee_from)


func _at_gap() -> bool:
	var f := WorldData.sample_flags(road)
	var i := clampi(int(si), 0, f.size() - 1)
	return (f[i] & 4) != 0


func _pick_activity() -> void:
	var r := _rng.randf()
	if r < 0.35:
		state = S.IDLE
		_timer = _rng.randf_range(3.0, 9.0)
		_cur_speed = 0.0
	elif r < 0.6:
		# chat with someone nearby, else just stand and talk on the phone
		state = S.CHAT
		_timer = _rng.randf_range(6.0, 14.0)
		var other := _closest_ped(6.0)
		if other:
			_face(other.global_position - global_position)
		animator.play_action("talk")
	else:
		_timer = _rng.randf_range(10.0, 30.0)


func _start_cross() -> void:
	state = S.CROSS
	_cross_t = 0.0
	_cross_from = global_position
	side = -side
	_cross_to = _path_point(si)
	side = -side


func _closest_ped(r: float) -> Node3D:
	var best: Node3D = null
	var bd := r
	if manager and "peds" in manager:
		for p in manager.peds:
			if p != self and is_instance_valid(p):
				var d := global_position.distance_to(p.global_position)
				if d < bd:
					bd = d
					best = p
	return best


func take_hit(from: Vector3, force: float) -> void:
	if state == S.DOWN:
		return
	_hits += 1
	_flee_from = from
	var away := global_position - from
	away.y = 0
	if force > 2.0 or _hits >= 2:
		state = S.DOWN
		animator.set_state("down")
		_timer = _rng.randf_range(3.0, 5.0) + force * 0.2
		rotation.y = atan2(away.x, away.z)   # fall backwards, away from the attacker
		global_position += away.normalized() * minf(force * 0.15, 2.0)
		collision_layer = 0
		get_tree().create_timer(_timer + 1.6).timeout.connect(func(): if is_instance_valid(self): collision_layer = 1 << (GameState.LAYER_NPC - 1))
	else:
		animator.play_action("hit_react")
		_flee(from)
	if manager and manager.has_method("alarm"):
		manager.alarm(global_position, from, self)


func _flee(from: Vector3) -> void:
	if state == S.DOWN:
		return
	_flee_from = from
	state = S.FLEE
	_timer = _rng.randf_range(8.0, 14.0)
	animator.cancel_action()
	var t := WorldData.road_tangent(road, int(si))
	var away := global_position - from
	dir = 1 if t.dot(away) >= 0.0 else -1


func alarm(from: Vector3) -> void:
	if state in [S.WALK, S.IDLE, S.CHAT, S.CROSS]:
		if state == S.CROSS:
			global_position = _cross_to
			side = -side
		_flee(from)
