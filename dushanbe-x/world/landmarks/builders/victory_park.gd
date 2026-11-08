extends RefCounted
## Victory Park memorial on the hill: raised granite terrace reached by monumental stairs,
## a 32 m stele, the eternal flame, a curved memorial wall with bronze reliefs, tree-lined esplanade.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	var granite := Color(0.5, 0.42, 0.4)
	var light := Color(0.85, 0.82, 0.78)
	LmKit.pave(k, "paving", Vector3(0, 0, 0), Vector2(110, 120), light, 0.0, 0.08, 1.4)
	var ty := 2.08
	LmKit.block(k, "stone", Vector3(0, -1.0, -14), Vector3(76, ty + 1.0, 62), granite.lightened(0.15))
	LmKit.stairs(k, "stone", Vector3(0, 0.0, 24.0), 30.0, 7.0, ty, 9, light)
	# stele
	LmKit.block(k, "stone", Vector3(0, ty, -30), Vector3(14, 2.0, 14), granite)
	LmKit.cyl(k, "stone", Vector3(0, ty + 2.0, -30), 3.6, 1.2, 32.0, light, 4, false)
	LmKit.cyl(k, "gold", Vector3(0, ty + 34.0, -30), 1.2, 0.0, 3.0, LmKit.GOLDC, 4, false)
	# memorial wall (curved, behind the stele)
	for i in 15:
		var a := PI * (0.15 + 0.7 * i / 14.0)
		var p := Vector3(cos(a) * 30.0, ty, -38.0 - sin(a) * 6.0)
		LmKit.block(k, "stone", p, Vector3(4.4, 6.0, 1.6), granite, (a - PI * 0.5) * 0.4)
		LmKit.block(k, "glossy", p + Vector3(0, 2.0, 0.1), Vector3(3.4, 2.6, 1.7), LmKit.BRONZE, (a - PI * 0.5) * 0.4)
	# eternal flame
	var fc := Vector3(0, ty, 2)
	LmKit.cyl(k, "stone", fc, 4.0, 4.0, 0.8, granite, 5)
	LmKit.cyl(k, "metal", fc + Vector3(0, 0.8, 0), 1.6, 2.2, 0.8, LmKit.BRONZE, 10)
	k.cylinder("lamp_always", LmKit.xf(fc + Vector3(0, 1.6, 0)), 1.0, 0.1, 2.0, 8, Color(1.0, 0.5, 0.1), false, false)
	k.cylinder("lamp_always", LmKit.xf(fc + Vector3(0.2, 1.6, 0.1)), 0.6, 0.0, 2.8, 6, Color(1.0, 0.75, 0.2), false, false)
	for i in 10:
		var z := -50.0 + i * 11.0
		for sx: float in [-1.0, 1.0]:
			LmKit.tree(k, Vector3(sx * 46, 0.1, z), 12.0, 1.6, 7100 + i + int(sx) * 13, 1)
			if i % 2 == 0:
				LmKit.lamp(d, Vector3(sx * 40, 0.08, z), 5.0)
	LmKit.label(lm, Vector3(0, ty + 1.4, -22.9), "1941 — 1945", 96, Color(1, 0.85, 0.4))
