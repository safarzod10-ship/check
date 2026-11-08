class_name CarFactory
extends RefCounted
## Procedural vehicle models (original generic designs, no real brands).
## Local frame: forward = +Z (VehicleBody3D convention), up = +Y, left = +X, right = -X.
## y = 0 is the ground under the car when the suspension is at rest.
##
## build(type, color) -> Dictionary:
##   body: ArrayMesh (paint, glass, trim, interior, headlamps)
##   brake: ArrayMesh (tail / brake lamps, separate so the material can be switched)
##   siren_red / siren_blue: ArrayMesh (police only)
##   wheel: ArrayMesh (centred, axle along X)
##   wheels: Array[Vector3] wheel centres, steer: Array[bool], drive: Array[bool]
##   wheel_radius, length, width, height, mass, seat (Vector3), door (Vector3), max_kmh
##   shapes: Array of [center: Vector3, size: Vector3] collision boxes

const TYPES := ["sedan", "hatchback", "suv", "taxi", "minibus", "bus", "police", "truck", "old_sedan"]

const PAINTS := [
	Color(0.85, 0.85, 0.86), Color(0.08, 0.08, 0.09), Color(0.62, 0.64, 0.67), Color(0.55, 0.06, 0.07),
	Color(0.07, 0.17, 0.42), Color(0.92, 0.92, 0.9), Color(0.1, 0.3, 0.18), Color(0.38, 0.38, 0.4),
	Color(0.7, 0.55, 0.3), Color(0.25, 0.45, 0.65), Color(0.95, 0.95, 0.95), Color(0.45, 0.12, 0.2),
]

static var _cache: Dictionary = {}
static var _wheel_cache: Dictionary = {}
static var _mats: Dictionary = {}


static func random_paint(rng: RandomNumberGenerator = null) -> Color:
	var i := (rng.randi() if rng else randi()) % PAINTS.size()
	return PAINTS[i]


static func default_color(type: String) -> Color:
	match type:
		"taxi":
			return Color(0.96, 0.78, 0.08)
		"police":
			return Color(0.95, 0.95, 0.96)
		"bus":
			return Color(0.15, 0.45, 0.75)
		"minibus":
			return Color(0.95, 0.95, 0.92)
		"truck":
			return Color(0.2, 0.32, 0.6)
	return PAINTS[0]


static func material(name: String) -> Material:
	if _mats.has(name):
		return _mats[name]
	var m: Material
	match name:
		"paint":
			var s := StandardMaterial3D.new()
			s.vertex_color_use_as_albedo = true
			s.vertex_color_is_srgb = true
			s.roughness = 0.28
			s.metallic = 0.35
			s.metallic_specular = 0.7
			m = s
		"headlamp":
			var sh := ShaderMaterial.new()
			sh.shader = load("res://util/shaders/lamp.gdshader")
			sh.set_shader_parameter("strength", 4.0)
			m = sh
		"brake_off":
			var sh := ShaderMaterial.new()
			sh.shader = load("res://util/shaders/lamp.gdshader")
			sh.set_shader_parameter("strength", 2.5)
			m = sh
		"brake_on":
			var sh := ShaderMaterial.new()
			sh.shader = load("res://util/shaders/lamp.gdshader")
			sh.set_shader_parameter("always_on", true)
			sh.set_shader_parameter("strength", 7.0)
			m = sh
		"siren_on":
			var sh := ShaderMaterial.new()
			sh.shader = load("res://util/shaders/lamp.gdshader")
			sh.set_shader_parameter("always_on", true)
			sh.set_shader_parameter("strength", 9.0)
			m = sh
		"siren_off":
			var s := StandardMaterial3D.new()
			s.vertex_color_use_as_albedo = true
			s.roughness = 0.3
			s.albedo_color = Color(0.35, 0.35, 0.35)
			m = s
		_:
			m = Mats.get_mat(name)
	_mats[name] = m
	return m


