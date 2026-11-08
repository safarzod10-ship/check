extends RefCounted
## Safedi Varzob viewpoint: concrete platform overhanging the slope with railings,
## coin binoculars, benches, a shaded pavilion and a small car park.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	var c := Color(0.75, 0.74, 0.72)
	# platform on pillars (front edge projects over the slope)
	LmKit.block(k, "concrete", Vector3(0, -0.5, 14), Vector3(40, 1.2, 22), c)
	for sx: float in [-15.0, -5.0, 5.0, 15.0]:
		LmKit.block(k, "concrete", Vector3(sx, -12.0, 23), Vector3(1.2, 11.5, 1.2), c.darkened(0.1))
	LmKit.railing(k, Vector3(-20, 0.7, 25), Vector3(20, 0.7, 25), 1.1, Color(0.2, 0.25, 0.3))
	LmKit.railing(k, Vector3(-20, 0.7, 4), Vector3(-20, 0.7, 25), 1.1, Color(0.2, 0.25, 0.3))
	LmKit.railing(k, Vector3(20, 0.7, 4), Vector3(20, 0.7, 25), 1.1, Color(0.2, 0.25, 0.3))
	for sx: float in [-8.0, 8.0]:
		k.cylinder("metal", LmKit.xf(Vector3(sx, 0.7, 23)), 0.08, 0.08, 1.2, 6, LmKit.DARK, false)
		LmKit.block(k, "metal", Vector3(sx, 1.9, 23), Vector3(0.5, 0.35, 0.7), Color(0.15, 0.4, 0.6))
	for i in 4:
		LmKit.bench(d, Vector3(-12 + i * 8, 0.7, 18), PI)
	# pavilion
	var pc := Vector3(0, 0.7, 8)
	for sx: float in [-4.0, 4.0]:
		for sz: float in [-3.0, 3.0]:
			LmKit.cyl(k, "wood", pc + Vector3(sx, 0, sz), 0.2, 0.2, 3.0, LmKit.WOOD, 8, false)
	LmKit.hip_roof(k, "tin", pc + Vector3(0, 3.0, 0), 10.0, 8.0, 2.0, Color(0.25, 0.45, 0.55))
	LmKit.parking_lot(k, Vector3(0, 0, -14), 36.0, 18.0)
	LmKit.label(lm, Vector3(0, 2.2, 25.2), "САФЕДИ ВАРЗОБ · СМОТРОВАЯ ПЛОЩАДКА", 56, Color(1, 1, 1), PI)
