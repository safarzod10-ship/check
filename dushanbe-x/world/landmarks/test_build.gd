extends SceneTree
## Headless smoke test: builds every landmark and POI once and prints triangle counts.
## godot --headless --path . -s res://world/landmarks/test_build.gd

func _initialize() -> void:
	var wd = root.get_node_or_null("WorldData")
	if wd == null:
		print("no WorldData autoload")
		quit(1)
		return
	wd.load_world()
	var total := 0
	for lm in wd.landmarks:
		var p := "res://world/landmarks/builders/%s.gd" % lm["id"]
		var b: GDScript = load(p)
		var k := MeshKit.new()
		var d := MeshKit.new()
		var l: Dictionary = lm.duplicate()
		l["_detail"] = d
		var swap := absf(sin(deg_to_rad(float(lm["yaw"])))) > 0.7
		l["hx"] = float(lm["pad"][1]) if swap else float(lm["pad"][0])
		l["hz"] = float(lm["pad"][0]) if swap else float(lm["pad"][1])
		b.build(k, l)
		var tris := _tris(k)
		var dt := _tris(d)
		total += tris + dt
		var bb := k.aabb()
		print("%-20s tris %6d detail %6d  aabb %s" % [lm["id"], tris, dt, str(bb.size)])
	var pb: GDScript = load("res://world/landmarks/builders/pois.gd")
	for poi in wd.pois:
		var k := MeshKit.new()
		var l: Dictionary = poi.duplicate()
		l["_detail"] = MeshKit.new()
		pb.build_poi(k, l)
		total += _tris(k)
	print("POIs ok; total tris ", total)
	quit()


func _tris(k: MeshKit) -> int:
	var t := 0
	for s in k.surfaces:
		t += k.surfaces[s]["i"].size() / 3
	return t
