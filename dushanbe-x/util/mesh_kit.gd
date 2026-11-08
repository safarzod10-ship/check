class_name MeshKit
extends RefCounted
## Lightweight procedural mesh builder. Geometry is accumulated per material slot
## (String) into packed arrays, then turned into a multi-surface ArrayMesh.
## Safe to use from worker threads (no scene / RenderingServer access) until build().
##
## Conventions: Y up, quads given counter-clockwise as seen from the front,
## UVs are in metres (u along the first edge, v along the second) * uv_scale.
## UV2 carries per-object data for shaders (e.g. building style / seed).

var surfaces: Dictionary = {}
## Optional slot remapping (e.g. {"stone": "plain"}) to merge materials and cut draw calls.
var slot_remap: Dictionary = {}
var uv_scale := 1.0
var uv2 := Vector2.ZERO


func _s(slot: String) -> Dictionary:
	if not slot_remap.is_empty():
		slot = slot_remap.get(slot, slot)
	if not surfaces.has(slot):
		surfaces[slot] = {
			"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(),
			"uv": PackedVector2Array(), "uv2": PackedVector2Array(), "i": PackedInt32Array(),
		}
	return surfaces[slot]


func vertex_count() -> int:
	var c := 0
	for k in surfaces:
		c += surfaces[k]["v"].size()
	return c


func is_empty() -> bool:
	return vertex_count() == 0


# ---------------------------------------------------------------------------
# Primitives
# ---------------------------------------------------------------------------
func tri(slot: String, a: Vector3, b: Vector3, c: Vector3, col: Color, n := Vector3.ZERO) -> void:
	var s := _s(slot)
	if n == Vector3.ZERO:
		n = (b - a).cross(c - a).normalized()
	var base: int = s["v"].size()
	s["v"].append_array([a, b, c])
	s["n"].append_array([n, n, n])
	s["c"].append_array([col, col, col])
	s["uv"].append_array([Vector2(a.x + a.z, a.y) * uv_scale, Vector2(b.x + b.z, b.y) * uv_scale, Vector2(c.x + c.z, c.y) * uv_scale])
	s["uv2"].append_array([uv2, uv2, uv2])
	s["i"].append_array([base, base + 2, base + 1])


## Quad a-b-c-d counter-clockwise seen from the front.
func quad(slot: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uv_override := PackedVector2Array()) -> void:
	var s := _s(slot)
	var n := (b - a).cross(d - a)
	if n.length_squared() < 1e-12:
		n = (c - b).cross(a - b)
	n = n.normalized()
	var base: int = s["v"].size()
	s["v"].append_array([a, b, c, d])
	s["n"].append_array([n, n, n, n])
	s["c"].append_array([col, col, col, col])
	if uv_override.size() == 4:
		s["uv"].append_array(uv_override)
	else:
		var w := a.distance_to(b) * uv_scale
		var h := a.distance_to(d) * uv_scale
		s["uv"].append_array([Vector2(0, h), Vector2(w, h), Vector2(w, 0), Vector2(0, 0)])
	s["uv2"].append_array([uv2, uv2, uv2, uv2])
	s["i"].append_array([base, base + 2, base + 1, base, base + 3, base + 2])


## Axis-aligned box in local space of t, centred at `center`.
func box(slot: String, t: Transform3D, center: Vector3, size: Vector3, col: Color, bottom := false, top := true) -> void:
	var h := size * 0.5
	var p := [
		t * (center + Vector3(-h.x, -h.y, -h.z)), t * (center + Vector3(h.x, -h.y, -h.z)),
		t * (center + Vector3(h.x, -h.y, h.z)), t * (center + Vector3(-h.x, -h.y, h.z)),
		t * (center + Vector3(-h.x, h.y, -h.z)), t * (center + Vector3(h.x, h.y, -h.z)),
		t * (center + Vector3(h.x, h.y, h.z)), t * (center + Vector3(-h.x, h.y, h.z)),
	]
	# sides (front +Z, right +X, back -Z, left -X)
	quad(slot, p[3], p[2], p[6], p[7], col)
	quad(slot, p[2], p[1], p[5], p[6], col)
	quad(slot, p[1], p[0], p[4], p[5], col)
	quad(slot, p[0], p[3], p[7], p[4], col)
	if top:
		quad(slot, p[7], p[6], p[5], p[4], col)
	if bottom:
		quad(slot, p[0], p[1], p[2], p[3], col)


