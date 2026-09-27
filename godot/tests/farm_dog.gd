# The dog must deform its actual skinned legs, follow host/client displacement,
# stop stepping at rest and stop animating after death.
extends SceneTree
var checks := 0
var failures := 0
var world: Node3D
var rendered := false

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func move_dog(dog: ZombieBeast, speed: float, seconds: float) -> void:
	for frame in ceili(seconds * 60):
		if dog.replica:
			dog.net_position.z += speed / 60.0
			dog._physics_process(1.0 / 60.0)
		else:
			dog.position.z += speed / 60.0
			dog._update_animation(1.0 / 60.0)
		dog.anim.advance(1.0 / 60.0)

func shot(dog: ZombieBeast, clip: String, phase: float) -> void:
	if not rendered: return
	dog.anim.play(clip, 0)
	dog.anim.seek(dog.anim.get_animation(clip).length * phase, true)
	for frame in 4: await process_frame
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://../artifacts/farm-dog/")
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir + "%s-%d.png" % [clip, int(phase * 100)])

func run() -> void:
	rendered = "--render-dog" in OS.get_cmdline_user_args()
	world = Node3D.new()
	root.add_child(world)
	current_scene = world
	if rendered:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1280, 720)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(0.09, 0.12, 0.13)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(0.8, 0.85, 1)
		env.environment.ambient_light_energy = 0.6
		world.add_child(env)
		var light := DirectionalLight3D.new()
		light.rotation_degrees = Vector3(-45, -40, 0)
		light.light_energy = 1.6
		light.shadow_enabled = true
		world.add_child(light)
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.position = Vector3(2.2, 0.9, 1.2)
		camera.look_at(Vector3(0, 0.4, 0))
		camera.current = true
		var plane := PlaneMesh.new()
		plane.size = Vector2(25, 25)
		DefenceTower.piece(world, plane, Vector3.ZERO, DefenceTower.material(Color(0.23, 0.26, 0.21)))
	for remote in [false, true]:
		var dog := ZombieBeast.new()
		dog.setup("zombie_dog", null, [], 1.0, Callable())
		dog.replica = remote
		world.add_child(dog)
		dog.set_physics_process(false)
		dog.agent.avoidance_enabled = false
		check(dog.anim != null and dog.model_path.ends_with("zombie_dog_animated.glb"), "Farm dog loads an animated rig (replica=%s)" % remote)
		if not dog.anim:
			dog.free()
			continue
		dog.anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var rig := dog.model.find_child("Skeleton3D", true, false) as Skeleton3D
		check(rig != null, "Farm dog has a skeleton")
		if not remote:
			for gait in ["walk", "run"]:
				for limb in ["FrontLeft", "FrontRight", "HindLeft", "HindRight"]:
					var paw := rig.find_bone(limb + "Paw")
					var low := Vector3(INF, INF, INF)
					var high := -low
					dog.anim.play(gait, 0)
					for sample in 33:
						dog.anim.seek(dog.anim.get_animation(gait).length * sample / 32.0, true)
						rig.force_update_all_bone_transforms()
						var point := rig.get_bone_global_pose(paw).origin
						low = low.min(point)
						high = high.max(point)
					check(high.z - low.z > 0.25 and high.y - low.y > 0.06, "%s %s paw swings forward and lifts off the ground" % [gait, limb])
			for phase in [0.0, 0.25, 0.5, 0.75]: await shot(dog, "run", phase)
		move_dog(dog, 7.2, 1.0)
		check(dog.anim.current_animation == "run" and dog.anim.speed_scale > 1.3, "Fast displacement drives the gallop (replica=%s)" % remote)
		var fast_rate := dog.anim.speed_scale
		move_dog(dog, 3.6, 1.0)
		check(dog.anim.current_animation == "run" and dog.anim.speed_scale < fast_rate * 0.65, "Slower movement slows the stride (replica=%s)" % remote)
		move_dog(dog, 0.7, 1.0)
		check(dog.anim.current_animation == "walk", "Slow movement uses a walk (replica=%s)" % remote)
		move_dog(dog, 0.0, 1.5)
		check(dog.anim.current_animation == "idle", "Stationary dog stops stepping (replica=%s)" % remote)
		dog.play("attack")
		move_dog(dog, 0.0, 0.18)
		check(dog.anim.current_animation == "attack" and is_equal_approx(dog.anim.speed_scale, 1.0) and dog.model.position.z > 0.45, "Bite animation and lunge peak at the damage tick (replica=%s)" % remote)
		move_dog(dog, 7.2, 0.8)
		check(dog.anim.current_animation == "run", "Gallop resumes after biting (replica=%s)" % remote)
		dog.replica = true # Avoid loot drops in this isolated animation test.
		dog.die(Vector3.ZERO)
		await create_timer(0.6).timeout
		check(not dog.anim.is_playing() and absf(dog.model.rotation.z) > 1.5, "Dead dog stops its gait and lies on its flank")
		dog.free()
	print("FARM_DOG_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
