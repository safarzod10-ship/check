extends RefCounted
## Ayni Opera and Ballet Theatre: peach neoclassical theatre with a column portico and
## pediment, arched windows, stage fly-tower behind and a fountain square in front.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	var peach := LmKit.PEACH
	var trim := Color(0.97, 0.94, 0.88)
	var w := 64.0
	var dep := 72.0
	var zc := -18.0
	var h := 18.0
	LmKit.block(k, "stone", Vector3(0, -1.5, zc), Vector3(w + 4, 3.0, dep + 4), Color(0.8, 0.74, 0.66))
	LmKit.block(k, "concrete", Vector3(0, 1.5, zc), Vector3(w, h, dep), peach)
	LmKit.cornice(k, "concrete", Vector3(0, 1.5 + h, zc), w + 1, dep + 1, trim)
	LmKit.block(k, "concrete", Vector3(0, 1.5, zc - 14), Vector3(w * 0.7, h + 10, 26), peach.darkened(0.05))   # fly tower
	LmKit.cornice(k, "concrete", Vector3(0, 1.5 + h + 10, zc - 14), w * 0.7 + 1, 27, trim)
	# arched windows on the sides (approximated: tall windows + round top)
	for sx: float in [-1.0, 1.0]:
		var t := Transform3D(Basis(Vector3.UP, sx * PI * 0.5), Vector3(sx * w * 0.5, 1.5, zc))
		for i in 8:
			var z := lerpf(-dep * 0.4, dep * 0.4, i / 7.0)
			k.box("glass", t, Vector3(z, 7.0, 0.05), Vector3(2.4, 6.0, 0.12), Color(0.25, 0.3, 0.36))
			k.cylinder("glass", t * Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(z, 10.0, 0.0)), 1.2, 1.2, 0.12, 10, Color(0.25, 0.3, 0.36), true, true)
			k.box("concrete", t, Vector3(z, 3.6, 0.2), Vector3(3.2, 0.3, 0.4), trim)
	# portico: 8 columns, entablature, pediment
	var pz := zc + dep * 0.5 + 6.0
	LmKit.block(k, "stone", Vector3(0, 1.5, pz - 2), Vector3(44, 0.6, 14), trim)
	LmKit.colonnade(k, "marble", Vector3(-18, 2.1, pz + 3), Vector3(18, 2.1, pz + 3), 8, 0.95, 14.0, trim)
	LmKit.block(k, "concrete", Vector3(0, 16.1, pz - 2), Vector3(44, 2.6, 14), trim)
	LmKit.pediment(k, "concrete", Vector3(0, 18.7, pz - 2), 44.0, 7.0, 14.0, trim)
	LmKit.pediment(k, "concrete", Vector3(0, 18.9, pz - 1.5), 40.0, 6.0, 13.6, peach)
	LmKit.block(k, "gold", Vector3(0, 19.5, pz + 5.25), Vector3(6, 3.0, 0.4), LmKit.GOLDC)     # lyre emblem
	var tf := LmKit.xf(Vector3(0, 1.5, zc + dep * 0.5))
	LmKit.windows(k, tf, -16, 16, 1.0, 2, 5, 6.5, 2.2, 4.0, 0.0, Color(0.3, 0.32, 0.38), trim)
	LmKit.stairs(k, "stone", Vector3(0, -0.2, pz + 10), 44.0, 6.0, 2.1, 7, trim)
	# fountain square
	var fz := pz + 26.0
	LmKit.pave(k, "paving", Vector3(0, 0, fz), Vector2(70, 36), Color(0.86, 0.82, 0.76))
	LmKit.fountain(k, Vector3(0, 0, fz), 9.0, LmKit.MARBLE, 3)
	for sx: float in [-1.0, 1.0]:
		LmKit.flower_bed(d, Vector3(sx * 24, 0, fz), Vector2(12, 6), 2000 + int(sx), 0.0)
		for i in 4:
			LmKit.lamp(d, Vector3(sx * 33, 0.05, fz - 15 + i * 10), 5.5, true)
			LmKit.tree(k, Vector3(sx * 40, 0.1, zc + i * 16 - 20), 9.0, 3.0, 2100 + i + int(sx) * 10, 1)
	LmKit.light(lm, Vector3(0, 0.5, fz + 10), Color(1.0, 0.85, 0.6), 70.0, 5.0, "spot", Vector3(0, 14, pz))
	LmKit.label(lm, Vector3(0, 16.0, pz + 4.6), "ТЕАТРИ ОПЕРА ВА БАЛЕТ БА НОМИ С. АЙНӢ", 64, Color(1, 0.88, 0.5))
