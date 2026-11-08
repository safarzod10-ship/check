class_name HumanoidAnims
extends RefCounted
## Procedural keyframed animations for HumanoidBuilder skeletons (AnimationLibrary "").
## Poses are dictionaries: bone -> Vector3 Euler degrees (YXZ), "hips" -> position offset, applied on
## top of identity rest rotations. See HumanoidBuilder for the axis conventions.
## Locomotion cycles all last 1.0 s and start with the LEFT foot forward so they can be cross-faded
## while preserving phase (HumanoidAnimator does that).

const SKEL := "Skeleton3D"
static var _lib: AnimationLibrary = null

## animation name -> loops?
const LOOPING := {"idle": true, "walk": true, "run": true, "sprint": true, "crouch_idle": true,
	"crouch_walk": true, "fall": true, "sit_drive": true, "wave": true, "talk": true, "swim": true}


static func library() -> AnimationLibrary:
	if _lib:
		return _lib
	var lib := AnimationLibrary.new()
	var defs := _definitions()
	for name in defs:
		lib.add_animation(name, _build(name, defs[name]))
	_lib = lib
	return lib


static func mirror(p: Dictionary) -> Dictionary:
	var out := {}
	for k in p:
		var nk: String = k
		if k.begins_with("Left"):
			nk = "Right" + k.substr(4)
		elif k.begins_with("Right"):
			nk = "Left" + k.substr(5)
		var val: Vector3 = p[k]
		if k == "hips":
			out[nk] = Vector3(-val.x, val.y, val.z)
		else:
			out[nk] = Vector3(val.x, -val.y, -val.z)
	return out


static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var o := a.duplicate()
	o.merge(b, true)
	return o


static func _build(name: String, keys: Array) -> Animation:
	# keys: [[time, pose], ...]
	var anim := Animation.new()
	var length: float = keys[keys.size() - 1][0]
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if LOOPING.has(name) else Animation.LOOP_NONE
	var bones := {}
	for k in keys:
		for b in k[1]:
			if b != "hips":
				bones[b] = true
	# always animate the main bones so blending from other animations resets them
	for b in ["Hips", "Spine", "Chest", "Neck", "Head", "LeftUpperArm", "LeftLowerArm", "RightUpperArm",
			"RightLowerArm", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot",
			"UpperChest", "LeftHand", "RightHand"]:
		bones[b] = true
	for b in bones:
		var t := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, NodePath("%s:%s" % [SKEL, b]))
		anim.track_set_interpolation_type(t, Animation.INTERPOLATION_CUBIC if LOOPING.has(name) else Animation.INTERPOLATION_LINEAR)
		for k in keys:
			var e: Vector3 = k[1].get(b, Vector3.ZERO)
			var q := Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)), EULER_ORDER_YXZ).get_rotation_quaternion()
			anim.rotation_track_insert_key(t, k[0], q)
	var pt := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pt, NodePath("%s:Hips" % SKEL))
	anim.track_set_interpolation_type(pt, Animation.INTERPOLATION_CUBIC if LOOPING.has(name) else Animation.INTERPOLATION_LINEAR)
	for k in keys:
		anim.position_track_insert_key(pt, k[0], Vector3(0, 0.95, 0) + k[1].get("hips", Vector3.ZERO))
	return anim


