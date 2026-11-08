class_name Ambience
extends Node
## Ambient soundscape (system "Audio"): crossfades city / mountain / village / river /
## wind / rain layers by the listener's context, plays thunder in storms and offers a
## pooled positional SFX helper for other modules:
##     Ambience.play_sfx("punch_hit", global_position)
##     Ambience.play_ui("ui_click")
##     var s := Ambience.get_stream("engine_loop")   # for own looping players (vehicles)

const SFX_DIR := "res://audio/sfx/"
const LAYERS := {
	"city": "city_ambience_loop",
	"birds": "birds_loop",
	"wind": "wind_loop",
	"rain": "rain_loop",
	"river": "river_loop",
}
const POOL_SIZE := 12

static var _instance: Ambience = null
static var _streams: Dictionary = {}

var is_idle := true
var _players: Dictionary = {}
var _target: Dictionary = {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_next := 0
var _ui_player: AudioStreamPlayer
var _ctx_timer := 0.0
var _thunder_timer := 8.0
var _river_pts := PackedVector3Array()
var _river_player: AudioStreamPlayer3D


static func get_stream(sfx_name: String) -> AudioStream:
	if not _streams.has(sfx_name):
		var path := SFX_DIR + sfx_name + ".wav"
		_streams[sfx_name] = load(path) if ResourceLoader.exists(path) else null
	return _streams[sfx_name]


static func play_sfx(sfx_name: String, pos: Vector3, volume_db := 0.0, pitch := 1.0) -> void:
	if _instance == null or not is_instance_valid(_instance):
		return
	_instance._play_at(sfx_name, pos, volume_db, pitch)


static func play_ui(sfx_name := "ui_click") -> void:
	if _instance == null or not is_instance_valid(_instance):
		return
	var s := get_stream(sfx_name)
	if s:
		_instance._ui_player.stream = s
		_instance._ui_player.play()


func _ready() -> void:
	_instance = self
	process_mode = Node.PROCESS_MODE_ALWAYS
	for k in LAYERS:
		var p := AudioStreamPlayer.new()
		p.name = "Amb_" + k
		p.stream = get_stream(LAYERS[k])
		p.volume_db = -80.0
		p.bus = "Master"
		add_child(p)
		p.play()
		_players[k] = p
		_target[k] = 0.0
	# river is positional: it sits at the closest river point
	_river_player = AudioStreamPlayer3D.new()
	_river_player.stream = get_stream("river_loop")
	_river_player.unit_size = 18.0
	_river_player.max_distance = 120.0
	_river_player.volume_db = 2.0
	add_child(_river_player)
	_river_player.play()
	_players["river"].stop()
	for i in POOL_SIZE:
		var q := AudioStreamPlayer3D.new()
		q.unit_size = 6.0
		q.max_distance = 80.0
		add_child(q)
		_pool.append(q)
	_ui_player = AudioStreamPlayer.new()
	_ui_player.volume_db = -6.0
	add_child(_ui_player)
	for r in WorldData.rivers:
		var pts: Array = r["pts"]
		for i in range(0, pts.size(), 4):
			_river_pts.append(Vector3(pts[i][0], pts[i][1], pts[i][2]))


func _exit_tree() -> void:
	if _instance == self:
		_instance = null


func _play_at(sfx_name: String, pos: Vector3, volume_db: float, pitch: float) -> void:
	var s := get_stream(sfx_name)
	if s == null:
		return
	var p := _pool[_pool_next]
	_pool_next = (_pool_next + 1) % _pool.size()
	p.stream = s
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.global_position = pos
	p.play()


func _process(delta: float) -> void:
	_ctx_timer -= delta
	if _ctx_timer <= 0.0:
		_ctx_timer = 0.5
		_update_context()
	for k in _players:
		var p: AudioStreamPlayer = _players[k]
		var lin := db_to_linear(p.volume_db) if p.volume_db > -79.0 else 0.0
		lin = move_toward(lin, _target[k], delta * 0.4)
		p.volume_db = linear_to_db(lin) if lin > 0.001 else -80.0
	if TimeWeather.weather == TimeWeather.Weather.STORM:
		_thunder_timer -= delta
		if _thunder_timer <= 0.0:
			_thunder_timer = randf_range(6.0, 18.0)
			var s := get_stream("thunder")
			if s:
				_ui_player.stream = s
				_ui_player.volume_db = randf_range(-8.0, 0.0)
				_ui_player.play()


func _update_context() -> void:
	var pos := GameState.view_position()
	var place := WorldData.place_name(pos.x, pos.z)
	var in_city := place.begins_with("Душанбе")
	var in_village := false
	for v in WorldData.world.get("villages", []):
		if Vector2(pos.x, pos.z).distance_to(Vector2(v["x"], v["z"])) < float(v["r"]) * 1.3:
			in_village = true
			break
	var ground := WorldData.height_at(pos.x, pos.z)
	var altitude := clampf((ground - 150.0) / 900.0, 0.0, 1.0)
	var night := TimeWeather.night_factor
	var rain := TimeWeather.rain
	_target["city"] = (0.55 if in_city else 0.0) * (1.0 - night * 0.4)
	var nature := 0.0 if in_city else (0.45 if in_village else 0.6)
	_target["birds"] = nature * (1.0 - night) * (1.0 - rain)
	_target["wind"] = clampf(0.08 + TimeWeather.wind * 0.35 + altitude * 0.35, 0.0, 0.8)
	_target["rain"] = clampf(rain * 0.9, 0.0, 0.9)
	_target["river"] = 0.0
	# nearest river point for the positional river loop
	var best := INF
	var bp := Vector3.ZERO
	for q in _river_pts:
		var d := (q.x - pos.x) * (q.x - pos.x) + (q.z - pos.z) * (q.z - pos.z)
		if d < best:
			best = d
			bp = q
	_river_player.global_position = bp + Vector3(0, 1.0, 0)
	_river_player.stream_paused = sqrt(best) > 140.0
