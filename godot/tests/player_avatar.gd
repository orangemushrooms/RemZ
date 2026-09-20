extends SceneTree

var failures := 0
var checks := 0
var stage: Node3D
var avatar: Node3D
var actor: Player
var camera: Camera3D

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error("FAIL: " + message)

func capture(name: String) -> void:
	if not "--render-avatar" in OS.get_cmdline_user_args(): return
	for i in 4: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/player-avatar")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder.path_join(name + ".png"))

func run() -> void:
	root.size = Vector2i(1200, 1000)
	stage = Node3D.new()
	root.add_child(stage)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("222a31")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("b8c9dd")
	environment.environment.ambient_light_energy = 0.65
	stage.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-38, -35, 0)
	light.light_energy = 1.5
	light.shadow_enabled = true
	stage.add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(20, 20)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("41484b")
	material.roughness = 0.9
	ground.material_override = material
	stage.add_child(ground)
	actor = Player.new()
	actor.remote_actor = true
	stage.add_child(actor)
	actor.rotation = Vector3.ZERO
	actor.set_physics_process(false)
	actor.flashlight.visible = false
	avatar = load("res://scripts/coop_avatar.gd").new()
	actor.add_child(avatar)
	avatar.setup(actor, "Survivor", 1)
	avatar.set_process(false)
	avatar.label.visible = false
	camera = Camera3D.new()
	stage.add_child(camera)
	camera.position = Vector3(2.3, 1.6, -3.4)
	camera.look_at(Vector3(0, 0.95, 0))
	camera.fov = 35
	camera.make_current()
	var rig: Skeleton3D = avatar.visual.skeleton
	var head := rig.to_global(rig.get_bone_global_pose(rig.find_bone("Head")).origin)
	check(head.y > 1.4 and head.y < 1.85, "human scale and head height")
	check(rig.get_bone_count() >= 20, "skinned humanoid skeleton")
	check(avatar.visual.animation.has_animation("walk"), "walk clip imported")
	check(avatar.visual.animation.has_animation("run"), "run clip imported")
	for id in Weapons.ORDER:
		avatar.set_weapon(id)
		for pitch in [-0.85, 0.0, 0.85]:
			actor.pitch = pitch
			avatar._process(0.016)
			for side in ["Right", "Left"]:
				var hand := rig.find_bone(side + "Hand")
				var wrist := rig.to_global(rig.get_bone_global_pose(hand).origin)
				var target: Vector3 = avatar.gun.to_global(avatar.right_grip if side == "Right" else avatar.left_grip)
				check(wrist.distance_to(target) < 0.04, "%s %s pitch %.2f wrist error %.3f" % [id, side, pitch, wrist.distance_to(target)])
		actor.pitch = 0.0
		avatar._process(0.016)
		if id in ["pistol", "ak47", "shotgun"]: await capture(id)
		if id == "ak47":
			var original := camera.transform
			camera.position = Vector3(0.85, 1.55, -1.5)
			camera.look_at(Vector3(0, 1.38, -0.1))
			await capture("grip-detail")
			camera.transform = original
	avatar.set_weapon("ak47")
	actor.velocity = Vector3(0, 0, -4.4)
	for i in 30: avatar._process(0.016)
	await capture("walking")
	actor.velocity = Vector3(0, 0, -7.2)
	for i in 30: avatar._process(0.016)
	check(avatar.visual.animation.current_animation == "run", "sprinting selects run animation")
	await capture("running")
	actor.velocity = Vector3.ZERO
	actor.alive = false
	for i in 90: avatar._process(0.016)
	check(not avatar.flash.visible, "downed muzzle flash hidden")
	await capture("downed")
	actor.alive = true
	for i in 90: avatar._process(0.016)
	check(absf(avatar.body.rotation.z) < 0.001, "revive upright")
	print("PLAYER_AVATAR_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
