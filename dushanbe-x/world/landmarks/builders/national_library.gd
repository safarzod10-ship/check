extends RefCounted
## National Library: monumental block with a full-height portico of tall square columns,
## golden glass centre and two angled "book cover" wings.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	var w := 120.0
	var dep := 44.0
	var h := 30.0
	var zc := -4.0
	var stone := Color(0.93, 0.9, 0.84)
	LmKit.block(k, "marble", Vector3(0, -2.0, zc), Vector3(w + 30, 3.5, dep + 8), Color(0.85, 0.82, 0.78))
	LmKit.block(k, "marble", Vector3(0, 1.5, zc - 4), Vector3(w - 20, h, dep - 8), stone)
	LmKit.block(k, "glass", Vector3(0, 1.5, zc + dep * 0.5 - 6.5), Vector3(w - 22, h - 4, 1.0), Color(0.55, 0.46, 0.25))
	# book wings: angled slabs
	for sx: float in [-1.0, 1.0]:
		var c := Vector3(sx * (w * 0.5 - 2), 1.5, zc)
		LmKit.block(k, "marble", c, Vector3(10, h + 2, dep), stone, sx * 0.22)
		LmKit.block(k, "glass", c + Vector3(-sx * 5.2, 3, 0), Vector3(0.4, h - 6, dep - 6), Color(0.25, 0.32, 0.4), sx * 0.22)
	# tall portico
	LmKit.block(k, "marble", Vector3(0, 1.5 + h - 1, zc + dep * 0.5 - 2), Vector3(w - 16, 3.0, 10), stone)
	for i in 14:
		var x := lerpf(-w * 0.5 + 14, w * 0.5 - 14, i / 13.0)
		LmKit.block(k, "marble", Vector3(x, 1.5, zc + dep * 0.5 + 1.5), Vector3(2.0, h - 1, 2.0), stone)
		LmKit.block(k, "gold", Vector3(x, 1.5 + h - 2.0, zc + dep * 0.5 + 1.5), Vector3(2.4, 0.8, 2.4), LmKit.GOLDC)
	LmKit.block(k, "gold", Vector3(0, 1.5 + h + 2.0, zc + dep * 0.5 + 3.0), Vector3(w - 16, 0.5, 0.3), LmKit.GOLDC)
	LmKit.stairs(k, "marble", Vector3(0, -0.2, zc + dep * 0.5 + 12), 90.0, 8.0, 1.8, 6, Color(0.88, 0.86, 0.82))
	for i in 8:
		var x := lerpf(-60, 60, i / 7.0)
		LmKit.lamp(d, Vector3(x, 0.0, lm["hz"] - 6.0), 5.0, true)
	LmKit.label(lm, Vector3(0, 1.5 + h + 0.2, zc + dep * 0.5 + 3.2), "КИТОБХОНАИ МИЛЛИИ ТОҶИКИСТОН", 90, Color(1, 0.85, 0.4))
