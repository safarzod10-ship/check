class_name LmKit
extends RefCounted
## Architectural helper primitives for landmark / POI builders (thread safe, MeshKit based).
## Local convention for every builder: origin = landmark centre at ground level (y = 0),
## main facade faces local +Z. LandmarkManager rotates by the layout yaw (Basis(UP, yaw)).

const MARBLE := Color(0.94, 0.92, 0.87)
const TRAVERTINE := Color(0.95, 0.84, 0.66)
const CREAM := Color(0.96, 0.88, 0.74)
const PEACH := Color(0.95, 0.78, 0.62)
const SAND := Color(0.86, 0.78, 0.62)
const BRICK := Color(0.66, 0.46, 0.32)
const MUD := Color(0.72, 0.6, 0.44)
const TURQ := Color(0.12, 0.62, 0.68)
const BLUE_TILE := Color(0.16, 0.32, 0.66)
const BRONZE := Color(0.45, 0.32, 0.18)
const GOLDC := Color(1.0, 0.78, 0.3)
const GLASS := Color(0.22, 0.34, 0.45)
const DARK := Color(0.18, 0.18, 0.2)
const LAWN := Color(0.24, 0.44, 0.15)
const SOIL := Color(0.36, 0.26, 0.18)
const WOOD := Color(0.55, 0.38, 0.22)
const METAL := Color(0.35, 0.36, 0.38)
const RED := Color(0.8, 0.1, 0.1)
const WHITE := Color(0.97, 0.97, 0.97)
const GREEN := Color(0.0, 0.5, 0.2)


static func xf(p: Vector3, yaw := 0.0) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), p)


static func box(k: MeshKit, slot: String, center: Vector3, size: Vector3, col: Color, yaw := 0.0, bottom := false) -> void:
	k.box(slot, xf(center, yaw), Vector3.ZERO, size, col, bottom)


## Box standing on y = base.y (base = bottom centre).
static func block(k: MeshKit, slot: String, base: Vector3, size: Vector3, col: Color, yaw := 0.0) -> void:
	k.box(slot, xf(base + Vector3(0, size.y * 0.5, 0), yaw), Vector3.ZERO, size, col)


static func cyl(k: MeshKit, slot: String, base: Vector3, r0: float, r1: float, h: float, col: Color, segs := 16, cap := true) -> void:
	k.cylinder(slot, xf(base), r0, r1, h, segs, col, cap, false)


static func dome(k: MeshKit, slot: String, center: Vector3, r: float, col: Color, segs := 24, squash := 1.0) -> void:
	var t := Transform3D(Basis.from_scale(Vector3(1, squash, 1)), center)
	k.sphere(slot, t, r, maxi(4, segs / 3), segs, col, true)


static func ball(k: MeshKit, slot: String, center: Vector3, r: float, col: Color, segs := 12, scale := Vector3.ONE) -> void:
	k.sphere(slot, Transform3D(Basis.from_scale(scale), center), r, maxi(4, segs / 2), segs, col, false)


## Central-Asian onion / ribbed dome on top of base.
static func onion(k: MeshKit, slot: String, base: Vector3, r: float, h: float, col: Color, segs := 24) -> void:
	var prof := [Vector2(r * 0.92, 0), Vector2(r * 1.04, h * 0.14), Vector2(r * 1.1, h * 0.3), Vector2(r * 1.0, h * 0.48),
		Vector2(r * 0.72, h * 0.68), Vector2(r * 0.36, h * 0.85), Vector2(r * 0.1, h * 0.96), Vector2(0.0, h)]
	k.lathe(slot, xf(base), prof, segs, col)


## Classical column: plinth, tapered shaft, capital.
static func column(k: MeshKit, slot: String, base: Vector3, r: float, h: float, col: Color, segs := 12) -> void:
	block(k, slot, base, Vector3(r * 2.6, r * 0.6, r * 2.6), col)
	k.cylinder(slot, xf(base + Vector3(0, r * 0.6, 0)), r, r * 0.86, h - r * 1.4, segs, col, false, false)
	block(k, slot, base + Vector3(0, h - r * 0.8, 0), Vector3(r * 2.4, r * 0.8, r * 2.4), col)