## Box from a world-space basis: origin at base centre, yaw in radians.
func box_yaw(slot: String, base_center: Vector3, yaw: float, size: Vector3, col: Color, bottom := false) -> void:
	var t := Transform3D(Basis(Vector3.UP, yaw), base_center)
	box(slot, t, Vector3(0, size.y * 0.5, 0), size, col, bottom)


## Cylinder / frustum / cone along local +Y starting at local origin.
func cylinder(slot: String, t: Transform3D, r0: float, r1: float, h: float, segs: int, col: Color,
		cap_top := true, cap_bottom := false, smooth := true) -> void:
	var s := _s(slot)
	var base: int = s["v"].size()
	var slope := (r0 - r1) / maxf(h, 0.001)
	for k in segs + 1:
		var a := TAU * k / segs
		var dir := Vector3(cos(a), 0, sin(a))
		var nl := (dir + Vector3(0, slope, 0)).normalized()
		var nw := (t.basis * nl).normalized()
		s["v"].append(t * (dir * r0))
		s["v"].append(t * (dir * r1 + Vector3(0, h, 0)))
		s["n"].append_array([nw, nw])
		s["c"].append_array([col, col])
		var u := float(k) / segs * TAU * maxf(r0, r1) * uv_scale
		s["uv"].append_array([Vector2(u, h * uv_scale), Vector2(u, 0)])
		s["uv2"].append_array([uv2, uv2])
	for k in segs:
		var i0 := base + k * 2
		# outward facing, clockwise front
		s["i"].append_array([i0, i0 + 2, i0 + 1, i0 + 2, i0 + 3, i0 + 1])
	if cap_top and r1 > 0.001:
		_disc(slot, t, h, r1, segs, col, true)
	if cap_bottom and r0 > 0.001:
		_disc(slot, t, 0.0, r0, segs, col, false)


func _disc(slot: String, t: Transform3D, y: float, r: float, segs: int, col: Color, up: bool) -> void:
	var s := _s(slot)
	var base: int = s["v"].size()
	var n := (t.basis * (Vector3.UP if up else Vector3.DOWN)).normalized()
	s["v"].append(t * Vector3(0, y, 0))
	s["n"].append(n)
	s["c"].append(col)
	s["uv"].append(Vector2.ZERO)
	s["uv2"].append(uv2)
	for k in segs + 1:
		var a := TAU * k / segs
		s["v"].append(t * Vector3(cos(a) * r, y, sin(a) * r))
		s["n"].append(n)
		s["c"].append(col)
		s["uv"].append(Vector2(cos(a), sin(a)) * r * uv_scale)
		s["uv2"].append(uv2)
	for k in segs:
		if up:
			s["i"].append_array([base, base + k + 1, base + k + 2])
		else:
			s["i"].append_array([base, base + k + 2, base + k + 1])


## Sphere / dome (hemi=true keeps the upper half) centred at local origin.
func sphere(slot: String, t: Transform3D, r: float, rings: int, segs: int, col: Color, hemi := false) -> void:
	var s := _s(slot)
	var base: int = s["v"].size()
	var phi_max := PI * 0.5 if hemi else PI
	for i in rings + 1:
		var phi := phi_max * float(i) / rings
		var y := cos(phi) * r
		var rr := sin(phi) * r
		for k in segs + 1:
			var a := TAU * k / segs
			var lp := Vector3(cos(a) * rr, y, sin(a) * rr)
			s["v"].append(t * lp)
			s["n"].append((t.basis * lp.normalized()).normalized())
			s["c"].append(col)
			s["uv"].append(Vector2(float(k) / segs * TAU * r, phi * r) * uv_scale)
			s["uv2"].append(uv2)
	for i in rings:
		for k in segs:
			var a := base + i * (segs + 1) + k
			var b := a + segs + 1
			s["i"].append_array([b, b + 1, a, b + 1, a + 1, a])


