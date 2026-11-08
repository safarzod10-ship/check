extends RefCounted
## Madrasai Kuhna (Old madrasa) in Hisor: fired-brick rectangle with a tall portal iwan,
## rows of hujra niches, corner guldasta towers and a dome over the darskhona.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var brick := Color(0.8, 0.6, 0.42)
	var w := 42.0
	var dep := 36.0
	var h := 9.0
	var zc := -4.0
	LmKit.block(k, "stone", Vector3(0, -1.5, zc), Vector3(w + 2, 1.6, dep + 2), brick.darkened(0.15))
	# perimeter walls around a courtyard
	var fz := zc + dep * 0.5
	LmKit.block(k, "stone", Vector3(0, 0, zc - dep * 0.5 + 3), Vector3(w, h, 6), brick)
	for sx: float in [-1.0, 1.0]:
		LmKit.block(k, "stone", Vector3(sx * (w * 0.5 - 3), 0, zc), Vector3(6, h, dep), brick)
		for i in 4:
			LmKit.iwan(k, "stone", Vector3(sx * (8.5 + i * 3.6), 0, fz - 0.6), 3.6, h, 2.2, 5.0, 1.2, brick, brick.darkened(0.4))
		LmKit.cyl(k, "stone", Vector3(sx * w * 0.5, 0, fz), 1.8, 1.4, h + 4.0, brick, 12)
		LmKit.onion(k, "stone", Vector3(sx * w * 0.5, h + 4.0, fz), 1.5, 2.6, brick, 12)
	# portal iwan
	LmKit.iwan(k, "stone", Vector3(0, 0, fz + 0.4), 14.0, 16.0, 7.0, 11.0, 5.0, brick, brick.darkened(0.35))
	# darskhona with dome at the back
	var dc := Vector3(0, h, zc - dep * 0.5 + 6)
	LmKit.block(k, "stone", Vector3(0, 0, dc.z), Vector3(14, h, 12), brick)
	LmKit.cyl(k, "stone", dc, 6.0, 6.0, 2.5, brick, 20)
	LmKit.dome(k, "stone", dc + Vector3(0, 2.5, 0), 6.0, brick.lightened(0.05), 20)
	LmKit.label(lm, Vector3(0, 13.2, fz + 1.5), "МАДРАСАИ КӮҲНА", 56, Color(1, 0.92, 0.7))
