extends RefCounted
## Ismaili Centre: layered, set-back volumes of light stone, geometric lattice screens,
## glazed pyramid skylight and a formal garden with water channels and cypresses.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	var stone := Color(0.9, 0.85, 0.75)
	var zc := -22.0
	LmKit.block(k, "stone", Vector3(0, -1.5, zc), Vector3(96, 3.0, 66), Color(0.82, 0.78, 0.7))
	LmKit.block(k, "stone", Vector3(0, 1.5, zc), Vector3(90, 10, 60), stone)
	LmKit.block(k, "stone", Vector3(0, 11.5, zc - 4), Vector3(60, 6, 40), stone.darkened(0.03))
	LmKit.block(k, "stone", Vector3(0, 17.5, zc - 6), Vector3(34, 4, 24), stone.darkened(0.06))
	# glazed pyramid skylight
	var pb := Vector3(0, 21.5, zc - 6)
	var s := 9.0
	var apex := pb + Vector3(0, 8, 0)
	var c := [pb + Vector3(-s, 0, s), pb + Vector3(s, 0, s), pb + Vector3(s, 0, -s), pb + Vector3(-s, 0, -s)]
	for i in 4:
		k.tri("glass", c[i], c[(i + 1) % 4], apex, Color(0.4, 0.6, 0.7))
	# lattice screens (geometric pattern of thin bars) on the main facade
	var fz := zc + 30.05
	for i in 22:
		var x := -40.0 + i * 3.8
		LmKit.box(k, "stone", Vector3(x, 6.5, fz + 0.3), Vector3(0.3, 9.0, 0.3), stone.lightened(0.1))
	for j in 5:
		LmKit.box(k, "stone", Vector3(0, 2.5 + j * 2.0, fz + 0.3), Vector3(82, 0.25, 0.3), stone.lightened(0.1))
	LmKit.box(k, "glass", Vector3(0, 6.5, fz - 0.1), Vector3(80, 8.0, 0.3), Color(0.22, 0.32, 0.38))
	# entrance portal (pointed proportion) with gilded frame
	LmKit.iwan(k, "stone", Vector3(0, 1.5, fz + 2.0), 16.0, 14.0, 8.0, 11.0, 4.0, stone, stone.darkened(0.25), 0.0)
	# garden: char-bagh water channels with fountains and cypress rows
	var gz := fz + 20.0
	LmKit.pave(k, "paving", Vector3(0, 0, gz), Vector2(90, 30), Color(0.88, 0.84, 0.76))
	for sx: float in [-1.0, 1.0]:
		LmKit.lawn(k, Vector3(sx * 24, 0, gz), Vector2(30, 24))
		for i in 6:
			LmKit.tree(k, Vector3(sx * (9 + i * 6.5), 0.1, gz + 13), 9.0, 1.4, 4100 + i + int(sx) * 20, 1)
	LmKit.block(k, "stone", Vector3(0, -0.1, gz), Vector3(5, 0.6, 30), stone)
	k.box("lm_water", LmKit.xf(Vector3(0, 0.52, gz)), Vector3.ZERO, Vector3(3.6, 0.02, 29), Color(0.3, 0.55, 0.7))
	LmKit.block(k, "stone", Vector3(0, -0.1, gz), Vector3(60, 0.6, 4), stone)
	k.box("lm_water", LmKit.xf(Vector3(0, 0.52, gz)), Vector3.ZERO, Vector3(59, 0.02, 2.8), Color(0.3, 0.55, 0.7))
	LmKit.fountain(k, Vector3(0, 0, gz), 3.5, stone, 1)
	for i in 6:
		LmKit.lamp(d, Vector3(-40 + i * 16, 0.05, gz - 13), 4.0)
	LmKit.label(lm, Vector3(0, 13.6, fz + 2.2), "МАРКАЗИ ИСМОИЛИЯ", 64, Color(0.95, 0.85, 0.55))
