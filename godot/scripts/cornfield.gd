extends Node3D
# Field coordinates follow the NW-SE forest edge; +V points downhill into the meadow.
const FIELD_ORIGIN := Vector2(-178,-40)
const FIELD_AXIS := Vector2(0.6,0.8)
const FIELD_CROSS := Vector2(-0.8,0.6)
const ORIGIN := Vector2(69,6)
const CELL := 3.0
const SIZE := 13
const BATCH_SIZE := 8.0
# Lower western meadow toward the village, downhill from Mara. +X is east (Sennhof).
const FIELD := Rect2(0,0,140,52)
const Bird = preload("res://scripts/field_bird.gd")
var game: Node
var passages: Dictionary = {}
var birds: Array = []
var plant_count := 0
var random := RandomNumberGenerator.new()
const LOD_DISTANCES := [12.0,42.0]
const LOD_HYSTERESIS := 2.0
var _plant_batches: Array[MultiMeshInstance3D] = []
var _plant_meshes: Array[ArrayMesh] = []
var _lod_elapsed := 0.0

static var _tree_cells: Dictionary = {}
static func field_to_world(p: Vector2) -> Vector2:
	return FIELD_ORIGIN + FIELD_AXIS*p.x + FIELD_CROSS*p.y
static func world_to_field(p: Vector2) -> Vector2:
	var relative := p-FIELD_ORIGIN
	return Vector2(relative.dot(FIELD_AXIS),relative.dot(FIELD_CROSS))
static func field_ground(p: Vector2) -> bool:
	if not FIELD.has_point(world_to_field(p)): return false
	if Map.meadow_weight(p.x,p.y)<0.75 or Map.leaf_weight(p.x,p.y)>0.12: return false
	if _tree_cells.is_empty():
		for tree in Map.TREES:
			var at := Vector2(tree[0],tree[1])
			var cell := Vector2i(floori(at.x/8.0),floori(at.y/8.0))
			if not _tree_cells.has(cell): _tree_cells[cell] = []
			_tree_cells[cell].append(at)
	var cell := Vector2i(floori(p.x/8.0),floori(p.y/8.0))
	for z in range(-1,2):
		for x in range(-1,2):
			for tree: Vector2 in _tree_cells.get(cell+Vector2i(x,z),[]):
				if p.distance_squared_to(tree)<36.0: return false
	return true

static func inside_maze(p: Vector2) -> bool:
	return Rect2(ORIGIN,Vector2.ONE*SIZE*CELL).has_point(world_to_field(p))
func cell_position(cell: Vector2i) -> Vector2:
	return field_to_world(ORIGIN+(Vector2(cell)+Vector2.ONE*0.5)*CELL)
