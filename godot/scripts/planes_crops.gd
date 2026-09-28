extends Node3D
const CELL := 16
var game: Node
var crop_image: Image
var corn_meshes: Array[Mesh] = []
var wheat_meshes: Array[Mesh] = []
var batches: Array[MultiMeshInstance3D] = []
var grass_batches: Array[MultiMeshInstance3D] = []
var counts := {"corn":0,"wheat":0,"grass":0}
var wind: ShaderMaterial
var _elapsed := 0.0
var rustle: AudioStreamPlayer

func sample(p: Vector2) -> Color:
	if not Map.extent().has_point(p): return Color.BLACK
	var uv := (p-Map.extent().position)/(Map.extent().size+Vector2.ONE)
	return crop_image.get_pixel(clampi(int(uv.x*crop_image.get_width()),0,crop_image.get_width()-1),clampi(int(uv.y*crop_image.get_height()),0,crop_image.get_height()-1))

func in_corn(p: Vector2) -> bool:
	return sample(p).r>0.5

func build(main: Node) -> void:
	game = main
	var tex: Texture2D = load("res://assets/planes/crops.png")
	crop_image = tex.get_image()
	if crop_image.is_compressed(): crop_image.decompress()
	for id in ["a","far","distant"]:
		corn_meshes.append(load("res://assets/cornfield/corn_%s.res" % id))
	wheat_meshes = [_wheat(false),_wheat(true)]
	wind = ShaderMaterial.new()
	wind.shader = load("res://shaders/corn_wind.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9404384
	var ext := Map.extent()
	var grass_material := Foliage.sprite_material("res://assets/sprites/grass.png",Vector2(4,1),1.0,Color(0.65,0.82,0.46))
	var grass_mesh := Foliage._tuft_mesh(0.52,0.19)
	for z in range(int(ext.position.y),int(ext.end.y),CELL):
		if game.boot: game.boot.step(0.48+0.35*(z-ext.position.y)/ext.size.y,true)
		for x in range(int(ext.position.x),int(ext.end.x),CELL):
			var origin := Map.ground_pos(x,z)
			var corn: Array[Transform3D] = []
			var wheat: Array[Transform3D] = []
			var grass: Array[Transform3D] = []
			for j in CELL*2:
				for i in CELL*2:
					var p := Vector2(x+i*0.5+rng.randf_range(0.05,0.4),z+j*0.5+rng.randf_range(0.05,0.4))
					if not ext.has_point(p): continue
					var crop := sample(p)
					if Map.cover(p.x,p.y).b>0.05: continue
					if game.near_building(p): continue
					var kind := "corn" if crop.r>0.5 else "wheat" if crop.g>0.5 else "grass"
					if kind=="grass":
						if i%2==1 or j%2==1: continue
						if Map.cover(p.x,p.y).g<0.92 or crop.b>0.1: continue
						# Low meadow tufts; skip mapped settlement footprints and their yards.
						if game.near_building(p): continue
					var scale := rng.randf_range(0.84,1.1)
					var at := Map.ground_pos(p.x,p.y)-origin
					var xf := Transform3D(Basis(Vector3.UP,rng.randf()*TAU).scaled(Vector3.ONE*scale),at)
					if kind=="corn": corn.append(xf)
					elif kind=="wheat": wheat.append(xf)
					else: grass.append(xf)
			for spec in [["corn",corn,corn_meshes[2]],["wheat",wheat,wheat_meshes[1]],["grass",grass,grass_mesh]]:
				if spec[1].is_empty(): continue
				var node := _batch(spec[1],spec[2],grass_material if spec[0]=="grass" else wind,origin)
				node.set_meta("kind",spec[0])
				node.visibility_range_end = 65 if spec[0]=="grass" else 440
				if spec[0]=="grass": grass_batches.append(node)
				else: batches.append(node)
				counts[spec[0]] += spec[1].size()
	rustle = AudioStreamPlayer.new()
	rustle.stream = Sfx.corn_bed()
	rustle.volume_db = -60
	add_child(rustle)
	rustle.play()
	update_lod()

func _batch(transforms: Array, mesh: Mesh, mat: Material, origin: Vector3) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	var bounds := AABB()
	var samples := PackedVector3Array()
	for i in transforms.size():
		mm.set_instance_transform(i,transforms[i])
		if i%37==0: samples.append(origin+transforms[i].origin)
		mm.set_instance_custom_data(i,Color(i%4,0.85+(i%9)*0.025,1.0,0.3))
		var b: AABB = transforms[i]*AABB(Vector3(-0.8,0,-0.8),Vector3(1.6,3.3,1.6))
		bounds = b if i==0 else bounds.merge(b)
	mm.custom_aabb = bounds
	var node := MultiMeshInstance3D.new()
	node.set_meta("placement_samples",samples)
	node.name = "Crops_%d_%d" % [origin.x,origin.z]
	node.multimesh = mm
	node.position = origin
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end_margin = 15
	add_child(node)
	return node

func update_lod() -> void:
	var p: Vector3 = game.player.global_position
	for node in batches:
		var distance := (node.position+Vector3(8,0,8)).distance_to(p)
		var corn: bool = node.get_meta("kind")=="corn"
		var lod := (0 if distance<24 else 1 if distance<62 else 2) if corn else (0 if distance<38 else 1)
		var mesh: Mesh = corn_meshes[lod] if corn else wheat_meshes[lod]
		if node.multimesh.mesh != mesh: node.multimesh.mesh = mesh

func _process(delta: float) -> void:
	if not game or not game.player: return
	_elapsed += delta
	if _elapsed>0.3:
		_elapsed = 0
		update_lod()
	if rustle:
		var moving: bool = game.player.active and Vector2(game.player.velocity.x,game.player.velocity.z).length()>0.5
		var inside := in_corn(Vector2(game.player.position.x,game.player.position.z))
		rustle.volume_db = move_toward(rustle.volume_db,-25.0 if moving and inside else -60.0,delta*25)

func _wheat(far: bool) -> ArrayMesh:
	# No wheat model exists in the library. Native stalks/ears complement the
	# existing maize meshes, with all colours/materials local to this map.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in (3 if far else 7):
		var x := sin(k*2.4)*0.22
		var z := cos(k*2.4)*0.22
		var h := 0.74+(k%4)*0.07
		var tint := Color(0.58+(k%3)*0.045,0.45+(k%3)*0.04,0.25)
		_ribbon(st,Vector3(x,0,z),Vector3(x+0.07,h,z+0.02),0.009,tint)
		_ribbon(st,Vector3(x+0.07,h-0.1,z+0.02),Vector3(x+0.085,h+0.09,z+0.04),0.031,tint.lightened(0.14))
		if not far:
			for side in [-1,1]:
				_ribbon(st,Vector3(x,h*0.4,z),Vector3(x+side*0.12,h*0.67,z+0.07),0.017,tint.darkened(0.12))
				for grain in 5:
					var a := Vector3(x+0.07,h-0.08+grain*0.03,z+0.02)
					_ribbon(st,a,a+Vector3(side*0.035,0.055,0.018),0.012,tint.lightened(0.2))
	st.generate_tangents()
	return st.commit()

func _ribbon(st: SurfaceTool, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	for axis in [Vector3.RIGHT,Vector3.BACK]:
		var vertices := [a-axis*width,a+axis*width,b+axis*width*0.2,b-axis*width*0.2]
		for i in [0,1,2,0,2,3]:
			st.set_color(color)
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(i%2,float(i/2)))
			st.set_uv2(Vector2.ZERO)
			st.add_vertex(vertices[i])
