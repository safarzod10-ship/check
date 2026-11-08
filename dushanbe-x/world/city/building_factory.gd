class_name BuildingFactory
extends RefCounted
## Procedural buildings. Record format (from world.json):
##   [cx, cz, yaw_deg, w, d, floors, style, base_y, seed]
## Local frame: X along the street (width w), Z depth d, +Z faces the street, Y up from base_y.
## Styles: 0 khrushchevka, 1 panel 9-16 floors, 2 modern glass tower, 3 Stalinist neoclassical,
##         4 shop/commercial, 5 private house with courtyard (havli), 6 school/administration,
##         7 village house with ayvan and mud walls.

const FLOOR_H := [2.8, 2.8, 3.4, 3.8, 3.6, 3.0, 3.6, 2.9]

const WALLS := {
	0: [Color(0.86, 0.82, 0.74), Color(0.80, 0.78, 0.76), Color(0.88, 0.84, 0.66), Color(0.76, 0.56, 0.44), Color(0.9, 0.88, 0.84)],
	1: [Color(0.9, 0.9, 0.88), Color(0.82, 0.84, 0.86), Color(0.88, 0.86, 0.78), Color(0.84, 0.8, 0.74)],
	2: [Color(0.75, 0.8, 0.85), Color(0.6, 0.66, 0.72), Color(0.85, 0.84, 0.8), Color(0.5, 0.56, 0.6)],
	3: [Color(0.93, 0.8, 0.55), Color(0.92, 0.72, 0.58), Color(0.95, 0.9, 0.78), Color(0.86, 0.78, 0.66), Color(0.9, 0.84, 0.62)],
	4: [Color(0.92, 0.9, 0.86), Color(0.8, 0.86, 0.9), Color(0.95, 0.86, 0.7), Color(0.85, 0.75, 0.7)],
	5: [Color(0.92, 0.88, 0.8), Color(0.86, 0.82, 0.72), Color(0.95, 0.94, 0.9), Color(0.82, 0.86, 0.88), Color(0.9, 0.8, 0.7)],
	6: [Color(0.95, 0.9, 0.78), Color(0.86, 0.88, 0.9), Color(0.92, 0.84, 0.7)],
	7: [Color(0.78, 0.66, 0.5), Color(0.84, 0.74, 0.58), Color(0.9, 0.86, 0.78), Color(0.74, 0.62, 0.48)],
}
const ROOF_TIN := [Color(0.3, 0.5, 0.7), Color(0.35, 0.6, 0.4), Color(0.7, 0.3, 0.25), Color(0.75, 0.76, 0.78), Color(0.2, 0.45, 0.55)]
const ACCENTS := [Color(0.85, 0.3, 0.25), Color(0.25, 0.5, 0.8), Color(0.95, 0.75, 0.2), Color(0.3, 0.65, 0.45), Color(0.6, 0.35, 0.65)]
const SIGNS := ["МАГАЗИН", "ДОРУХОНА", "НОН", "ОЗИҚ-ОВҚАТ", "КАФЕ", "САЛОН", "МАРКЕТ", "АПТЕКА", "ТЕЛЕФОН", "БАНК", "МЕВА"]


static func rnd(seed: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed
	return r


static func transform_of(b: Array, org: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -deg_to_rad(float(b[2]))), Vector3(b[0], b[7], b[1]) - org)


static func height_of(b: Array) -> float:
	var st: int = b[6]
	return FLOOR_H[st] * int(b[5]) + (0.8 if st != 7 else 0.4)


## Far LOD: a facade-shaded box + roof.
static func build_far(kit: MeshKit, b: Array, org: Vector3) -> void:
	var st: int = b[6]
	var r := rnd(int(b[8]))
	var t := transform_of(b, org)
	var w: float = b[3]
	var d: float = b[4]
	if st == 5 or st == 7:
		w *= 0.6
		d *= 0.5
	var h := height_of(b)
	var col: Color = WALLS[st][r.randi() % WALLS[st].size()]
	kit.uv2 = Vector2(st + r.randf() * 0.98, h + 2.0)
	_walls(kit, t, Vector3(0, -2.0, 0), Vector3(w, h + 2.0, d), col)
	kit.uv2 = Vector2.ZERO
	var rc: Color = ROOF_TIN[r.randi() % ROOF_TIN.size()] if st == 5 else Color(0.45, 0.45, 0.47)
	kit.quad("plain", t * Vector3(-w / 2, h, d / 2), t * Vector3(w / 2, h, d / 2), t * Vector3(w / 2, h, -d / 2), t * Vector3(-w / 2, h, -d / 2), rc)