## Row of columns between a and b (inclusive).
static func colonnade(k: MeshKit, slot: String, a: Vector3, b: Vector3, n: int, r: float, h: float, col: Color) -> void:
	for i in n:
		var t := float(i) / maxf(1.0, n - 1)
		column(k, slot, a.lerp(b, t), r, h, col)


## Stairs rising towards -Z. front = bottom-front centre.
static func stairs(k: MeshKit, slot: String, front: Vector3, width: float, depth: float, height: float, steps: int, col: Color, yaw := 0.0) -> void:
	var sd := depth / steps
	var sh := height / steps
	var b := Basis(Vector3.UP, yaw)
	for i in steps:
		var zc := -(i * sd + (depth - i * sd) * 0.5)
		var hh := (i + 1) * sh
		k.box(slot, Transform3D(b, front + b * Vector3(0, hh * 0.5, zc)), Vector3.ZERO, Vector3(width, hh, depth - i * sd), col)


## Triangular pediment; base = centre of the bottom edge (front face at +Z of the centre).
static func pediment(k: MeshKit, slot: String, base: Vector3, w: float, h: float, d: float, col: Color, yaw := 0.0) -> void:
	var t := xf(base, yaw)
	var hd := d * 0.5
	var af := t * Vector3(-w * 0.5, 0, hd)
	var bf := t * Vector3(w * 0.5, 0, hd)
	var cf := t * Vector3(0, h, hd)
	var ab := t * Vector3(-w * 0.5, 0, -hd)
	var bb := t * Vector3(w * 0.5, 0, -hd)
	var cb := t * Vector3(0, h, -hd)
	k.tri(slot, af, bf, cf, col)
	k.tri(slot, bb, ab, cb, col)
	k.quad(slot, bf, bb, cb, cf, col)
	k.quad(slot, af, cf, cb, ab, col)


## Gable / pitched roof over a w x d rectangle, ridge along X. base = centre at eave height.
static func gable_roof(k: MeshKit, slot: String, base: Vector3, w: float, d: float, h: float, col: Color, yaw := 0.0) -> void:
	var t := xf(base, yaw)
	var hw := w * 0.5
	var hd := d * 0.5
	var a := t * Vector3(-hw, 0, hd)
	var b := t * Vector3(hw, 0, hd)
	var c := t * Vector3(hw, h, 0)
	var dd := t * Vector3(-hw, h, 0)
	var e := t * Vector3(hw, 0, -hd)
	var f := t * Vector3(-hw, 0, -hd)
	k.quad(slot, a, b, c, dd, col)
	k.quad(slot, e, f, dd, c, col)
	k.tri(slot, b, e, c, col)
	k.tri(slot, f, a, dd, col)


## Hip roof (4 slopes) — pyramid-ish over a rectangle. base = centre at eave height.
static func hip_roof(k: MeshKit, slot: String, base: Vector3, w: float, d: float, h: float, col: Color, yaw := 0.0) -> void:
	var t := xf(base, yaw)
	var hw := w * 0.5
	var hd := d * 0.5
	var r := minf(hw, hd) * 0.9
	var a := t * Vector3(-hw, 0, hd)
	var b := t * Vector3(hw, 0, hd)
	var c := t * Vector3(hw, 0, -hd)
	var d2 := t * Vector3(-hw, 0, -hd)
	var r1 := t * Vector3(hw - r, h, 0)
	var r0 := t * Vector3(-(hw - r), h, 0)
	k.quad(slot, a, b, r1, r0, col)
	k.quad(slot, c, d2, r0, r1, col)
	k.tri(slot, b, c, r1, col)
	k.tri(slot, d2, a, r0, col)


## Arched portal wall in the local XY plane, depth along Z, centred at base (bottom centre).
static func portal(k: MeshKit, slot: String, base: Vector3, w: float, h: float, d: float, ow: float, oh: float, col: Color, yaw := 0.0) -> void:
	k.arch_wall(slot, xf(base, yaw), w, h, d, ow, oh, col, 12)


