extends SceneTree

const Effects = preload("res://scripts/elemental_effects.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.035, 0.045, 0.06)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	scene.add_child(environment)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.position = Vector3(0, 1.3, 5)
	camera.look_at(Vector3(0, 1.1, 0))
	for mode in ["fire", "frost"]:
		var x := -0.9 if mode == "fire" else 0.9
		var body := MeshInstance3D.new()
		body.mesh = CapsuleMesh.new()
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.2, 0.25, 0.2)
		body.material_override = material
		scene.add_child(body)
		body.position = Vector3(x, 1, 0)
		if mode == "frost":
			var ice := ShaderMaterial.new()
			ice.shader = preload("res://shaders/frost_surface.gdshader")
			body.material_overlay = ice
		var particles := Effects.particles(mode, 0.3, 1.8)
		scene.add_child(particles)
		particles.position = Vector3(x, 0.85, 0)
		particles.emitting = true
		var label := Label3D.new()
		label.text = mode.to_upper()
		label.position = Vector3(x, 2.4, 0)
		scene.add_child(label)
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../logs/elemental-visual.png")
	print("ELEMENTAL_VISUAL_DONE")
	quit()
