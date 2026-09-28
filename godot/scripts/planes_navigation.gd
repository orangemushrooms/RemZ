extends RefCounted
## Build only when survival is requested; source geometry is immutable during bake.
static var cached: NavigationMesh

static func prepare(game: Node3D) -> NavigationRegion3D:
	var region := NavigationRegion3D.new()
	game.add_child(region)
	var map := game.get_world_3d().navigation_map
	var previous_merge := NavigationServer3D.map_get_merge_rasterizer_cell_scale(map)
	game.tree_exiting.connect(func(): NavigationServer3D.map_set_merge_rasterizer_cell_scale(map,previous_merge),CONNECT_ONE_SHOT)
	NavigationServer3D.map_set_cell_size(game.get_world_3d().navigation_map,0.8)
	NavigationServer3D.map_set_cell_height(game.get_world_3d().navigation_map,0.25)
	NavigationServer3D.map_set_merge_rasterizer_cell_scale(game.get_world_3d().navigation_map,0.001)
	if not cached:
		var mesh := NavigationMesh.new()
		mesh.cell_size = 0.8
		mesh.cell_height = 0.25
		mesh.agent_radius = 0.8
		mesh.agent_height = 2.0
		mesh.agent_max_climb = 0.75
		mesh.agent_max_slope = 42.0
		mesh.detail_sample_distance = 6.0
		mesh.detail_sample_max_error = 0.5
		var source := NavigationMeshSourceGeometryData3D.new()
		var vertices := PackedVector3Array()
		var indices := PackedInt32Array()
		var ext := Map.BOUNDS.grow(-2)
		var step := 4.0
		var width := floori(ext.size.x/step)+1
		var depth := floori(ext.size.y/step)+1
		for j in depth:
			for i in width:
				var p := Map.ground_pos(ext.position.x+i*step,ext.position.y+j*step)
				vertices.append(p)
		for j in depth-1:
			for i in width-1:
				var a := j*width+i
				indices.append_array(PackedInt32Array([a,a+1,a+width,a+1,a+width+1,a+width]))
		# add_mesh_array converts Godot clockwise faces to Recast's winding.
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_INDEX] = indices
		source.add_mesh_array(arrays,Transform3D.IDENTITY)
		for building: Dictionary in Map.VILLAGE:
			var polygon := PackedVector2Array()
			for p in building.poly: polygon.append(Vector2(p[0],p[1]))
			if polygon.size()>3 and polygon[0]==polygon[-1]: polygon.remove_at(polygon.size()-1)
			if polygon.size()<3: continue
			for part in Geometry2D.decompose_polygon_in_convex(polygon):
				var outline := PackedVector3Array()
				for p in part: outline.append(Vector3(p.x,0,p.y))
				source.add_projected_obstruction(outline,-100,350,false)
		for tree: Array in Map._d.landscape_trees:
			var polygon := PackedVector3Array()
			for i in 8:
				var angle := TAU*i/8.0
				polygon.append(Vector3(tree[0]+cos(angle)*0.65,0,tree[1]+sin(angle)*0.65))
			source.add_projected_obstruction(polygon,-100,350,false)
		var completed := [false]
		NavigationServer3D.bake_from_source_geometry_data_async(mesh,source,func(): completed[0]=true)
		while not completed[0]: await game.get_tree().process_frame
		cached = mesh
	region.navigation_mesh = cached
	# Empty-region iterations precede the asynchronous region + map builds.
	# Wait until actual polygon data is available to queries, not a frame count.
	if cached.get_polygon_count()>0:
		while NavigationServer3D.map_get_closest_point_owner(region.get_navigation_map(),Vector3.ZERO)!=region.get_rid():
			await game.get_tree().physics_frame
	print("PLANES_NAV polygons=",cached.get_polygon_count())
	return region