## Four facade walls around a box (no top/bottom). origin = bottom centre in local space.
static func _walls(kit: MeshKit, t: Transform3D, o: Vector3, size: Vector3, col: Color, slot := "facade") -> void:
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	var y0 := o.y
	var y1 := o.y + size.y
	var p := [
		t * Vector3(o.x - hx, y0, o.z + hz), t * Vector3(o.x + hx, y0, o.z + hz),
		t * Vector3(o.x + hx, y0, o.z - hz), t * Vector3(o.x - hx, y0, o.z - hz),
		t * Vector3(o.x - hx, y1, o.z + hz), t * Vector3(o.x + hx, y1, o.z + hz),
		t * Vector3(o.x + hx, y1, o.z - hz), t * Vector3(o.x - hx, y1, o.z - hz),
	]
	kit.quad(slot, p[0], p[1], p[5], p[4], col)   # front (+Z)
	kit.quad(slot, p[1], p[2], p[6], p[5], col)   # right
	kit.quad(slot, p[2], p[3], p[7], p[6], col)   # back
	kit.quad(slot, p[3], p[0], p[4], p[7], col)   # left


static func _roof_flat(kit: MeshKit, t: Transform3D, w: float, d: float, h: float, parapet: float, col: Color) -> void:
	kit.box("plain", t, Vector3(0, h - 0.05, 0), Vector3(w - 0.2, 0.1, d - 0.2), Color(0.4, 0.4, 0.42))
	if parapet > 0.0:
		var pc := col.darkened(0.08)
		kit.box("plain", t, Vector3(0, h + parapet * 0.5, d / 2 - 0.15), Vector3(w, parapet, 0.3), pc)
		kit.box("plain", t, Vector3(0, h + parapet * 0.5, -d / 2 + 0.15), Vector3(w, parapet, 0.3), pc)
		kit.box("plain", t, Vector3(w / 2 - 0.15, h + parapet * 0.5, 0), Vector3(0.3, parapet, d - 0.6), pc)
		kit.box("plain", t, Vector3(-w / 2 + 0.15, h + parapet * 0.5, 0), Vector3(0.3, parapet, d - 0.6), pc)


static func _roof_gable(kit: MeshKit, t: Transform3D, w: float, d: float, h: float, rise: float, col: Color, over := 0.6) -> void:
	var hx := w / 2 + over
	var hz := d / 2 + over
	var a := t * Vector3(-hx, h, hz)
	var b := t * Vector3(hx, h, hz)
	var c := t * Vector3(hx, h + rise, 0)
	var dd := t * Vector3(-hx, h + rise, 0)
	kit.quad("tin", a, b, c, dd, col)
	var e := t * Vector3(hx, h, -hz)
	var f := t * Vector3(-hx, h, -hz)
	kit.quad("tin", e, f, dd, c, col)
	# gables
	var wall := Color(0.85, 0.8, 0.72)
	kit.tri("plain", t * Vector3(w / 2, h, d / 2), t * Vector3(w / 2, h, -d / 2), t * Vector3(w / 2, h + rise, 0), wall)
	kit.tri("plain", t * Vector3(-w / 2, h, -d / 2), t * Vector3(-w / 2, h, d / 2), t * Vector3(-w / 2, h + rise, 0), wall)


static func _roof_hip(kit: MeshKit, t: Transform3D, w: float, d: float, h: float, rise: float, col: Color) -> void:
	var hx := w / 2 + 0.5
	var hz := d / 2 + 0.5
	var r := minf(hx, hz) * 0.9
	var p0 := t * Vector3(-hx, h, hz)
	var p1 := t * Vector3(hx, h, hz)
	var p2 := t * Vector3(hx, h, -hz)
	var p3 := t * Vector3(-hx, h, -hz)
	var ra := t * Vector3(-hx + r, h + rise, 0)
	var rb := t * Vector3(hx - r, h + rise, 0)
	kit.quad("tin", p0, p1, rb, ra, col)
	kit.quad("tin", p2, p3, ra, rb, col)
	kit.tri("tin", p1, p2, rb, col)
	kit.tri("tin", p3, p0, ra, col)