## Iwan: tall arched portal with a deep niche behind it (thin boxes, visible from inside).
static func iwan(k: MeshKit, slot: String, base: Vector3, w: float, h: float, ow: float, oh: float, depth: float,
		col: Color, inner: Color, yaw := 0.0, frame_col := Color(-1, 0, 0)) -> void:
	var t := xf(base, yaw)
	var fc := frame_col if frame_col.r >= 0.0 else col
	k.arch_wall(slot, t, w, h, 2.0, ow, oh, fc, 14)
	# niche: back wall, side walls, ceiling (thin)
	k.box(slot, t, Vector3(0, oh * 0.5, -depth), Vector3(ow, oh, 0.6), inner)
	k.box(slot, t, Vector3(-ow * 0.5 - 0.2, oh * 0.5, -depth * 0.5), Vector3(0.4, oh, depth), inner)
	k.box(slot, t, Vector3(ow * 0.5 + 0.2, oh * 0.5, -depth * 0.5), Vector3(0.4, oh, depth), inner)
	k.box(slot, t, Vector3(0, oh + 0.2, -depth * 0.5), Vector3(ow + 0.8, 0.4, depth), inner)
	# glazed tile frame band around the portal
	k.box("glossy", t, Vector3(0, h - 0.6, 1.05), Vector3(w * 0.92, 0.9, 0.12), TURQ)
	k.box("glossy", t, Vector3(-w * 0.46 + 0.4, h * 0.5, 1.05), Vector3(0.8, h - 1.0, 0.12), BLUE_TILE)
	k.box("glossy", t, Vector3(w * 0.46 - 0.4, h * 0.5, 1.05), Vector3(0.8, h - 1.0, 0.12), BLUE_TILE)


## Windows grid on a facade plane facing +Z of t. Window panes protrude 0.08 m.
static func windows(k: MeshKit, t: Transform3D, x0: float, x1: float, y0: float, rows: int, cols: int,
		floor_h: float, ww: float, wh: float, z: float, col := GLASS, frame := Color(0.9, 0.9, 0.88)) -> void:
	for r in rows:
		for c in cols:
			var x := lerpf(x0, x1, (c + 0.5) / cols)
			var y := y0 + r * floor_h + floor_h * 0.5
			k.box("glass", t, Vector3(x, y, z + 0.04), Vector3(ww, wh, 0.1), col)
			k.box("plain", t, Vector3(x, y - wh * 0.5 - 0.08, z + 0.1), Vector3(ww + 0.3, 0.16, 0.25), frame)


static func cornice(k: MeshKit, slot: String, center: Vector3, w: float, d: float, col: Color, yaw := 0.0) -> void:
	box(k, slot, center, Vector3(w, 0.7, d), col, yaw)
	box(k, slot, center + Vector3(0, 0.5, 0), Vector3(w + 0.6, 0.3, d + 0.6), col, yaw)


## Flat ground pieces (raised slightly to avoid z-fighting with the terrain).
static func pave(k: MeshKit, slot: String, center: Vector3, size_xz: Vector2, col: Color, yaw := 0.0, y := 0.05, thick := 0.5) -> void:
	box(k, slot, center + Vector3(0, y - thick * 0.5, 0), Vector3(size_xz.x, thick, size_xz.y), col, yaw)


static func lawn(k: MeshKit, center: Vector3, size_xz: Vector2, yaw := 0.0) -> void:
	pave(k, "plain", center, size_xz, LAWN, yaw, 0.12, 0.4)


static func disc(k: MeshKit, slot: String, center: Vector3, r: float, col: Color, h := 0.12, segs := 32) -> void:
	k.cylinder(slot, xf(center + Vector3(0, -0.3, 0)), r, r, h + 0.3, segs, col, true, false)


