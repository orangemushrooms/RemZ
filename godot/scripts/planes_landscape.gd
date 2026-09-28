extends Node3D
## Rendering only; source terrain and collision use the same one-metre raster.
var tree_count := 0
var terrain_chunks := 0
var tree_models: Dictionary = {}

func build() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/planes_ground.gdshader")
	mat.set_shader_parameter("cover_map", load("res://assets/planes/ground.png"))
	mat.set_shader_parameter("crop_map", load("res://assets/planes/crops.png"))
	mat.set_shader_parameter("origin", Map.extent().position)
	mat.set_shader_parameter("size", Map.extent().size+Vector2.ONE)
	mat.set_shader_parameter("litter",load("res://assets/textures/leaves_albedo.jpg"))
	for pair in [["meadow","ph_meadow_albedo"],["gravel","ph_gravel_albedo"],["soil","ph_forestfloor_albedo"],["gravel_normal","ph_gravel_normal"]]:
		mat.set_shader_parameter(pair[0], load("res://assets/textures/%s.jpg" % pair[1]))
	var ext := Map.extent()
	for z in range(int(ext.position.y),int(ext.end.y),64):
		for x in range(int(ext.position.x),int(ext.end.x),64):
			_tile(Rect2(x,z,minf(64,ext.end.x-x),minf(64,ext.end.y-z)),1,mat)
	# Same surveyed raster at ten-metre intervals for the distant village slopes.
	var outer := Rect2(-1000,-900,2200,1600)
	var distant := Foliage.pbr("ph_meadow",0.25,Color(0.62,0.73,0.5))
	for z in range(-900,700,100):
		for x in range(-1000,1200,100):
			var rect := Rect2(x,z,100,100)
			if ext.encloses(rect): continue
			_tile(rect,10,distant,true)
	var body := StaticBody3D.new()
	body.name = "SurveyedTerrainCollision"
	body.add_to_group("terrain_ground")
	var collision := CollisionShape3D.new()
	var shape := HeightMapShape3D.new()
	shape.map_width = Map._w
	shape.map_depth = Map._hh
	shape.map_data = Map._h
	collision.shape = shape
	collision.position = Vector3(ext.get_center().x,0,ext.get_center().y)
	body.add_child(collision)
	add_child(body)
	add_child(load("res://scripts/planes_buildings.gd").new().build())
	_building_collisions()
	_trees()
	_signs()

func _tile(rect: Rect2, step: int, material: Material, skirt := false) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var width := int(rect.size.x/step)+1
	var depth := int(rect.size.y/step)+1
	for j in depth:
		for i in width:
			var p := rect.position+Vector2(i,j)*step
			var h := Map.ground_height(p.x,p.y)
			st.set_uv(p)
			st.set_normal(Map.ground_normal(p.x,p.y))
			st.add_vertex(Vector3(p.x,h-0.06 if skirt else h,p.y))
	for j in depth-1:
		for i in width-1:
			var p := rect.position+Vector2(i+0.5,j+0.5)*step
			if skirt and Map.extent().grow(-10).has_point(p): continue
			var a := j*width+i
			for v in [a,a+1,a+width,a+1,a+width+1,a+width]: st.add_index(v)
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.name = "Terrain_%d_%d" % [rect.position.x,rect.position.y]
	mi.mesh = st.commit()
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	terrain_chunks += 1

func _building_collisions() -> void:
	for building: Dictionary in Map.VILLAGE:
		var poly := PackedVector2Array()
		for p in building.poly: poly.append(Vector2(p[0],p[1]))
		if poly.size()>3 and poly[0]==poly[-1]: poly.remove_at(poly.size()-1)
		if poly.size()<3: continue
		var center := Vector2.ZERO
		for p in poly: center += p
		center /= poly.size()
		if not Map.BOUNDS.has_point(center): continue
		var base := Map.ground_height(center.x,center.y)
		var body := StaticBody3D.new()
		body.name = "Building_%s" % building.osm_id
		for part in Geometry2D.decompose_polygon_in_convex(poly):
			var points := PackedVector3Array()
			for p in part:
				points.append(Vector3(p.x,base-4,p.y))
				points.append(Vector3(p.x,base+float(building.h)+2,p.y))
			var shape := ConvexPolygonShape3D.new()
			shape.points = points
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
		add_child(body)

func _trees() -> void:
	var forest = load("res://scripts/planes_trees.gd").new()
	add_child(forest)
	forest.build()
	tree_count = forest.count

func _signs() -> void:
	# The two small markers visible at the maize corner in photos 4/5.
	for offset in [Vector2(-106,9),Vector2(-104,8.5)]:
		var p := Map.ground_pos(offset.x,offset.y)
		var pole := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.height = 1.15; cylinder.top_radius = 0.018; cylinder.bottom_radius = 0.018
		pole.mesh = cylinder
		pole.position = p+Vector3.UP*0.575
		add_child(pole)
		var sign := MeshInstance3D.new()
		var disk := CylinderMesh.new()
		disk.top_radius = 0.15; disk.bottom_radius = 0.15; disk.height = 0.02
		sign.mesh = disk
		sign.position = p+Vector3.UP*1.1
		sign.rotation_degrees.x = 90
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.9,0.87,0.75)
		sign.material_override = material
		add_child(sign)
