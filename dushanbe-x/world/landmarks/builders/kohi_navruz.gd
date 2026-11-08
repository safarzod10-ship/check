extends RefCounted
## Kohi Navruz: richly ornamented palace — grand central iwan, two flanking towers,
## arcades of smaller iwans along the facade, large ribbed turquoise dome and four golden domes,
## plaza with fountains and stone edging of the pond in front.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	var cream := Color(0.96, 0.9, 0.78)
	var w := 150.0
	var dep := 70.0
	var h := 20.0
	var zc := -30.0
	LmKit.block(k, "stone", Vector3(0, -2.0, zc), Vector3(w + 10, 4.0, dep + 10), Color(0.82, 0.76, 0.68))
	LmKit.block(k, "stone", Vector3(0, 2.0, zc - 4), Vector3(w, h, dep - 8), cream)
	# arcade of iwans along the front, both sides of the central portal
	var fz := zc + dep * 0.5 - 4.0
	for sx: float in [-1.0, 1.0]:
		for i in 6:
			var x := sx * (24.0 + i * 8.5)
			LmKit.iwan(k, "stone", Vector3(x, 2.0, fz + 1.0), 8.5, h - 4.0, 5.0, 11.0, 3.0, cream, LmKit.BLUE_TILE)
		LmKit.block(k, "stone", Vector3(sx * 47.5, 2.0 + h - 4.0, fz + 1.0), Vector3(51, 4.0, 2.0), cream)
		k.box("glossy", LmKit.xf(Vector3(sx * 47.5, 2.0 + h - 2.0, fz + 2.06)), Vector3.ZERO, Vector3(50, 1.2, 0.12), LmKit.TURQ)
	# grand central iwan (taller than the body)
	LmKit.iwan(k, "stone", Vector3(0, 2.0, fz + 3.0), 40.0, h + 14.0, 20.0, h + 6.0, 10.0, cream, LmKit.BLUE_TILE)
	LmKit.block(k, "gold", Vector3(0, 2.0 + h + 11.0, fz + 4.1), Vector3(30, 1.6, 0.3), LmKit.GOLDC)
	for sx: float in [-1.0, 1.0]:
		# guldasta towers at the corners of the central portal
		var tb := Vector3(sx * 21.0, 2.0, fz + 3.0)
		LmKit.cyl(k, "stone", tb, 2.6, 2.2, h + 16.0, cream, 16, false)
		k.cylinder("glossy", LmKit.xf(tb + Vector3(0, h + 4.0, 0)), 2.35, 2.3, 4.0, 16, LmKit.TURQ, false)
		LmKit.cyl(k, "stone", tb + Vector3(0, h + 16.0, 0), 3.0, 3.0, 1.0, cream, 16)
		LmKit.onion(k, "gold", tb + Vector3(0, h + 17.0, 0), 2.4, 5.5, LmKit.GOLDC, 16)
		# corner domes
		for sz: float in [-1.0, 1.0]:
			var dc := Vector3(sx * (w * 0.5 - 12), 2.0 + h, zc - 4 + sz * (dep * 0.5 - 16))
			LmKit.cyl(k, "stone", dc, 7.0, 7.0, 4.0, cream, 24)
			LmKit.onion(k, "gold", dc + Vector3(0, 4.0, 0), 6.5, 10.0, LmKit.GOLDC, 24)
	# central ribbed turquoise dome on a high drum
	var cd := Vector3(0, 2.0 + h, zc - 8)
	LmKit.cyl(k, "stone", cd, 17.0, 17.0, 3.0, cream, 40)
	k.cylinder("glossy", LmKit.xf(cd + Vector3(0, 3.0, 0)), 15.0, 15.0, 7.0, 40, LmKit.BLUE_TILE, false)
	for i in 16:
		var a := TAU * i / 16.0
		LmKit.box(k, "stone", cd + Vector3(cos(a) * 15.2, 6.0, sin(a) * 15.2), Vector3(1.2, 6.0, 1.2), cream, -a)
	LmKit.onion(k, "glossy", cd + Vector3(0, 10.0, 0), 15.5, 26.0, LmKit.TURQ, 40)
	LmKit.cyl(k, "gold", cd + Vector3(0, 35.5, 0), 0.6, 0.2, 5.0, LmKit.GOLDC, 8)
	LmKit.ball(k, "gold", cd + Vector3(0, 38.0, 0), 0.9, LmKit.GOLDC, 8)
	# parapet with crenellation pattern
	for i in 40:
		var x := lerpf(-w * 0.5 + 2, w * 0.5 - 2, i / 39.0)
		LmKit.block(k, "stone", Vector3(x, 2.0 + h, zc - 4 + (dep - 8) * 0.5), Vector3(1.6, 1.6, 0.8), cream)
	# front plaza with fountains and the pond edging (pond water itself = water system)
	var pz := fz + 12.0
	var plaza_d: float = lm["hz"] - pz
	LmKit.pave(k, "paving", Vector3(0, 0, pz + plaza_d * 0.5), Vector2(w, plaza_d), Color(0.88, 0.84, 0.78))
	for sx: float in [-1.0, 0.0, 1.0]:
		LmKit.fountain(k, Vector3(sx * 40.0, 0.05, pz + plaza_d * 0.5), 7.0 if sx == 0.0 else 5.0, LmKit.MARBLE, 2)
	for i in 12:
		var x := lerpf(-w * 0.5 + 6, w * 0.5 - 6, i / 11.0)
		LmKit.lamp(d, Vector3(x, 0.05, pz + 4), 5.5, true)
		LmKit.tree(k, Vector3(x, 0.1, lm["hz"] - 6.0), 8.0, 2.0, 3100 + i, 1)
	# stone edging of the pond in front (pond centre is ~160 m in front of the palace)
	var pond_z := 160.0
	for i in 32:
		var a := TAU * i / 32.0
		LmKit.box(k, "stone", Vector3(cos(a) * 41.0, 0.3, pond_z + sin(a) * 41.0), Vector3(8.4, 0.8, 1.4), Color(0.85, 0.82, 0.76), -a + PI * 0.5)
	LmKit.label(lm, Vector3(0, 2.0 + h + 8.6, fz + 4.3), "КОХИ НАВРӮЗ", 110, Color(1, 0.85, 0.4))