# ---------------------------------------------------------------------------
static func build_near(kit: MeshKit, b: Array, org: Vector3, labels: Array) -> void:
	var st: int = b[6]
	match st:
		0, 1:
			_panel_block(kit, b, org)
		2:
			_tower(kit, b, org, labels)
		3:
			_stalinist(kit, b, org)
		4:
			_shop(kit, b, org, labels)
		5:
			_havli(kit, b, org)
		6:
			_school(kit, b, org)
		7:
			_village_house(kit, b, org)
		_:
			build_far(kit, b, org)


static func _panel_block(kit: MeshKit, b: Array, org: Vector3) -> void:
	var st: int = b[6]
	var r := rnd(int(b[8]))
	var t := transform_of(b, org)
	var w: float = b[3]
	var d: float = b[4]
	var floors: int = b[5]
	var fh: float = FLOOR_H[st]
	var h := fh * floors + 0.8
	var col: Color = WALLS[st][r.randi() % WALLS[st].size()]
	kit.uv2 = Vector2(st + r.randf() * 0.98, h + 2.0)
	_walls(kit, t, Vector3(0, -2.0, 0), Vector3(w, h + 2.0, d), col)
	kit.uv2 = Vector2.ZERO
	_roof_flat(kit, t, w, d, h, 0.6, col)
	var entrances := maxi(1, int(w / 15.0))
	var seg := w / entrances
	# entrances (podyezd) on the back (yard) side, -Z, with canopies
	for e in entrances:
		var x := -w / 2 + seg * (e + 0.5)
		kit.box("plain", t, Vector3(x, 1.1, -d / 2 - 0.05), Vector3(1.6, 2.2, 0.12), Color(0.35, 0.25, 0.18))
		kit.box("concrete", t, Vector3(x, 2.5, -d / 2 - 0.9), Vector3(2.6, 0.15, 1.8), Color(0.75, 0.74, 0.72))
		kit.box("concrete", t, Vector3(x, 0.15, -d / 2 - 1.0), Vector3(2.4, 0.3, 2.0), Color(0.7, 0.7, 0.68))
		# stairwell windows strip / colored panel on panel blocks
		if st == 1:
			var acc: Color = ACCENTS[r.randi() % ACCENTS.size()]
			kit.box("plain", t, Vector3(x, h * 0.5 + 1.5, -d / 2 - 0.06), Vector3(1.2, h - 3.5, 0.1), acc)
		# roof exit
		kit.box("plain", t, Vector3(x, h + 1.2, -d / 4), Vector3(3.0, 2.4, 3.0), col.darkened(0.1))
	if st == 1:
		# lift machine room
		kit.box("plain", t, Vector3(0, h + 1.8, 0), Vector3(5.0, 3.6, 5.0), col.darkened(0.12))
	# balconies on the street side (+Z), some glazed
	var bal_col := col.darkened(0.15)
	var cols_n := int(w / 3.2)
	for f in range(1, floors):
		var y := fh * f + 0.8
		for c in cols_n:
			if r.randf() < 0.45:
				continue
			var x2 := -w / 2 + 3.2 * (c + 0.5)
			if absf(x2) > w / 2 - 1.5:
				continue
			kit.box("plain", t, Vector3(x2, y - 0.05, d / 2 + 0.6), Vector3(2.4, 0.15, 1.2), bal_col)
			if r.randf() < 0.55:
				var glz: Color = Color(0.55, 0.62, 0.66) if r.randf() < 0.7 else ACCENTS[r.randi() % ACCENTS.size()]
				kit.box("glass", t, Vector3(x2, y + 1.0, d / 2 + 1.15), Vector3(2.4, 1.9, 0.08), glz)
				kit.box("plain", t, Vector3(x2 - 1.17, y + 1.0, d / 2 + 0.6), Vector3(0.06, 1.9, 1.1), glz.darkened(0.2))
				kit.box("plain", t, Vector3(x2 + 1.17, y + 1.0, d / 2 + 0.6), Vector3(0.06, 1.9, 1.1), glz.darkened(0.2))
				kit.box("plain", t, Vector3(x2, y + 2.0, d / 2 + 0.6), Vector3(2.4, 0.1, 1.2), bal_col)
			else:
				kit.box("metal", t, Vector3(x2, y + 0.5, d / 2 + 1.18), Vector3(2.4, 1.0, 0.05), Color(0.6, 0.62, 0.64))
	# AC units
	for q in r.randi_range(2, 8):
		var y3 := fh * r.randi_range(1, floors - 1) + 1.2
		var x3 := r.randf_range(-w / 2 + 1.0, w / 2 - 1.0)
		kit.box("plain", t, Vector3(x3, y3, d / 2 + 0.25), Vector3(0.8, 0.55, 0.3), Color(0.92, 0.92, 0.9))
	# satellite dishes on the roof
	for q in r.randi_range(0, 3):
		var tt := t * Transform3D(Basis(Vector3.RIGHT, 1.1), Vector3(r.randf_range(-w / 3, w / 3), h + 1.2, r.randf_range(-d / 4, d / 4)))
		kit.cylinder("plain", tt, 0.5, 0.1, 0.2, 8, Color(0.85, 0.85, 0.85), true, true)


