class_name PedestrianManager
extends Node3D
## System "Pedestrians": keeps a pool of ambient pedestrians around the player on sidewalks of city
## streets and along village lanes. Count scales with GameSettings "pedestrian_density".

const SPAWN_MIN := 35.0
const SPAWN_MAX := 110.0
const DESPAWN := 150.0
const BASE_COUNT := 25

var peds: Array = []
var is_idle := true
var _timer := 0.0
var _rng := RandomNumberGenerator.new()
var _seed := 1


func _ready() -> void:
	_rng.randomize()


func max_count() -> int:
	return int(BASE_COUNT * float(GameSettings.get_v("pedestrian_density", 1.0)))


func _process(delta: float) -> void:
	var focus := GameState.focus_position()
	var cam := GameState.view_position()
	for p in peds:
		if is_instance_valid(p):
			p.step(delta, cam.distance_to(p.global_position))
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = 0.4
	if GameState.screenshot_mode or GameState.player == null:
		return
	# despawn
	for i in range(peds.size() - 1, -1, -1):
		var p = peds[i]
		if not is_instance_valid(p):
			peds.remove_at(i)
		elif p.global_position.distance_to(focus) > DESPAWN:
			p.queue_free()
			peds.remove_at(i)
	# spawn a couple per tick (spreads mesh building over frames)
	var want := max_count()
	# fewer pedestrians while driving fast (they would be out of range quickly)
	if GameState.current_vehicle:
		want = int(want * 0.6)
	for _k in 2:
		if peds.size() >= want:
			break
		_try_spawn(focus)


func _try_spawn(focus: Vector3) -> void:
	var ang := _rng.randf() * TAU
	var r := _rng.randf_range(SPAWN_MIN, SPAWN_MAX)
	var p := focus + Vector3(cos(ang), 0, sin(ang)) * r
	var nr := WorldData.nearest_road(p.x, p.z, 60.0)
	if nr.is_empty():
		return
	var ri: int = nr["road"]
	var road: Dictionary = WorldData.roads[ri]
	var rt: Dictionary = WorldData.road_type(ri)
	var walkable: bool = float(rt["sidewalk"]) > 0.0 or road.has("village") or road["type"] in ["rural", "dirt"]
	if not walkable:
		return
	var flags := WorldData.sample_flags(ri)
	var idx: int = nr["index"]
	if (flags[idx] & 2) != 0:   # no pedestrians in tunnels
		return
	var n: int = road["pts"].size()
	if n < 6:
		return
	idx = clampi(idx, 2, n - 3)
	var ped := Pedestrian.new()
	_seed += 1
	var app := HumanoidBuilder.random_appearance(_rng)
	ped.setup(ri, idx, 1 if _rng.randf() < 0.5 else -1, 1 if _rng.randf() < 0.5 else -1, app, _seed + _rng.randi())
	ped.manager = self
	add_child(ped)
	peds.append(ped)


## A pedestrian was attacked: people nearby flee.
func alarm(where: Vector3, from: Vector3, victim: Node) -> void:
	for p in peds:
		if is_instance_valid(p) and p != victim and p.global_position.distance_to(where) < 18.0:
			p.alarm(from)