## Onion / bulb dome profile (Central Asian style). profile: Array of Vector2(radius, height)
func lathe(slot: String, t: Transform3D, profile: Array, segs: int, col: Color) -> void:
	var s := _s(slot)
	var base: int = s["v"].size()
	var np := profile.size()
	for i in np:
		var pr: Vector2 = profile[i]
		var prev: Vector2 = profile[maxi(0, i - 1)]
		var nxt: Vector2 = profile[mini(np - 1, i + 1)]
		var tan := (nxt - prev).normalized()
		var n2 := Vector2(tan.y, -tan.x)   # outward normal in (r,h)
		for k in segs + 1:
			var a := TAU * k / segs
			var dir := Vector3(cos(a), 0, sin(a))
			s["v"].append(t * (dir * pr.x + Vector3(0, pr.y, 0)))
			s["n"].append((t.basis * (dir * n2.x + Vector3(0, n2.y, 0))).normalized())
			s["c"].append(col)
			s["uv"].append(Vector2(float(k) / segs * TAU * pr.x, pr.y) * uv_scale)
			s["uv2"].append(uv2)
	for i in np - 1:
		for k in segs:
			var a := base + i * (segs + 1) + k
			var b := a + segs + 1
			s["i"].append_array([a, a + 1, b, a + 1, b + 1, b])


## Vertical prism from a 2D polygon (x,z) given counter-clockwise seen from above.
func prism(slot: String, t: Transform3D, poly: PackedVector2Array, h: float, col: Color, top := true, bottom := false, y0 := 0.0) -> void:
	var cnt := poly.size()
	var area := 0.0
	for k in cnt:
		area += poly[k].cross(poly[(k + 1) % cnt])
	if area < 0.0:
		poly = poly.duplicate()
		poly.reverse()
	for k in cnt:
		var p0 := poly[k]
		var p1 := poly[(k + 1) % cnt]
		var a := t * Vector3(p0.x, y0, p0.y)
		var b := t * Vector3(p1.x, y0, p1.y)
		quad(slot, b, a, a + t.basis.y * h, b + t.basis.y * h, col)
	if top or bottom:
		var idx := Geometry2D.triangulate_polygon(poly)
		for q in range(0, idx.size(), 3):
			var pa := poly[idx[q]]
			var pb := poly[idx[q + 1]]
			var pc := poly[idx[q + 2]]
			# make sure the 2D triangle is counter-clockwise in (x,z) so the top faces +Y
			if (pb - pa).cross(pc - pa) < 0.0:
				var tmp := pb
				pb = pc
				pc = tmp
			if top:
				tri(slot, t * Vector3(pa.x, y0 + h, pa.y), t * Vector3(pc.x, y0 + h, pc.y), t * Vector3(pb.x, y0 + h, pb.y), col)
			if bottom:
				tri(slot, t * Vector3(pa.x, y0, pa.y), t * Vector3(pb.x, y0, pb.y), t * Vector3(pc.x, y0, pc.y), col)


## Semi-circular arch (solid wall with an arched opening) in the local XY plane, depth along Z.
func arch_wall(slot: String, t: Transform3D, width: float, height: float, depth: float, open_w: float,
		open_h: float, col: Color, segs := 10) -> void:
	var hw := width * 0.5
	var ow := open_w * 0.5
	var spring := open_h - ow           # where the arch curve starts
	var hd := depth * 0.5
	# piers
	box(slot, t, Vector3(-(hw + ow) * 0.5, height * 0.5, 0), Vector3(hw - ow, height, depth), col)
	box(slot, t, Vector3((hw + ow) * 0.5, height * 0.5, 0), Vector3(hw - ow, height, depth), col)
	# spandrel above the opening between the piers
	box(slot, t, Vector3(0, (open_h + height) * 0.5, 0), Vector3(open_w, height - open_h, depth), col)
	# arch intrados fill (curved underside) between spring and open_h
	for k in segs:
		var a0 := PI * k / segs
		var a1 := PI * (k + 1) / segs
		var x0 := cos(a0) * ow
		var y0 := spring + sin(a0) * ow
		var x1 := cos(a1) * ow
		var y1 := spring + sin(a1) * ow
		var xe0 := ow if x0 > 0 else -ow
		# front & back faces between curve and the spandrel bottom (open_h)
		quad(slot, t * Vector3(x1, y1, hd), t * Vector3(x0, y0, hd), t * Vector3(x0, open_h, hd), t * Vector3(x1, open_h, hd), col)
		quad(slot, t * Vector3(x0, y0, -hd), t * Vector3(x1, y1, -hd), t * Vector3(x1, open_h, -hd), t * Vector3(x0, open_h, -hd), col)
		# soffit
		quad(slot, t * Vector3(x0, y0, -hd), t * Vector3(x0, y0, hd), t * Vector3(x1, y1, hd), t * Vector3(x1, y1, -hd), col)
		var _unused := xe0