static func spec(type: String) -> Dictionary:
	# top: side profile (z, y) from front to rear of the lower body (above the arches)
	# cabin: glass house profile (z, y), counter clockwise not required
	match type:
		"hatchback":
			return {"L": 3.95, "W": 1.72, "clr": 0.24, "r": 0.31, "wf": 1.28, "wr": -1.22, "mass": 1050.0, "max": 160.0,
				"top": [[1.97, 0.5], [1.97, 0.72], [1.75, 0.86], [0.75, 0.96], [-1.75, 0.98], [-1.97, 0.95], [-1.97, 0.5]],
				"cabin": [[0.75, 0.96], [-0.05, 1.42], [-1.55, 1.44], [-1.9, 0.98]], "tumble": 0.17,
				"seat_z": -0.15, "drive": "front"}
		"suv":
			return {"L": 4.65, "W": 1.9, "clr": 0.36, "r": 0.38, "wf": 1.45, "wr": -1.38, "mass": 1800.0, "max": 165.0,
				"top": [[2.32, 0.62], [2.32, 0.98], [2.05, 1.12], [0.95, 1.2], [-2.15, 1.22], [-2.32, 1.15], [-2.32, 0.62]],
				"cabin": [[0.95, 1.2], [0.1, 1.78], [-2.0, 1.8], [-2.25, 1.22]], "tumble": 0.16,
				"seat_z": -0.05, "drive": "all"}
		"minibus":
			return {"L": 5.5, "W": 1.98, "clr": 0.3, "r": 0.36, "wf": 1.75, "wr": -1.85, "mass": 2400.0, "max": 120.0,
				"top": [[2.75, 0.55], [2.75, 0.95], [2.35, 1.15], [1.95, 1.2], [-2.75, 1.25], [-2.75, 0.55]],
				"cabin": [[1.95, 1.2], [1.35, 2.2], [-2.7, 2.25], [-2.75, 1.25]], "tumble": 0.08,
				"seat_z": 1.35, "drive": "rear", "pillars": 5}
		"bus":
			return {"L": 11.0, "W": 2.5, "clr": 0.32, "r": 0.5, "wf": 3.6, "wr": -2.6, "mass": 9500.0, "max": 85.0,
				"top": [[5.5, 0.6], [5.5, 1.1], [5.42, 1.2], [-5.5, 1.2], [-5.5, 0.6]],
				"cabin": [[5.42, 1.2], [5.35, 2.75], [-5.45, 2.75], [-5.5, 1.2]], "tumble": 0.03,
				"seat_z": 4.6, "drive": "rear", "pillars": 9, "roof_h": 0.35}
		"truck":
			return {"L": 5.9, "W": 2.05, "clr": 0.38, "r": 0.42, "wf": 1.95, "wr": -1.85, "mass": 3800.0, "max": 100.0,
				"top": [[2.95, 0.62], [2.95, 1.15], [2.8, 1.25], [1.25, 1.3], [1.25, 1.0], [-2.95, 1.0], [-2.95, 0.62]],
				"cabin": [[2.8, 1.25], [2.55, 2.25], [1.3, 2.3], [1.25, 1.3]], "tumble": 0.06,
				"seat_z": 1.95, "drive": "rear", "cargo": true}
		"old_sedan":
			return {"L": 4.15, "W": 1.62, "clr": 0.26, "r": 0.31, "wf": 1.25, "wr": -1.2, "mass": 1050.0, "max": 140.0,
				"top": [[2.07, 0.5], [2.07, 0.8], [2.0, 0.86], [0.8, 0.9], [-1.25, 0.9], [-2.0, 0.88], [-2.07, 0.8], [-2.07, 0.5]],
				"cabin": [[0.8, 0.9], [0.25, 1.38], [-0.85, 1.38], [-1.25, 0.9]], "tumble": 0.12,
				"seat_z": -0.25, "drive": "rear"}
	# sedan, taxi, police
	return {"L": 4.55, "W": 1.8, "clr": 0.26, "r": 0.32, "wf": 1.38, "wr": -1.32, "mass": 1300.0, "max": 185.0,
		"top": [[2.27, 0.48], [2.27, 0.74], [2.05, 0.86], [0.95, 0.98], [-1.55, 1.0], [-2.2, 0.98], [-2.27, 0.9], [-2.27, 0.48]],
		"cabin": [[0.95, 0.98], [0.1, 1.44], [-0.95, 1.45], [-1.6, 1.0]], "tumble": 0.18,
		"seat_z": -0.2, "drive": "rear"}


