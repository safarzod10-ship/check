extends RefCounted
## Dusti (Friendship) Square: large paved plaza around the Somoni monument with fountains,
## flower beds, lawns, lamps and benches. Facade (+Z) faces Rudaki Avenue.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	var hx: float = lm["hx"] - 4.0
	var hz: float = lm["hz"] - 4.0
	LmKit.pave(k, "paving", Vector3.ZERO, Vector2(hx * 2, hz * 2), Color(0.86, 0.82, 0.76), 0.0, 0.06, 1.2)
	# granite inlay stripes along the main axis
	LmKit.pave(k, "stone", Vector3(0, 0, hz * 0.5), Vector2(14, hz), Color(0.62, 0.42, 0.36), 0.0, 0.09, 0.2)
	# lawns along the sides
	for sx: float in [-1.0, 1.0]:
		LmKit.lawn(k, Vector3(sx * (hx - 14), 0, 0), Vector2(20, hz * 1.6))
		for i in 6:
			var z := lerpf(-hz * 0.7, hz * 0.7, i / 5.0)
			LmKit.tree(k, Vector3(sx * (hx - 14), 0.1, z), 9.0, 3.2, 100 + i * 7 + int(sx * 3), 0 if i % 2 == 0 else 1)
	# fountains in front of the monument
	for sx: float in [-1.0, 1.0]:
		LmKit.fountain(k, Vector3(sx * 30.0, 0, 30.0), 9.0, LmKit.MARBLE, 2)
		LmKit.flower_bed(d, Vector3(sx * 30.0, 0, 48.0), Vector2(16, 4), 11 + int(sx), 0.0)
		LmKit.flower_bed(d, Vector3(sx * 30.0, 0, 12.0), Vector2(16, 3), 21 + int(sx), 0.0)
	# lamps and benches along the plaza
	for i in 9:
		var z := lerpf(-hz * 0.85, hz * 0.85, i / 8.0)
		for sx: float in [-1.0, 1.0]:
			LmKit.lamp(d, Vector3(sx * (hx - 27), 0.06, z), 6.0, true)
			LmKit.bench(d, Vector3(sx * (hx - 25), 0.06, z + 5.0), -sx * PI * 0.5)
	LmKit.block(k, "stone", Vector3(0, 0.0, hz - 4.0), Vector3(16, 1.6, 1.2), Color(0.55, 0.38, 0.32))
	LmKit.label(lm, Vector3(0, 0.85, hz - 3.35), "МАЙДОНИ ДӮСТӢ\nПлощадь Дусти", 40, Color(1, 0.88, 0.5))