static func _tower(kit: MeshKit, b: Array, org: Vector3, labels: Array) -> void:
	var r := rnd(int(b[8]))
	var t := transform_of(b, org)
	var w: float = b[3]
	var d: float = b[4]
	var floors: int = b[5]
	var fh: float = FLOOR_H[2]
	var col: Color = WALLS[2][r.randi() % WALLS[2].size()]
	# podium (2 floors, shops)
	var ph := 7.6
	kit.uv2 = Vector2(4 + r.randf() * 0.98, ph + 2.0)
	_walls(kit, t, Vector3(0, -2.0, 0), Vector3(w, ph + 2.0, d), Color(0.82, 0.8, 0.76))
	kit.uv2 = Vector2.ZERO
	_roof_flat(kit, t, w, d, ph, 0.0, col)
	# tower shaft, with optional setback at 2/3 height
	var tw := w * 0.8
	var td := d * 0.8
	var th := fh * (floors - 2)
	var setback := r.randf() < 0.5
	var h1 := th * (0.68 if setback else 1.0)
	kit.uv2 = Vector2(2 + r.randf() * 0.98, h1)
	_walls(kit, t, Vector3(0, ph, 0), Vector3(tw, h1, td), col)
	if setback:
		kit.uv2 = Vector2(2 + r.randf() * 0.98, th - h1)
		_walls(kit, t, Vector3(0, ph + h1, 0), Vector3(tw * 0.75, th - h1, td * 0.75), col)
		kit.uv2 = Vector2.ZERO
		_roof_flat(kit, t, tw, td, ph + h1, 0.8, col)
		_roof_flat(kit, t, tw * 0.75, td * 0.75, ph + th, 1.2, col)
	else:
		kit.uv2 = Vector2.ZERO
		_roof_flat(kit, t, tw, td, ph + th, 1.2, col)
	kit.uv2 = Vector2.ZERO
	# vertical fins / crown
	var top := ph + th
	kit.box("metal", t, Vector3(0, top + 3.0, 0), Vector3(tw * (0.5 if setback else 0.7), 6.0, 0.4), Color(0.8, 0.82, 0.85))
	if r.randf() < 0.5:
		kit.cylinder("metal", t * Transform3D(Basis(), Vector3(0, top + 6.0, 0)), 0.15, 0.05, 10.0, 6, Color(0.8, 0.8, 0.8))
		kit.sphere("lamp_always", t * Transform3D(Basis(), Vector3(0, top + 16.0, 0)), 0.35, 4, 6, Color(1.0, 0.2, 0.1))
	# canopy over the entrance
	kit.box("metal", t, Vector3(0, 4.0, d / 2 + 1.5), Vector3(8.0, 0.25, 3.0), Color(0.3, 0.32, 0.35))
	labels.append([t * Vector3(0, 5.6, d / 2 + 0.3), -deg_to_rad(float(b[2])), ["БИЗНЕС-ЦЕНТР", "ТОҶИКИСТОН", "ПЛАЗА", "МЕҲР"][r.randi() % 4], Color(1, 1, 1)])


