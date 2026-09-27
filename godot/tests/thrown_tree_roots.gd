extends SceneTree
var checks := 0
var failures := 0
var rendered := false
var camera: Camera3D
var world: Node3D

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func shot(name: String, position: Vector3, target: Vector3) -> void:
	if not rendered: return
	camera.position = position
	camera.look_at(target)
	for frame in 8: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/tree-roots/")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder + name + ".png")

func run() -> void:
	rendered = "--render-roots" in OS.get_cmdline_user_args()
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	if rendered:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1600, 900)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.10, 0.14, 0.15)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.78, 0.86, 1.0)
		env.environment.ambient_light_energy = 0.65
		world.add_child(env)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-40, -30, 0)
		light.light_energy = 1.5
		light.shadow_enabled = true
		world.add_child(light)
		camera = Camera3D.new()
		camera.fov = 55
		world.add_child(camera)
		camera.current = true
		var floor_mesh := PlaneMesh.new()
		floor_mesh.size = Vector2(50, 50)
		DefenceTower.piece(world, floor_mesh, Vector3(0, -2.0, 0), DefenceTower.material(Color(0.19, 0.23, 0.15)))
	for id in TreeRootBall.VARIANTS:
		var origin := Vector3(id * 3.0, 0, 0)
		var roots := TreeRootBall.make(origin)
		world.add_child(roots)
		var mesh := roots.mesh
		check(mesh.get_surface_count() == 3, "Variant %d merges soil, bark and torn wood into three surfaces" % id)
		var total := 0
		var textured := true
		for surface in mesh.get_surface_count():
			total += mesh.surface_get_array_len(surface)
			var mat := mesh.surface_get_material(surface) as StandardMaterial3D
			textured = textured and mat.albedo_texture != null and mat.normal_enabled
		check(textured and total > 1000 and total < 60000, "Variant %d has textured detailed roots within the geometry budget (%d vertices)" % [id, total])
		check(mesh.get_aabb().size.x > 3.0 and mesh.get_aabb().size.z > 3.0, "Variant %d has a spreading root silhouette" % id)
		var client := TreeRootBall.make(origin)
		check(client.mesh == mesh and client.get_meta("root_variant") == roots.get_meta("root_variant"), "Host and replica reuse identical roots for variant %d" % id)
		client.free()
		await shot("roots-%d" % id, Vector3(4, 1.8, 4), Vector3(0, -0.5, 0))
		roots.free()
	for kind in ThrownTree.MODELS:
		var tree := ThrownTree.new()
		world.add_child(tree)
		# x=0 selects fir; x=1 selects spruce_hd in ThrownTree._tree_model.
		var origin := Vector3(0 if kind == "fir" else 1, 5, 0)
		tree.setup(origin, Vector3(0, 0, 12), 2.0, null, true)
		tree.set_process(false)
		check(tree._visual.get_child(0).name == "TornRoots", kind + " uses the new root system")
		tree.position = Vector3.ZERO
		await shot(kind + "-upright", Vector3(5, 1.5, 5), Vector3(0, -0.1, 0))
		tree._process(0.7)
		check(not tree.landed and tree.position.y > origin.y, kind + " follows its existing flight arc")
		await shot(kind + "-flight", tree.position + Vector3(6, 2, 7), tree.position)
		tree._impact()
		check(tree.landed, kind + " lands normally as a harmless replica")
		tree.position = Vector3(0, -0.9, 0) # display on the preview floor at y=-2
		if rendered: await create_timer(2.6).timeout # let the impact dust settle
		await shot(kind + "-landed", Vector3(5, 1.0, -5), Vector3(0, -0.4, 0))
		tree.free()
	check(TreeRootBall._meshes.size() <= TreeRootBall.VARIANTS, "Root geometry cache stays bounded across throws")
	print("THROWN_TREE_ROOTS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
