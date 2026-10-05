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
		builder._build_house({"osm_id": -1100, "poly":source,"h":5.6},11)
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
	var stand: Dictionary
	for building: Dictionary in Map.VILLAGE:
		if building.get("kind","")=="shooting_targets": stand = building
	check(not stand.is_empty() and int(stand.osm_id)==1558294553 and int(stand.layer)==-1,"The verified underground target footprint is classified separately from houses")
	var target_builder := preload("res://scripts/planes_buildings.gd").new()
	target_builder._cube = BoxMesh.new().get_mesh_arrays()
	target_builder._build_house(stand,0)
	var front_ok := target_builder.target_panels.size()==6
	for face: Transform3D in target_builder.target_panels:
		var direction := Vector2(stand.facing[0]-face.origin.x,stand.facing[1]-face.origin.z).normalized()
		front_ok = front_ok and Vector2(face.basis.z.x,face.basis.z.z).dot(direction)>0.998
	check(front_ok,"All six target faces point downhill towards the mapped shooting house")
	var low := true
	var materials: Array = []
	var triangles := 0
	for batch: Dictionary in target_builder._batches.values():
		materials.append(batch.material)
		var mesh: ArrayMesh = batch.surface.commit()
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		triangles += vertices.size()/3
		for p: Vector3 in vertices:
			low = low and p.y+batch.origin.y<=target_builder._frame.origin.y+float(stand.collision_height)
	check(low and not materials.has("glass") and not materials.has("tiles") and not materials.has("slate"),"The stand stays below 2.3 m with no residential windows or pitched roof")
	# Compare the old generated building to ensure this correction adds no render cost.
	var old_data := stand.duplicate(true)
	old_data.erase("kind")
	old_data.h = 5.6
	var old_builder := preload("res://scripts/planes_buildings.gd").new()
	old_builder._cube = BoxMesh.new().get_mesh_arrays()
	old_builder._build_house(old_data,0)
	var old_triangles := 0
	for batch: Dictionary in old_builder._batches.values():
		old_triangles += (batch.surface.commit() as ArrayMesh).surface_get_array_len(0)/3
	check(triangles<=old_triangles and target_builder._batches.size()<=old_builder._batches.size(),"Target stand does not increase geometry or material batches")
	print("TARGET_GEOMETRY before=",old_triangles," after=",triangles," batches=",target_builder._batches.size())
	print("PLANES_BUILDINGS_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