static func _stalinist(kit: MeshKit, b: Array, org: Vector3) -> void:
	var r := rnd(int(b[8]))
	var t := transform_of(b, org)
	var w: float = b[3]
	var d: float = b[4]
	var floors: int = b[5]
	var fh: float = FLOOR_H[3]
	var h := fh * floors + 0.8
	var col: Color = WALLS[3][r.randi() % WALLS[3].size()]
	var trim := Color(0.97, 0.95, 0.9)
	kit.uv2 = Vector2(3 + r.randf() * 0.98, h + 2.0)
	_walls(kit, t, Vector3(0, -2.0, 0), Vector3(w, h + 2.0, d), col)
	kit.uv2 = Vector2.ZERO
	# rusticated base band, cornices
	kit.box("stone", t, Vector3(0, fh * 0.5 + 0.4, d / 2 + 0.12), Vector3(w + 0.1, fh + 0.4, 0.25), col.darkened(0.12))
	kit.box("plain", t, Vector3(0, fh + 0.9, 0), Vector3(w + 0.5, 0.35, d + 0.5), trim)
	kit.box("plain", t, Vector3(0, h - 0.2, 0), Vector3(w + 1.2, 0.6, d + 1.2), trim)
	kit.box("plain", t, Vector3(0, h + 0.35, 0), Vector3(w + 0.6, 0.5, d + 0.6), trim)
	# pilasters on the street facade
	var n := int(w / 3.6)
	for i in n + 1:
		var x := -w / 2 + w * float(i) / n
		kit.box("plain", t, Vector3(x, fh + 1.1 + (h - fh - 1.6) * 0.5, d / 2 + 0.15), Vector3(0.5, h - fh - 1.6, 0.3), trim)
	# central portal with columns and pediment
	var pw := minf(14.0, w * 0.35)
	for i in 4:
		var x2 := -pw / 2 + pw * float(i) / 3.0
		kit.cylinder("marble", t * Transform3D(Basis(), Vector3(x2, 0, d / 2 + 2.2)), 0.45, 0.4, fh * 2.0, 10, trim)
	kit.box("plain", t, Vector3(0, fh * 2.0 + 0.3, d / 2 + 1.4), Vector3(pw + 1.6, 0.6, 3.2), trim)
	var tp := t
	var pa := tp * Vector3(-pw / 2 - 0.8, fh * 2.0 + 0.6, d / 2 + 3.0)
	var pb := tp * Vector3(pw / 2 + 0.8, fh * 2.0 + 0.6, d / 2 + 3.0)
	var pc := tp * Vector3(0, fh * 2.0 + 2.6, d / 2 + 3.0)
	kit.tri("plain", pa, pb, pc, trim)
	kit.quad("plain", tp * Vector3(pw / 2 + 0.8, fh * 2.0 + 0.6, d / 2 + 3.0), tp * Vector3(pw / 2 + 0.8, fh * 2.0 + 0.6, d / 2 - 0.2),
		tp * Vector3(0, fh * 2.0 + 2.6, d / 2 - 0.2), tp * Vector3(0, fh * 2.0 + 2.6, d / 2 + 3.0), Color(0.5, 0.5, 0.52))
	kit.quad("plain", tp * Vector3(-pw / 2 - 0.8, fh * 2.0 + 0.6, d / 2 - 0.2), tp * Vector3(-pw / 2 - 0.8, fh * 2.0 + 0.6, d / 2 + 3.0),
		tp * Vector3(0, fh * 2.0 + 2.6, d / 2 + 3.0), tp * Vector3(0, fh * 2.0 + 2.6, d / 2 - 0.2), Color(0.5, 0.5, 0.52))
	kit.box("concrete", t, Vector3(0, 0.3, d / 2 + 3.5), Vector3(pw + 4.0, 0.6, 3.0), Color(0.8, 0.78, 0.74))
	# hip roof
	_roof_hip(kit, t, w, d, h + 0.6, minf(d * 0.35, 5.0), Color(0.45, 0.5, 0.48))


static func _shop(kit: MeshKit, b: Array, org: Vector3, labels: Array) -> void:
	var r := rnd(int(b[8]))
	var t := transform_of(b, org)
	var w: float = b[3]
	var d: float = b[4]
	var floors: int = b[5]
	var h := FLOOR_H[4] * floors + 0.6
	var col: Color = WALLS[4][r.randi() % WALLS[4].size()]
	kit.uv2 = Vector2(4 + r.randf() * 0.98, h + 2.0)
	_walls(kit, t, Vector3(0, -2.0, 0), Vector3(w, h + 2.0, d), col)
	kit.uv2 = Vector2.ZERO
	_roof_flat(kit, t, w, d, h, 0.8, col)
	var acc: Color = ACCENTS[r.randi() % ACCENTS.size()]
	# sign board and awning
	kit.box("plain", t, Vector3(0, 3.9, d / 2 + 0.25), Vector3(w * 0.85, 1.1, 0.3), acc)
	kit.box("plain2", t, Vector3(0, 3.1, d / 2 + 1.2), Vector3(w * 0.9, 0.08, 2.2), acc.lightened(0.3))
	kit.box("concrete", t, Vector3(0, 0.12, d / 2 + 1.5), Vector3(w, 0.24, 3.0), Color(0.75, 0.74, 0.72))
	labels.append([t * Vector3(0, 3.9, d / 2 + 0.42), -deg_to_rad(float(b[2])), SIGNS[r.randi() % SIGNS.size()], Color(1, 1, 1)])


