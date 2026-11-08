extends RefCounted
## National Flag Park: 165 m flagpole with a 50 x 25 m waving Tajik flag, circular plaza,
## lawns, fountains and trees.

const POLE_H := 165.0
const FLAG_L := 50.0
const FLAG_H := 25.0


static func build(k: MeshKit, lm: Dictionary) -> void:
	var d: MeshKit = lm["_detail"]
	var hx: float = lm["hx"] - 4.0
	var hz: float = lm["hz"] - 4.0
	# lawns over the whole park + circular plaza
	LmKit.lawn(k, Vector3.ZERO, Vector2(hx * 2, hz * 2))
	LmKit.disc(k, "paving", Vector3(0, 0, 0), 46.0, Color(0.88, 0.84, 0.78), 0.2, 48)
	LmKit.disc(k, "stone", Vector3(0, 0, 0), 14.0, Color(0.6, 0.42, 0.36), 0.35, 32)
	# radial alleys
	for a in 4:
		var yaw := a * PI * 0.5 + PI * 0.25
		var b := Basis(Vector3.UP, yaw)
		k.box("paving", Transform3D(b, b * Vector3(0, 0.0, 70)), Vector3.ZERO, Vector3(8, 0.36, 60), Color(0.86, 0.82, 0.76))
	# pedestal with steps
	for i in 3:
		LmKit.cyl(k, "stone", Vector3(0, 0.2 + i * 0.6, 0), 10.0 - i * 2.5, 10.0 - i * 2.5, 0.6, Color(0.66, 0.5, 0.42), 32)
	var base_y := 2.0
	# the pole: tapered white steel, gold ball on top
	LmKit.cyl(k, "metal", Vector3(0, base_y, 0), 1.6, 0.55, POLE_H - base_y, Color(0.9, 0.9, 0.92), 16, false)
	LmKit.ball(k, "gold", Vector3(0, POLE_H + 0.6, 0), 1.2, LmKit.GOLDC, 12)
	# the flag: grid in local XY plane, UV.x = metres from pole, UV.y = metres from bottom
	var top := POLE_H - 1.5
	var bot := top - FLAG_H
	var nx := 40
	var red_h := FLAG_H * 2.0 / 7.0
	var white_h := FLAG_H * 3.0 / 7.0
	var bands := [[bot, bot + red_h, Color(0.0, 0.48, 0.2)], [bot + red_h, bot + red_h + white_h, Color(0.98, 0.98, 0.98)],
		[bot + red_h + white_h, top, Color(0.82, 0.06, 0.08)]]
	for band in bands:
		var y0: float = band[0]
		var y1: float = band[1]
		var col: Color = band[2]
		var ny := 4
		for j in ny:
			var ya := lerpf(y0, y1, float(j) / ny)
			var yb := lerpf(y0, y1, float(j + 1) / ny)
			for i in nx:
				var xa := 0.6 + FLAG_L * float(i) / nx
				var xb := 0.6 + FLAG_L * float(i + 1) / nx
				var uv := PackedVector2Array([Vector2(xa, ya - bot), Vector2(xb, ya - bot), Vector2(xb, yb - bot), Vector2(xa, yb - bot)])
				k.quad("flag", Vector3(xa, ya, 0), Vector3(xb, ya, 0), Vector3(xb, yb, 0), Vector3(xa, yb, 0), col, uv)
	# emblem: crown + arc of seven stars (gold), on both sides of the flag
	var cx := 0.6 + FLAG_L * 0.42
	var cy := bot + red_h + white_h * 0.42
	var gold := Color(0.95, 0.75, 0.15)
	for side: float in [0.06, -0.06]:
		_flag_rect(k, cx - 2.0, cy - 1.0, cx + 2.0, cy, side, gold, bot)
		for i in 3:
			var px := cx - 1.6 + i * 1.6
			_flag_rect(k, px - 0.45, cy, px + 0.45, cy + 1.3 + (0.4 if i == 1 else 0.0), side, gold, bot)
		for i in 7:
			var a := PI * (0.12 + 0.76 * i / 6.0)
			var sx := cx + cos(a) * 4.0
			var sy := cy + 0.5 + sin(a) * 3.0
			_flag_rect(k, sx - 0.4, sy - 0.4, sx + 0.4, sy + 0.4, side, gold, bot)
	# fountains on the diagonals
	for a in 4:
		var yaw := a * PI * 0.5
		LmKit.fountain(k, Vector3(cos(yaw), 0, sin(yaw)) * 32.0, 5.0, LmKit.MARBLE, 1)
	# tree ring and lamps
	var n := 28
	for i in n:
		var a := TAU * i / n
		LmKit.tree(k, Vector3(cos(a) * 55.0, 0.1, sin(a) * 55.0), 10.0, 3.5, 300 + i, 0 if i % 3 else 1)
		LmKit.lamp(d, Vector3(cos(a + 0.1) * 47.0, 0.2, sin(a + 0.1) * 47.0), 5.0)
		if i % 2 == 0:
			LmKit.bench(d, Vector3(cos(a) * 44.0, 0.2, sin(a) * 44.0), -a - PI * 0.5)
	for i in 8:
		var a := TAU * i / 8.0 + 0.2
		LmKit.flower_bed(d, Vector3(cos(a) * 22.0, 0.1, sin(a) * 22.0), Vector2(6, 3), 50 + i, -a)
	LmKit.label(lm, Vector3(0, 3.5, 10.5), "ПАРКИ ПАРЧАМИ ДАВЛАТӢ\nПарк Национального флага", 64, Color(1, 0.9, 0.5))


static func _flag_rect(k: MeshKit, x0: float, y0: float, x1: float, y1: float, z: float, col: Color, bot: float) -> void:
	var uv := PackedVector2Array([Vector2(x0, y0 - bot), Vector2(x1, y0 - bot), Vector2(x1, y1 - bot), Vector2(x0, y1 - bot)])
	if z > 0.0:
		k.quad("flag", Vector3(x0, y0, z), Vector3(x1, y0, z), Vector3(x1, y1, z), Vector3(x0, y1, z), col, uv)
	else:
		var uv2 := PackedVector2Array([uv[1], uv[0], uv[3], uv[2]])
		k.quad("flag", Vector3(x1, y0, z), Vector3(x0, y0, z), Vector3(x0, y1, z), Vector3(x1, y1, z), col, uv2)
