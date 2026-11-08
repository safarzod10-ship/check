extends RefCounted
## Monument to Ismoil Somoni: tiered granite platform, ~40 m travertine arch crowned with a
## golden crown and arc of seven stars, golden statue of the king with a raised sceptre, two lions.

static func build(k: MeshKit, lm: Dictionary) -> void:
	var granite := Color(0.55, 0.36, 0.3)
	# tiered platform (3 tiers)
	for i in 3:
		var s := 46.0 - i * 7.0
		LmKit.block(k, "stone", Vector3(0, i * 0.8 - 0.3, -4), Vector3(s, 1.1, s), granite.lightened(i * 0.05))
	var top := 2.1
	# arch portal (facade faces +Z)
	var arch_y := top
	LmKit.portal(k, "stone", Vector3(0, arch_y, -10), 24.0, 36.0, 6.0, 12.0, 27.0, LmKit.TRAVERTINE)
	# decorative pilasters and cornice
	for sx: float in [-1.0, 1.0]:
		LmKit.block(k, "stone", Vector3(sx * 9.0, arch_y, -6.6), Vector3(2.2, 33.0, 1.0), LmKit.TRAVERTINE.darkened(0.05))
		LmKit.block(k, "gold", Vector3(sx * 9.0, arch_y + 33.0, -6.4), Vector3(2.6, 0.8, 1.4), LmKit.GOLDC)
	LmKit.cornice(k, "stone", Vector3(0, arch_y + 36.0, -10), 25.0, 7.0, LmKit.TRAVERTINE)
	# golden frame around the opening
	LmKit.block(k, "gold", Vector3(0, arch_y + 27.4, -6.9), Vector3(12.6, 0.6, 0.3), LmKit.GOLDC)
	# crown on top: band + spikes + small dome
	var cb := Vector3(0, arch_y + 37.0, -10)
	LmKit.cyl(k, "gold", cb, 4.2, 4.6, 2.4, LmKit.GOLDC, 24)
	for i in 7:
		var a := PI * (0.1 + 0.8 * i / 6.0)
		var p := cb + Vector3(cos(a) * 4.4, 2.4, sin(a) * 4.4)
		LmKit.cyl(k, "gold", p, 0.45, 0.0, 2.4, LmKit.GOLDC, 6, false)
		var p2 := cb + Vector3(-cos(a) * 4.4, 2.4, -sin(a) * 4.4)
		LmKit.cyl(k, "gold", p2, 0.45, 0.0, 2.4, LmKit.GOLDC, 6, false)
	LmKit.dome(k, "gold", cb + Vector3(0, 2.4, 0), 3.6, LmKit.GOLDC, 20, 1.15)
	LmKit.cyl(k, "gold", cb + Vector3(0, 6.4, 0), 0.25, 0.1, 2.0, LmKit.GOLDC, 6)
	# arc of seven stars above the crown (in the facade plane)
	for i in 7:
		var a := PI * (0.15 + 0.7 * i / 6.0)
		var p := cb + Vector3(cos(a) * 7.0, 3.0 + sin(a) * 5.0, 0)
		LmKit.ball(k, "gold", p, 0.7, LmKit.GOLDC, 8, Vector3(1, 1, 0.3))
	# pedestal + statue in front of the arch
	LmKit.block(k, "stone", Vector3(0, top, 3), Vector3(7, 1.0, 7), granite)
	LmKit.block(k, "stone", Vector3(0, top + 1.0, 3), Vector3(5, 4.5, 5), granite.lightened(0.08))
	LmKit.block(k, "gold", Vector3(0, top + 5.5, 3), Vector3(5.4, 0.4, 5.4), LmKit.GOLDC)
	LmKit.statue(k, "gold", Vector3(0, top + 5.9, 3), 11.0, LmKit.GOLDC, 0.0, true, true, true)
	# guardian lions at the front corners of the platform
	for sx: float in [-1.0, 1.0]:
		LmKit.block(k, "stone", Vector3(sx * 15.0, top, 12), Vector3(4.5, 2.5, 6), granite)
		LmKit.lion(k, "gold", Vector3(sx * 15.0, top + 2.5, 12), 2.2, LmKit.GOLDC, 0.0)
	# front stairs
	LmKit.stairs(k, "stone", Vector3(0, -0.3, 19.5), 18.0, 4.0, 2.4, 6, granite.lightened(0.1))
	LmKit.label(lm, Vector3(0, 1.8, 22.6), "ИСМОИЛИ СОМОНӢ\n849 — 907", 72, Color(1, 0.86, 0.45))