static func build(type: String, color := Color(0, 0, 0, 0)) -> Dictionary:
	if color.a == 0.0:
		color = default_color(type)
	var key := "%s_%s" % [type, color.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var sp := spec(type)
	var k := MeshKit.new()
	var kb := MeshKit.new()
	var kr := MeshKit.new()
	var kblu := MeshKit.new()
	var L: float = sp["L"]
	var W: float = sp["W"]
	var hw := W * 0.5
	var r: float = sp["r"]
	var clr: float = sp["clr"]
	var wf: float = sp["wf"]
	var wr: float = sp["wr"]
	var trim := Color(0.06, 0.06, 0.07)
	var chrome := Color(0.75, 0.76, 0.78)
	var paint := color

	# ---- lower body: side profile with wheel arches, extruded across the width
	var prof := PackedVector2Array()
	for p in sp["top"]:
		prof.append(Vector2(p[0], p[1]))
	var rear_z: float = sp["top"][sp["top"].size() - 1][0]
	var front_z: float = sp["top"][0][0]
	var arch := r + 0.07
	var bottom: Array = []   # rear -> front along the bottom
	bottom.append(Vector2(rear_z + 0.06, clr))
	for wz in [wr, wf]:
		bottom.append(Vector2(wz - arch, clr))
		for a in range(0, 9):
			var ang := PI - PI * a / 8.0
			bottom.append(Vector2(wz + cos(ang) * arch, maxf(clr, r + 0.02 + sin(ang) * arch * 0.98)))
		bottom.append(Vector2(wz + arch, clr))
	bottom.append(Vector2(front_z - 0.06, clr))
	for b in bottom:
		prof.append(b)
	var arch_flags: Array = []
	for i in prof.size():
		var pz := prof[i].x
		var py := prof[i].y
		arch_flags.append(py > clr + 0.01 and i >= sp["top"].size() and (absf(pz - wf) <= arch + 0.01 or absf(pz - wr) <= arch + 0.01))
	_extrude(k, "paint", prof, func(_y): return hw, paint, arch_flags, trim)

	# ---- cabin (glass) with tumblehome, then pillars and roof in body colour
	var cab := PackedVector2Array()
	for p in sp["cabin"]:
		cab.append(Vector2(p[0], p[1]))
	var y0: float = sp["cabin"][0][1]
	var y1: float = sp["cabin"][1][1]
	var tumble: float = sp["tumble"]
	var cab_hw := func(y: float) -> float: return hw - 0.04 - tumble * clampf((y - y0) / maxf(y1 - y0, 0.01), 0.0, 1.0)
	_extrude(k, "glass", cab, cab_hw, Color(0.12, 0.16, 0.2), [], trim)
	var pil := 0.07
	var roof_front: Vector2 = cab[1]
	var roof_back: Vector2 = cab[2]
	var rh: float = sp.get("roof_h", 0.06)
	for side in [-1.0, 1.0]:
		for i in cab.size():
			var a2: Vector2 = cab[i]
			var b2: Vector2 = cab[(i + 1) % cab.size()]
			if i == cab.size() - 1:
				continue   # bottom edge (beltline) is covered by the body
			var pa := Vector3(side * (cab_hw.call(a2.y) + 0.005), a2.y, a2.x)
			var pb := Vector3(side * (cab_hw.call(b2.y) + 0.005), b2.y, b2.x)
			_beam(k, "paint", pa, pb, pil, paint)
		# B pillars / bus window pillars
		var npil: int = sp.get("pillars", 1)
		for q in npil:
			var tq := float(q + 1) / (npil + 1)
			var zq := lerpf(roof_front.x, roof_back.x, tq)
			var ybot := y0
			_beam(k, "paint", Vector3(side * (cab_hw.call(ybot) + 0.005), ybot, zq), Vector3(side * (cab_hw.call(y1) + 0.005), y1, zq), pil * 1.3, paint)
	# roof panel
	var rw: float = cab_hw.call(y1)
	k.box("paint", Transform3D.IDENTITY, Vector3(0, y1 + rh * 0.5 - 0.01, (roof_front.x + roof_back.x) * 0.5),
		Vector3(rw * 2.0 + 0.02, rh, absf(roof_front.x - roof_back.x) + 0.04), paint)

	# ---- trim: bumpers, grille, plates, mirrors, door lines, side skirts
	var bump_y := clr + 0.18
	k.box("plain", Transform3D.IDENTITY, Vector3(0, bump_y, front_z + 0.04), Vector3(W - 0.06, 0.26, 0.14), trim)
	k.box("plain", Transform3D.IDENTITY, Vector3(0, bump_y, rear_z - 0.04), Vector3(W - 0.06, 0.26, 0.14), trim)
	var top_front: float = sp["top"][1][1]
	k.box("plain", Transform3D.IDENTITY, Vector3(0, (bump_y + top_front) * 0.5 + 0.06, front_z + 0.012), Vector3(W * 0.45, 0.16, 0.04), Color(0.03, 0.03, 0.035))
	k.box("plain", Transform3D.IDENTITY, Vector3(0, bump_y, front_z + 0.115), Vector3(0.52, 0.12, 0.02), Color(0.95, 0.95, 0.95))
	k.box("plain", Transform3D.IDENTITY, Vector3(0, bump_y + 0.24, rear_z - 0.02), Vector3(0.52, 0.12, 0.02), Color(0.95, 0.95, 0.95))
	# flag stripe on plates (TJ style red/white/green hint)
	k.box("plain", Transform3D.IDENTITY, Vector3(0.21, bump_y, front_z + 0.122), Vector3(0.07, 0.1, 0.01), Color(0.1, 0.45, 0.2))
	for side in [-1.0, 1.0]:
		k.box("paint", Transform3D.IDENTITY, Vector3(side * (hw + 0.09), y0 + 0.08, cab[0].x - 0.12), Vector3(0.16, 0.1, 0.07), paint)
		k.box("plain", Transform3D.IDENTITY, Vector3(side * (hw + 0.002), clr + 0.06, (wf + wr) * 0.5), Vector3(0.02, 0.1, absf(wf - wr) - arch * 2.0), trim)
		# door seams
		var dz := (cab[0].x + cab[cab.size() - 1].x) * 0.5
		k.box("plain", Transform3D.IDENTITY, Vector3(side * (hw + 0.003), (clr + y0) * 0.5 + 0.08, dz), Vector3(0.01, y0 - clr - 0.2, 0.012), trim)
		k.box("chrome", Transform3D.IDENTITY, Vector3(side * (hw + 0.012), y0 - 0.17, dz + 0.32), Vector3(0.02, 0.03, 0.16), chrome)

	# ---- lamps
	var lamp_y: float = lerpf(bump_y, top_front, 0.72)
	for side in [-1.0, 1.0]:
		k.box("headlamp", Transform3D.IDENTITY, Vector3(side * (hw - 0.26), lamp_y, front_z + 0.005), Vector3(0.32, 0.12, 0.05), Color(1.0, 0.96, 0.85))
		kb.box("brake", Transform3D.IDENTITY, Vector3(side * (hw - 0.2), lamp_y + 0.02, rear_z - 0.005), Vector3(0.3, 0.13, 0.05), Color(0.95, 0.06, 0.04))

	# ---- interior (visible through glass)
	var seat_z: float = sp["seat_z"]
	var seat_y := y0 - 0.25
	var icol := Color(0.13, 0.12, 0.12)
	for side in [-1.0, 1.0]:
		k.box("plain", Transform3D.IDENTITY, Vector3(side * hw * 0.45, seat_y, seat_z), Vector3(0.5, 0.15, 0.5), icol)
		k.box("plain", Transform3D.IDENTITY, Vector3(side * hw * 0.45, seat_y + 0.38, seat_z - 0.27), Vector3(0.5, 0.65, 0.12), icol)
		if type not in ["bus", "truck"]:
			k.box("plain", Transform3D.IDENTITY, Vector3(side * hw * 0.45, seat_y, seat_z - 0.95), Vector3(0.55, 0.15, 0.5), icol)
	if type == "bus" or type == "minibus":
		var rows := int((L - 2.5) / 0.85) if type == "bus" else 4
		for q in rows:
			var zz := seat_z - 1.2 - q * 0.85
			for side in [-1.0, 1.0]:
				k.box("plain", Transform3D.IDENTITY, Vector3(side * hw * 0.55, seat_y + 0.15, zz), Vector3(0.9, 0.12, 0.45), Color(0.5, 0.15, 0.12))
				k.box("plain", Transform3D.IDENTITY, Vector3(side * hw * 0.55, seat_y + 0.45, zz - 0.22), Vector3(0.9, 0.55, 0.08), Color(0.5, 0.15, 0.12))
	k.box("plain", Transform3D.IDENTITY, Vector3(0, y0 - 0.05, cab[0].x - 0.3), Vector3(W - 0.2, 0.18, 0.45), Color(0.08, 0.08, 0.09))   # dashboard
	var sw_t := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-65.0)), Vector3(hw * 0.45, y0 + 0.08, seat_z + 0.48))
	k.cylinder("plain", sw_t, 0.18, 0.18, 0.03, 12, Color(0.05, 0.05, 0.05), true, true)

	# ---- type specific extras
	var extras := {}
	match type:
		"taxi":
			var tz := (roof_front.x + roof_back.x) * 0.5
			k.box("plain", Transform3D.IDENTITY, Vector3(0, y1 + rh + 0.1, tz), Vector3(0.6, 0.2, 0.22), Color(0.98, 0.98, 0.95))
			for q in 6:
				var c := Color(0.05, 0.05, 0.05) if q % 2 == 0 else Color(0.97, 0.8, 0.1)
				for side in [-1.0, 1.0]:
					k.box("plain", Transform3D.IDENTITY, Vector3(side * (hw + 0.004), y0 - 0.06, cab[0].x - 0.35 - q * 0.18), Vector3(0.01, 0.09, 0.18), c)
			extras["sign"] = Vector3(0, y1 + rh + 0.1, tz)
		"police":
			for side in [-1.0, 1.0]:
				k.box("plain", Transform3D.IDENTITY, Vector3(side * (hw + 0.004), (clr + y0) * 0.5 + 0.02, (wf + wr) * 0.5), Vector3(0.01, 0.16, L * 0.8), Color(0.08, 0.2, 0.62))
			var bz := (roof_front.x + roof_back.x) * 0.5
			k.box("plain", Transform3D.IDENTITY, Vector3(0, y1 + rh + 0.03, bz), Vector3(1.1, 0.06, 0.25), Color(0.15, 0.15, 0.15))
			kr.box("siren", Transform3D.IDENTITY, Vector3(0.28, y1 + rh + 0.11, bz), Vector3(0.5, 0.12, 0.22), Color(1.0, 0.08, 0.05))
			kblu.box("siren", Transform3D.IDENTITY, Vector3(-0.28, y1 + rh + 0.11, bz), Vector3(0.5, 0.12, 0.22), Color(0.1, 0.25, 1.0))
			extras["lights"] = Vector3(0, y1 + rh + 0.11, bz)
		"bus", "minibus":
			# doors on the right side (-X)
			var dcount := 2 if type == "bus" else 1
			for q in dcount:
				var dzz: float = (front_z - 1.1) if q == 0 else (wf + wr) * 0.5 - 0.6
				if type == "minibus":
					dzz = 0.2
				k.box("glass", Transform3D.IDENTITY, Vector3(-hw - 0.012, (clr + y1) * 0.5 + 0.05, dzz), Vector3(0.02, y1 - clr - 0.25, 1.0), Color(0.08, 0.1, 0.12))
				k.box("plain", Transform3D.IDENTITY, Vector3(-hw - 0.02, (clr + y1) * 0.5 + 0.05, dzz), Vector3(0.02, y1 - clr - 0.25, 0.05), trim)
			# destination board
			k.box("headlamp", Transform3D.IDENTITY, Vector3(0, y1 - 0.18, cab[1].x + 0.02), Vector3(W * 0.7, 0.2, 0.03), Color(1.0, 0.7, 0.2))
			# livery band
			for side in [-1.0, 1.0]:
				k.box("plain", Transform3D.IDENTITY, Vector3(side * (hw + 0.003), y0 - 0.25, 0), Vector3(0.01, 0.14, L * 0.92), Color(0.95, 0.85, 0.2) if type == "bus" else Color(0.85, 0.15, 0.15))
		"truck":
			var cz0 := -2.95
			var cz1 := 1.1
			k.box("plain", Transform3D.IDENTITY, Vector3(0, 1.02, (cz0 + cz1) * 0.5), Vector3(W + 0.05, 0.08, cz1 - cz0), trim)
			k.box("plain", Transform3D.IDENTITY, Vector3(0, 1.95, (cz0 + cz1) * 0.5), Vector3(W + 0.1, 1.8, cz1 - cz0 - 0.05), Color(0.82, 0.8, 0.72))
			k.box("plain", Transform3D.IDENTITY, Vector3(0, 2.87, (cz0 + cz1) * 0.5), Vector3(W + 0.12, 0.06, cz1 - cz0), Color(0.6, 0.58, 0.52))
	# ---- wheel
	var wheel := _wheel_mesh(r, 0.22 if type not in ["bus", "truck"] else 0.3)
	var wx := hw - 0.17 - (0.02 if type == "bus" else 0.0)
	var wheels := [Vector3(wx, r, wf), Vector3(-wx, r, wf), Vector3(wx, r, wr), Vector3(-wx, r, wr)]
	var steer := [true, true, false, false]
	var drive_mode: String = sp["drive"]
	var drive := [drive_mode != "rear", drive_mode != "rear", drive_mode != "front", drive_mode != "front"]
	var mats := {"paint": material("paint"), "headlamp": material("headlamp")}
	var res := {
		"type": type, "color": color,
		"body": k.build(mats),
		"brake": kb.build({"brake": material("brake_off")}),
		"siren_red": kr.build({"siren": material("siren_off")}) if not kr.is_empty() else null,
		"siren_blue": kblu.build({"siren": material("siren_off")}) if not kblu.is_empty() else null,
		"wheel": wheel, "wheels": wheels, "steer": steer, "drive": drive, "wheel_radius": r,
		"length": L, "width": W, "height": y1 + rh, "mass": sp["mass"], "max_kmh": sp["max"],
		"seat": Vector3(hw * 0.45, seat_y + 0.1, seat_z), "door": Vector3(hw + 0.8, 0.0, seat_z + 0.2),
		"shapes": [
			[Vector3(0, (clr + y0) * 0.5 + 0.05, (front_z + rear_z) * 0.5), Vector3(W, y0 - clr - 0.05, front_z - rear_z)],
			[Vector3(0, (y0 + y1) * 0.5, (cab[0].x + cab[cab.size() - 1].x) * 0.5), Vector3(W - tumble * 2.0, y1 - y0, absf(cab[0].x - cab[cab.size() - 1].x))],
		],
		"extras": extras,
	}
	if type == "truck":
		res["shapes"].append([Vector3(0, 1.95, -0.92), Vector3(W + 0.1, 1.85, 4.0)])
	_cache[key] = res
	return res


