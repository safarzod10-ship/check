class_name HumanoidBuilder
extends RefCounted
## Procedural skinned humanoid (≈1.75 m) with a Godot SkeletonProfileHumanoid-compatible skeleton.
##
## Bind pose: standing, arms hanging down, the character faces -Z (Godot "forward"), its right is +X.
## All rest rotations are identity, so animation rotations are expressed in world-aligned axes:
##   * hanging limbs: +X rotation swings them forward; Z rotation moves them sideways (+Z -> towards +X)
##   * upward bones (spine/neck/head): -X leans forward, +Y turns towards the character's left
##
## Replacing the model with an imported .glb:
##   1. Import the .glb, in the import dock set Skeleton3D > Retarget > Bone Map = SkeletonProfileHumanoid
##      (the importer renames bones to Hips, Spine, Chest, UpperChest, Neck, Head, LeftUpperArm ...).
##   2. Enable "Overwrite Axis" / rest fixer so the rest pose matches (facing +Z in glTF; rotate the model
##      node by 180° around Y so it faces -Z like this builder).
##   3. Instance the scene instead of HumanoidBuilder.create(): the procedural AnimationLibrary uses
##      tracks "Skeleton3D:<BoneName>", so name the skeleton node "Skeleton3D" under the model root.
##      Retargeted rests are not identity, so for best results re-author the animations in Blender with
##      the same names (idle, walk, run, ...) — HumanoidAnimator only relies on the animation names.

const BONES := [
	["Hips", "", Vector3(0, 0.95, 0)],
	["Spine", "Hips", Vector3(0, 0.10, 0)],
	["Chest", "Spine", Vector3(0, 0.13, 0)],
	["UpperChest", "Chest", Vector3(0, 0.12, 0)],
	["Neck", "UpperChest", Vector3(0, 0.15, 0)],
	["Head", "Neck", Vector3(0, 0.09, 0)],
	["LeftShoulder", "UpperChest", Vector3(-0.03, 0.10, 0)],
	["LeftUpperArm", "LeftShoulder", Vector3(-0.15, -0.02, 0)],
	["LeftLowerArm", "LeftUpperArm", Vector3(0, -0.28, 0)],
	["LeftHand", "LeftLowerArm", Vector3(0, -0.25, 0)],
	["RightShoulder", "UpperChest", Vector3(0.03, 0.10, 0)],
	["RightUpperArm", "RightShoulder", Vector3(0.15, -0.02, 0)],
	["RightLowerArm", "RightUpperArm", Vector3(0, -0.28, 0)],
	["RightHand", "RightLowerArm", Vector3(0, -0.25, 0)],
	["LeftUpperLeg", "Hips", Vector3(-0.10, -0.04, 0)],
	["LeftLowerLeg", "LeftUpperLeg", Vector3(0, -0.42, 0)],
	["LeftFoot", "LeftLowerLeg", Vector3(0, -0.41, 0)],
	["LeftToes", "LeftFoot", Vector3(0, -0.05, -0.12)],
	["RightUpperLeg", "Hips", Vector3(0.10, -0.04, 0)],
	["RightLowerLeg", "RightUpperLeg", Vector3(0, -0.42, 0)],
	["RightFoot", "RightLowerLeg", Vector3(0, -0.41, 0)],
	["RightToes", "RightFoot", Vector3(0, -0.05, -0.12)],
]

const SKIN_TONES := [Color(0.87, 0.70, 0.56), Color(0.80, 0.62, 0.47), Color(0.72, 0.54, 0.40),
	Color(0.62, 0.45, 0.32), Color(0.92, 0.78, 0.66)]
const HAIR := [Color(0.06, 0.05, 0.04), Color(0.12, 0.08, 0.05), Color(0.25, 0.17, 0.10), Color(0.55, 0.55, 0.55)]
const SHIRTS := [Color(0.92, 0.92, 0.9), Color(0.2, 0.3, 0.55), Color(0.6, 0.15, 0.15), Color(0.25, 0.45, 0.3),
	Color(0.15, 0.15, 0.17), Color(0.75, 0.65, 0.4), Color(0.4, 0.55, 0.75), Color(0.85, 0.5, 0.2)]
const PANTS := [Color(0.12, 0.13, 0.18), Color(0.2, 0.22, 0.28), Color(0.35, 0.3, 0.22), Color(0.1, 0.1, 0.1),
	Color(0.3, 0.35, 0.45)]
