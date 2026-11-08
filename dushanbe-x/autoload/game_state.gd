extends Node
## Runtime game state shared between systems (player, vehicle, wanted level, money).

signal wanted_changed(level: int)
signal money_changed(amount: int)
signal notify(text: String)

var player: Node3D = null
var camera: Camera3D = null
var current_vehicle: Node3D = null
var money := 500
var wanted := 0
var _wanted_decay := 0.0
var screenshot_mode := false
## Camera look input accumulated by touch drag / mouse (pixels). The camera rig consumes and resets it.
var look_delta := Vector2.ZERO

## Collision layers (bit numbers, 1-based as in the editor)
const LAYER_WORLD := 1        # terrain, roads, buildings, landmarks
const LAYER_PLAYER := 2
const LAYER_VEHICLE := 3
const LAYER_NPC := 4
const LAYER_PROP := 5


func focus_position() -> Vector3:
	if current_vehicle and is_instance_valid(current_vehicle):
		return current_vehicle.global_position
	if player and is_instance_valid(player):
		return player.global_position
	if camera:
		return camera.global_position
	return Vector3.ZERO


func view_position() -> Vector3:
	if camera and is_instance_valid(camera):
		return camera.global_position
	return focus_position()


func add_crime(points: int) -> void:
	set_wanted(mini(5, wanted + points))
	_wanted_decay = 45.0


func set_wanted(v: int) -> void:
	if v > wanted:
		_wanted_decay = 45.0
	if v != wanted:
		wanted = v
		wanted_changed.emit(wanted)


func add_money(v: int) -> void:
	money += v
	money_changed.emit(money)


func message(t: String) -> void:
	notify.emit(t)


func _process(delta: float) -> void:
	if wanted > 0:
		_wanted_decay -= delta
		if _wanted_decay <= 0.0:
			set_wanted(wanted - 1)
			_wanted_decay = 30.0
	if player:
		RenderingServer.global_shader_parameter_set("player_pos", focus_position())