static func _havli(kit: MeshKit, b: Array, org: Vector3) -> void:
	var r := rnd(int(b[8]))
	var t := transform_of(b, org)
	var w: float = b[3]
	var d: float = b[4]
	var floors: int = b[5]
	var col: Color = WALLS[5][r.randi() % WALLS[5].size()]
	# courtyard wall (plastered), gate on the street side
	var wall_h := 2.4
	var wc := Color(0.88, 0.85, 0.78) if r.randf() < 0.6 else col
	var gate_w := 3.6
	kit.box("plain", t, Vector3(-(w / 2 + gate_w / 2) / 2 - 0.0, wall_h / 2 - 0.5, d / 2), Vector3(w / 2 - gate_w / 2, wall_h + 1.0, 0.3), wc)
	kit.box("plain", t, Vector3((w / 2 + gate_w / 2) / 2, wall_h / 2 - 0.5, d / 2), Vector3(w / 2 - gate_w / 2, wall_h + 1.0, 0.3), wc)
	kit.box("plain", t, Vector3(0, wall_h / 2 - 0.5, -d / 2), Vector3(w, wall_h + 1.0, 0.3), wc)
	kit.box("plain", t, Vector3(w / 2, wall_h / 2 - 0.5, 0), Vector3(0.3, wall_h + 1.0, d), wc)
	kit.box("plain", t, Vector3(-w / 2, wall_h / 2 - 0.5, 0), Vector3(0.3, wall_h + 1.0, d), wc)
	var gate_col: Color = [Color(0.2, 0.45, 0.65), Color(0.25, 0.5, 0.3), Color(0.55, 0.2, 0.15), Color(0.75, 0.6, 0.2)][r.randi() % 4]
	kit.box("metal", t, Vector3(0, 1.3, d / 2), Vector3(gate_w, 2.6, 0.08), gate_col)
	kit.box("plain", t, Vector3(0, 2.75, d / 2), Vector3(gate_w + 0.6, 0.3, 0.5), gate_col.darkened(0.2))
	# house at the back of the plot
	var hw := w * 0.62
	var hd := minf(9.0, d * 0.42)
	var hz := -d / 2 + hd / 2 + 1.0
	var fh := FLOOR_H[5]
	var h := fh * floors + 0.6
	kit.uv2 = Vector2(5 + r.randf() * 0.98, h + 1.0)
	_walls(kit, t, Vector3(0, -1.0, hz), Vector3(hw, h + 1.0, hd), col)
	kit.uv2 = Vector2.ZERO
	var roof_col: Color = ROOF_TIN[r.randi() % ROOF_TIN.size()]
	var tr := t * Transform3D(Basis(), Vector3(0, 0, hz))
	if r.randf() < 0.65:
		_roof_hip(kit, tr, hw, hd, h, 2.2, roof_col)
	else:
		_roof_gable(kit, tr, hw, hd, h, 2.0, roof_col)
	# veranda (ayvan) along the front of the house
	var vz := hz + hd / 2 + 1.4
	kit.box("wood", t, Vector3(0, 0.25, vz), Vector3(hw, 0.5, 2.8), Color(0.6, 0.45, 0.3))
	for i in 4:
		var x := -hw / 2 + 0.3 + (hw - 0.6) * float(i) / 3.0
		kit.box("wood", t, Vector3(x, 1.75, vz + 1.2), Vector3(0.22, 2.5, 0.22), Color(0.55, 0.38, 0.24))
	kit.box("wood", t, Vector3(0, 3.05, vz), Vector3(hw + 0.4, 0.12, 3.0), Color(0.5, 0.36, 0.24))
	# grape trellis over the yard
	if r.randf() < 0.6:
		for i in 3:
			for j in 2:
				kit.box("wood", t, Vector3(-hw / 3 + hw / 3 * i, 1.3, vz + 2.5 + j * 3.5), Vector3(0.12, 2.6, 0.12), Color(0.45, 0.33, 0.22))
		kit.box("foliage", t, Vector3(0, 2.65, vz + 4.2), Vector3(hw * 0.8, 0.3, 4.2), Color(0.3, 0.5, 0.2))
	# tapchan (raised platform) in the yard
	kit.box("wood", t, Vector3(w / 4, 0.45, d / 4), Vector3(2.4, 0.15, 2.0), Color(0.55, 0.4, 0.25))
	kit.box("plain", t, Vector3(w / 4, 0.56, d / 4), Vector3(2.2, 0.08, 1.8), Color(0.75, 0.2, 0.2))


