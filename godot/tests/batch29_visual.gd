# Visual check of the 27 Sep 2026 skins (windowed): artifacts/batch29/
#   bake_<skin>.png    studio, grazing light: the web export's high-poly (0.5-2 M triangles, loaded at runtime from
#                      assets/raw) | the game mesh with its baked normal map | the same mesh without the map
#   lineup_<clip>.png  the five skins on the meadow at 16:30, frozen in one clip
#   portrait_<skin>.png close-up in the game light
#   rise_<n>.png       a businessman getting up from the forest floor
#   Godot.exe --path godot --script res://tests/run.gd -- --suite=batch29_visual --no-intro --no-music
extends SceneTree

const SKINS := {"zombie_businessman": "shambler", "zombie_wanderer": "shambler", "zombie_wastelander": "runner",
	"zombie_wraith": "stalker", "zombie_bride": "bride"}
const BAKED := ["zombie_businessman", "zombie_wastelander", "zombie_wraith", "zombie_bride"]
const SHEETS := {"idle": 0.5, "walk": 0.3, "attack": "peak", "scream": 0.5, "arise": 0.45}
var game: Node
var began := Time.get_ticks_msec()
var dir := ProjectSettings.globalize_path("res://../artifacts/batch29/")

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 600000:
		print("BATCH29_VISUAL timeout")
		quit(1)
	return false

func capture(image: Image, file: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	image.save_png(dir + file + ".png")
	print("BATCH29_SHOT ", file)

func frames(n: int) -> void:
	for i in n: await process_frame
	await RenderingServer.frame_post_draw

# the rest pose of a skinned model: no clip, bones at rest
func rest_pose(model: Node3D) -> void:
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if player:
		player.stop()
		player.active = false
	var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
	if rig: rig.reset_bone_poses()

func studio_bake(skin: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1800, 1000)
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.16, 0.17, 0.19)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.5, 0.5, 0.52)
	environment.ambient_light_energy = 0.35
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world := WorldEnvironment.new()
	world.environment = environment
	vp.add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-18, 58, 0)     # low and from the side: folds and wrinkles cast their shading
	sun.light_energy = 2.2
	sun.shadow_enabled = true
	vp.add_child(sun)
	var camera := Camera3D.new()
	camera.fov = 26.0
	vp.add_child(camera)
	camera.position = Vector3(0, 1.25, 5.4)
	camera.look_at(Vector3(0, 1.05, 0))
	camera.current = true
	# the high-poly web export, straight from assets/raw (no import): Meshy statics are 1.9 units, centred
	var source := ProjectSettings.globalize_path("res://../assets/raw/%s_v3/source.glb" % skin)
	var state := GLTFState.new()
	var document := GLTFDocument.new()
	var t0 := Time.get_ticks_msec()
	if document.append_from_file(source, state) == OK:
		var high: Node3D = document.generate_scene(state)
		vp.add_child(high)
		high.scale = Vector3.ONE * (1.7 / 1.9)
		high.position = Vector3(-0.95, 0.95 * 1.7 / 1.9, 0)
	print("BATCH29_SOURCE %s loaded in %d ms" % [skin, Time.get_ticks_msec() - t0])
	for i in 2:
		var model: Node3D = load("res://assets/models/%s.glb" % skin).instantiate()
		vp.add_child(model)
		model.position = Vector3(0.0 if i == 0 else 0.95, 0, 0)
		rest_pose(model)
		if i == 1:
			for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
				for surface in mesh.mesh.get_surface_count():
					var material := (mesh.mesh.surface_get_material(surface) as StandardMaterial3D).duplicate() as StandardMaterial3D
					material.normal_enabled = false
					mesh.set_surface_override_material(surface, material)
	await frames(12)
	capture(vp.get_texture().get_image(), "bake_" + skin)
	vp.queue_free()
	await frames(2)

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	for skin in BAKED: await studio_bake(skin)
	# ---- the game
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	if "achievements" in game and game.achievements: game.achievements.hide()
	game.day_night.clock_seconds = 16 * 3600 + 30 * 60
	game.day_night.advance(1)
	game.day_night.set_process(false)
	game.weather.force("clear")
	game.hud.message("", 0.0)
	var bodies: Array[Zombie] = []
	var x := -3.4
	for skin in SKINS:
		Zombie.force_skin = skin
		game.spawn_zombie(SKINS[skin], Vector2(x, 62), 1.0, "east")
		Zombie.force_skin = ""
		var z: Zombie = game.zombies_root.get_children().back()
		z.set_physics_process(false)
		z.agent.avoidance_enabled = false
		z.rotation.y = PI
		if z.cloak < 1.0:
			z.cloak = 1.0
			z._update_cloak(0.0)
			for material in z._materials:
				material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
				material.albedo_color.a = 1.0
		bodies.append(z)
		x += 1.7
	var eye := Map.ground_pos(0.0, 55.5)
	game.player.global_position = eye + Vector3(0, 0.2, 0)
	game.player.camera.look_at(Map.ground_pos(0.0, 62.0) + Vector3(0, 1.0, 0))
	await create_timer(1.0).timeout
	for clip in SHEETS:
		for z in bodies:
			if not z.anim.has_animation(clip): continue
			z.anim.play(clip)
			var length := z.anim.get_animation(clip).length
			var at: float = float(Zombie.clip_info(z.model_path).get(clip, {}).get("peak", length * 0.5)) if str(SHEETS[clip]) == "peak" else length * float(SHEETS[clip])
			z.anim.seek(at, true)
			z.anim.pause()
		await frames(8)
		capture(root.get_texture().get_image(), "lineup_" + clip)
	# portraits in the game light
	for i in bodies.size():
		var z := bodies[i]
		z.anim.play("idle")
		z.anim.seek(1.0, true)
		z.anim.pause()
		var at := z.global_position + Vector3(0, 1.25, 0)
		game.player.global_position = Map.ground_pos(z.global_position.x + 0.6, z.global_position.z - 2.3) + Vector3(0, -0.3, 0)
		game.player.camera.look_at(at)
		await frames(8)
		capture(root.get_texture().get_image(), "portrait_" + z.model_path.get_file().get_basename())
	for z in bodies: z.queue_free()
	await frames(2)
	# the rise from the forest floor, 5 m in front of the camera
	Zombie.force_skin = "zombie_businessman"
	var spot := Vector2(2.0, 66.0)
	game.player.global_position = Map.ground_pos(spot.x, spot.y - 5.0) + Vector3(0, 0.2, 0)
	game.player.camera.look_at(Map.ground_pos(spot.x, spot.y) + Vector3(0, 0.7, 0))
	game.spawn_zombie("shambler", spot, 1.0, "", 0.0, -1, true)
	Zombie.force_skin = ""
	var riser: Zombie = game.zombies_root.get_children().back()
	riser.set_physics_process(false)
	riser.rotation.y = PI
	for t in [0.05, 0.5, 0.9, 1.25, 1.6]:
		riser.anim.play("arise")
		riser.anim.seek(t, true)
		riser.anim.pause()
		await frames(6)
		capture(root.get_texture().get_image(), "rise_%.2f" % t)
	print("BATCH29_VISUAL_DONE")
	quit(0)
