extends RefCounted
## Tajik National University main building: Stalinist neoclassical block with a central
## tower and spire, columned portico, symmetrical wings and a front square.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	var beige := Color(0.92, 0.82, 0.66)
	var trim := Color(0.97, 0.94, 0.88)
	var w := 170.0
	var dep := 22.0
	var h := 22.0
	var zc := -30.0
	LmKit.block(k, "stone", Vector3(0, -1.5, zc), Vector3(w + 4, 3.0, dep + 4), Color(0.7, 0.62, 0.55))
	LmKit.block(k, "concrete", Vector3(0, 1.5, zc), Vector3(w, h, dep), beige)
	LmKit.cornice(k, "concrete", Vector3(0, 1.5 + h, zc), w + 1, dep + 1, trim)
	# end wings coming forward
	for sx: float in [-1.0, 1.0]:
		LmKit.block(k, "concrete", Vector3(sx * (w * 0.5 - 10), 1.5, zc + 18), Vector3(20, h, 36), beige)
		LmKit.cornice(k, "concrete", Vector3(sx * (w * 0.5 - 10), 1.5 + h, zc + 18), 21, 37, trim)
		var tw := LmKit.xf(Vector3(sx * (w * 0.5 - 10), 1.5, zc + 36))
		LmKit.windows(k, tw, -7, 7, 1.0, 5, 3, 4.0, 1.6, 2.4, 0.0, Color(0.25, 0.3, 0.36), trim)
	var tf := LmKit.xf(Vector3(0, 1.5, zc + dep * 0.5))
	LmKit.windows(k, tf, -w * 0.5 + 22, -14, 1.0, 5, 12, 4.0, 1.6, 2.4, 0.0, Color(0.25, 0.3, 0.36), trim)
	LmKit.windows(k, tf, 14, w * 0.5 - 22, 1.0, 5, 12, 4.0, 1.6, 2.4, 0.0, Color(0.25, 0.3, 0.36), trim)
	# central tower with clock and spire
	var tb := Vector3(0, 1.5, zc)
	LmKit.block(k, "concrete", tb, Vector3(26, h + 18, 26), beige)
	LmKit.cornice(k, "concrete", tb + Vector3(0, h + 18, 0), 27, 27, trim)
	LmKit.block(k, "concrete", tb + Vector3(0, h + 18.5, 0), Vector3(16, 9, 16), beige.lightened(0.05))
	k.cylinder("plain", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), tb + Vector3(0, h + 12, 13.35)), 3.2, 3.2, 0.3, 24, trim, true, true)
	LmKit.block(k, "metal", tb + Vector3(0, h + 11.8, 13.6), Vector3(0.3, 2.4, 0.2), LmKit.DARK)
	LmKit.block(k, "metal", tb + Vector3(0.8, h + 12.0, 13.6), Vector3(1.8, 0.3, 0.2), LmKit.DARK)
	LmKit.cyl(k, "gold", tb + Vector3(0, h + 27.5, 0), 6.0, 0.4, 16.0, LmKit.GOLDC, 8, false)
	# portico
	var pz := zc + dep * 0.5 + 6.0
	LmKit.colonnade(k, "marble", Vector3(-12, 1.5, pz + 3), Vector3(12, 1.5, pz + 3), 6, 1.0, 16.0, trim)
	LmKit.block(k, "concrete", Vector3(0, 17.5, pz), Vector3(28, 2.4, 10), trim)
	LmKit.pediment(k, "concrete", Vector3(0, 19.9, pz), 28.0, 5.0, 10.0, trim)
	LmKit.stairs(k, "stone", Vector3(0, -0.2, pz + 12), 34.0, 6.0, 1.7, 6, trim)
	# square with lawns and trees
	var sz := pz + 30.0
	LmKit.pave(k, "paving", Vector3(0, 0, sz), Vector2(40, 34), Color(0.86, 0.82, 0.76))
	for sx: float in [-1.0, 1.0]:
		LmKit.lawn(k, Vector3(sx * 55, 0, sz), Vector2(60, 34))
		for i in 5:
			LmKit.tree(k, Vector3(sx * (34 + i * 10), 0.1, sz), 10.0, 3.0, 5100 + i + int(sx) * 9, 0)
			LmKit.lamp(d, Vector3(sx * 21, 0.05, sz - 14 + i * 7), 5.0)
	LmKit.label(lm, Vector3(0, 18.0, pz + 5.2), "ДОНИШГОҲИ МИЛЛИИ ТОҶИКИСТОН", 64, Color(1, 0.9, 0.55))
