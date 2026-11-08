class_name GameEvents
extends Node3D
## Gameplay layer on top of the world:
##  * services at POIs: gas stations (refuel/repair), shops, markets, cafes, chaikhanas (food heals)
##  * delivery jobs between landmarks / villages with a 3D beacon and a money reward
##  * random city events: wedding convoys, police patrols, market days, traffic news
##  * landmark discovery bonus

const SERVICE_RADIUS := 16.0
const SERVICES := {
	"gas_station": {"text": "Заправка: ДЕЙСТВИЕ — заправить и починить (30 смн)", "cost": 30, "heal": 0.0, "car": true},
	"shop": {"text": "Магазин: ДЕЙСТВИЕ — купить воду и лепёшку (8 смн)", "cost": 8, "heal": 25.0, "car": false},
	"market": {"text": "Бозор: ДЕЙСТВИЕ — купить фрукты (12 смн)", "cost": 12, "heal": 40.0, "car": false},
	"cafe": {"text": "Кафе: ДЕЙСТВИЕ — пообедать (20 смн)", "cost": 20, "heal": 60.0, "car": false},
	"chaikhana": {"text": "Чайхана: ДЕЙСТВИЕ — чай и плов (25 смн)", "cost": 25, "heal": 100.0, "car": false},
	"restaurant": {"text": "Ресторан: ДЕЙСТВИЕ — ужин (35 смн)", "cost": 35, "heal": 100.0, "car": false},
}
const NEWS := [
	"Радио Душанбе: на проспекте Рудаки плотное движение.",
	"Сегодня на рынке Мехргон свежие абрикосы и дыни.",
	"В Варзобском ущелье прохладно — отличная погода для отдыха.",
	"Перевал над Сафеди Варзоб: возможен туман на серпантине.",
	"В Гиссаре начался сбор хлопка.",
	"Вечером в парке Рудаки работают фонтаны.",
]

var is_idle := true
var _near_service: Dictionary = {}
var _prompt_cd := 0.0
var _job: Dictionary = {}
var _beacon: MeshInstance3D
var _event_timer := 90.0
var _job_timer := 40.0
var _discovered: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_beacon = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.0
	cyl.bottom_radius = 3.0
	cyl.height = 400.0
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(1.0, 0.8, 0.1, 0.35)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	cyl.material = m
	_beacon.mesh = cyl
	_beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beacon.visible = false
	add_child(_beacon)


func _process(delta: float) -> void:
	if GameState.screenshot_mode or GameState.player == null:
		return
	var pos := GameState.focus_position()
	_services(pos, delta)
	_discovery(pos)
	_jobs(pos, delta)
	_random_events(pos, delta)


func _services(pos: Vector3, delta: float) -> void:
	_prompt_cd -= delta
	var best := {}
	var bd := SERVICE_RADIUS
	for p in WorldData.pois:
		if not SERVICES.has(p["type"]):
			continue
		var d := Vector2(pos.x, pos.z).distance_to(Vector2(p["x"], p["z"]))
		var r := SERVICE_RADIUS * (2.0 if p["type"] == "gas_station" else 1.0)
		if d < r and d < bd + (r - SERVICE_RADIUS):
			bd = d
			best = p
	if best.is_empty():
		_near_service = {}
		return
	var svc: Dictionary = SERVICES[best["type"]]
	if _near_service != best:
		_near_service = best
		_prompt_cd = 0.0
	if _prompt_cd <= 0.0:
		GameState.message(svc["text"])
		_prompt_cd = 12.0
	if Input.is_action_just_pressed("interact"):
		if GameState.money < int(svc["cost"]):
			GameState.message("Недостаточно денег.")
			return
		GameState.add_money(-int(svc["cost"]))
		if svc["car"]:
			GameState.message("Бак полный, машина отремонтирована. Роҳи сафед!")
		else:
			var pl := GameState.player
			if pl and pl.has_method("heal"):
				pl.heal(float(svc["heal"]))
			GameState.message("Нуши ҷон! Здоровье восстановлено.")