## Extrude a side profile (z,y) polygon across the width. hw_fn(y) -> half width.
static func _extrude(k: MeshKit, slot: String, prof: PackedVector2Array, hw_fn: Callable, col: Color, edge_dark: Array, dark: Color) -> void:
	# ensure counter-clockwise in (z, y)
	var area := 0.0
	var n := prof.size()
	for i in n:
		area += prof[i].cross(prof[(i + 1) % n])
	var flags := edge_dark.duplicate()
	if area < 0.0:
		prof = prof.duplicate()
		prof.reverse()
		flags.reverse()
	# perimeter
	for i in n:
		var a := prof[i]
		var b := prof[(i + 1) % n]
		var ha: float = hw_fn.call(a.y)
		var hb: float = hw_fn.call(b.y)
		var e := b - a
		var out := Vector3(0, -e.x, e.y).normalized()   # outward for CCW (z,y): (dy, -dz) -> (y:-dz, z:dy)
		var c := col
		if flags.size() == n and flags[i] and flags[(i + 1) % n]:
			c = dark
		_quad_n(k, slot, Vector3(ha, a.y, a.x), Vector3(hb, b.y, b.x), Vector3(-hb, b.y, b.x), Vector3(-ha, a.y, a.x), c, out)
	# sides
	var idx := Geometry2D.triangulate_polygon(prof)
	for q in range(0, idx.size(), 3):
		var p0 := prof[idx[q]]
		var p1 := prof[idx[q + 1]]
		var p2 := prof[idx[q + 2]]
		for side in [-1.0, 1.0]:
			var a3 := Vector3(side * hw_fn.call(p0.y), p0.y, p0.x)
			var b3 := Vector3(side * hw_fn.call(p1.y), p1.y, p1.x)
			var c3 := Vector3(side * hw_fn.call(p2.y), p2.y, p2.x)
			_tri_n(k, slot, a3, b3, c3, col, Vector3(side, 0, 0))


