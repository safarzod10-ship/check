class_name HumanoidAnimator
extends Node
## Drives an AnimationPlayer for a HumanoidBuilder model: speed-based locomotion with phase-preserving
## cross-fades, one-shot actions (punch, kick, enter_car ...) and persistent states (down, drive).
## Call tick(delta) every frame (or less often for far NPCs: the player is in manual process mode).

signal action_finished(name: String)

const LOCO_REF := {"walk": 1.5, "run": 3.0, "sprint": 4.0, "crouch_walk": 1.2}

var ap: AnimationPlayer
var state := "normal"         # normal | down | drive
var _action := ""
var _action_left := 0.0
var _current := ""
var manual := false


func setup(model: Node3D, manual_process := false) -> void:
	ap = AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	model.add_child(ap)
	ap.root_node = NodePath("..")
	ap.add_animation_library("", HumanoidAnims.library())
	manual = manual_process
	if manual:
		ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_play("idle", 0.0)


func _play(name: String, blend := 0.2, keep_phase := false, speed := 1.0) -> void:
	if name == _current:
		ap.speed_scale = speed
		return
	var phase := 0.0
	if keep_phase and _current != "" and ap.has_animation(_current) and ap.current_animation != "":
		var ol := ap.get_animation(_current).length
		phase = fposmod(ap.current_animation_position, ol) / ol
	ap.play(name, blend)
	ap.speed_scale = speed
	if keep_phase:
		ap.seek(phase * ap.get_animation(name).length, false)
	_current = name


func is_busy() -> bool:
	return _action != ""


func current_action() -> String:
	return _action


## Plays a one-shot animation; returns its duration in seconds.
func play_action(name: String, speed := 1.0, blend := 0.12) -> float:
	if not ap.has_animation(name):
		return 0.0
	_action = name
	_current = ""
	ap.play(name, blend)
	ap.speed_scale = speed
	ap.seek(0.0, false)
	_current = name
	_action_left = ap.get_animation(name).length / speed
	return _action_left


func cancel_action() -> void:
	_action = ""
	_action_left = 0.0


func set_state(s: String) -> void:
	if s == state:
		return
	state = s
	cancel_action()
	match s:
		"down":
			_play("knocked_down", 0.1)
		"drive":
			_play("sit_drive", 0.25)


## speed in m/s (horizontal), crouch flag, on floor, vertical velocity
func tick(delta: float, speed := 0.0, crouch := false, on_floor := true, vy := 0.0) -> void:
	if _action != "":
		_action_left -= delta
		if _action_left <= 0.0:
			var fin := _action
			_action = ""
			action_finished.emit(fin)
	if _action == "" and state == "normal":
		if not on_floor and vy < -2.5:
			_play("fall", 0.3)
		elif not on_floor and vy > 0.5:
			pass   # keep jump_up action / current
		elif crouch:
			if speed < 0.2:
				_play("crouch_idle", 0.25)
			else:
				_play("crouch_walk", 0.2, true, clampf(speed / LOCO_REF["crouch_walk"], 0.4, 2.0))
		elif speed < 0.15:
			_play("idle", 0.3)
		elif speed < 2.4:
			_play("walk", 0.25, true, clampf(speed / LOCO_REF["walk"], 0.5, 1.8))
		elif speed < 5.4:
			_play("run", 0.25, true, clampf(speed / LOCO_REF["run"], 0.8, 1.8))
		else:
			_play("sprint", 0.25, true, clampf(speed / LOCO_REF["sprint"], 1.0, 2.0))
	if manual:
		ap.advance(delta)