func build(main: Node) -> void:
	game = main
	random.seed = 87261
	add_to_group("render_dynamic")
	# Deterministic depth-first maze: every chamber is reachable in all peers.
	var stack: Array[Vector2i] = [Vector2i(1,1)]
	passages[stack[0]] = true
	while not stack.is_empty():
		var here := stack.back() as Vector2i
		var options: Array[Vector2i] = []
		for step: Vector2i in [Vector2i(2,0),Vector2i(-2,0),Vector2i(0,2),Vector2i(0,-2)]:
			var next := here+step
			if next.x>0 and next.y>0 and next.x<SIZE-1 and next.y<SIZE-1 and not passages.has(next): options.append(next)
		if options.is_empty(): stack.pop_back()
		else:
			var next := options[random.randi_range(0,options.size()-1)]
			passages[(here+next)/2] = true
			passages[next] = true
			stack.append(next)
	passages[Vector2i(1,0)] = true
	passages[Vector2i(SIZE-2,SIZE-1)] = true
	var batches: Dictionary = {}
	for z in range(int(FIELD.position.y) + 1, int(FIELD.end.y)):
		for x in range(int(FIELD.position.x) + 1, int(FIELD.end.x)):
			var local := Vector2(x,z)
			var p := field_to_world(local)
			if not field_ground(p) or Map.on_road(p.x,p.y,2.5): continue
			# Open access lanes keep all existing field spawns connected.
			if absf(p.x-10)<5 or p.distance_to(Vector2(-110,108))<10 or p.distance_to(Vector2(-42,126))<8: continue
			if inside_maze(p):
				var cell := Vector2i((local-ORIGIN)/CELL)
				if passages.has(cell): continue
			elif (local.x>ORIGIN.x and local.x<ORIGIN.x+CELL*3 and local.y<ORIGIN.y) or (local.x>ORIGIN.x+CELL*10 and local.x<ORIGIN.x+CELL*13 and local.y>ORIGIN.y+CELL*SIZE): continue
			# Staggered rows: six stalks per square metre, eight in maze walls.
			var row_count := 4 if inside_maze(p) else 3
			for j in row_count*2:
				var at := field_to_world(local+Vector2((j%2)*0.5-0.25+random.randf_range(-0.07,0.07), (floori(j/2.0)+0.5)/row_count-0.5+random.randf_range(-0.04,0.04)))
				if not field_ground(at): continue
				if inside_maze(at) and passages.has(Vector2i((world_to_field(at)-ORIGIN)/CELL)): continue
				var key := Vector3i(floori(at.x/BATCH_SIZE),floori(at.y/BATCH_SIZE),random.randi_range(0,1))
				if not batches.has(key): batches[key] = []
				var scale := random.randf_range(0.98,1.14)
				var yaw := j*0.73+random.randf_range(-0.35,0.35)
				batches[key].append(Transform3D(Basis(Vector3.UP,yaw).scaled(Vector3.ONE*scale),Map.ground_pos(at.x,at.y)))
				plant_count += 1
	var wind := ShaderMaterial.new()
	wind.shader = load("res://shaders/corn_wind.gdshader")
	for asset in ["a","b","far","distant"]:
		_plant_meshes.append(load("res://assets/cornfield/corn_%s.res" % asset))
	for key: Vector3i in batches:
		var tile := Vector3(key.x*BATCH_SIZE,0,key.y*BATCH_SIZE)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = _plant_meshes[3]
		multimesh.instance_count = batches[key].size()
		# All detail levels use one stable bound, including maximum wind displacement.
		var plant_bounds := _plant_meshes[key.z].get_aabb().merge(_plant_meshes[2].get_aabb()).merge(_plant_meshes[3].get_aabb()).grow(0.2)
		var bounds := AABB()
		for i in multimesh.instance_count:
			var transform: Transform3D = batches[key][i]
			transform.origin -= tile
			multimesh.set_instance_transform(i,transform)
			var instance_bounds := transform * plant_bounds
			bounds = instance_bounds if i==0 else bounds.merge(instance_bounds)
		multimesh.custom_aabb = bounds
		var node := MultiMeshInstance3D.new()
		node.multimesh = multimesh
		node.material_override = wind
		node.position = tile
		node.visibility_range_end = 150
		node.visibility_range_end_margin = 4
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.set_meta("corn_variant",key.z)
		node.set_meta("corn_lod",2)
		node.add_to_group("render_dynamic")
		add_child(node)
		_plant_batches.append(node)
	for y in SIZE:
		for x in SIZE:
			if passages.has(Vector2i(x,y)): continue
			var p := cell_position(Vector2i(x,y))
			var wall := StaticBody3D.new()
			wall.collision_layer = 1
			wall.add_to_group("navsource")
			var shape := CollisionShape3D.new()
			var box := BoxShape3D.new()
			var low := Map.ground_height(p.x,p.y)
			var high := low
			for corner: Vector2 in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:
				var edge := p+(FIELD_AXIS*corner.x+FIELD_CROSS*corner.y)*CELL*0.5
				var height := Map.ground_height(edge.x,edge.y)
				low = minf(low,height)
				high = maxf(high,height)
			box.size = Vector3(CELL,high-low+2.6,CELL)
			shape.shape = box
			shape.position.y = (low+high)*0.5-Map.ground_height(p.x,p.y)+1.2
			wall.add_child(shape)
			add_child(wall)
			wall.global_position = Map.ground_pos(p.x,p.y)
			wall.rotation.y = -FIELD_AXIS.angle()
	# Meshy figures mounted on timber stakes, with no floating entrance label.
	var timber := Foliage.pbr("planks",0.8,Color(0.38,0.31,0.22))
	for cell: Vector2i in [Vector2i(1,0),Vector2i(11,12),Vector2i(5,5),Vector2i(9,3)]:
		var p := cell_position(cell)
		var scarecrow := Node3D.new()
		scarecrow.name = "Scarecrow_%d_%d" % [cell.x,cell.y]
		add_child(scarecrow)
		var beside := p-FIELD_AXIS*1.1
		scarecrow.global_position = Map.ground_pos(beside.x,beside.y)
		scarecrow.rotation.y = -FIELD_AXIS.angle() + (PI if cell.y==0 else (0.0 if cell.y==SIZE-1 else random.randf()*TAU))
		var figure: Node3D = load("res://assets/models/scarecrow_real.glb").instantiate()
		figure.position.y = 0.8
		scarecrow.add_child(figure)
		var stake := MeshInstance3D.new()
		var pole := CylinderMesh.new()
		pole.height = 2.05
		pole.top_radius = 0.045
		pole.bottom_radius = 0.065
		pole.radial_segments = 8
		stake.mesh = pole
		stake.material_override = timber
		stake.position = Vector3(0,1.025,-0.08)
		scarecrow.add_child(stake)
		var brace := MeshInstance3D.new()
		var beam := BoxMesh.new()
		beam.size = Vector3(1.05,0.07,0.085)
		brace.mesh = beam
		brace.material_override = timber
		brace.position = Vector3(0,1.8,-0.10)
		brace.rotation.z = -0.09
		scarecrow.add_child(brace)
	_path_surface()
	_make_caches()
	for i in 10:
		var bird := Bird.new()
		bird.owl = i>=7
		bird.index = i
		bird.game = game
		add_child(bird)
		var home := cell_position(Vector2i(1+2*(i%6),1+2*((i*3)%6)))
		bird.home = Map.ground_pos(home.x,home.y)+Vector3.UP*(3.7 if bird.owl else 0.2)
		bird.position = bird.home
		birds.append(bird)

