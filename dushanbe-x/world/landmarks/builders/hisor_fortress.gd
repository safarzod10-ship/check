extends RefCounted
## Hisor fortress: the famous gate — two massive tapered round towers of fired brick with
## crenellations and a tall arched portal between them — plus eroded mud-brick walls on the hill.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	var brick := Color(0.80, 0.52, 0.34)
	var mud := LmKit.MUD
	var hz: float = lm["hz"]
	var hx: float = lm["hx"]
	var gz := hz - 22.0
	# ramp / path to the gate
	LmKit.pave(k, "dirt", Vector3(0, 0, gz + 12), Vector2(10, 22), Color(0.75, 0.62, 0.48), 0.0, 0.1)
	for sx: float in [-1.0, 1.0]:
		var tb := Vector3(sx * 12.0, -1.0, gz)
		LmKit.cyl(k, "stone", tb, 8.0, 5.8, 20.0, brick, 28, false)
		LmKit.cyl(k, "stone", tb + Vector3(0, 20.0, 0), 6.2, 6.2, 1.2, brick.darkened(0.1), 28)
		for i in 14:
			var a := TAU * i / 14.0
			LmKit.block(k, "stone", tb + Vector3(cos(a) * 5.6, 21.2, sin(a) * 5.6), Vector3(1.4, 1.4, 1.0), brick, -a + PI * 0.5)
		# decorative brick bands
		k.cylinder("stone", LmKit.xf(tb + Vector3(0, 8.0, 0)), 7.15, 7.05, 0.6, 28, brick.darkened(0.2), false)
		k.cylinder("stone", LmKit.xf(tb + Vector3(0, 14.0, 0)), 6.55, 6.45, 0.6, 28, brick.darkened(0.2), false)
	# portal between the towers
	LmKit.portal(k, "stone", Vector3(0, -1.0, gz - 1.0), 18.0, 19.0, 9.0, 6.5, 11.0, brick)
	for i in 8:
		LmKit.block(k, "stone", Vector3(-6.3 + i * 1.8, 18.0, gz + 2.0), Vector3(1.1, 1.3, 1.0), brick)
	LmKit.block(k, "wood", Vector3(0, -1.0, gz - 3.0), Vector3(6.5, 11.0, 0.5), Color(0.38, 0.26, 0.16))
	# mud walls along the hill edge, broken into eroded segments
	var rng := RandomNumberGenerator.new()
	rng.seed = 1400
	var pts := [Vector3(-hx + 8, 0, gz), Vector3(-hx + 8, 0, -hz + 8), Vector3(hx - 8, 0, -hz + 8), Vector3(hx - 8, 0, gz)]
	for e in 3:
		var a: Vector3 = pts[e]
		var b: Vector3 = pts[e + 1]
		var n := int(a.distance_to(b) / 9.0)
		var yaw := atan2(b.x - a.x, b.z - a.z)
		for i in n:
			if rng.randf() < 0.25:
				continue
			var p := a.lerp(b, (i + 0.5) / n)
			_wall_seg(k, p, yaw, a.distance_to(b) / n, rng.randf_range(2.5, 7.0), mud)
	for sx: float in [-1.0, 1.0]:
		var a := Vector3(sx * 20.0, 0, gz)
		var b := Vector3(sx * (hx - 8), 0, gz)
		var n := int(a.distance_to(b) / 9.0)
		for i in n:
			var p := a.lerp(b, (i + 0.5) / n)
			_wall_seg(k, p, PI * 0.5, a.distance_to(b) / n, rng.randf_range(3, 7), mud)
	# ruins inside
	for i in 6:
		var p := Vector3(rng.randf_range(-hx * 0.5, hx * 0.5), 0, rng.randf_range(-hz * 0.5, hz * 0.2))
		LmKit.block(d, "dirt", p + Vector3(0, -0.5, 0), Vector3(rng.randf_range(4, 10), rng.randf_range(1, 2.5), 1.5), mud, rng.randf() * PI)
	LmKit.label(lm, Vector3(0, 2.0, gz + 9.0), "ҚАЛЪАИ ҲИСОР", 80, Color(1, 0.9, 0.6))


## Eroded mud-brick (pakhsa) wall segment: battered profile, uneven crest, length along local Z.
static func _wall_seg(k: MeshKit, p: Vector3, yaw: float, length: float, h: float, mud: Color) -> void:
	var t := Transform3D(Basis(Vector3.UP, yaw), p + Vector3(0, -1.0, 0))
	var poly := PackedVector2Array([Vector2(-2.2, -length * 0.5), Vector2(2.2, -length * 0.5), Vector2(2.2, length * 0.5), Vector2(-2.2, length * 0.5)])
	k.prism("dirt", t, poly, h * 0.6, mud)
	var poly2 := PackedVector2Array([Vector2(-1.5, -length * 0.45), Vector2(1.5, -length * 0.45), Vector2(1.5, length * 0.4), Vector2(-1.5, length * 0.4)])
	k.prism("dirt", t, poly2, h * 0.4, mud.darkened(0.06), true, false, h * 0.6)
	k.prism("dirt", t, PackedVector2Array([Vector2(-0.9, -length * 0.3), Vector2(0.9, -length * 0.3), Vector2(0.9, length * 0.15), Vector2(-0.9, length * 0.15)]), h * 0.18, mud.darkened(0.1), true, false, h)
