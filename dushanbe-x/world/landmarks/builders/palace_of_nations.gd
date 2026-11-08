extends RefCounted
## Palace of Nations (Kohi Millat): long white neoclassical palace, full colonnade,
## central drum ringed by columns and a big golden dome, stairs and front garden with fountain.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	var w := 150.0
	var dep := 56.0
	var h := 22.0
	var zc := -20.0            # building centre (front garden towards +Z)
	var white := LmKit.MARBLE
	# podium + main body
	LmKit.block(k, "marble", Vector3(0, -2.0, zc), Vector3(w + 8, 4.0, dep + 8), Color(0.85, 0.83, 0.78))
	LmKit.block(k, "marble", Vector3(0, 2.0, zc), Vector3(w, h, dep), white)
	# side pavilions slightly higher
	for sx: float in [-1.0, 1.0]:
		LmKit.block(k, "marble", Vector3(sx * (w * 0.5 - 12), 2.0, zc + 2), Vector3(24, h + 4, dep + 4), white)
		LmKit.cornice(k, "marble", Vector3(sx * (w * 0.5 - 12), 2.0 + h + 4, zc + 2), 25, dep + 5, white)
	LmKit.cornice(k, "marble", Vector3(0, 2.0 + h, zc), w + 1, dep + 1, white)
	# front colonnade (portico) with roof slab
	var fz := zc + dep * 0.5 + 6.0
	LmKit.colonnade(k, "marble", Vector3(-w * 0.5 + 28, 2.0, fz), Vector3(w * 0.5 - 28, 2.0, fz), 22, 0.9, h - 2.0, white)
	LmKit.block(k, "marble", Vector3(0, h, fz - 3.0), Vector3(w - 52, 2.0, 8.0), white)
	LmKit.block(k, "marble", Vector3(0, 2.0, fz - 1.0), Vector3(w - 52, 0.4, 10.0), Color(0.8, 0.78, 0.74))
	# central projecting portico with pediment
	LmKit.colonnade(k, "marble", Vector3(-12, 2.0, fz + 6), Vector3(12, 2.0, fz + 6), 6, 1.1, h, white)
	LmKit.block(k, "marble", Vector3(0, h + 2.0, fz + 2), Vector3(30, 2.0, 12), white)
	LmKit.pediment(k, "marble", Vector3(0, h + 4.0, fz + 2), 30.0, 6.0, 12.0, white)
	LmKit.block(k, "gold", Vector3(0, h + 5.2, fz + 8.1), Vector3(4, 2.0, 0.3), LmKit.GOLDC)   # emblem
	# windows on facade behind the columns (two floors)
	var t := LmKit.xf(Vector3(0, 2.0, zc + dep * 0.5))
	LmKit.windows(k, t, -w * 0.5 + 26, w * 0.5 - 26, 1.0, 2, 24, 9.0, 1.8, 5.5, 0.0, Color(0.25, 0.3, 0.38))
	# central drum with columns and golden dome
	var dc := Vector3(0, 2.0 + h, zc)
	LmKit.cyl(k, "marble", dc, 18.0, 18.0, 2.0, white, 40)
	LmKit.cyl(k, "marble", dc + Vector3(0, 2, 0), 14.0, 14.0, 10.0, white, 36)
	for i in 20:
		var a := TAU * i / 20.0
		LmKit.column(k, "marble", dc + Vector3(cos(a) * 15.5, 2.0, sin(a) * 15.5), 0.6, 10.0, white, 8)
	LmKit.cyl(k, "marble", dc + Vector3(0, 12, 0), 16.5, 16.0, 1.4, white, 40)
	LmKit.dome(k, "gold", dc + Vector3(0, 13.4, 0), 14.5, LmKit.GOLDC, 36, 0.92)
	LmKit.cyl(k, "gold", dc + Vector3(0, 26.4, 0), 2.2, 2.0, 3.0, LmKit.GOLDC, 12)
	LmKit.dome(k, "gold", dc + Vector3(0, 29.4, 0), 2.2, LmKit.GOLDC, 12)
	LmKit.cyl(k, "metal", dc + Vector3(0, 31.5, 0), 0.12, 0.08, 9.0, Color(0.9, 0.9, 0.9), 6)
	# small flag on the dome
	var ft := dc + Vector3(0.1, 38.0, 0)
	for b in [[0.0, 0.857, Color(0, 0.48, 0.2)], [0.857, 2.143, Color(0.98, 0.98, 0.98)], [2.143, 3.0, Color(0.82, 0.06, 0.08)]]:
		k.quad("plain2", ft + Vector3(0, b[0], 0), ft + Vector3(6, b[0], 0), ft + Vector3(6, b[1], 0), ft + Vector3(0, b[1], 0), b[2])
	# stairs to the portico
	LmKit.stairs(k, "marble", Vector3(0, -0.2, fz + 18.0), 40.0, 9.0, 2.2, 8, Color(0.88, 0.86, 0.82))
	# front garden: lawns, central fountain, trees, fence
	var gz := fz + 36.0
	LmKit.pave(k, "paving", Vector3(0, 0, gz), Vector2(60, 36), Color(0.86, 0.82, 0.76))
	LmKit.fountain(k, Vector3(0, 0, gz), 10.0, LmKit.MARBLE, 2)
	for sx: float in [-1.0, 1.0]:
		LmKit.lawn(k, Vector3(sx * 55, 0, gz), Vector2(48, 36))
		for i in 4:
			LmKit.tree(k, Vector3(sx * (40 + i * 10), 0.1, gz - 10), 8.0, 2.4, 700 + i * 3 + int(sx), 1)
			LmKit.flower_bed(d, Vector3(sx * (40 + i * 10), 0, gz + 8), Vector2(6, 3), 800 + i, 0.0)
	var fence_z: float = minf(lm["hz"] - 3.0, gz + 20.0)
	LmKit.railing(d, Vector3(-75, 0, fence_z), Vector3(-10, 0, fence_z), 2.2, Color(0.85, 0.7, 0.3))
	LmKit.railing(d, Vector3(10, 0, fence_z), Vector3(75, 0, fence_z), 2.2, Color(0.85, 0.7, 0.3))
	LmKit.label(lm, Vector3(0, h + 1.0, fz + 8.3), "КОХИ МИЛЛАТ", 80, Color(1, 0.85, 0.4))