func _process(delta: float) -> void:
	_lod_elapsed += delta
	if _lod_elapsed < 0.1: return
	_lod_elapsed = 0.0
	var camera := get_viewport().get_camera_3d()
	if camera: _update_plant_lods(camera.global_position)

func _update_plant_lods(camera_position: Vector3) -> void:
	# Swap one mesh instead of independently hiding three overlapping copies.
	# Shared hysteresis prevents camera bob/wind from toggling whole tiles each frame.
	for node in _plant_batches:
		var center := node.global_transform * node.multimesh.custom_aabb.get_center()
		var distance := camera_position.distance_to(center)
		var previous: int = node.get_meta("corn_lod")
		var lod := previous
		while lod < 2 and distance > LOD_DISTANCES[lod] + LOD_HYSTERESIS: lod += 1
		while lod > 0 and distance < LOD_DISTANCES[lod-1] - LOD_HYSTERESIS: lod -= 1
		if lod == previous: continue
		var mesh_index: int = node.get_meta("corn_variant") if lod == 0 else lod+1
		node.multimesh.mesh = _plant_meshes[mesh_index]
		node.set_meta("corn_lod",lod)

func _make_caches() -> void:
	var ends: Array[Vector2i] = []
	for cell: Vector2i in passages:
		if cell.x<=0 or cell.y<=0 or cell.x>=SIZE-1 or cell.y>=SIZE-1: continue
		var exits := 0
		for d: Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if passages.has(cell+d): exits += 1
		if exits == 1: ends.append(cell)
	ends.sort_custom(func(a: Vector2i,b: Vector2i): return a.distance_squared_to(Vector2i(1,0))>b.distance_squared_to(Vector2i(1,0)))
	var rewards := ["fire","frost","cache_cash","cache_grenade","ammo"]
	for i in mini(ends.size(),rewards.size()):
		var item := Loot.new()
		item.setup("maze_cache",rewards[i],["Feuerpatronen (12)","Frostpatronen (12)","Versteckter Geldbeutel (250 P)","Granatenversteck","Munitionskiste"][i])
		add_child(item)
		var p := cell_position(ends[i])
		item.global_position = Map.ground_pos(p.x,p.y)+Vector3.UP*0.12
		var mesh := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.65,0.35,0.42)
		mesh.mesh = box
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.29,0.19,0.075)
		mesh.material_override = material
		mesh.position.y = 0.175
		item.add_child(mesh)
		var band := MeshInstance3D.new()
		var strip := BoxMesh.new()
		strip.size = Vector3(0.12,0.37,0.44)
		band.mesh = strip
		var gold := StandardMaterial3D.new()
		gold.albedo_color = Color(0.8,0.57,0.18)
		band.material_override = gold
		band.position.y = 0.175
		item.add_child(band)
		game.loots.append(item)

func scare(origin: Vector3) -> void:
	for bird in birds: bird.scare(origin)

func _path_surface() -> void:
	# Match the terrain's world-grid triangles exactly, so the soil neither floats
	# above the hillside nor intersects it when the field is rotated.
	var bounds := Rect2(FIELD_ORIGIN,Vector2.ZERO)
	for corner in [Vector2.ZERO,Vector2(FIELD.size.x,0),FIELD.size,Vector2(0,FIELD.size.y)]:
		bounds = bounds.expand(field_to_world(corner))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(floori(bounds.position.y)-1,ceili(bounds.end.y)+1):
		for x in range(floori(bounds.position.x)-1,ceili(bounds.end.x)+1):
			if not FIELD.grow(1.5).has_point(world_to_field(Vector2(x+0.5,z+0.5))): continue
			var points := [Vector2(x,z),Vector2(x+1,z),Vector2(x+1,z+1),Vector2(x,z+1)]
			for index in [0,3,1,1,3,2]:
				var at: Vector2 = points[index]
				var local := world_to_field(at)
				var path := 0.0
				if inside_maze(at) and passages.has(Vector2i((local-ORIGIN)/CELL)): path = 1.0
				st.set_color(Color(path,0,0,1))
				st.set_uv(at*0.5)
				st.set_uv2(local)
				st.set_normal(Map.ground_normal(at.x,at.y))
				st.add_vertex(Vector3(at.x,Map.surface_height(at.x,at.y)+0.018,at.y))
	st.generate_tangents()
	st.index()
	var node := MeshInstance3D.new()
	node.name = "CornSoil"
	node.mesh = st.commit()
	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/corn_soil.gdshader")
	for channel in ["albedo","normal","rough","ao"]:
		material.set_shader_parameter(channel+"_tex",load("res://assets/textures/gravel_"+channel+".jpg"))
	material.set_shader_parameter("field_size",FIELD.size)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)
