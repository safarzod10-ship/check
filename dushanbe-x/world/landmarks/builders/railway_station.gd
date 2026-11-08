extends RefCounted
## Dushanbe railway station: symmetrical station building with tall central arched portal,
## clock, small spire, arcaded wings and a forecourt with parking.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	var col := Color(0.93, 0.88, 0.76)
	var trim := Color(0.98, 0.95, 0.9)
	var w := 120.0
	var dep := 26.0
	var h := 14.0
	var zc := -14.0
	LmKit.block(k, "stone", Vector3(0, -1.5, zc), Vector3(w + 4, 3.0, dep + 4), Color(0.72, 0.66, 0.6))
	LmKit.block(k, "concrete", Vector3(0, 1.5, zc), Vector3(w, h, dep), col)
	LmKit.cornice(k, "concrete", Vector3(0, 1.5 + h, zc), w + 1, dep + 1, trim)
	var fz := zc + dep * 0.5
	for sx: float in [-1.0, 1.0]:
		for i in 7:
			LmKit.iwan(k, "concrete", Vector3(sx * (18 + i * 6.0), 1.5, fz + 0.4), 6.0, 10.0, 3.6, 8.0, 1.2, col, Color(0.3, 0.33, 0.38), 0.0, trim)
	# central portal
	LmKit.block(k, "concrete", Vector3(0, 1.5, fz - 4), Vector3(30, 24, 18), col)
	LmKit.portal(k, "concrete", Vector3(0, 1.5, fz + 5.5), 30.0, 24.0, 2.0, 16.0, 19.0, trim)
	LmKit.block(k, "glass", Vector3(0, 1.5, fz + 4.0), Vector3(16, 19, 0.3), Color(0.32, 0.4, 0.48))
	LmKit.cornice(k, "concrete", Vector3(0, 25.5, fz - 4), 31, 19, trim)
	k.cylinder("plain", Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(0, 22.6, fz + 6.6)), 1.6, 1.6, 0.2, 20, Color(1, 1, 1), true, true)
	LmKit.block(k, "metal", Vector3(0, 22.4, fz + 6.8), Vector3(0.2, 1.2, 0.1), LmKit.DARK)
	LmKit.cyl(k, "gold", Vector3(0, 26.5, fz - 4), 1.6, 0.2, 9.0, LmKit.GOLDC, 8, false)
	# forecourt + parking
	var cz := fz + 18.0
	LmKit.pave(k, "paving", Vector3(0, 0, cz), Vector2(w, 24), Color(0.84, 0.8, 0.74))
	LmKit.fountain(k, Vector3(0, 0, cz), 5.0, LmKit.MARBLE, 1)
	for sx: float in [-1.0, 1.0]:
		LmKit.parking_lot(k, Vector3(sx * 40, 0, cz), 34.0, 18.0)
		for i in 4:
			LmKit.lamp(d, Vector3(sx * (14 + i * 14), 0.05, cz + 11), 6.0, true)
	LmKit.label(lm, Vector3(0, 26.3, fz + 1.0), "ВОКЗАЛ · ДУШАНБЕ", 110, Color(1, 0.88, 0.5))
