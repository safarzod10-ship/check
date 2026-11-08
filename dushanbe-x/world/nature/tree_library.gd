class_name TreeLibrary
extends RefCounted
## Procedural low-poly vegetation meshes (built once). Each species has a near mesh and a far (impostor-like) mesh.

const SPECIES := ["chinar", "poplar", "archa", "pine", "apricot", "willow", "walnut", "bush", "rock", "boulder"]

static var near_meshes: Dictionary = {}
static var far_meshes: Dictionary = {}


static func ensure() -> void:
	if not near_meshes.is_empty():
		return
	for s in SPECIES:
		var kn := MeshKit.new()
		var kf := MeshKit.new()
		_build(s, kn, true)
		_build(s, kf, false)
		near_meshes[s] = kn.build()
		far_meshes[s] = kf.build()


static func _crown(kit: MeshKit, c: Vector3, r: Vector3, col: Color, rings := 4, segs := 6) -> void:
	var t := Transform3D(Basis().scaled(r), c)
	kit.sphere("foliage", t, 1.0, rings, segs, col)


static func _build(s: String, kit: MeshKit, near: bool) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(s)
	var bark := Color(0.45, 0.38, 0.3)
	var segs := 6 if near else 4
	match s:
		"chinar":   # oriental plane: massive pale trunk, big rounded crown
			kit.cylinder("bark", Transform3D(), 0.55, 0.38, 5.5, segs, Color(0.72, 0.68, 0.58), false)
			if near:
				for a in 3:
					var ang := TAU * a / 3.0 + 0.4
					var tb := Transform3D(Basis(Vector3(cos(ang), 0, sin(ang)).cross(Vector3.UP).normalized(), 0.6), Vector3(0, 4.8, 0))
					kit.cylinder("bark", tb, 0.3, 0.15, 4.0, 5, Color(0.7, 0.66, 0.56), false)
				var g := Color(0.27, 0.41, 0.17)
				_crown(kit, Vector3(0, 10.0, 0), Vector3(5.5, 4.2, 5.5), g)
				for k in 4:
					var a2 := TAU * k / 4.0 + 0.3
					_crown(kit, Vector3(cos(a2) * 3.6, 8.6 + rng.randf() * 2.0, sin(a2) * 3.6), Vector3(3.2, 2.8, 3.2), g.lightened(rng.randf() * 0.1))
				_crown(kit, Vector3(0.5, 13.2, 0.3), Vector3(3.4, 2.6, 3.4), g.lightened(0.08))
			else:
				_crown(kit, Vector3(0, 10.0, 0), Vector3(7.0, 5.2, 7.0), Color(0.27, 0.41, 0.17), 3, 6)
		"poplar":   # Lombardy poplar: tall narrow column
			kit.cylinder("bark", Transform3D(), 0.3, 0.12, 16.0, segs, bark, false)
			var g2 := Color(0.26, 0.4, 0.16)
			if near:
				for k in 4:
					_crown(kit, Vector3(rng.randf_range(-0.4, 0.4), 6.0 + k * 4.0, rng.randf_range(-0.4, 0.4)), Vector3(2.0 - k * 0.22, 3.0, 2.0 - k * 0.22), g2)
			else:
				_crown(kit, Vector3(0, 12.0, 0), Vector3(1.9, 8.5, 1.9), g2, 3, 5)
		"archa":    # juniper (archa): irregular dark conical crown, twisted trunk
			kit.cylinder("bark", Transform3D(), 0.35, 0.15, 3.0, segs, Color(0.4, 0.3, 0.24), false)
			var g3 := Color(0.2, 0.33, 0.22)
			if near:
				for k in 4:
					kit.cylinder("foliage", Transform3D(Basis(), Vector3(rng.randf_range(-0.3, 0.3), 1.5 + k * 1.6, 0)), 2.8 - k * 0.55, 0.6, 2.6, 7, g3)
				kit.cylinder("foliage", Transform3D(Basis(), Vector3(0, 7.6, 0)), 0.9, 0.0, 1.8, 6, g3)
			else:
				kit.cylinder("foliage", Transform3D(Basis(), Vector3(0, 1.4, 0)), 2.9, 0.0, 8.0, 5, g3, false, true)
		"pine":
			kit.cylinder("bark", Transform3D(), 0.32, 0.12, 14.0, segs, Color(0.48, 0.34, 0.24), false)
			var g4 := Color(0.18, 0.34, 0.2)
			if near:
				for k in 5:
					kit.cylinder("foliage", Transform3D(Basis(), Vector3(0, 5.0 + k * 2.1, 0)), 3.0 - k * 0.5, 0.4, 2.4, 8, g4, false, true)
			else:
				kit.cylinder("foliage", Transform3D(Basis(), Vector3(0, 4.5, 0)), 3.0, 0.0, 11.0, 5, g4, false, true)
		"apricot":  # small rounded fruit tree
			kit.cylinder("bark", Transform3D(), 0.18, 0.12, 1.8, segs, bark, false)
			var g5 := Color(0.33, 0.47, 0.18)
			if near:
				_crown(kit, Vector3(0, 3.4, 0), Vector3(2.6, 1.9, 2.6), g5)
				_crown(kit, Vector3(1.2, 3.0, 0.6), Vector3(1.5, 1.3, 1.5), g5.lightened(0.05))
				_crown(kit, Vector3(-1.0, 3.2, -0.8), Vector3(1.5, 1.3, 1.5), g5.darkened(0.05))
				# fruit
				for k in 10:
					var a3 := rng.randf() * TAU
					var p := Vector3(cos(a3) * 2.3, 2.8 + rng.randf() * 1.6, sin(a3) * 2.3)
					kit.box("plain", Transform3D(), p, Vector3(0.14, 0.14, 0.14), Color(0.98, 0.6, 0.1))
			else:
				_crown(kit, Vector3(0, 3.3, 0), Vector3(2.8, 2.0, 2.8), g5, 3, 5)
		"willow":
			kit.cylinder("bark", Transform3D(), 0.45, 0.25, 4.0, segs, Color(0.42, 0.36, 0.28), false)
			var g6 := Color(0.37, 0.48, 0.22)
			if near:
				_crown(kit, Vector3(0, 7.0, 0), Vector3(4.5, 3.0, 4.5), g6)
				for k in 8:
					var a4 := TAU * k / 8.0
					kit.cylinder("foliage", Transform3D(Basis(Vector3.RIGHT, PI), Vector3(cos(a4) * 3.6, 7.5, sin(a4) * 3.6)), 1.3, 0.3, 5.0, 5, g6.darkened(0.06))
			else:
				_crown(kit, Vector3(0, 6.0, 0), Vector3(4.8, 4.0, 4.8), g6, 3, 5)
		"walnut":
			kit.cylinder("bark", Transform3D(), 0.45, 0.3, 3.5, segs, Color(0.5, 0.46, 0.4), false)
			var g7 := Color(0.25, 0.38, 0.16)
			if near:
				_crown(kit, Vector3(0, 7.0, 0), Vector3(6.0, 3.6, 6.0), g7)
				for k in 5:
					var a5 := TAU * k / 5.0
					_crown(kit, Vector3(cos(a5) * 4.0, 6.2, sin(a5) * 4.0), Vector3(2.8, 2.2, 2.8), g7.lightened(0.05))
			else:
				_crown(kit, Vector3(0, 6.8, 0), Vector3(7.0, 4.0, 7.0), g7, 3, 6)
		"bush":
			var g8 := Color(0.3, 0.45, 0.2)
			if near:
				_crown(kit, Vector3(0, 0.6, 0), Vector3(1.3, 0.9, 1.3), g8, 3, 6)
				_crown(kit, Vector3(0.8, 0.5, 0.3), Vector3(0.9, 0.7, 0.9), g8.lightened(0.06), 3, 6)
				_crown(kit, Vector3(-0.6, 0.45, -0.5), Vector3(0.8, 0.6, 0.8), g8.darkened(0.05), 3, 6)
			else:
				_crown(kit, Vector3(0, 0.6, 0), Vector3(1.6, 0.9, 1.6), g8, 2, 4)
		"rock":
			_rock(kit, 1.0, rng, near)
		"boulder":
			_rock(kit, 3.5, rng, near)


static func _rock(kit: MeshKit, size: float, rng: RandomNumberGenerator, near: bool) -> void:
	var rings := 4 if near else 2
	var segs := 7 if near else 4
	var start: int = kit._s("rock")["v"].size()
	kit.sphere("rock", Transform3D(Basis().scaled(Vector3(1.0, 0.65, 0.85) * size), Vector3(0, size * 0.25, 0)), 1.0, rings, segs, Color(0.82, 0.78, 0.72))
	# jitter vertices for an irregular silhouette (consistent per position)
	var s: Dictionary = kit._s("rock")
	var cache := {}
	for i in range(start, s["v"].size()):
		var v: Vector3 = s["v"][i]
		var key := Vector3i(roundi(v.x * 100), roundi(v.y * 100), roundi(v.z * 100))
		if not cache.has(key):
			cache[key] = Vector3(rng.randf_range(-0.22, 0.22), rng.randf_range(-0.15, 0.15), rng.randf_range(-0.22, 0.22)) * size
		s["v"][i] = v + cache[key]
