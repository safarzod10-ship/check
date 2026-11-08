extends RefCounted
## Roadside points of interest. Local +Z faces the road (the road edge is ~4 m beyond +hz).

const SIZE := {"gas_station": Vector2(26, 20), "cafe": Vector2(14, 12), "chaikhana": Vector2(18, 14),
	"viewpoint": Vector2(16, 12), "tourist_base": Vector2(40, 30), "restaurant": Vector2(20, 16),
	"market": Vector2(40, 28), "parking": Vector2(30, 20), "shop": Vector2(10, 8)}


static func build_poi(k: MeshKit, lm: Dictionary) -> void:
	var t: String = lm["type"]
	var s: Vector2 = SIZE.get(t, Vector2(10, 10))
	lm["hx"] = s.x
	lm["hz"] = s.y
	match t:
		"gas_station": _gas(k, lm)
		"cafe": _cafe(k, lm, "КАФЕ", Color(0.95, 0.85, 0.7), false)
		"restaurant": _cafe(k, lm, "РЕСТОРАН «ВАРЗОБ»", Color(0.85, 0.75, 0.62), true)
		"chaikhana": _chaikhana(k, lm)
		"viewpoint": _viewpoint(k, lm)
		"tourist_base": _tourist(k, lm)
		"market": _market(k, lm)
		"parking": LmKit.parking_lot(k, Vector3.ZERO, s.x * 2.0 - 2.0, s.y * 2.0 - 2.0)
		"shop": _shop(k, lm)


static func _slab(k: MeshKit, slot: String, w: float, d: float, col: Color, z := 0.0) -> void:
	LmKit.block(k, slot, Vector3(0, -2.0, z), Vector3(w, 2.12, d), col)