const DRESSES := [Color(0.75, 0.1, 0.25), Color(0.1, 0.45, 0.6), Color(0.85, 0.65, 0.1), Color(0.45, 0.15, 0.55),
	Color(0.1, 0.55, 0.35), Color(0.9, 0.35, 0.45)]

static var _skin_cache: Skin = null
static var _mesh_cache: Dictionary = {}
static var _material: StandardMaterial3D = null


static func bone_index(name: String) -> int:
	for i in BONES.size():
		if BONES[i][0] == name:
			return i
	return -1


static func rest_global(name: String) -> Vector3:
	var i := bone_index(name)
	var p := Vector3.ZERO
	while i >= 0:
		p += BONES[i][2]
		i = bone_index(BONES[i][1]) if BONES[i][1] != "" else -1
	return p


static func default_appearance() -> Dictionary:
	return {"gender": "m", "skin": SKIN_TONES[1], "hair": HAIR[0], "shirt": Color(0.92, 0.92, 0.9),
		"pants": Color(0.15, 0.17, 0.25), "shoes": Color(0.1, 0.08, 0.07), "hat": "none", "sleeves": "long",
		"beard": false, "height": 1.0, "dress": DRESSES[0], "scarf": Color(0.9, 0.85, 0.75), "jacket": false,
		"jacket_col": Color(0.25, 0.22, 0.2)}


static func random_appearance(rng: RandomNumberGenerator) -> Dictionary:
	var a := default_appearance()
	a["gender"] = "f" if rng.randf() < 0.45 else "m"
	a["skin"] = SKIN_TONES[rng.randi() % SKIN_TONES.size()]
	a["hair"] = HAIR[rng.randi() % (HAIR.size() if rng.randf() < 0.25 else 3)]
	a["shirt"] = SHIRTS[rng.randi() % SHIRTS.size()]
	a["pants"] = PANTS[rng.randi() % PANTS.size()]
	a["shoes"] = [Color(0.08, 0.07, 0.06), Color(0.3, 0.2, 0.12), Color(0.85, 0.85, 0.85)][rng.randi() % 3]
	a["sleeves"] = "short" if rng.randf() < 0.4 else "long"
	a["height"] = rng.randf_range(0.93, 1.05)
	if a["gender"] == "m":
		var r := rng.randf()
		a["hat"] = "doppi" if r < 0.25 else ("cap" if r < 0.35 else "none")
		a["beard"] = rng.randf() < 0.2
		a["jacket"] = rng.randf() < 0.3
		a["jacket_col"] = [Color(0.2, 0.2, 0.22), Color(0.35, 0.28, 0.2), Color(0.15, 0.2, 0.35)][rng.randi() % 3]
	else:
		a["height"] *= 0.95
		a["dress"] = DRESSES[rng.randi() % DRESSES.size()]
		a["pants"] = a["dress"].darkened(0.35) if rng.randf() < 0.6 else DRESSES[rng.randi() % DRESSES.size()]
		a["hat"] = "scarf" if rng.randf() < 0.6 else "none"
		a["scarf"] = [Color(0.95, 0.95, 0.92), Color(0.85, 0.2, 0.3), Color(0.2, 0.25, 0.5), Color(0.9, 0.75, 0.3)][rng.randi() % 4]
	return a


## Builds the Skeleton3D with the humanoid hierarchy (rest = bind pose).
static func build_skeleton() -> Skeleton3D:
	var sk := Skeleton3D.new()
	sk.name = "Skeleton3D"
	for b in BONES:
		var idx := sk.add_bone(b[0])
		if b[1] != "":
			sk.set_bone_parent(idx, sk.find_bone(b[1]))
		sk.set_bone_rest(idx, Transform3D(Basis(), b[2]))
	sk.reset_bone_poses()
	return sk


static func get_skin() -> Skin:
	if _skin_cache:
		return _skin_cache
	var skin := Skin.new()
	for b in BONES:
		skin.add_named_bind(b[0], Transform3D(Basis(), rest_global(b[0])).affine_inverse())
	_skin_cache = skin
	return skin


static func get_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.8
	return _material


## Returns a model root: Node3D "Model" > Skeleton3D "Skeleton3D" > MeshInstance3D "Body".
static func create(appearance: Dictionary = {}) -> Node3D:
	var a := default_appearance()
	a.merge(appearance, true)
	var root := Node3D.new()
	root.name = "Model"
	root.scale = Vector3.ONE * float(a["height"])
	var sk := build_skeleton()
	root.add_child(sk)
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = get_mesh(a)
	mi.skin = get_skin()
	sk.add_child(mi)
	mi.skeleton = NodePath("..")
	return root


