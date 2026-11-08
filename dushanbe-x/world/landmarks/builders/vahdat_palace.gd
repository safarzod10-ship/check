extends RefCounted
## Vahdat Palace (Kohi Vahdat): large modern palace with a monumental portico, a big
## white-and-gold dome on a drum, wide ceremonial stairs and flanking wings.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	var cream := Color(0.95, 0.92, 0.86)
	var w := 150.0
	var dep := 76.0
	var h := 26.0
	var zc := -20.0
	LmKit.block(k, "marble", Vector3(0, -2.0, zc), Vector3(w + 10, 5.0, dep + 10), Color(0.84, 0.8, 0.74))
	LmKit.block(k, "marble", Vector3(0, 3.0, zc), Vector3(w * 0.6, h, dep), cream)
	for sx: float in [-1.0, 1.0]:
		LmKit.block(k, "marble", Vector3(sx * w * 0.38, 3.0, zc + 4), Vector3(w * 0.25, h - 6, dep - 16), cream)
		var tw := LmKit.xf(Vector3(sx * w * 0.38, 3.0, zc + 4 + (dep - 16) * 0.5))
		LmKit.windows(k, tw, -w * 0.1, w * 0.1, 0.5, 4, 7, 4.8, 2.0, 3.2, 0.0, Color(0.32, 0.4, 0.5))
		LmKit.cornice(k, "marble", Vector3(sx * w * 0.38, 3.0 + h - 6, zc + 4), w * 0.25 + 1, dep - 15, cream)
	LmKit.cornice(k, "marble", Vector3(0, 3.0 + h, zc), w * 0.6 + 1, dep + 1, cream)
	# portico
	var pz := zc + dep * 0.5 + 7.0
	LmKit.colonnade(k, "marble", Vector3(-30, 3.0, pz + 4), Vector3(30, 3.0, pz + 4), 12, 1.2, h - 1.0, cream)
	LmKit.block(k, "marble", Vector3(0, 2.0 + h, pz), Vector3(66, 3.0, 14), cream)
	LmKit.block(k, "gold", Vector3(0, 2.6 + h, pz + 7.05), Vector3(64, 1.0, 0.25), LmKit.GOLDC)
	LmKit.block(k, "glass", Vector3(0, 3.0, zc + dep * 0.5 + 0.1), Vector3(56, h - 4, 0.3), Color(0.35, 0.42, 0.5))
	# dome
	var dc := Vector3(0, 3.0 + h, zc - 6)
	LmKit.cyl(k, "marble", dc, 22.0, 22.0, 3.0, cream, 48)
	LmKit.cyl(k, "marble", dc + Vector3(0, 3, 0), 18.0, 18.0, 9.0, cream, 44)
	for i in 24:
		var a := TAU * i / 24.0
		LmKit.box(k, "glass", dc + Vector3(cos(a) * 18.05, 7.5, sin(a) * 18.05), Vector3(2.0, 6.0, 0.3), Color(0.3, 0.4, 0.5), -a + PI * 0.5)
	LmKit.dome(k, "marble", dc + Vector3(0, 12, 0), 18.5, Color(0.96, 0.96, 0.96), 44, 0.85)
	for i in 12:
		var a := TAU * i / 12.0
		var b := Basis(Vector3.UP, -a)
		k.box("gold", Transform3D(b, dc + Vector3(cos(a) * 12.0, 23.0, sin(a) * 12.0)), Vector3.ZERO, Vector3(0.6, 8.0, 0.6), LmKit.GOLDC)
	LmKit.dome(k, "gold", dc + Vector3(0, 27.4, 0), 4.0, LmKit.GOLDC, 16)
	LmKit.cyl(k, "gold", dc + Vector3(0, 31.0, 0), 0.4, 0.1, 6.0, LmKit.GOLDC, 6)
	# ceremonial stairs and square
	LmKit.stairs(k, "marble", Vector3(0, -0.2, pz + 20), 80.0, 12.0, 3.2, 10, Color(0.88, 0.86, 0.82))
	var sq_z := pz + 20.0 + 18.0
	LmKit.pave(k, "paving", Vector3(0, 0, sq_z), Vector2(w, 36), Color(0.86, 0.82, 0.76))
	for sx: float in [-1.0, 1.0]:
		LmKit.fountain(k, Vector3(sx * 38, 0.05, sq_z), 7.0, LmKit.MARBLE, 2)
		for i in 5:
			LmKit.lamp(d, Vector3(sx * (12 + i * 14), 0.05, sq_z + 15), 6.0, true)
	LmKit.label(lm, Vector3(0, 2.0 + h - 1.0, pz + 7.3), "КОХИ ВАҲДАТ", 110, Color(1, 0.85, 0.4))
