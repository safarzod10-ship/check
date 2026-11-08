extends RefCounted
## National Museum of Tajikistan: long white modern-classical building, square-pillar
## colonnade over blue glass, raised central hall, wide stairs and a reflecting pool.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	var w := 190.0
	var dep := 46.0
	var h := 20.0
	var zc := -14.0
	var white := Color(0.95, 0.94, 0.9)
	LmKit.block(k, "marble", Vector3(0, -2.0, zc), Vector3(w + 6, 4.0, dep + 14), Color(0.86, 0.84, 0.8))
	# glass core
	LmKit.block(k, "glass", Vector3(0, 2.0, zc - 2), Vector3(w - 10, h - 2, dep - 10), Color(0.2, 0.38, 0.55))
	# outer frame: roof slab, end walls
	LmKit.block(k, "marble", Vector3(0, 2.0 + h - 2, zc), Vector3(w, 3.0, dep + 6), white)
	for sx: float in [-1.0, 1.0]:
		LmKit.block(k, "marble", Vector3(sx * (w * 0.5 - 4), 2.0, zc), Vector3(8, h, dep + 6), white)
	# square pillars (front & back)
	for i in 30:
		var x := lerpf(-w * 0.5 + 10, w * 0.5 - 10, i / 29.0)
		LmKit.block(k, "marble", Vector3(x, 2.0, zc + dep * 0.5 + 1), Vector3(1.6, h - 2, 1.6), white)
		LmKit.block(k, "marble", Vector3(x, 2.0, zc - dep * 0.5 - 1), Vector3(1.6, h - 2, 1.6), white)
	# raised central hall with a gilded attic band
	LmKit.block(k, "marble", Vector3(0, 2.0 + h + 1, zc), Vector3(56, 9, 30), white)
	LmKit.block(k, "gold", Vector3(0, 2.0 + h + 7.5, zc + 15.1), Vector3(50, 1.2, 0.3), LmKit.GOLDC)
	LmKit.block(k, "glass", Vector3(0, 2.0 + h + 2, zc + 15.05), Vector3(48, 4.0, 0.2), Color(0.25, 0.45, 0.6))
	# entrance canopy
	LmKit.block(k, "marble", Vector3(0, 9.0, zc + dep * 0.5 + 6), Vector3(36, 1.2, 10), white)
	for sx: float in [-1.0, 1.0]:
		LmKit.column(k, "marble", Vector3(sx * 16, 2.0, zc + dep * 0.5 + 10), 0.7, 7.0, white)
	LmKit.stairs(k, "marble", Vector3(0, -0.2, zc + dep * 0.5 + 22), 70.0, 10.0, 2.2, 8, Color(0.88, 0.86, 0.82))
	# reflecting pools on both sides of the stairs
	for sx: float in [-1.0, 1.0]:
		var pc := Vector3(sx * 62, 0, zc + dep * 0.5 + 20)
		LmKit.block(k, "marble", pc + Vector3(0, -0.2, 0), Vector3(46, 0.7, 14), white)
		k.box("lm_water", LmKit.xf(pc + Vector3(0, 0.52, 0)), Vector3.ZERO, Vector3(44, 0.02, 12), Color(0.3, 0.55, 0.7))
		for i in 4:
			LmKit.lamp(d, pc + Vector3(-18 + i * 12, 0.1, 9), 5.0)
	LmKit.label(lm, Vector3(0, 10.4, zc + dep * 0.5 + 11.1), "ОСОРХОНАИ МИЛЛИИ ТОҶИКИСТОН", 72, Color(1, 0.85, 0.4))
