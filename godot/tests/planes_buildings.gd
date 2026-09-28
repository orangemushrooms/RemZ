extends SceneTree
## Regression: mixed OSM winding hid most facades; a fixed Z/Y UV projection
## collapsed tiled roofs. Inspect actual generated geometry, including a concave outline.
var failures := 0
var checks := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",message)

func run() -> void:
	Map.use_region("planes")
	Map._ensure()
	for reverse in [false,true]:
		var polygon := PackedVector2Array([Vector2(-212,-110),Vector2(-192,-110),Vector2(-192,-104),Vector2(-197,-104),Vector2(-197,-100),Vector2(-212,-100)])
		if reverse: polygon.reverse()
		var source: Array = []
		for point in polygon: source.append([point.x,point.y])
		source.append(source[0])
		var builder := preload("res://scripts/planes_buildings.gd").new()
		builder._cube = BoxMesh.new().get_mesh_arrays()
		builder._build_house({"poly":source,"h":5.6},11)
		var windows := 0
		var outside := true
		var roof_uv := true
		var roof_count := 0
		for batch: Dictionary in builder._batches.values():
			if batch.material not in ["glass","tiles","slate"]: continue
			var mesh: ArrayMesh = batch.surface.commit()
			var arrays := mesh.surface_get_arrays(0)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			for i in range(0,vertices.size(),3):
				if batch.material=="glass":
					windows += 1
					var p: Vector3 = (vertices[i]+vertices[i+1]+vertices[i+2])/3.0+batch.origin
					outside = outside and not Geometry2D.is_point_in_polygon(Vector2(p.x,p.z),polygon)
				else:
					roof_count += 1
					roof_uv = roof_uv and absf((uvs[i+1]-uvs[i]).cross(uvs[i+2]-uvs[i]))>0.001
		check(windows>12 and outside,"Every window faces outside a concave house, reversed=%s" % reverse)
		check(roof_count>2 and roof_uv,"Roof textures retain area on every slope, reversed=%s" % reverse)
	print("PLANES_BUILDINGS_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
