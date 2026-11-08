extends RefCounted
## Mehrgon market: large hall with a monumental arched entrance, tiled ornament bands,
## a row of small domes on the roof, plus open-air stalls with colourful awnings in front.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	var sand := Color(0.93, 0.85, 0.7)
	var w := 130.0
	var dep := 80.0
	var h := 16.0
	var zc := -22.0
	LmKit.block(k, "stone", Vector3(0, -1.5, zc), Vector3(w + 4, 3.0, dep + 4), Color(0.8, 0.74, 0.66))
	LmKit.block(k, "stone", Vector3(0, 1.5, zc), Vector3(w, h, dep), sand)
	var fz := zc + dep * 0.5
	# arched windows bands
	for sx: float in [-1.0, 1.0]:
		for i in 6:
			var x := sx * (24.0 + i * 7.0)
			LmKit.iwan(k, "stone", Vector3(x, 1.5, fz + 0.4), 7.0, 12.0, 4.0, 9.0, 1.2, sand, Color(0.3, 0.32, 0.36))
	k.box("glossy", LmKit.xf(Vector3(0, 1.5 + h - 1.5, fz + 0.1)), Vector3.ZERO, Vector3(w, 1.4, 0.2), LmKit.TURQ)
	# monumental central portal
	LmKit.iwan(k, "stone", Vector3(0, 1.5, fz + 4.0), 34.0, h + 12.0, 18.0, h + 4.0, 8.0, sand, Color(0.35, 0.3, 0.26))
	for sx: float in [-1.0, 1.0]:
		LmKit.cyl(k, "stone", Vector3(sx * 18.5, 1.5, fz + 4.5), 1.8, 1.5, h + 15.0, sand, 12)
		LmKit.onion(k, "glossy", Vector3(sx * 18.5, 1.5 + h + 15.0, fz + 4.5), 1.9, 4.0, LmKit.TURQ, 12)
	# roof domes
	for i in 5:
		for j in 2:
			var dc := Vector3(-48 + i * 24.0, 1.5 + h, zc - 14 + j * 24.0)
			LmKit.cyl(k, "stone", dc, 6.0, 6.0, 2.0, sand, 20)
			LmKit.dome(k, "glossy", dc + Vector3(0, 2.0, 0), 5.6, LmKit.TURQ if (i + j) % 2 == 0 else Color(0.9, 0.9, 0.86), 20)
	# market stalls with awnings in front
	var cols := [Color(0.85, 0.15, 0.15), Color(0.1, 0.45, 0.8), Color(0.95, 0.75, 0.1), Color(0.15, 0.6, 0.3), Color(0.9, 0.45, 0.1)]
	var fruit := [Color(0.95, 0.55, 0.1), Color(0.8, 0.1, 0.1), Color(0.95, 0.85, 0.2), Color(0.4, 0.7, 0.2), Color(0.5, 0.15, 0.4)]
	var sz := fz + 24.0
	LmKit.pave(k, "paving", Vector3(0, 0, sz), Vector2(w, 34), Color(0.8, 0.77, 0.72))
	for row in 2:
		for i in 9:
			var x := -56.0 + i * 14.0
			if absf(x) < 12.0:
				continue
			var p := Vector3(x, 0.1, sz - 6 + row * 14)
			var c: Color = cols[(i + row) % cols.size()]
			LmKit.block(d, "wood", p, Vector3(5.0, 0.9, 2.2), LmKit.WOOD)
			for f in 6:
				LmKit.ball(d, "plain", p + Vector3(-2.0 + f * 0.8, 1.05, 0.2 * (f % 2)), 0.32, fruit[(f + i) % fruit.size()], 6)
			for sxp: float in [-2.4, 2.4]:
				k.cylinder("metal", LmKit.xf(p + Vector3(sxp, 0, -1.0)), 0.06, 0.06, 2.8, 5, LmKit.DARK, false)
				k.cylinder("metal", LmKit.xf(p + Vector3(sxp, 0, 1.2)), 0.06, 0.06, 2.3, 5, LmKit.DARK, false)
			k.quad("awning", p + Vector3(-2.7, 2.3, 1.6), p + Vector3(2.7, 2.3, 1.6), p + Vector3(2.7, 2.85, -1.3), p + Vector3(-2.7, 2.85, -1.3), c)
	LmKit.label(lm, Vector3(0, 1.5 + h + 6.0, fz + 8.2), "БОЗОРИ МЕҲРГОН", 120, Color(1, 0.9, 0.5))