func _discovery(pos: Vector3) -> void:
	var lm := WorldData.nearest_landmark(pos.x, pos.z, 110.0)
	if lm.is_empty() or _discovered.has(lm["id"]):
		return
	_discovered[lm["id"]] = true
	GameState.add_money(25)
	GameState.message("Открыто место: %s  (+25 смн)" % lm["name"])


func _jobs(pos: Vector3, delta: float) -> void:
	if _job.is_empty():
		_job_timer -= delta
		if _job_timer <= 0.0:
			_offer_job(pos)
		return
	var target: Vector3 = _job["target"]
	_beacon.visible = true
	_beacon.global_position = target + Vector3(0, 200.0, 0)
	var d := Vector2(pos.x, pos.z).distance_to(Vector2(target.x, target.z))
	_job["time"] -= delta
	if d < 25.0:
		GameState.add_money(int(_job["reward"]))
		GameState.message("Доставка выполнена: +%d смн" % int(_job["reward"]))
		_end_job()
	elif _job["time"] <= 0.0:
		GameState.message("Время доставки истекло.")
		_end_job()


func _offer_job(pos: Vector3) -> void:
	var dests: Array = []
	for lm in WorldData.landmarks:
		dests.append([lm["name"], Vector3(lm["x"], lm["y"], lm["z"])])
	for v in WorldData.world["villages"]:
		dests.append(["кишлак " + str(v["name"]), Vector3(v["x"], WorldData.height_at(v["x"], v["z"]), v["z"])])
	dests.shuffle()
	for dd in dests:
		var dist := Vector2(pos.x, pos.z).distance_to(Vector2(dd[1].x, dd[1].z))
		if dist > 800.0 and dist < 5000.0:
			var nr := WorldData.nearest_road(dd[1].x, dd[1].z, 200.0)
			var tgt: Vector3 = nr["pos"] if not nr.is_empty() else dd[1]
			_job = {"name": dd[0], "target": tgt, "reward": int(30 + dist * 0.03), "time": 120.0 + dist * 0.12}
			GameState.message("Заказ: доставьте посылку — %s (%.1f км, награда %d смн). Следуйте к жёлтому лучу." % [dd[0], dist / 1000.0, _job["reward"]])
			return
	_job_timer = 30.0


func _end_job() -> void:
	_job = {}
	_beacon.visible = false
	_job_timer = _rng.randf_range(45.0, 120.0)


func _random_events(pos: Vector3, delta: float) -> void:
	_event_timer -= delta
	if _event_timer > 0.0:
		return
	_event_timer = _rng.randf_range(90.0, 200.0)
	var r := _rng.randf()
	var traffic := get_parent().get_node_or_null("Traffic")
	if r < 0.3 and traffic and traffic.has_method("spawn_on"):
		# wedding convoy: a few decorated cars honking along the nearest big road
		var nr := WorldData.nearest_road(pos.x, pos.z, 300.0)
		if not nr.is_empty():
			var types := ["sedan", "suv", "sedan", "minibus"]
			for k in 4:
				var car = traffic.spawn_on(nr["road"], maxi(0, int(nr["index"]) - 40 - k * 6), 1, 0, types[k])
				if car:
					car.set_meta("wedding", true)
			GameState.message("Свадебный кортеж! Слышите клаксоны?")
			return
	if r < 0.5 and traffic and traffic.has_method("spawn_on"):
		var nr2 := WorldData.nearest_road(pos.x, pos.z, 300.0)
		if not nr2.is_empty():
			traffic.spawn_on(nr2["road"], maxi(0, int(nr2["index"]) - 50), 1, 0, "police")
			GameState.message("Патруль милиции на дороге.")
			return
	GameState.message(NEWS[_rng.randi() % NEWS.size()])