static func _key(a: Dictionary) -> String:
	return "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % [a["gender"], a["skin"].to_html(), a["hair"].to_html(),
		a["shirt"].to_html(), a["pants"].to_html(), a["shoes"].to_html(), a["hat"], a["sleeves"], a["beard"],
		a["dress"].to_html(), a["scarf"].to_html(), str(a["jacket"]) + a["jacket_col"].to_html()]


static func get_mesh(a: Dictionary) -> ArrayMesh:
	var k := _key(a)
	if _mesh_cache.has(k):
		return _mesh_cache[k]
	var m := _BodyMesh.new().build(a)
	if _mesh_cache.size() > 48:
		_mesh_cache.clear()
	_mesh_cache[k] = m
	return m


# ---------------------------------------------------------------------------
# Skinned mesh construction
# ---------------------------------------------------------------------------
class _BodyMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	var idx := PackedInt32Array()

	func _bi(name: String) -> int:
		return HumanoidBuilder.bone_index(name)

	func _add_vertex(p: Vector3, nn: Vector3, col: Color, w: Array) -> int:
		v.append(p)
		n.append(nn.normalized())
		c.append(col)
		# w = [[bone_name, weight], ...] -> 4 slots, normalised
		var total := 0.0
		for e in w:
			total += float(e[1])
		for q in 4:
			if q < w.size():
				bones.append(_bi(w[q][0]))
				weights.append(float(w[q][1]) / maxf(total, 0.0001))
			else:
				bones.append(0)
				weights.append(0.0)
		return v.size() - 1

	## Emits a triangle facing `outward` (Godot front faces are clockwise).
	func _tri(a: int, b: int, cc: int, outward: Vector3) -> void:
		var gn := (v[b] - v[a]).cross(v[cc] - v[a])
		if gn.dot(outward) > 0.0:
			idx.append_array([a, cc, b])
		else:
			idx.append_array([a, b, cc])

	## Generalised tube: rings around a polyline with elliptic radii.
	func tube(centers: Array, radii: Array, ws: Array, cols: Array, segs := 8, cap_start := false, cap_end := false) -> void:
		var rings: Array = []
		var nr := centers.size()
		for i in nr:
			var d: Vector3
			if i < nr - 1:
				d = (centers[i + 1] - centers[i]).normalized()
			else:
				d = (centers[i] - centers[i - 1]).normalized()
			var ref := Vector3(0, 0, 1) if absf(d.z) < 0.9 else Vector3(1, 0, 0)
			var u := ref.cross(d).normalized()
			var w := d.cross(u)
			var r: Vector2 = radii[i]
			var ring: Array = []
			for k in segs:
				var ang := TAU * k / segs
				var off: Vector3 = u * cos(ang) * r.x + w * sin(ang) * r.y
				var nrm: Vector3 = u * cos(ang) / maxf(r.x, 0.001) + w * sin(ang) / maxf(r.y, 0.001)
				ring.append(_add_vertex(centers[i] + off, nrm, cols[i], ws[i]))
			rings.append(ring)
		for i in nr - 1:
			for k in segs:
				var k2 := (k + 1) % segs
				var a: int = rings[i][k]
				var b: int = rings[i][k2]
				var cc: int = rings[i + 1][k]
				var dd: int = rings[i + 1][k2]
				var out: Vector3 = (v[a] + v[b] + v[cc] + v[dd]) * 0.25 - (centers[i] + centers[i + 1]) * 0.5
				_tri(a, b, cc, out)
				_tri(b, dd, cc, out)
		for e in [[cap_start, 0, -1.0], [cap_end, nr - 1, 1.0]]:
			if not e[0]:
				continue
			var ri: int = e[1]
			var dir: Vector3 = (centers[mini(ri + 1, nr - 1)] - centers[maxi(ri - 1, 0)]).normalized() * float(e[2])
			var center := _add_vertex(centers[ri] + dir * 0.01, dir, cols[ri], ws[ri])
			for k in segs:
				_tri(center, rings[ri][k], rings[ri][(k + 1) % segs], dir)

	func ellipsoid(center: Vector3, r: Vector3, col: Color, w: Array, rings := 7, segs := 10,
			phi_max := PI, tilt := 0.0, col_fn := Callable()) -> void:
		var basis := Basis(Vector3.RIGHT, tilt)
		var start := v.size()
		for i in rings + 1:
			var phi := phi_max * float(i) / rings
			for k in segs:
				var ang := TAU * k / segs
				var unit := Vector3(sin(phi) * cos(ang), cos(phi), sin(phi) * sin(ang))
				var p := basis * Vector3(unit.x * r.x, unit.y * r.y, unit.z * r.z)
				var nn := basis * Vector3(unit.x / r.x, unit.y / r.y, unit.z / r.z)
				var cc := col
				if col_fn.is_valid():
					cc = col_fn.call(unit, col)
				_add_vertex(center + p, nn, cc, w)
		for i in rings:
			for k in segs:
				var k2 := (k + 1) % segs
				var a := start + i * segs + k
				var b := start + i * segs + k2
				var cc := a + segs
				var dd := b + segs
				var out: Vector3 = (v[a] + v[dd]) * 0.5 - center
				if i == 0:
					_tri(a, cc, dd, out)
				else:
					_tri(a, b, cc, out)
					_tri(b, dd, cc, out)

	func box(center: Vector3, size: Vector3, col: Color, w: Array, rot := Basis()) -> void:
		var h := size * 0.5
		var faces := [
			[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
			[Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)],
			[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
			[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
			[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
			[Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		]
		for f in faces:
			var fn: Vector3 = f[0]
			var t1: Vector3 = f[1]
			var t2: Vector3 = f[2]
			var base := center + rot * (fn * h)
			var e1 := rot * (t1 * h)
			var e2 := rot * (t2 * h)
			var wn := rot * fn
			var i0 := _add_vertex(base - e1 - e2, wn, col, w)
			var i1 := _add_vertex(base + e1 - e2, wn, col, w)
			var i2 := _add_vertex(base + e1 + e2, wn, col, w)
			var i3 := _add_vertex(base - e1 + e2, wn, col, w)
			_tri(i0, i1, i2, wn)
			_tri(i0, i2, i3, wn)

	func build(a: Dictionary) -> ArrayMesh:
		var skin: Color = a["skin"]
		var shirt: Color = a["shirt"]
		var pants: Color = a["pants"]
		var shoes: Color = a["shoes"]
		var hair: Color = a["hair"]
		var female: bool = a["gender"] == "f"
		var top: Color = a["jacket_col"] if a["jacket"] else shirt
		var short: bool = a["sleeves"] == "short" and not a["jacket"]

		# ---- legs ----
		for s in [-1, 1]:
			var side := "Left" if s < 0 else "Right"
			var UL := side + "UpperLeg"
			var LL := side + "LowerLeg"
			var FT := side + "Foot"
			var ys := [0.98, 0.90, 0.75, 0.60, 0.52, 0.46, 0.35, 0.22, 0.12]
			var rs := [0.088, 0.086, 0.076, 0.064, 0.058, 0.056, 0.059, 0.047, 0.042]
			var ws := [[["Hips", 0.6], [UL, 0.4]], [[UL, 0.8], ["Hips", 0.2]], [[UL, 1.0]], [[UL, 1.0]],
				[[UL, 0.5], [LL, 0.5]], [[LL, 0.85], [UL, 0.15]], [[LL, 1.0]], [[LL, 1.0]], [[LL, 0.7], [FT, 0.3]]]
			var cs: Array = []
			var radii: Array = []
			var cols: Array = []
			for i in ys.size():
				var x: float = s * lerpf(0.095, 0.088, (0.98 - ys[i]) / 0.86)
				var z := 0.0
				if ys[i] > 0.6:
					z = 0.005
				if ys[i] < 0.5 and ys[i] > 0.3:
					z = 0.012   # calf
				cs.append(Vector3(x, ys[i], z))
				radii.append(Vector2(rs[i], rs[i] * (1.08 if ys[i] < 0.45 and ys[i] > 0.25 else 1.0)))
				cols.append(pants)
			tube(cs, radii, ws, cols, 8)
			# shoe
			box(Vector3(s * 0.09, 0.045, -0.035), Vector3(0.105, 0.09, 0.27), shoes, [[FT, 1.0]])
			box(Vector3(s * 0.09, 0.008, -0.035), Vector3(0.11, 0.016, 0.28), shoes.darkened(0.5), [[FT, 1.0]])

		# ---- torso ----
		var ty := [0.84, 0.95, 1.00, 1.08, 1.18, 1.28, 1.37, 1.435, 1.47, 1.49, 1.56]
		var trx := [0.15, 0.165, 0.155, 0.148, 0.16, 0.172, 0.18, 0.15, 0.075, 0.058, 0.052]
		var trz := [0.10, 0.115, 0.108, 0.104, 0.11, 0.122 if not female else 0.135, 0.115, 0.095, 0.07, 0.058, 0.052]
		var tw := [[["Hips", 1.0]], [["Hips", 1.0]], [["Hips", 0.5], ["Spine", 0.5]], [["Spine", 1.0]],
			[["Chest", 0.7], ["Spine", 0.3]], [["UpperChest", 0.6], ["Chest", 0.4]], [["UpperChest", 1.0]],
			[["UpperChest", 0.85], ["Neck", 0.15]], [["UpperChest", 0.5], ["Neck", 0.5]], [["Neck", 1.0]],
			[["Neck", 0.5], ["Head", 0.5]]]
		var tc := [pants, pants.darkened(0.3), top, top, top, top, top, top, shirt, skin, skin]
		var tcent: Array = []
		var trad: Array = []
		for i in ty.size():
			tcent.append(Vector3(0, ty[i], 0.0 if ty[i] < 1.45 else 0.01))
			trad.append(Vector2(trx[i], trz[i]))
		tube(tcent, trad, tw, tc, 10, true, false)
		if a["jacket"]:
			# open jacket hem
			tube([Vector3(0, 0.88, 0), Vector3(0, 1.02, 0)], [Vector2(0.172, 0.125), Vector2(0.162, 0.118)],
				[[["Hips", 1.0]], [["Spine", 0.5], ["Hips", 0.5]]], [top, top], 10)
			box(Vector3(0, 1.2, -0.112), Vector3(0.05, 0.36, 0.01), shirt, [["Chest", 1.0]])

		# ---- dress (female) ----
		if female:
			var dress: Color = a["dress"]
			var dy := [1.36, 1.22, 1.05, 0.92, 0.75, 0.58, 0.48]
			var drx := [0.182, 0.165, 0.158, 0.19, 0.215, 0.235, 0.245]
			var drz := [0.128, 0.118, 0.112, 0.135, 0.16, 0.18, 0.19]
			var dw := [[["UpperChest", 1.0]], [["Chest", 0.8], ["UpperChest", 0.2]], [["Spine", 0.6], ["Hips", 0.4]],
				[["Hips", 1.0]], [["Hips", 0.6], ["LeftUpperLeg", 0.2], ["RightUpperLeg", 0.2]],
				[["Hips", 0.4], ["LeftUpperLeg", 0.3], ["RightUpperLeg", 0.3]],
				[["Hips", 0.3], ["LeftUpperLeg", 0.35], ["RightUpperLeg", 0.35]]]
			var dcent: Array = []
			var drad: Array = []
			var dcol: Array = []
			for i in dy.size():
				dcent.append(Vector3(0, dy[i], 0.0))
				drad.append(Vector2(drx[i], drz[i]))
				# simple embroidered band near the hem (atlas-silk look)
				dcol.append(dress.lightened(0.25) if i == 5 else dress)
			tube(dcent, drad, dw, dcol, 12)

		# ---- arms ----
		for s in [-1, 1]:
			var side := "Left" if s < 0 else "Right"
			var SH := side + "Shoulder"
			var UA := side + "UpperArm"
			var LA := side + "LowerArm"
			var HD := side + "Hand"
			var sleeve: Color = a["dress"] if female else top
			var ay := [1.43, 1.36, 1.22, 1.12, 1.04, 0.90, 0.865]
			var ar := [0.058, 0.056, 0.049, 0.045, 0.043, 0.036, 0.033]
			var aw := [[["UpperChest", 0.5], [UA, 0.5]], [[UA, 0.85], [SH, 0.15]], [[UA, 1.0]], [[UA, 0.5], [LA, 0.5]],
				[[LA, 1.0]], [[LA, 1.0]], [[LA, 0.6], [HD, 0.4]]]
			var acent: Array = []
			var arad: Array = []
			var acol: Array = []
			for i in ay.size():
				acent.append(Vector3(s * (0.18 + (1.43 - ay[i]) * 0.012), ay[i], 0.0))
				arad.append(Vector2(ar[i], ar[i]))
				var col := sleeve
				if (short and ay[i] < 1.2) or i == ay.size() - 1:
					col = skin
				acol.append(col)
			tube(acent, arad, aw, acol, 8, false, true)
			# hand (palm + fingers block + thumb)
			box(Vector3(s * 0.19, 0.80, -0.005), Vector3(0.05, 0.10, 0.085), skin, [[HD, 1.0]])
			box(Vector3(s * 0.19, 0.725, -0.01), Vector3(0.045, 0.07, 0.075), skin.darkened(0.05), [[HD, 1.0]])
			box(Vector3(s * 0.175, 0.80, -0.055), Vector3(0.022, 0.06, 0.025), skin, [[HD, 1.0]])

		# ---- head ----
		var hc := Vector3(0, 1.655, 0)
		ellipsoid(hc, Vector3(0.093, 0.115, 0.105), skin, [["Head", 1.0]], 8, 12)
		var dark := Color(0.05, 0.04, 0.04)
		box(hc + Vector3(0, -0.02, -0.105), Vector3(0.026, 0.045, 0.035), skin.darkened(0.06), [["Head", 1.0]])  # nose
		for s in [-1, 1]:
			box(hc + Vector3(s * 0.034, 0.012, -0.094), Vector3(0.026, 0.014, 0.012), Color(0.95, 0.95, 0.95), [["Head", 1.0]])
			box(hc + Vector3(s * 0.034, 0.012, -0.1), Vector3(0.012, 0.013, 0.006), dark, [["Head", 1.0]])
			box(hc + Vector3(s * 0.036, 0.04, -0.097), Vector3(0.034, 0.008, 0.01), hair.darkened(0.2), [["Head", 1.0]])
			box(hc + Vector3(s * 0.094, -0.005, 0.0), Vector3(0.018, 0.045, 0.03), skin.darkened(0.05), [["Head", 1.0]])
		box(hc + Vector3(0, -0.06, -0.093), Vector3(0.04, 0.008, 0.01), Color(0.55, 0.3, 0.28), [["Head", 1.0]])  # mouth
		if a["beard"]:
			box(hc + Vector3(0, -0.085, -0.06), Vector3(0.12, 0.06, 0.09), hair, [["Head", 1.0]])
			box(hc + Vector3(0, -0.04, -0.098), Vector3(0.07, 0.012, 0.012), hair, [["Head", 1.0]])
		var hat: String = a["hat"]
		if hat == "scarf":
			var sc: Color = a["scarf"]
			ellipsoid(hc + Vector3(0, 0.01, 0.006), Vector3(0.108, 0.128, 0.118), sc, [["Head", 1.0]], 6, 12, PI * 0.62, 0.45)
			box(hc + Vector3(0, -0.13, 0.07), Vector3(0.16, 0.2, 0.05), sc, [["Neck", 0.6], ["UpperChest", 0.4]], Basis(Vector3.RIGHT, 0.15))
		else:
			# hair cap tilted back so the forehead stays visible
			var long_hair := female
			ellipsoid(hc + Vector3(0, 0.006, 0.01), Vector3(0.1, 0.118, 0.112), hair, [["Head", 1.0]], 5, 12, PI * 0.5, 0.5)
			if long_hair:
				box(hc + Vector3(0, -0.11, 0.075), Vector3(0.17, 0.26, 0.04), hair, [["Head", 0.5], ["Neck", 0.5]])
			if hat == "doppi":
				# Tajik tubeteika: black, square-ish with white "chust" pepper motifs
				var dc := Color(0.04, 0.04, 0.05)
				var pat := func(u: Vector3, base: Color) -> Color:
					var ang := atan2(u.z, u.x)
					return Color(0.95, 0.95, 0.92) if fmod(ang + TAU, PI * 0.5) < 0.35 and u.y < 0.8 else base
				ellipsoid(hc + Vector3(0, 0.072, 0.005), Vector3(0.104, 0.07, 0.112), dc, [["Head", 1.0]], 4, 4, PI * 0.5, 0.0, pat)
			elif hat == "cap":
				var cc: Color = shirt.darkened(0.2)
				ellipsoid(hc + Vector3(0, 0.05, 0.005), Vector3(0.104, 0.08, 0.114), cc, [["Head", 1.0]], 4, 12, PI * 0.5, 0.0)
				box(hc + Vector3(0, 0.05, -0.15), Vector3(0.15, 0.012, 0.09), cc, [["Head", 1.0]])

		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = v
		arr[Mesh.ARRAY_NORMAL] = n
		arr[Mesh.ARRAY_COLOR] = c
		arr[Mesh.ARRAY_BONES] = bones
		arr[Mesh.ARRAY_WEIGHTS] = weights
		arr[Mesh.ARRAY_INDEX] = idx
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(0, HumanoidBuilder.get_material())
		return mesh