## Fountain with stone basin, water surface and central jets.
static func fountain(k: MeshKit, center: Vector3, r: float, stone := MARBLE, tiers := 2) -> void:
	k.cylinder("marble", xf(center), r + 0.4, r + 0.4, 0.75, 32, stone, true, false)
	k.cylinder("lm_water", xf(center + Vector3(0, 0.78, 0)), r - 0.3, r - 0.3, 0.02, 32, Color(0.3, 0.55, 0.65), true, false)
	var y := 0.78
	var rr := r * 0.35
	for i in tiers:
		k.cylinder("marble", xf(center + Vector3(0, y, 0)), rr * 0.25, rr * 0.25, 1.2, 10, stone, false, false)
		y += 1.2
		k.cylinder("marble", xf(center + Vector3(0, y, 0)), rr * 0.3, rr, 0.35, 16, stone, true, false)
		k.cylinder("lm_water", xf(center + Vector3(0, y + 0.36, 0)), rr * 0.85, rr * 0.85, 0.01, 16, Color(0.4, 0.6, 0.7), true, false)
		y += 0.36
		rr *= 0.55
	# jets
	k.cylinder("lm_water", xf(center + Vector3(0, y, 0)), 0.12, 0.05, 2.5, 6, Color(0.85, 0.92, 1.0), false, false)
	for a in 8:
		var ang := TAU * a / 8.0
		var p := center + Vector3(cos(ang), 0, sin(ang)) * (r * 0.7)
		k.cylinder("lm_water", xf(p + Vector3(0, 0.78, 0)), 0.08, 0.03, 1.4, 5, Color(0.85, 0.92, 1.0), false, false)


