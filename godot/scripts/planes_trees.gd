extends Node3D
## Existing Meshy branch skeletons with open leaf clusters instead of solid crowns.
const CELL := 48.0
var count := 0
var cells: Array[Dictionary] = []
var elapsed := 0.0
var branch_meshes: Array[Mesh] = []

func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 84712
	var template: Node3D = load("res://assets/models/tree_birch.glb").instantiate()
	var original := Trees._first_mesh(template,Transform3D.IDENTITY)
	var bounds := Barricade._bounds(template)
	for lod in ["near","far"]:
		var source: Node3D = load("res://assets/planes/branches_%s.glb" % lod).instantiate()
		var part := Trees._first_mesh(source,Transform3D.IDENTITY)
		var mesh: Mesh = part[0].duplicate()
		var material := ShaderMaterial.new()
		material.shader = load("res://shaders/planes_bark.gdshader")
		material.set_shader_parameter("height",mesh.get_aabb().size.y)
		material.set_shader_parameter("bark",load("res://assets/textures/ph_bark_oak_albedo.jpg"))
		for surface in mesh.get_surface_count(): mesh.surface_set_material(surface,material)
		branch_meshes.append(mesh)
		source.free()
	var branches := {}
	var crowns := {}
	for i in Map._d.landscape_trees.size():
		var tree: Array = Map._d.landscape_trees[i]
		var p := Vector2(tree[0],tree[1])
		var key := Vector2i(floori(p.x/CELL),floori(p.y/CELL))
		var at := Map.ground_pos(p.x,p.y)
		var height := float(tree[3])
		var k := height/bounds.size.y
		var basis := Basis(Vector3.UP,deg_to_rad(tree[4])).scaled(Vector3(k*1.15,k,k*rng.randf_range(0.9,1.2)))
		var fit: Transform3D = Transform3D(basis,at-basis*Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z))*original[1]
		if not branches.has(key): branches[key] = []; crowns[key] = []
		branches[key].append(fit)
		_crown(at,height,rng,crowns[key])
		var body := StaticBody3D.new()
		body.position = at
		var cs := CollisionShape3D.new()
		var cylinder := CylinderShape3D.new()
		cylinder.radius = 0.28 if i<5 else 0.38
		cylinder.height = height*0.58
		cs.position.y = cylinder.height*0.5
		cs.shape = cylinder
		body.add_child(cs)
		add_child(body)
		count += 1
	var leaves := Trees._leaf_material("beech")
	# The source sprite has no imported mipmaps. A local mip chain keeps small
	# distant leaves stable and avoids sampling the full atlas for every pixel.
	var leaf_image: Image = load("res://assets/sprites/leaf_beech.png").get_image()
	if leaf_image.is_compressed(): leaf_image.decompress()
	leaf_image.generate_mipmaps()
	leaves.set_shader_parameter("tex",ImageTexture.create_from_image(leaf_image))
	leaves.set_shader_parameter("autumn",0.0)
	leaves.set_shader_parameter("tint",Vector3(0.58,0.72,0.4))
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	for key: Vector2i in branches:
		var origin := Vector3(key.x*CELL,0,key.y*CELL)
		var trunk := _batch(branch_meshes[0],branches[key],origin)
		trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		trunk.visibility_range_end = 700
		var cards: Array = []
		var shadow_cards: Array = []
		var shadow_data: Array = []
		for i in crowns[key].size():
			var item: Array = crowns[key][i]
			cards.append(item[0])
			if i%6==0:
				var xf: Transform3D = item[0]
				xf.basis = xf.basis.scaled_local(Vector3(2.0,2.0,1.0))
				shadow_cards.append(xf)
				shadow_data.append([xf,item[1]])
		var canopy := _batch(quad,cards,origin,crowns[key])
		canopy.material_override = leaves
		canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		canopy.visibility_range_end = 700
		var shadow := _batch(quad,shadow_cards,origin,shadow_data)
		shadow.material_override = leaves
		shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		shadow.visibility_range_end = 120
		cells.append({"node":trunk,"center":Vector2(origin.x+CELL/2,origin.z+CELL/2),"lod":0})
	set_meta("open_canopies",count)
	template.free()

func _crown(at: Vector3, height: float, rng: RandomNumberGenerator, out: Array) -> void:
	var center := at+Vector3.UP*height*0.75
	var radius := height*rng.randf_range(0.22,0.28)
	var lobes: Array[Vector3] = []
	# Cover the leading shoot and all branch directions, retaining irregular gaps
	# between groups instead of leaving a row of bare spikes above the canopy.
	lobes.append(at+Vector3.UP*height*0.94)
	for i in 8:
		var angle := i*TAU/8+rng.randf_range(-0.25,0.25)
		lobes.append(center+Vector3(cos(angle)*radius*0.65,rng.randf_range(-0.13,0.14)*height,sin(angle)*radius*0.65))
	# Branch-sized groups with gaps; leaf sprays stay much smaller than old crown cards.
	for i in 420:
		var lobe := lobes[i%lobes.size()]
		var direction := Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1)).normalized()
		var p := lobe+direction*radius*rng.randf_range(0.08,0.48)
		var width := height*rng.randf_range(0.055,0.085)
		var b := Basis(Vector3.UP,rng.randf()*TAU)*Basis(Vector3.RIGHT,rng.randf_range(-1.3,1.3))
		b = b.scaled_local(Vector3(width,width*rng.randf_range(0.7,1.1),1))
		out.append([Transform3D(b,p),Color(lobe.x,lobe.y,lobe.z,rng.randf_range(0.78,1.1))])

func _batch(mesh: Mesh, transforms: Array, origin: Vector3, custom: Array = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = not custom.is_empty()
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		var fit: Transform3D = transforms[i]
		fit.origin -= origin
		mm.set_instance_transform(i,fit)
		if mm.use_custom_data: mm.set_instance_custom_data(i,custom[i][1])
	var node := MultiMeshInstance3D.new()
	node.position = origin
	node.multimesh = mm
	add_child(node)
	return node

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed<0.25: return
	elapsed = 0.0
	var camera := get_viewport().get_camera_3d()
	if not camera: return
	var at := Vector2(camera.global_position.x,camera.global_position.z)
	for cell: Dictionary in cells:
		var distance: float = at.distance_to(cell.center)
		var lod := 0 if distance<65 else 1
		if lod==cell.lod: continue
		cell.node.multimesh.mesh = branch_meshes[lod]
		cell.lod = lod
