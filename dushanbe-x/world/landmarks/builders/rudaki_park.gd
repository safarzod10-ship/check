extends RefCounted
## Rudaki Park: alleys, lawns, fountains along the main axis and the golden statue of the poet
## Abuabdullohi Rudaki in front of a tall mosaic arch.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	var hx: float = lm["hx"] - 5.0
	var hz: float = lm["hz"] - 5.0
	LmKit.lawn(k, Vector3.ZERO, Vector2(hx * 2, hz * 2))
	var pv := Color(0.84, 0.8, 0.74)
	# main axis (towards Rudaki Avenue = +Z) and cross alleys
	LmKit.pave(k, "paving", Vector3(0, 0, 0), Vector2(16, hz * 2), pv, 0.0, 0.2)
	LmKit.pave(k, "paving", Vector3(0, 0, 0), Vector2(hx * 2, 10), pv, 0.0, 0.2)
	for sx: float in [-1.0, 1.0]:
		LmKit.pave(k, "paving", Vector3(sx * hx * 0.55, 0, 0), Vector2(6, hz * 2), pv, 0.0, 0.2)
		LmKit.pave(k, "paving", Vector3(0, 0, sx * hz * 0.6), Vector2(hx * 2, 6), pv, 0.0, 0.2)
	# monument: arch + statue at the back of the axis
	var mz := -hz * 0.55
	LmKit.pave(k, "stone", Vector3(0, 0, mz), Vector2(40, 30), Color(0.6, 0.45, 0.4), 0.0, 0.35)
	LmKit.iwan(k, "stone", Vector3(0, 0.35, mz - 6), 18.0, 24.0, 10.0, 17.0, 3.0, Color(0.93, 0.87, 0.75), LmKit.BLUE_TILE)
	# mosaic panels on the arch faces
	for sx: float in [-1.0, 1.0]:
		LmKit.box(k, "glossy", Vector3(sx * 6.9, 12.0, mz - 4.9), Vector3(2.4, 16.0, 0.2), LmKit.TURQ)
	LmKit.box(k, "gold", Vector3(0, 20.6, mz - 4.85), Vector3(9.0, 1.6, 0.25), LmKit.GOLDC)
	LmKit.block(k, "stone", Vector3(0, 0.35, mz + 4), Vector3(4.5, 3.5, 4.5), Color(0.55, 0.38, 0.32))
	LmKit.statue(k, "gold", Vector3(0, 3.85, mz + 4), 6.5, LmKit.GOLDC, 0.0, false, false, false)
	# fountains on the axis
	for i in 3:
		LmKit.fountain(k, Vector3(0, 0.2, -hz * 0.05 + i * hz * 0.32), 6.0 - i, LmKit.MARBLE, 2 - i % 2)
	# trees: rows along alleys + groves
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 14:
		var z := lerpf(-hz * 0.9, hz * 0.9, i / 13.0)
		for sx: float in [-1.0, 1.0]:
			LmKit.tree(k, Vector3(sx * 12.0, 0.1, z), 10.0, 3.0, 900 + i * 2 + int(sx), 0)
			if i % 2 == 0:
				LmKit.lamp(d, Vector3(sx * 9.0, 0.2, z + 4.0), 4.5)
				LmKit.bench(d, Vector3(sx * 8.6, 0.2, z), -sx * PI * 0.5)
	for g in 26:
		var p := Vector3(rng.randf_range(-hx, hx) * 0.9, 0.1, rng.randf_range(-hz, hz) * 0.9)
		if absf(p.x) < 20 or absf(p.z) < 10:
			continue
		LmKit.tree(k, p, rng.randf_range(7, 12), rng.randf_range(2.5, 4.0), 1000 + g, 1 if rng.randf() < 0.3 else 0)
	for i in 10:
		var a := TAU * i / 10.0
		LmKit.flower_bed(d, Vector3(sx_of(i) * hx * 0.3, 0.1, lerpf(-hz * 0.3, hz * 0.8, (i % 5) / 4.0)), Vector2(8, 3), 1100 + i, 0.0)
		var _u := a
	LmKit.label(lm, Vector3(0, 3.0, mz + 6.4), "АБӮАБДУЛЛОҲИ РӮДАКӢ", 56, Color(1, 0.86, 0.45))


static func sx_of(i: int) -> float:
	return -1.0 if i < 5 else 1.0