static func _tri_n(k: MeshKit, slot: String, a: Vector3, b: Vector3, c: Vector3, col: Color, want: Vector3) -> void:
	var nn := (b - a).cross(c - a)
	if nn.dot(want) < 0.0:
		k.tri(slot, a, c, b, col, want.normalized())
	else:
		k.tri(slot, a, b, c, col, want.normalized())


static func _quad_n(k: MeshKit, slot: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, want: Vector3) -> void:
	var nn := (b - a).cross(d - a)
	if nn.length_squared() < 1e-10:
		nn = (c - b).cross(a - b)
	if nn.dot(want) < 0.0:
		k.quad(slot, a, d, c, b, col)
	else:
		k.quad(slot, a, b, c, d, col)


static func _beam(k: MeshKit, slot: String, a: Vector3, b: Vector3, t: float, col: Color) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		return
	var up := Vector3.UP if absf(d.normalized().y) < 0.95 else Vector3.RIGHT
	var basis := Basis.looking_at(d.normalized(), up)
	k.box(slot, Transform3D(basis, (a + b) * 0.5), Vector3.ZERO, Vector3(t, t, l + t * 0.5), col)


static func _wheel_mesh(r: float, width: float) -> ArrayMesh:
	var key := "%.2f_%.2f" % [r, width]
	if _wheel_cache.has(key):
		return _wheel_cache[key]
	var k := MeshKit.new()
	# axle along X: rotate a Y cylinder by -90 deg around Z, centred
	var rot := Basis(Vector3.BACK, -PI * 0.5)
	var t := Transform3D(rot, Vector3(-width * 0.5, 0, 0))
	k.cylinder("rubber", t, r, r, width, 18, Color(0.07, 0.07, 0.07), true, true)
	# tread grooves (thin rings slightly inset)
	var rim_r := r * 0.62
	for side in [-1.0, 1.0]:
		var rt := Transform3D(Basis(Vector3.BACK, -PI * 0.5 * side), Vector3(side * width * 0.5, 0, 0))
		k.cylinder("chrome", rt, rim_r, rim_r * 0.9, 0.012, 14, Color(0.72, 0.73, 0.75), true, false)
		# spokes
		for s in 5:
			var ang := TAU * s / 5.0
			var dir := Vector3(0, cos(ang), sin(ang))
			k.box("chrome", Transform3D(Basis(Vector3.RIGHT, ang), Vector3(side * (width * 0.5 + 0.014), 0, 0) + dir * rim_r * 0.45),
				Vector3.ZERO, Vector3(0.012, rim_r * 0.75, 0.05), Color(0.6, 0.61, 0.63))
		k.cylinder("plain", Transform3D(Basis(Vector3.BACK, -PI * 0.5 * side), Vector3(side * (width * 0.5 + 0.012), 0, 0)), 0.06, 0.05, 0.02, 8, Color(0.2, 0.2, 0.22), true, false)
	var m := k.build()
	_wheel_cache[key] = m
	return m
