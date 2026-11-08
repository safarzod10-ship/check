extends RefCounted
## Avicenna Tajik State Medical University: classical academic block with portico and
## a seated statue of Abu Ali ibn Sino (Avicenna) in front.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	var col := Color(0.88, 0.86, 0.8)
	var trim := Color(0.97, 0.96, 0.92)
	var w := 120.0
	var dep := 20.0
	var h := 18.0
	var zc := -30.0
	LmKit.block(k, "stone", Vector3(0, -1.5, zc), Vector3(w + 4, 3.0, dep + 4), Color(0.7, 0.64, 0.58))
	LmKit.block(k, "concrete", Vector3(0, 1.5, zc), Vector3(w, h, dep), col)
	LmKit.cornice(k, "concrete", Vector3(0, 1.5 + h, zc), w + 1, dep + 1, trim)
	for sx: float in [-1.0, 1.0]:
		LmKit.block(k, "concrete", Vector3(sx * (w * 0.5 - 8), 1.5, zc - 18), Vector3(16, h, 36), col)
	var tf := LmKit.xf(Vector3(0, 1.5, zc + dep * 0.5))
	LmKit.windows(k, tf, -w * 0.5 + 4, -12, 1.0, 4, 11, 4.2, 1.6, 2.4, 0.0, Color(0.25, 0.32, 0.4), trim)
	LmKit.windows(k, tf, 12, w * 0.5 - 4, 1.0, 4, 11, 4.2, 1.6, 2.4, 0.0, Color(0.25, 0.32, 0.4), trim)
	var pz := zc + dep * 0.5 + 5.0
	LmKit.colonnade(k, "marble", Vector3(-10, 1.5, pz + 2), Vector3(10, 1.5, pz + 2), 6, 0.85, 15.0, trim)
	LmKit.block(k, "concrete", Vector3(0, 16.5, pz), Vector3(24, 2.2, 8), trim)
	LmKit.pediment(k, "concrete", Vector3(0, 18.7, pz), 24.0, 4.0, 8.0, trim)
	LmKit.stairs(k, "stone", Vector3(0, -0.2, pz + 9), 28.0, 5.0, 1.6, 6, trim)
	# Avicenna statue
	var sz := pz + 30.0
	LmKit.pave(k, "paving", Vector3(0, 0, sz), Vector2(40, 30), Color(0.86, 0.82, 0.76))
	LmKit.block(k, "stone", Vector3(0, 0.05, sz), Vector3(5, 3.2, 4), Color(0.45, 0.38, 0.36))
	LmKit.statue(k, "glossy", Vector3(0, 3.25, sz), 4.2, LmKit.BRONZE, 0.0, false, false, false, true)
	for sx: float in [-1.0, 1.0]:
		LmKit.flower_bed(d, Vector3(sx * 10, 0, sz), Vector2(8, 4), 6000 + int(sx), 0.0)
		for i in 4:
			LmKit.tree(k, Vector3(sx * 26, 0.1, sz - 12 + i * 8), 8.0, 2.8, 6100 + i + int(sx) * 7, 0)
	LmKit.label(lm, Vector3(0, 1.0, sz + 2.1), "АБӮАЛӢ ИБНИ СИНО", 48, Color(1, 0.9, 0.55))
	LmKit.label(lm, Vector3(0, 16.6, pz + 4.2), "ДОНИШГОҲИ ДАВЛАТИИ ТИББӢ", 56, Color(1, 0.95, 0.7))