static func flower_bed(k: MeshKit, center: Vector3, size: Vector2, seed: int, yaw := 0.0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	box(k, "stone", center + Vector3(0, 0.2, 0), Vector3(size.x + 0.4, 0.4, size.y + 0.4), Color(0.8, 0.78, 0.72), yaw)
	box(k, "plain", center + Vector3(0, 0.42, 0), Vector3(size.x, 0.06, size.y), SOIL, yaw)
	var cols := [Color(0.9, 0.1, 0.15), Color(1.0, 0.8, 0.1), Color(0.95, 0.4, 0.6), Color(0.6, 0.2, 0.8), Color(1, 1, 1), Color(1.0, 0.5, 0.1)]
	var b := Basis(Vector3.UP, yaw)
	var n := int(size.x * size.y * 0.8)
	var palette := [cols[rng.randi() % cols.size()], cols[rng.randi() % cols.size()]]
	for i in mini(n, 160):
		var lp := Vector3(rng.randf_range(-0.5, 0.5) * size.x, 0.45, rng.randf_range(-0.5, 0.5) * size.y)
		var c: Color = palette[i % 2]
		k.box("plain", Transform3D(b, center + b * lp + Vector3(0, 0.15, 0)), Vector3.ZERO, Vector3(0.28, 0.3, 0.28), c)


static func tree(k: MeshKit, base: Vector3, h: float, r: float, seed: int, kind := 0) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var g := Color(0.22 + rng.randf() * 0.08, 0.42 + rng.randf() * 0.12, 0.16)
	if kind == 1:   # cypress / juniper column
		k.cylinder("bark", xf(base), 0.25, 0.2, h * 0.2, 6, WOOD, false)
		k.cylinder("lm_leaves", xf(base + Vector3(0, h * 0.15, 0)), r, 0.05, h * 0.85, 8, g.darkened(0.25), false)
		return
	k.cylinder("bark", xf(base), r * 0.09, r * 0.06, h * 0.55, 6, WOOD, false)
	ball(k, "lm_leaves", base + Vector3(0, h * 0.62, 0), r, g, 10, Vector3(1, 0.85, 1))
	ball(k, "lm_leaves", base + Vector3(r * 0.45, h * 0.78, r * 0.2), r * 0.7, g.lightened(0.08), 8)
	ball(k, "lm_leaves", base + Vector3(-r * 0.35, h * 0.82, -r * 0.3), r * 0.65, g.darkened(0.08), 8)


static func bench(k: MeshKit, pos: Vector3, yaw: float) -> void:
	var t := xf(pos, yaw)
	k.box("wood", t, Vector3(0, 0.45, 0), Vector3(1.8, 0.08, 0.5), WOOD)
	k.box("wood", t, Vector3(0, 0.75, -0.22), Vector3(1.8, 0.4, 0.06), WOOD)
	k.box("metal", t, Vector3(-0.8, 0.22, 0), Vector3(0.08, 0.45, 0.5), DARK)
	k.box("metal", t, Vector3(0.8, 0.22, 0), Vector3(0.08, 0.45, 0.5), DARK)


static func lamp(k: MeshKit, pos: Vector3, h := 5.0, double := false) -> void:
	k.cylinder("metal", xf(pos), 0.14, 0.08, h, 8, DARK, false)
	if double:
		k.box("metal", xf(pos + Vector3(0, h - 0.2, 0)), Vector3.ZERO, Vector3(1.6, 0.1, 0.1), DARK)
		ball(k, "lamp", pos + Vector3(-0.8, h - 0.4, 0), 0.32, Color(1.0, 0.92, 0.7), 8)
		ball(k, "lamp", pos + Vector3(0.8, h - 0.4, 0), 0.32, Color(1.0, 0.92, 0.7), 8)
	else:
		ball(k, "lamp", pos + Vector3(0, h + 0.25, 0), 0.38, Color(1.0, 0.92, 0.7), 8)


static func railing(k: MeshKit, a: Vector3, b: Vector3, h := 1.1, col := DARK) -> void:
	var d := a.distance_to(b)
	var n := maxi(1, int(d / 2.0))
	var dir := (b - a).normalized()
	var yaw := atan2(dir.x, dir.z)
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		k.box("metal", xf(p + Vector3(0, h * 0.5, 0)), Vector3.ZERO, Vector3(0.07, h, 0.07), col)
	var mid := (a + b) * 0.5
	k.box("metal", xf(mid + Vector3(0, h, 0), yaw), Vector3.ZERO, Vector3(0.08, 0.08, d), col)
	k.box("metal", xf(mid + Vector3(0, h * 0.5, 0), yaw), Vector3.ZERO, Vector3(0.05, 0.05, d), col)


## Stylised standing human figure (statues). base = feet centre, faces +Z of yaw.
static func statue(k: MeshKit, slot: String, base: Vector3, h: float, col: Color, yaw := 0.0, crown := false,
		staff := false, raised_arm := false, seated := false) -> void:
	var t := xf(base, yaw)
	var s := h / 1.8
	if seated:
		k.box(slot, t, Vector3(0, 0.25 * s, -0.05 * s), Vector3(0.6 * s, 0.5 * s, 0.6 * s), col)          # seat block
		k.box(slot, t, Vector3(0, 0.55 * s, 0.12 * s), Vector3(0.5 * s, 0.18 * s, 0.55 * s), col)         # thighs
		k.box(slot, t, Vector3(0, 0.3 * s, 0.38 * s), Vector3(0.45 * s, 0.5 * s, 0.18 * s), col)          # shins/robe
		k.cylinder(slot, t * Transform3D(Basis(), Vector3(0, 0.6 * s, -0.08 * s)), 0.27 * s, 0.2 * s, 0.6 * s, 10, col, false)
		k.sphere(slot, t * Transform3D(Basis(), Vector3(0, 1.32 * s, -0.08 * s)), 0.13 * s, 6, 10, col)
		k.cylinder(slot, t * Transform3D(Basis(), Vector3(0, 1.38 * s, -0.08 * s)), 0.15 * s, 0.13 * s, 0.14 * s, 10, col)  # turban
		k.box(slot, t, Vector3(0.3 * s, 0.85 * s, 0.1 * s), Vector3(0.12 * s, 0.4 * s, 0.4 * s), col)
		k.box(slot, t, Vector3(-0.3 * s, 0.85 * s, 0.1 * s), Vector3(0.12 * s, 0.4 * s, 0.4 * s), col)
		return
	# legs (in a long robe => frustum)
	k.cylinder(slot, t, 0.32 * s, 0.22 * s, 0.95 * s, 12, col, false)
	k.cylinder(slot, t * Transform3D(Basis(), Vector3(0, 0.95 * s, 0)), 0.22 * s, 0.24 * s, 0.5 * s, 12, col, false)
	k.box(slot, t, Vector3(0, 1.45 * s, 0), Vector3(0.62 * s, 0.14 * s, 0.32 * s), col)           # shoulders
	k.sphere(slot, t * Transform3D(Basis(), Vector3(0, 1.62 * s, 0)), 0.13 * s, 6, 10, col)         # head
	k.cylinder(slot, t * Transform3D(Basis(), Vector3(0, 1.48 * s, 0)), 0.07 * s, 0.07 * s, 0.1 * s, 6, col, false)
	# cape
	k.box(slot, t, Vector3(0, 0.95 * s, -0.25 * s), Vector3(0.6 * s, 1.0 * s, 0.06 * s), col)
	# arms
	k.box(slot, t, Vector3(-0.36 * s, 1.18 * s, 0.02 * s), Vector3(0.12 * s, 0.55 * s, 0.14 * s), col)
	if raised_arm:
		k.box(slot, t * Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0.36 * s, 1.55 * s, 0.15 * s)), Vector3.ZERO, Vector3(0.12 * s, 0.6 * s, 0.14 * s), col)
	else:
		k.box(slot, t, Vector3(0.36 * s, 1.18 * s, 0.05 * s), Vector3(0.12 * s, 0.55 * s, 0.14 * s), col)
	if crown:
		k.cylinder("gold", t * Transform3D(Basis(), Vector3(0, 1.7 * s, 0)), 0.13 * s, 0.15 * s, 0.12 * s, 10, GOLDC, false)
		for i in 5:
			var a := TAU * i / 5.0
			k.cylinder("gold", t * Transform3D(Basis(), Vector3(cos(a) * 0.13 * s, 1.82 * s, sin(a) * 0.13 * s)), 0.03 * s, 0.0, 0.1 * s, 4, GOLDC, false)
	if staff:
		k.cylinder("gold", t * Transform3D(Basis(Vector3.RIGHT, 0.0), Vector3(0.42 * s, 0.0, 0.18 * s)), 0.035 * s, 0.03 * s, 2.2 * s, 6, GOLDC, false)
		k.sphere("gold", t * Transform3D(Basis(), Vector3(0.42 * s, 2.25 * s, 0.18 * s)), 0.09 * s, 5, 8, GOLDC)


