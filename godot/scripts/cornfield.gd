extends Node3D
const ORIGIN := Vector2(35,72)
const CELL := 3.5
const SIZE := 13
const FIELD := Rect2(-120,62,234,76)
const Bird = preload("res://scripts/field_bird.gd")
var game: Node
var passages: Dictionary = {}
var birds: Array = []
var plant_count := 0
var random := RandomNumberGenerator.new()

static func inside_maze(p: Vector2) -> bool:
	return Rect2(ORIGIN,Vector2.ONE*SIZE*CELL).has_point(p)
func cell_position(cell: Vector2i) -> Vector2:
	return ORIGIN+(Vector2(cell)+Vector2.ONE*0.5)*CELL
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
	for z in range(63,138):
		for x in range(-119,114):
			var p := Vector2(x,z)
			if Map.on_road(x,z,2.5) or Map.leaf_weight(x,z)>0.4: continue
			# Open access lanes keep all existing field spawns connected.
			if absf(p.x-10)<5 or p.distance_to(Vector2(-110,108))<10 or p.distance_to(Vector2(-42,126))<8: continue
			if inside_maze(p):
				var cell := Vector2i((p-ORIGIN)/CELL)
				if passages.has(cell): continue
			elif (p.x>ORIGIN.x and p.x<ORIGIN.x+CELL*3 and p.y<ORIGIN.y) or (p.x>ORIGIN.x+CELL*10 and p.x<ORIGIN.x+CELL*13 and p.y>ORIGIN.y+CELL*SIZE): continue
			# Denser maze hedges; one stalk per square metre in the outer rows.
			for j in (2 if inside_maze(p) else 1):
				var at := p+Vector2(random.randf_range(-0.28,0.28),j*0.45-0.22)
				var key := Vector3i(floori(x/16.0),floori(z/16.0),random.randi_range(0,1))
				if not batches.has(key): batches[key] = []
				var scale := random.randf_range(0.88,1.15)
				batches[key].append(Transform3D(Basis(Vector3.UP,random.randf()*TAU).scaled(Vector3.ONE*scale),Map.ground_pos(at.x,at.y)))
				plant_count += 1
	var wind := ShaderMaterial.new()
	wind.shader = load("res://shaders/corn_wind.gdshader")
	for key: Vector3i in batches:
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = load("res://assets/cornfield/corn_%s.res" % ("a" if key.z==0 else "b"))
		multimesh.instance_count = batches[key].size()
		var tile := Vector3(key.x*16,0,key.y*16)
		for i in multimesh.instance_count:
			var t: Transform3D = batches[key][i]
			t.origin -= tile
			multimesh.set_instance_transform(i,t)
		var node := MultiMeshInstance3D.new()
		node.multimesh = multimesh
		node.material_override = wind
		node.position = tile
		node.visibility_range_end = 28
		node.visibility_range_end_margin = 2
		node.extra_cull_margin = 0.4
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_to_group("render_dynamic")
		add_child(node)
		var distant := MultiMeshInstance3D.new()
		distant.multimesh = MultiMesh.new()
		distant.multimesh.transform_format = MultiMesh.TRANSFORM_3D
		distant.multimesh.mesh = load("res://assets/cornfield/corn_far.res")
		distant.multimesh.instance_count = multimesh.instance_count
		for i in multimesh.instance_count:
			var t: Transform3D = batches[key][i]
			t.origin -= tile
			distant.multimesh.set_instance_transform(i,t)
		distant.material_override = wind
		distant.position = tile
		distant.visibility_range_begin = 28
		distant.visibility_range_begin_margin = 2
		distant.visibility_range_end = 150
		distant.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		distant.extra_cull_margin = 0.4
		distant.add_to_group("render_dynamic")
		add_child(distant)
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
				var edge := p+corner*CELL*0.5
				var height := Map.ground_height(edge.x,edge.y)
				low = minf(low,height)
				high = maxf(high,height)
			box.size = Vector3(CELL,high-low+2.6,CELL)
			shape.shape = box
			shape.position.y = (low+high)*0.5-Map.ground_height(p.x,p.y)+1.2
			wall.add_child(shape)
			add_child(wall)
			wall.global_position = Map.ground_pos(p.x,p.y)
	# Wooden markers and original scarecrow mesh establish readable entrances.
	for cell: Vector2i in [Vector2i(1,0),Vector2i(11,12),Vector2i(5,5),Vector2i(9,3)]:
		var p := cell_position(cell)
		var scarecrow := MeshInstance3D.new()
		scarecrow.mesh = load("res://assets/cornfield/scarecrow.res")
		add_child(scarecrow)
		scarecrow.global_position = Map.ground_pos(p.x-1.1,p.y)
		scarecrow.rotation.y = random.randf()*TAU
	var sign := Label3D.new()
	sign.text = "MAISLABYRINTH\nVersteckte Vorräte - zwei Ausgänge"
	sign.font_size = 40
	sign.pixel_size = 0.006
	sign.modulate = Color(0.93,0.78,0.46)
	add_child(sign)
	var entrance := cell_position(Vector2i(1,0))
	sign.position = Map.ground_pos(entrance.x,entrance.y-2)+Vector3.UP*2.8
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
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell: Vector2i in passages:
		var base := ORIGIN+Vector2(cell)*CELL
		for z in 4:
			for x in 4:
				var points: Array[Vector3] = []
				for offset: Vector2 in [Vector2(x,z),Vector2(x+1,z),Vector2(x+1,z+1),Vector2(x,z+1)]:
					var p := base+offset*CELL/4
					points.append(Vector3(p.x,Map.surface_height(p.x,p.y)+0.025,p.y))
				for i in [0,2,1,0,3,2]:
					st.set_color(Color(0.28,0.21,0.115).lightened(random.randf_range(0,0.045)))
					st.add_vertex(points[i])
	st.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = material
	add_child(node)