static func _school(kit: MeshKit, b: Array, org: Vector3) -> void:
	var r := rnd(int(b[8]))
	var t := transform_of(b, org)
	var w: float = b[3]
	var d: float = b[4]
	var floors: int = b[5]
	var fh: float = FLOOR_H[6]
	var h := fh * floors + 0.8
	var col: Color = WALLS[6][r.randi() % WALLS[6].size()]
	kit.uv2 = Vector2(6 + r.randf() * 0.98, h + 2.0)
	_walls(kit, t, Vector3(0, -2.0, 0), Vector3(w, h + 2.0, d), col)
	# entrance block
	kit.uv2 = Vector2(6 + r.randf() * 0.98, h + 4.0)
	_walls(kit, t, Vector3(0, -2.0, d / 2 + 2.5), Vector3(14.0, h + 4.0, 5.0), col.lightened(0.05))
	kit.uv2 = Vector2.ZERO
	_roof_flat(kit, t, w, d, h, 0.7, col)
	var te := t * Transform3D(Basis(), Vector3(0, 0, d / 2 + 2.5))
	_roof_flat(kit, te, 14.0, 5.0, h + 2.0, 0.7, col)
	kit.box("concrete", t, Vector3(0, 0.3, d / 2 + 6.5), Vector3(12.0, 0.6, 3.0), Color(0.8, 0.78, 0.74))
	kit.box("plain", t, Vector3(0, 3.6, d / 2 + 5.3), Vector3(8.0, 0.25, 2.6), Color(0.9, 0.9, 0.88))
	# flagpole with the national flag colours
	var fp := Vector3(9.0, 0, d / 2 + 9.0)
	kit.cylinder("metal", t * Transform3D(Basis(), fp), 0.08, 0.06, 10.0, 6, Color(0.8, 0.8, 0.8))
	kit.box("plain2", t, fp + Vector3(1.0, 9.4, 0), Vector3(2.0, 0.4, 0.03), Color(0.8, 0.0, 0.0))
	kit.box("plain2", t, fp + Vector3(1.0, 9.0, 0), Vector3(2.0, 0.4, 0.03), Color(1, 1, 1))
	kit.box("plain2", t, fp + Vector3(1.0, 8.6, 0), Vector3(2.0, 0.4, 0.03), Color(0.0, 0.5, 0.15))
	# sports ground outline / fence in front
	kit.box("metal", t, Vector3(0, 0.75, d / 2 + 14.0), Vector3(w, 1.5, 0.05), Color(0.35, 0.55, 0.4))