## Generic ribbon between two polylines (left, right) — e.g. roads, rivers, walls.
## u = across (0..1 * width), v = along in metres.
func ribbon(slot: String, left: PackedVector3Array, right: PackedVector3Array, col: Color,
		v_start := 0.0, up_normal := false, cols := PackedColorArray()) -> void:
	var s := _s(slot)
	var cnt := left.size()
	if cnt < 2:
		return
	var base: int = s["v"].size()
	var v := v_start
	for k in cnt:
		if k > 0:
			v += ((left[k] + right[k]) * 0.5).distance_to((left[k - 1] + right[k - 1]) * 0.5)
		var along := (left[mini(k + 1, cnt - 1)] + right[mini(k + 1, cnt - 1)]) - (left[maxi(k - 1, 0)] + right[maxi(k - 1, 0)])
		var across := right[k] - left[k]
		var n := Vector3.UP if up_normal else across.cross(along).normalized()
		if n.y < 0 and up_normal == false and absf(n.y) > 0.5:
			n = -n
		var w := across.length()
		s["v"].append_array([left[k], right[k]])
		s["n"].append_array([n, n])
		var c := cols[k] if cols.size() == cnt else col
		s["c"].append_array([c, c])
		s["uv"].append_array([Vector2(0, v) * uv_scale, Vector2(w, v) * uv_scale])
		s["uv2"].append_array([Vector2(0, v), Vector2(1, v)])
	for k in cnt - 1:
		var a := base + k * 2
		# left->right across, forward along: winding so +Y faces up when left is on the left
		s["i"].append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])


## Append another kit, transformed.
func merge(other: MeshKit, t := Transform3D.IDENTITY) -> void:
	for slot in other.surfaces:
		var src: Dictionary = other.surfaces[slot]
		var dst := _s(slot)
		var base: int = dst["v"].size()
		if t == Transform3D.IDENTITY:
			dst["v"].append_array(src["v"])
			dst["n"].append_array(src["n"])
		else:
			for p in src["v"]:
				dst["v"].append(t * p)
			for nn in src["n"]:
				dst["n"].append((t.basis * nn).normalized())
		dst["c"].append_array(src["c"])
		dst["uv"].append_array(src["uv"])
		dst["uv2"].append_array(src["uv2"])
		var idx: PackedInt32Array = src["i"]
		for q in idx:
			dst["i"].append(q + base)


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------
## Builds the ArrayMesh. materials: slot -> Material (missing slots use Mats.get_mat(slot)).
func build(materials := {}) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for slot in surfaces:
		var s: Dictionary = surfaces[slot]
		if s["i"].is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = s["v"]
		arr[Mesh.ARRAY_NORMAL] = s["n"]
		arr[Mesh.ARRAY_COLOR] = s["c"]
		arr[Mesh.ARRAY_TEX_UV] = s["uv"]
		arr[Mesh.ARRAY_TEX_UV2] = s["uv2"]
		arr[Mesh.ARRAY_INDEX] = s["i"]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var m: Material = materials.get(slot, null)
		if m == null:
			m = Mats.get_mat(slot)
		mesh.surface_set_material(mesh.get_surface_count() - 1, m)
		mesh.surface_set_name(mesh.get_surface_count() - 1, slot)
	return mesh


## Triangle soup for a ConcavePolygonShape3D (optionally only some slots).
func collision_faces(only_slots := []) -> PackedVector3Array:
	var faces := PackedVector3Array()
	for slot in surfaces:
		if not only_slots.is_empty() and not only_slots.has(slot):
			continue
		var s: Dictionary = surfaces[slot]
		var v: PackedVector3Array = s["v"]
		var idx: PackedInt32Array = s["i"]
		for q in idx:
			faces.append(v[q])
	return faces


func aabb() -> AABB:
	var first := true
	var bb := AABB()
	for slot in surfaces:
		for p in surfaces[slot]["v"]:
			if first:
				bb = AABB(p, Vector3.ZERO)
				first = false
			else:
				bb = bb.expand(p)
	return bb