## Sitting lion (guardian). base = feet centre, faces +Z.
static func lion(k: MeshKit, slot: String, base: Vector3, s: float, col: Color, yaw := 0.0) -> void:
	var t := xf(base, yaw)
	k.sphere(slot, t * Transform3D(Basis.from_scale(Vector3(0.7, 0.6, 1.2)), Vector3(0, 0.75 * s, -0.4 * s)), 0.7 * s, 6, 12, col)
	k.sphere(slot, t * Transform3D(Basis.from_scale(Vector3(1.0, 1.1, 0.9)), Vector3(0, 1.45 * s, 0.35 * s)), 0.55 * s, 6, 12, col)  # mane
	k.sphere(slot, t * Transform3D(Basis(), Vector3(0, 1.5 * s, 0.75 * s)), 0.32 * s, 6, 10, col)            # head
	k.box(slot, t, Vector3(0, 1.4 * s, 1.02 * s), Vector3(0.28 * s, 0.24 * s, 0.25 * s), col)            # muzzle
	for sx: float in [-0.3, 0.3]:
		k.box(slot, t, Vector3(sx * s, 0.45 * s, 0.6 * s), Vector3(0.22 * s, 0.9 * s, 0.25 * s), col)   # front legs
		k.box(slot, t, Vector3(sx * 1.4 * s, 0.25 * s, -0.6 * s), Vector3(0.3 * s, 0.5 * s, 0.8 * s), col)  # haunches


## Simple car-park markings and kerb.
static func parking_lot(k: MeshKit, center: Vector3, w: float, d: float, yaw := 0.0) -> void:
	pave(k, "concrete", center, Vector2(w, d), Color(0.45, 0.45, 0.47), yaw, 0.1, 0.6)
	var b := Basis(Vector3.UP, yaw)
	var n := int(w / 3.0)
	for i in n + 1:
		var x := -w * 0.5 + i * 3.0
		for zs in [-1.0, 1.0]:
			var p := center + b * Vector3(x, 0.12, zs * d * 0.25)
			k.box("plain", Transform3D(b, p), Vector3.ZERO, Vector3(0.12, 0.02, d * 0.4), WHITE)


## Label spec helper: builders append to lm["_labels"].
static func label(lm: Dictionary, pos: Vector3, text: String, size := 64, col := Color(1, 1, 1), yaw := 0.0) -> void:
	if not lm.has("_labels"):
		lm["_labels"] = []
	lm["_labels"].append([pos, text, size, col, yaw])