static func _village_house(kit: MeshKit, b: Array, org: Vector3) -> void:
	var r := rnd(int(b[8]))
	var t := transform_of(b, org)
	var w: float = b[3]
	var d: float = b[4]
	var floors: int = b[5]
	var col: Color = WALLS[7][r.randi() % WALLS[7].size()]
	if w < 15.0:
		# small village shop / building without yard
		var h0 := FLOOR_H[7] * floors + 0.4
		kit.uv2 = Vector2(7 + r.randf() * 0.98, h0 + 1.5)
		_walls(kit, t, Vector3(0, -1.5, 0), Vector3(w, h0 + 1.5, d), col.lightened(0.1))
		kit.uv2 = Vector2.ZERO
		_roof_flat(kit, t, w, d, h0, 0.5, col)
		kit.box("plain", t, Vector3(0, 2.6, d / 2 + 0.2), Vector3(w * 0.7, 0.8, 0.2), Color(0.2, 0.45, 0.7))
		return
	# mud-brick duval (yard wall)
	var mud := Color(0.72, 0.6, 0.45)
	var wh := 2.0
	var gate_w := 3.0
	kit.box("dirt", t, Vector3(-(w / 2 + gate_w / 2) / 2, wh / 2 - 0.5, d / 2), Vector3(w / 2 - gate_w / 2, wh + 1.0, 0.45), mud)
	kit.box("dirt", t, Vector3((w / 2 + gate_w / 2) / 2, wh / 2 - 0.5, d / 2), Vector3(w / 2 - gate_w / 2, wh + 1.0, 0.45), mud)
	kit.box("dirt", t, Vector3(0, wh / 2 - 0.5, -d / 2), Vector3(w, wh + 1.0, 0.45), mud)
	kit.box("dirt", t, Vector3(w / 2, wh / 2 - 0.5, 0), Vector3(0.45, wh + 1.0, d), mud)
	kit.box("dirt", t, Vector3(-w / 2, wh / 2 - 0.5, 0), Vector3(0.45, wh + 1.0, d), mud)
	kit.box("wood", t, Vector3(0, 1.1, d / 2), Vector3(gate_w, 2.2, 0.1), Color(0.5, 0.35, 0.2))
	# house: L-shape or straight, flat earth roof or low tin roof
	var hw := w * 0.7
	var hd := 6.5
	var hz := -d / 2 + hd / 2 + 0.8
	var h := FLOOR_H[7] * floors + 0.3
	kit.uv2 = Vector2(7 + r.randf() * 0.98, h + 1.0)
	_walls(kit, t, Vector3(0, -1.0, hz), Vector3(hw, h + 1.0, hd), col)
	var lshape := r.randf() < 0.5
	if lshape:
		_walls(kit, t, Vector3(-hw / 2 + 3.0, -1.0, hz + hd / 2 + 3.5), Vector3(6.0, h + 1.0, 7.0), col)
	kit.uv2 = Vector2.ZERO
	var tr := t * Transform3D(Basis(), Vector3(0, 0, hz))
	if r.randf() < 0.5:
		_roof_flat(kit, tr, hw + 0.8, hd + 0.8, h, 0.3, col.darkened(0.15))
		if lshape:
			_roof_flat(kit, t * Transform3D(Basis(), Vector3(-hw / 2 + 3.0, 0, hz + hd / 2 + 3.5)), 6.8, 7.8, h, 0.3, col.darkened(0.15))
		# hay stack on the roof
		if r.randf() < 0.4:
			kit.sphere("plain", t * Transform3D(Basis().scaled(Vector3(1.6, 0.8, 1.2)), Vector3(hw / 4, h + 0.5, hz)), 1.0, 5, 8, Color(0.82, 0.72, 0.4))
	else:
		_roof_gable(kit, tr, hw, hd, h, 1.6, ROOF_TIN[r.randi() % ROOF_TIN.size()])
		if lshape:
			_roof_flat(kit, t * Transform3D(Basis(), Vector3(-hw / 2 + 3.0, 0, hz + hd / 2 + 3.5)), 6.8, 7.8, h, 0.3, col.darkened(0.15))
	# ayvan with carved wooden columns
	var vz := hz + hd / 2 + 1.3
	var vx := 2.0 if lshape else 0.0
	var vw := hw - (6.0 if lshape else 0.0)
	kit.box("wood", t, Vector3(vx, 0.2, vz), Vector3(vw, 0.4, 2.6), Color(0.55, 0.42, 0.3))
	var nc := maxi(2, int(vw / 2.5))
	for i in nc + 1:
		var x := vx - vw / 2 + 0.2 + (vw - 0.4) * float(i) / nc
		kit.cylinder("wood", t * Transform3D(Basis(), Vector3(x, 0.4, vz + 1.1)), 0.13, 0.11, 2.4, 6, Color(0.5, 0.35, 0.22))
		kit.box("wood", t, Vector3(x, 2.75, vz + 1.1), Vector3(0.45, 0.25, 0.3), Color(0.48, 0.34, 0.22))
	kit.box("wood", t, Vector3(vx, 2.95, vz), Vector3(vw + 0.3, 0.15, 2.9), Color(0.45, 0.33, 0.22))
	# tapchan and a small tandoor oven in the yard
	kit.box("wood", t, Vector3(w / 4, 0.45, d / 4), Vector3(2.4, 0.15, 2.0), Color(0.55, 0.4, 0.25))
	kit.box("plain", t, Vector3(w / 4, 0.56, d / 4), Vector3(2.2, 0.08, 1.8), Color(0.7, 0.15, 0.2))
	kit.cylinder("dirt", t * Transform3D(Basis(), Vector3(-w / 3, 0, d / 3)), 0.8, 0.5, 1.3, 10, Color(0.8, 0.68, 0.52))