static func _gas(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	_slab(k, "concrete", 52, 40, Color(0.55, 0.55, 0.56))
	# canopy over 2 pump islands
	var cz := 6.0
	for sx: float in [-8.0, 8.0]:
		for sz: float in [-4.0, 4.0]:
			LmKit.block(k, "metal", Vector3(sx, 0.1, cz + sz), Vector3(0.5, 5.6, 0.5), Color(0.9, 0.9, 0.9))
	LmKit.block(k, "plain", Vector3(0, 5.7, cz), Vector3(24, 1.0, 14), Color(0.95, 0.95, 0.95))
	LmKit.block(k, "glossy", Vector3(0, 5.75, cz + 7.02), Vector3(24, 0.9, 0.1), Color(0.1, 0.45, 0.25))
	LmKit.block(k, "glossy", Vector3(0, 5.75, cz - 7.02), Vector3(24, 0.9, 0.1), Color(0.1, 0.45, 0.25))
	k.box("lamp", LmKit.xf(Vector3(0, 5.68, cz)), Vector3.ZERO, Vector3(20, 0.05, 10), Color(1, 1, 0.95))
	for sx: float in [-8.0, 8.0]:
		LmKit.block(k, "concrete", Vector3(sx, 0.1, cz), Vector3(1.6, 0.25, 6.0), Color(0.8, 0.8, 0.8))
		for sz: float in [-1.5, 1.5]:
			LmKit.block(k, "glossy", Vector3(sx, 0.35, cz + sz), Vector3(0.9, 1.8, 0.6), Color(0.15, 0.5, 0.3))
			LmKit.block(k, "glass", Vector3(sx, 1.6, cz + sz + 0.31), Vector3(0.6, 0.4, 0.02), Color(0.1, 0.1, 0.12))
	# shop building
	LmKit.block(k, "concrete", Vector3(0, 0.1, -12), Vector3(16, 4.2, 9), Color(0.92, 0.9, 0.86))
	LmKit.block(k, "glass", Vector3(0, 0.4, -7.45), Vector3(10, 2.8, 0.1), Color(0.3, 0.42, 0.5))
	LmKit.block(k, "glossy", Vector3(0, 3.6, -7.4), Vector3(16, 0.8, 0.2), Color(0.1, 0.45, 0.25))
	# price pylon
	LmKit.block(k, "metal", Vector3(20, 0.1, 15), Vector3(0.6, 7.0, 0.6), LmKit.METAL)
	LmKit.block(k, "glossy", Vector3(20, 5.0, 15), Vector3(3.0, 4.0, 0.5), Color(0.1, 0.45, 0.25))
	LmKit.light(lm, Vector3(0, 5.2, cz), Color(1.0, 0.98, 0.92), 26.0, 2.5)
	LmKit.label(lm, Vector3(20, 6.3, 15.3), "АЗС", 110, Color(1, 1, 1))
	LmKit.label(lm, Vector3(20, 5.4, 15.3), "АИ-92  10.2\nАИ-95  11.5\nДТ     10.8", 36, Color(1, 0.9, 0.3))
	LmKit.label(lm, Vector3(0, 6.2, cz + 7.12), "ЗАПРАВКА", 90, Color(1, 1, 1))
	LmKit.label(lm, Vector3(0, 4.0, -7.25), "МАҒОЗА 24/7", 50, Color(1, 1, 1))
	for i in 3:
		LmKit.bench(d, Vector3(-6 + i * 6, 0.1, -6.5), 0.0)


static func _cafe(k: MeshKit, lm: Dictionary, name: String, wall: Color, big: bool) -> void:
	var d: MeshKit = lm["_detail"]
	var w := 22.0 if big else 14.0
	var dep := 12.0 if big else 9.0
	_slab(k, "paving", w + 14, dep + 18, Color(0.8, 0.76, 0.7))
	var bz := -4.0
	LmKit.block(k, "concrete", Vector3(0, 0.1, bz), Vector3(w, 3.8, dep), wall)
	LmKit.hip_roof(k, "tin", Vector3(0, 3.9, bz), w + 1.6, dep + 1.6, 2.4, Color(0.55, 0.2, 0.15))
	LmKit.block(k, "glass", Vector3(0, 0.5, bz + dep * 0.5 + 0.02), Vector3(w * 0.7, 2.4, 0.1), Color(0.35, 0.45, 0.5))
	# terrace with umbrellas
	var tz := bz + dep * 0.5 + 5.0
	LmKit.block(k, "wood", Vector3(0, 0.1, tz), Vector3(w, 0.3, 8), LmKit.WOOD)
	var cols := [Color(0.85, 0.2, 0.2), Color(0.95, 0.95, 0.9), Color(0.2, 0.5, 0.8)]
	for i in (3 if not big else 4):
		var p := Vector3(-w * 0.35 + i * (w * 0.7 / (2 if not big else 3)), 0.4, tz)
		LmKit.cyl(d, "plain", p, 0.5, 0.5, 0.75, Color(0.9, 0.9, 0.9), 10)
		LmKit.cyl(d, "metal", p, 0.04, 0.04, 2.4, LmKit.DARK, 4, false)
		LmKit.cyl(k, "awning", p + Vector3(0, 2.2, 0), 1.6, 0.05, 0.6, cols[i % 3], 8, false)
		for a in 4:
			var ang := a * PI * 0.5
			LmKit.block(d, "wood", p + Vector3(cos(ang) * 0.9, 0, sin(ang) * 0.9), Vector3(0.45, 0.45, 0.45), LmKit.WOOD)
	LmKit.label(lm, Vector3(0, 3.3, bz + dep * 0.5 + 0.12), name, 64, Color(1, 0.95, 0.75))


static func _chaikhana(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	_slab(k, "dirt", 38, 30, Color(0.7, 0.6, 0.48))
	# main house
	LmKit.block(k, "concrete", Vector3(0, 0.1, -9), Vector3(18, 3.6, 7), Color(0.93, 0.9, 0.82))
	LmKit.block(k, "plain", Vector3(0, 3.7, -9), Vector3(19, 0.4, 8), Color(0.45, 0.35, 0.25))
	# ayvan: raised wooden platform with carved columns and a roof
	var az := 1.0
	LmKit.block(k, "wood", Vector3(0, 0.1, az), Vector3(22, 0.8, 12), LmKit.WOOD)
	for i in 6:
		var x := -10.0 + i * 4.0
		for z: float in [az - 5.5, az + 5.5]:
			LmKit.cyl(k, "wood", Vector3(x, 0.9, z), 0.22, 0.18, 3.2, Color(0.5, 0.33, 0.2), 8, false)
			LmKit.ball(k, "wood", Vector3(x, 1.4, z), 0.3, Color(0.45, 0.3, 0.18), 8)       # carved bulge
			LmKit.block(k, "wood", Vector3(x, 3.8, z), Vector3(0.7, 0.35, 0.7), Color(0.45, 0.3, 0.18))
	LmKit.block(k, "wood", Vector3(0, 4.1, az), Vector3(23, 0.4, 13), Color(0.45, 0.3, 0.18))
	LmKit.block(k, "glossy", Vector3(0, 4.1, az + 6.52), Vector3(23, 0.4, 0.06), LmKit.TURQ)
	# tapchans (raised wooden beds) with low tables, red kurpacha cushions
	for i in 3:
		var p := Vector3(-7 + i * 7, 0.9, az)
		LmKit.block(d, "wood", p, Vector3(4.0, 0.5, 3.0), Color(0.5, 0.34, 0.2))
		LmKit.block(d, "plain", p + Vector3(0, 0.5, 0), Vector3(3.8, 0.12, 2.8), Color(0.7, 0.1, 0.12))
		LmKit.block(d, "wood", p + Vector3(0, 0.62, 0), Vector3(1.6, 0.3, 1.0), Color(0.35, 0.22, 0.12))
		LmKit.ball(d, "glossy", p + Vector3(0.3, 1.0, 0), 0.15, Color(0.95, 0.95, 0.95), 6)   # teapot
	# outdoor tapchans under a shade tree
	LmKit.tree(k, Vector3(12, 0.1, 9), 9.0, 4.0, 77, 0)
	LmKit.block(d, "wood", Vector3(12, 0.1, 9), Vector3(4, 0.6, 3), LmKit.WOOD)
	LmKit.light(lm, Vector3(0, 3.6, az), Color(1.0, 0.8, 0.55), 18.0, 2.0)
	LmKit.label(lm, Vector3(0, 4.7, az + 6.6), "ЧОЙХОНА", 90, Color(1, 0.9, 0.5))


static func _viewpoint(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	_slab(k, "gravel", 30, 22, Color(0.7, 0.68, 0.64))
	LmKit.parking_lot(k, Vector3(0, 0, 4), 26.0, 12.0)
	LmKit.block(k, "stone", Vector3(0, 0.1, -9), Vector3(30, 0.8, 4), Color(0.6, 0.55, 0.5))
	LmKit.railing(k, Vector3(-15, 0.9, -10.8), Vector3(15, 0.9, -10.8), 1.0)
	for i in 3:
		LmKit.bench(d, Vector3(-8 + i * 8, 0.9, -8.5), PI)
	k.cylinder("metal", LmKit.xf(Vector3(0, 0.9, -10)), 0.08, 0.08, 1.2, 6, LmKit.DARK, false)
	LmKit.block(k, "metal", Vector3(0, 2.1, -10), Vector3(0.5, 0.35, 0.7), Color(0.15, 0.4, 0.6))
	LmKit.label(lm, Vector3(0, 2.5, -7.0), "СМОТРОВАЯ ПЛОЩАДКА", 48, Color(1, 1, 1))


static func _tourist(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	_slab(k, "dirt", 80, 60, Color(0.55, 0.5, 0.38))
	# reception lodge
	LmKit.block(k, "wood", Vector3(0, 0.1, 18), Vector3(14, 3.6, 8), Color(0.62, 0.45, 0.28))
	LmKit.gable_roof(k, "tin", Vector3(0, 3.7, 18), 15.0, 9.5, 3.0, Color(0.2, 0.42, 0.3))
	# cabins
	for i in 6:
		var p := Vector3(-28 + (i % 3) * 28, 0.1, -16 + int(i / 3) * 18 - 4)
		LmKit.block(k, "wood", p, Vector3(7, 3.0, 6), Color(0.6, 0.42, 0.26))
		LmKit.gable_roof(k, "tin", p + Vector3(0, 3.0, 0), 8.0, 7.6, 2.8, Color(0.55, 0.15, 0.1))
		LmKit.block(k, "wood", p + Vector3(0, 0, 3.6), Vector3(5, 0.4, 1.4), LmKit.WOOD)
		LmKit.block(k, "glass", p + Vector3(1.6, 1.2, 3.02), Vector3(1.4, 1.0, 0.06), Color(0.3, 0.4, 0.5))
		LmKit.tree(k, p + Vector3(6, 0, 2), 10.0, 1.6, 900 + i, 1)
	# fire pit + benches
	LmKit.cyl(d, "stone", Vector3(14, 0.1, 4), 1.2, 1.2, 0.4, Color(0.5, 0.48, 0.45), 10)
	for a in 4:
		var ang := a * PI * 0.5
		LmKit.bench(d, Vector3(14, 0.1, 4) + Vector3(cos(ang), 0, sin(ang)) * 3.0, -ang + PI * 0.5)
	LmKit.label(lm, Vector3(0, 4.4, 22.1), "ТУРБАЗА «ВАРЗОБ»", 70, Color(1, 0.95, 0.75))


static func _market(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	_slab(k, "paving", 80, 56, Color(0.72, 0.68, 0.62))
	var cols := [Color(0.85, 0.15, 0.15), Color(0.1, 0.45, 0.8), Color(0.95, 0.75, 0.1), Color(0.15, 0.6, 0.3), Color(0.9, 0.45, 0.1)]
	var fruit := [Color(0.95, 0.55, 0.1), Color(0.8, 0.1, 0.1), Color(0.95, 0.85, 0.2), Color(0.4, 0.7, 0.2), Color(0.55, 0.2, 0.45)]
	for row in 3:
		for i in 8:
			var p := Vector3(-30 + i * 8.5, 0.1, -18 + row * 14)
			LmKit.block(d, "wood", p, Vector3(5.0, 0.9, 2.2), LmKit.WOOD)
			for f in 6:
				LmKit.ball(d, "plain", p + Vector3(-2.0 + f * 0.8, 1.05, 0.2 * (f % 2)), 0.32, fruit[(f + i + row) % fruit.size()], 6)
			for sx: float in [-2.4, 2.4]:
				k.cylinder("metal", LmKit.xf(p + Vector3(sx, 0, -1.0)), 0.06, 0.06, 2.8, 5, LmKit.DARK, false)
				k.cylinder("metal", LmKit.xf(p + Vector3(sx, 0, 1.2)), 0.06, 0.06, 2.3, 5, LmKit.DARK, false)
			k.quad("awning", p + Vector3(-2.7, 2.3, 1.6), p + Vector3(2.7, 2.3, 1.6), p + Vector3(2.7, 2.85, -1.3), p + Vector3(-2.7, 2.85, -1.3), cols[(i + row * 2) % cols.size()])
	# gate arch
	LmKit.portal(k, "stone", Vector3(0, 0.1, 25), 14.0, 8.0, 1.2, 8.0, 6.5, Color(0.9, 0.84, 0.72))
	LmKit.block(k, "glossy", Vector3(0, 6.6, 25.62), Vector3(12, 1.0, 0.05), LmKit.TURQ)
	LmKit.label(lm, Vector3(0, 7.1, 25.7), "БОЗОР", 100, Color(1, 1, 1))


static func _shop(k: MeshKit, lm: Dictionary) -> void:
	_slab(k, "concrete", 18, 14, Color(0.6, 0.6, 0.6))
	LmKit.block(k, "concrete", Vector3(0, 0.1, -1), Vector3(10, 3.4, 7), Color(0.92, 0.9, 0.84))
	LmKit.block(k, "plain", Vector3(0, 3.5, -1), Vector3(11, 0.3, 8), Color(0.35, 0.35, 0.38))
	LmKit.block(k, "glass", Vector3(-1.5, 0.5, 2.52), Vector3(4.5, 2.2, 0.08), Color(0.35, 0.45, 0.5))
	LmKit.block(k, "wood", Vector3(2.8, 0.1, 2.52), Vector3(1.4, 2.4, 0.1), Color(0.4, 0.25, 0.15))
	LmKit.block(k, "glossy", Vector3(0, 2.8, 2.55), Vector3(9, 0.7, 0.12), Color(0.15, 0.35, 0.7))
	k.quad("awning", Vector3(-5, 2.6, 4.5), Vector3(5, 2.6, 4.5), Vector3(5, 3.3, 2.6), Vector3(-5, 3.3, 2.6), Color(0.15, 0.45, 0.75))
	LmKit.label(lm, Vector3(0, 2.8, 2.65), "МАГАЗИН · ДӮКОН", 44, Color(1, 1, 1))