static func _definitions() -> Dictionary:
	var d := {}
	var arms_down := {"LeftUpperArm": Vector3(0, 0, -6), "RightUpperArm": Vector3(0, 0, 6),
		"LeftLowerArm": Vector3(8, 0, 0), "RightLowerArm": Vector3(8, 0, 0)}
	# ---------------- idle ----------------
	var i0 := merge(arms_down, {"Spine": Vector3(0, 0, 0), "Head": Vector3(-2, 0, 0)})
	var i1 := merge(arms_down, {"Chest": Vector3(2.5, 0, 0), "LeftUpperArm": Vector3(1, 0, -7),
		"RightUpperArm": Vector3(1, 0, 7), "Head": Vector3(-3, 4, 0), "hips": Vector3(0.008, 0.004, 0),
		"LeftUpperLeg": Vector3(0, 0, 1), "RightUpperLeg": Vector3(0, 0, 1)})
	d["idle"] = [[0.0, i0], [1.5, i1], [3.0, i0]]

	# ---------------- walk ----------------
	var wa := {"LeftUpperLeg": Vector3(26, 0, 0), "LeftLowerLeg": Vector3(-6, 0, 0), "LeftFoot": Vector3(12, 0, 0),
		"RightUpperLeg": Vector3(-20, 0, 0), "RightLowerLeg": Vector3(-16, 0, 0), "RightFoot": Vector3(-14, 0, 0),
		"LeftUpperArm": Vector3(-20, 0, -6), "LeftLowerArm": Vector3(14, 0, 0),
		"RightUpperArm": Vector3(22, 0, 6), "RightLowerArm": Vector3(26, 0, 0),
		"Spine": Vector3(-3, -4, 0), "Chest": Vector3(0, 7, 0), "Head": Vector3(0, -3, 0), "hips": Vector3(0, -0.025, 0)}
	var wb := {"LeftUpperLeg": Vector3(-2, 0, 0), "LeftLowerLeg": Vector3(-4, 0, 0), "LeftFoot": Vector3(2, 0, 0),
		"RightUpperLeg": Vector3(20, 0, 0), "RightLowerLeg": Vector3(-58, 0, 0), "RightFoot": Vector3(8, 0, 0),
		"LeftUpperArm": Vector3(0, 0, -6), "LeftLowerArm": Vector3(14, 0, 0),
		"RightUpperArm": Vector3(0, 0, 6), "RightLowerArm": Vector3(14, 0, 0),
		"Spine": Vector3(-3, 0, 0), "hips": Vector3(0.012, 0.02, 0)}
	d["walk"] = [[0.0, wa], [0.25, wb], [0.5, mirror(wa)], [0.75, mirror(wb)], [1.0, wa]]

	# ---------------- run ----------------
	var ra := {"LeftUpperLeg": Vector3(48, 0, 0), "LeftLowerLeg": Vector3(-22, 0, 0), "LeftFoot": Vector3(10, 0, 0),
		"RightUpperLeg": Vector3(-28, 0, 0), "RightLowerLeg": Vector3(-55, 0, 0), "RightFoot": Vector3(-25, 0, 0),
		"LeftUpperArm": Vector3(-42, 0, -10), "LeftLowerArm": Vector3(80, 0, 0),
		"RightUpperArm": Vector3(48, 0, 10), "RightLowerArm": Vector3(88, 0, 0),
		"Spine": Vector3(-12, -8, 0), "Chest": Vector3(0, 12, 0), "Neck": Vector3(7, 0, 0), "hips": Vector3(0, -0.05, 0)}
	var rb := {"LeftUpperLeg": Vector3(2, 0, 0), "LeftLowerLeg": Vector3(-25, 0, 0), "LeftFoot": Vector3(-8, 0, 0),
		"RightUpperLeg": Vector3(35, 0, 0), "RightLowerLeg": Vector3(-105, 0, 0), "RightFoot": Vector3(10, 0, 0),
		"LeftUpperArm": Vector3(0, 0, -10), "LeftLowerArm": Vector3(85, 0, 0),
		"RightUpperArm": Vector3(5, 0, 10), "RightLowerArm": Vector3(85, 0, 0),
		"Spine": Vector3(-12, 0, 0), "Neck": Vector3(7, 0, 0), "hips": Vector3(0, 0.05, 0)}
	d["run"] = [[0.0, ra], [0.25, rb], [0.5, mirror(ra)], [0.75, mirror(rb)], [1.0, ra]]

	# ---------------- sprint ----------------
	var sa := {"LeftUpperLeg": Vector3(62, 0, 0), "LeftLowerLeg": Vector3(-35, 0, 0), "LeftFoot": Vector3(5, 0, 0),
		"RightUpperLeg": Vector3(-35, 0, 0), "RightLowerLeg": Vector3(-70, 0, 0), "RightFoot": Vector3(-30, 0, 0),
		"LeftUpperArm": Vector3(-60, 0, -8), "LeftLowerArm": Vector3(90, 0, 0),
		"RightUpperArm": Vector3(68, 0, 8), "RightLowerArm": Vector3(95, 0, 0),
		"Spine": Vector3(-18, -10, 0), "Chest": Vector3(-2, 14, 0), "Neck": Vector3(12, 0, 0), "hips": Vector3(0, -0.07, 0)}
	var sb := {"LeftUpperLeg": Vector3(0, 0, 0), "LeftLowerLeg": Vector3(-30, 0, 0), "LeftFoot": Vector3(-10, 0, 0),
		"RightUpperLeg": Vector3(45, 0, 0), "RightLowerLeg": Vector3(-125, 0, 0), "RightFoot": Vector3(10, 0, 0),
		"LeftUpperArm": Vector3(0, 0, -8), "LeftLowerArm": Vector3(90, 0, 0),
		"RightUpperArm": Vector3(5, 0, 8), "RightLowerArm": Vector3(90, 0, 0),
		"Spine": Vector3(-18, 0, 0), "Neck": Vector3(12, 0, 0), "hips": Vector3(0, 0.06, 0)}
	d["sprint"] = [[0.0, sa], [0.25, sb], [0.5, mirror(sa)], [0.75, mirror(sb)], [1.0, sa]]

	# ---------------- crouch ----------------
	var ci := {"hips": Vector3(0, -0.37, 0.04), "Spine": Vector3(-24, 0, 0), "Chest": Vector3(-6, 0, 0),
		"Neck": Vector3(16, 0, 0), "Head": Vector3(10, 0, 0),
		"LeftUpperLeg": Vector3(72, 0, -5), "RightUpperLeg": Vector3(72, 0, 5),
		"LeftLowerLeg": Vector3(-112, 0, 0), "RightLowerLeg": Vector3(-112, 0, 0),
		"LeftFoot": Vector3(40, 0, 0), "RightFoot": Vector3(40, 0, 0),
		"LeftUpperArm": Vector3(22, 0, -10), "RightUpperArm": Vector3(22, 0, 10),
		"LeftLowerArm": Vector3(45, 0, 0), "RightLowerArm": Vector3(45, 0, 0)}
	var ci2 := merge(ci, {"Chest": Vector3(-4, 0, 0), "hips": Vector3(0, -0.365, 0.04)})
	d["crouch_idle"] = [[0.0, ci], [1.5, ci2], [3.0, ci]]
	var cwa := merge(ci, {"LeftUpperLeg": Vector3(90, 0, -5), "LeftLowerLeg": Vector3(-115, 0, 0), "LeftFoot": Vector3(30, 0, 0),
		"RightUpperLeg": Vector3(50, 0, 5), "RightLowerLeg": Vector3(-100, 0, 0), "RightFoot": Vector3(45, 0, 0),
		"LeftUpperArm": Vector3(10, 0, -10), "RightUpperArm": Vector3(32, 0, 10)})
	var cwb := merge(ci, {"LeftUpperLeg": Vector3(65, 0, -5), "RightUpperLeg": Vector3(80, 0, 5),
		"RightLowerLeg": Vector3(-130, 0, 0), "hips": Vector3(0, -0.34, 0.04)})
	d["crouch_walk"] = [[0.0, cwa], [0.25, cwb], [0.5, mirror(cwa)], [0.75, mirror(cwb)], [1.0, cwa]]

	# ---------------- air ----------------
	var j0 := {"LeftUpperLeg": Vector3(40, 0, 0), "RightUpperLeg": Vector3(40, 0, 0),
		"LeftLowerLeg": Vector3(-62, 0, 0), "RightLowerLeg": Vector3(-62, 0, 0),
		"LeftFoot": Vector3(25, 0, 0), "RightFoot": Vector3(25, 0, 0), "Spine": Vector3(-12, 0, 0),
		"LeftUpperArm": Vector3(-30, 0, -8), "RightUpperArm": Vector3(-30, 0, 8), "hips": Vector3(0, -0.17, 0)}
	var j1 := {"LeftUpperLeg": Vector3(-6, 0, 0), "RightUpperLeg": Vector3(4, 0, 0), "LeftFoot": Vector3(-30, 0, 0),
		"RightFoot": Vector3(-30, 0, 0), "LeftUpperArm": Vector3(110, 0, -15), "RightUpperArm": Vector3(110, 0, 15),
		"LeftLowerArm": Vector3(20, 0, 0), "RightLowerArm": Vector3(20, 0, 0), "hips": Vector3(0, 0.02, 0)}
	var j2 := {"LeftUpperLeg": Vector3(50, 0, -4), "RightUpperLeg": Vector3(30, 0, 4),
		"LeftLowerLeg": Vector3(-80, 0, 0), "RightLowerLeg": Vector3(-60, 0, 0),
		"LeftUpperArm": Vector3(55, 0, -25), "RightUpperArm": Vector3(55, 0, 25),
		"LeftLowerArm": Vector3(35, 0, 0), "RightLowerArm": Vector3(35, 0, 0), "Spine": Vector3(-5, 0, 0)}
	d["jump_up"] = [[0.0, j0], [0.15, j1], [0.45, j2]]
	var f0 := {"LeftUpperLeg": Vector3(25, 0, -5), "RightUpperLeg": Vector3(10, 0, 5),
		"LeftLowerLeg": Vector3(-40, 0, 0), "RightLowerLeg": Vector3(-25, 0, 0),
		"LeftUpperArm": Vector3(10, 0, -65), "RightUpperArm": Vector3(-5, 0, 60),
		"LeftLowerArm": Vector3(25, 0, 0), "RightLowerArm": Vector3(25, 0, 0), "Spine": Vector3(3, 0, 0)}
	d["fall"] = [[0.0, f0], [0.4, mirror(f0)], [0.8, f0]]
	var l0 := merge(ci, {"hips": Vector3(0, -0.28, 0.02), "Spine": Vector3(-18, 0, 0),
		"LeftUpperArm": Vector3(30, 0, -25), "RightUpperArm": Vector3(30, 0, 25)})
	d["land"] = [[0.0, l0], [0.35, i0]]

	# ---------------- combat ----------------
	var guard := {"LeftUpperArm": Vector3(42, 10, -14), "LeftLowerArm": Vector3(118, 0, 0),
		"RightUpperArm": Vector3(38, -10, 14), "RightLowerArm": Vector3(118, 0, 0),
		"Spine": Vector3(-7, 10, 0), "Head": Vector3(6, -8, 0),
		"LeftUpperLeg": Vector3(16, 0, -4), "RightUpperLeg": Vector3(-10, 0, 6),
		"LeftLowerLeg": Vector3(-18, 0, 0), "RightLowerLeg": Vector3(-14, 0, 0), "hips": Vector3(0, -0.05, 0)}
	d["guard"] = [[0.0, guard], [1.0, guard]]
	var pr := merge(guard, {"RightUpperArm": Vector3(88, 18, 6), "RightLowerArm": Vector3(6, 0, 0),
		"Chest": Vector3(0, 28, 0), "Spine": Vector3(-8, 14, 0), "RightUpperLeg": Vector3(-16, 0, 6),
		"hips": Vector3(0, -0.06, -0.06)})
	d["punch_r"] = [[0.0, guard], [0.16, pr], [0.26, pr], [0.5, guard]]
	var pl := merge(guard, {"LeftUpperArm": Vector3(88, -18, -6), "LeftLowerArm": Vector3(6, 0, 0),
		"Chest": Vector3(0, -24, 0), "Spine": Vector3(-8, -6, 0), "hips": Vector3(0, -0.06, -0.05)})
	d["punch_l"] = [[0.0, guard], [0.15, pl], [0.24, pl], [0.48, guard]]
	var k1 := merge(guard, {"RightUpperLeg": Vector3(85, 0, 4), "RightLowerLeg": Vector3(-95, 0, 0),
		"Spine": Vector3(6, 0, 0), "LeftUpperLeg": Vector3(-4, 0, -4), "LeftLowerLeg": Vector3(-8, 0, 0)})
	var k2 := merge(k1, {"RightUpperLeg": Vector3(88, 0, 4), "RightLowerLeg": Vector3(-6, 0, 0), "RightFoot": Vector3(-35, 0, 0),
		"Spine": Vector3(16, 0, 0), "Chest": Vector3(6, 0, 0)})
	d["kick"] = [[0.0, guard], [0.22, k1], [0.36, k2], [0.48, k2], [0.75, guard]]
	var hr := {"Spine": Vector3(18, -10, 0), "Neck": Vector3(14, 0, 0), "Head": Vector3(12, 8, 0),
		"LeftUpperArm": Vector3(-18, 0, -28), "RightUpperArm": Vector3(-14, 0, 26),
		"LeftLowerArm": Vector3(30, 0, 0), "RightLowerArm": Vector3(30, 0, 0),
		"LeftUpperLeg": Vector3(-8, 0, 0), "RightUpperLeg": Vector3(14, 0, 0), "RightLowerLeg": Vector3(-20, 0, 0),
		"hips": Vector3(0, -0.03, 0.06)}
	d["hit_react"] = [[0.0, i0], [0.1, hr], [0.45, i0]]
	var kd1 := {"Hips": Vector3(35, 0, 0), "hips": Vector3(0, -0.2, 0.3), "Spine": Vector3(10, 0, 0),
		"LeftUpperArm": Vector3(-30, 0, -40), "RightUpperArm": Vector3(-30, 0, 40),
		"LeftUpperLeg": Vector3(30, 0, 0), "RightUpperLeg": Vector3(10, 0, 0), "LeftLowerLeg": Vector3(-30, 0, 0)}
	var kd2 := {"Hips": Vector3(88, 0, 0), "hips": Vector3(0, -0.82, 0.62), "Spine": Vector3(2, 0, 0),
		"Head": Vector3(-8, 15, 0), "LeftUpperArm": Vector3(0, 0, -75), "RightUpperArm": Vector3(10, 0, 65),
		"LeftLowerArm": Vector3(20, 0, 0), "RightLowerArm": Vector3(10, 0, 0),
		"LeftUpperLeg": Vector3(8, 0, -8), "RightUpperLeg": Vector3(22, 0, 6), "RightLowerLeg": Vector3(-30, 0, 0)}
	d["knocked_down"] = [[0.0, i0], [0.25, kd1], [0.6, kd2], [1.2, kd2]]
	var gu1 := {"Hips": Vector3(55, 0, 0), "hips": Vector3(0, -0.68, 0.45), "Spine": Vector3(-35, 0, 0), "Chest": Vector3(-15, 0, 0),
		"LeftUpperArm": Vector3(-30, 0, -20), "RightUpperArm": Vector3(-30, 0, 20),
		"LeftUpperLeg": Vector3(40, 0, -8), "RightUpperLeg": Vector3(60, 0, 8),
		"LeftLowerLeg": Vector3(-40, 0, 0), "RightLowerLeg": Vector3(-100, 0, 0)}
	d["get_up"] = [[0.0, kd2], [0.5, gu1], [1.0, ci], [1.5, i0]]

	# ---------------- vehicles ----------------
	var sit := {"LeftUpperLeg": Vector3(84, 0, -6), "RightUpperLeg": Vector3(84, 0, 6),
		"LeftLowerLeg": Vector3(-78, 0, 0), "RightLowerLeg": Vector3(-78, 0, 0),
		"LeftFoot": Vector3(-5, 0, 0), "RightFoot": Vector3(-5, 0, 0), "Spine": Vector3(6, 0, 0),
		"LeftUpperArm": Vector3(48, 0, -10), "RightUpperArm": Vector3(48, 0, 10),
		"LeftLowerArm": Vector3(38, 0, 0), "RightLowerArm": Vector3(38, 0, 0), "Head": Vector3(-4, 0, 0)}
	var sit2 := merge(sit, {"Head": Vector3(-4, 6, 0), "Chest": Vector3(1.5, 0, 0)})
	d["sit_drive"] = [[0.0, sit], [1.5, sit2], [3.0, sit]]
	var ec := {"Spine": Vector3(-35, 0, 0), "Neck": Vector3(12, 0, 0), "hips": Vector3(0, -0.22, 0),
		"LeftUpperLeg": Vector3(40, 0, -5), "LeftLowerLeg": Vector3(-60, 0, 0),
		"RightUpperLeg": Vector3(70, 0, 8), "RightLowerLeg": Vector3(-70, 0, 0),
		"LeftUpperArm": Vector3(40, 0, -10), "RightUpperArm": Vector3(60, 0, 20), "RightLowerArm": Vector3(20, 0, 0)}
	d["enter_car"] = [[0.0, i0], [0.4, ec], [0.8, sit]]
	d["exit_car"] = [[0.0, sit], [0.4, ec], [0.8, i0]]

	# ---------------- interaction ----------------
	var it := merge(i0, {"RightUpperArm": Vector3(72, 0, 8), "RightLowerArm": Vector3(12, 0, 0),
		"Spine": Vector3(-20, 0, 0), "Head": Vector3(10, 0, 0), "hips": Vector3(0, -0.08, 0.02),
		"LeftUpperLeg": Vector3(20, 0, 0), "LeftLowerLeg": Vector3(-25, 0, 0)})
	d["interact"] = [[0.0, i0], [0.35, it], [0.55, it], [0.9, i0]]
	var pk := merge(ci, {"RightUpperArm": Vector3(60, 0, 8), "RightLowerArm": Vector3(10, 0, 0),
		"Spine": Vector3(-45, 0, 0)})
	d["pickup"] = [[0.0, i0], [0.45, pk], [0.65, pk], [1.1, i0]]
	var wv := merge(i0, {"RightUpperArm": Vector3(0, 0, 145), "RightLowerArm": Vector3(0, 0, 25), "Head": Vector3(0, -8, 0)})
	var wv2 := merge(wv, {"RightLowerArm": Vector3(0, 0, -20)})
	d["wave"] = [[0.0, wv], [0.3, wv2], [0.6, wv], [0.9, wv2], [1.2, wv]]
	var tk := merge(i0, {"RightUpperArm": Vector3(25, -10, 12), "RightLowerArm": Vector3(75, 0, 0),
		"LeftUpperArm": Vector3(8, 0, -8), "LeftLowerArm": Vector3(40, 0, 0), "Head": Vector3(-3, 6, 0)})
	var tk2 := merge(i0, {"RightUpperArm": Vector3(15, 0, 16), "RightLowerArm": Vector3(55, 0, 0),
		"LeftUpperArm": Vector3(22, 10, -14), "LeftLowerArm": Vector3(70, 0, 0), "Head": Vector3(4, -4, 0)})
	d["talk"] = [[0.0, tk], [0.8, tk2], [1.6, i0], [2.4, tk]]
	return d
