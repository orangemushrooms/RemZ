extends Node3D
## Existing Meshy trees, baked distance meshes and photographic canopy details.
const CELL := 24.0
var count := 0
var cells: Array[Dictionary] = []
var elapsed := 0.0

func build() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 84712
	var leaves := Trees._leaf_material("beech")
	leaves.set_shader_parameter("autumn",0.0)
	leaves.set_shader_parameter("tint",Vector3(0.48,0.68,0.32))
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var trunk_mesh := Trees._trunk_mesh("beech",rng)
	var trunk_material := Trees._bark_material("ph_bark_oak",Color(0.42,0.38,0.3))
	for variant in ["a","b"]:
		var template: Node3D = load("res://assets/models/tree_autumn_%s.glb" % variant).instantiate()
		var bounds := Barricade._bounds(template)
		var original: Array = Trees._first_mesh(template,Transform3D.IDENTITY)
		var meshes: Array[Mesh] = []
		for lod in ["near","far"]:
			var source: Node3D = template if lod=="near" else load("res://assets/planes/tree_%s_%s.glb" % [variant,lod]).instantiate()
			var part: Array = Trees._first_mesh(source,Transform3D.IDENTITY)
			var mesh: Mesh = part[0].duplicate()
			for surface in mesh.get_surface_count():
				var material := ShaderMaterial.new()
				material.shader = load("res://shaders/planes_tree.gdshader")
				material.set_shader_parameter("vertex_colour",lod!="near")
				material.set_shader_parameter("base",mesh.get_aabb().position.y)
				material.set_shader_parameter("height",mesh.get_aabb().size.y)
				material.set_shader_parameter("bark",load("res://assets/textures/ph_bark_oak_albedo.jpg"))
				if lod=="near": material.set_shader_parameter("albedo",mesh.surface_get_material(surface).albedo_texture)
				mesh.surface_set_material(surface,material)
			meshes.append(mesh)
			if source!=template: source.free()
		var batches := {}
		var crowns := {}
		var trunks := {}
		for i in Map._d.landscape_trees.size():
			if (i%3==0) != (variant=="b"): continue
			var tree: Array = Map._d.landscape_trees[i]
			var p := Vector2(tree[0],tree[1])
			var key := Vector2i(floori(p.x/CELL),floori(p.y/CELL))
			var at := Map.ground_pos(p.x,p.y)
			var scale := float(tree[3])/bounds.size.y
			var basis := Basis(Vector3.UP,deg_to_rad(tree[4])).scaled(Vector3(scale*rng.randf_range(0.92,1.16),scale,scale*rng.randf_range(0.88,1.1)))
			var fit: Transform3D = Transform3D(basis,at-basis*Vector3(bounds.get_center().x,bounds.position.y,bounds.get_center().z))*original[1]
			if not batches.has(key): batches[key] = []; crowns[key] = []; trunks[key] = []
			batches[key].append(fit)
			trunks[key].append(Transform3D(Basis(Vector3.UP,deg_to_rad(tree[4])).scaled(Vector3.ONE*float(tree[3])/26.0),at))
			Trees._crown_cards("beech",float(tree[3])/26.0,float(tree[4]),at,rng,crowns[key],0.65)
			var body := StaticBody3D.new()
			body.position = at
			var cs := CollisionShape3D.new()
			var cylinder := CylinderShape3D.new()
			cylinder.radius = 0.28 if i<5 else 0.38
			cylinder.height = float(tree[3])*0.58
			cs.position.y = cylinder.height*0.5
			cs.shape = cylinder
			body.add_child(cs)
			add_child(body)
			count += 1
		for key: Vector2i in batches:
			var origin := Vector3(key.x*CELL,0,key.y*CELL)
			var instance := _batch(meshes[0],batches[key],origin)
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.hide()
			var trunk := _batch(trunk_mesh,trunks[key],origin)
			trunk.material_override = trunk_material
			trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var shadow := _batch(meshes[1],batches[key],origin)
			shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
			shadow.visibility_range_end = 145
			var cards: Array = []
			for item in crowns[key]: cards.append(item[0])
			var canopy := _batch(quad,cards,origin,crowns[key])
			canopy.material_override = leaves
			canopy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			canopy.visibility_range_end = 700
			cells.append({"node":instance,"trunk":trunk,"center":Vector2(origin.x+CELL/2,origin.z+CELL/2),"lod":1})
		template.free()

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
		var lod := 0 if distance<60 else 1
		if lod==cell.lod: continue
		cell.node.visible = lod==0
		cell.trunk.visible = lod==1
		cell.lod = lod
