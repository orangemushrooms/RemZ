# Pose sheet of the zombie rigs (windowed): one body per skin in a row on the meadow south of the plaza, every
# sheet freezes all of them in one clip at a telling moment (gait mid-stride, strike, flinch, idle, scream,
# end of the fall). Screenshots: artifacts/zombies_v3/pose_<clip>.png plus a close-up of the first three.
#   Godot.exe --path godot --script res://tests/run.gd -- --suite=zombie_anim_visual --no-intro --no-music
extends SceneTree

var game: Node
var began := Time.get_ticks_msec()
const SKINS := ["zombie_shambler", "zombie_farmer", "zombie_hiker", "zombie_grandma", "zombie_soldier", "zombie_forester",
	"zombie_runner", "zombie_jogger", "zombie_nurse", "zombie_bloater"]
const KINDS := {"zombie_runner": "runner", "zombie_jogger": "runner", "zombie_nurse": "nurse", "zombie_soldier": "soldier",
	"zombie_forester": "soldier", "zombie_bloater": "brute"}
# clip -> fraction of the clip (or "peak" for the measured strike)
const SHEETS := {"walk": 0.3, "walk2": 0.3, "run": 0.3, "attack": "peak", "attack2": "peak", "hit": 0.35, "idle": 0.5,
	"scream": 0.55, "death": 0.99, "death2": 0.99}

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 300000:
		print("ZOMBIE_ANIM_VISUAL timeout")
		quit(1)
	return false

func capture(file: String) -> void:
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	var dir := ProjectSettings.globalize_path("res://../artifacts/zombies_v3/")
	DirAccess.make_dir_recursive_absolute(dir)
	root.get_texture().get_image().save_png(dir + file + ".png")
	print("ZOMBIE_ANIM_SHOT ", file)

func look(from: Vector2, at: Vector3) -> void:
	game.player.global_position = Map.ground_pos(from.x, from.y) + Vector3(0, 0.2, 0)
	game.player.camera.look_at(at)

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1920, 1080)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	if "achievements" in game and game.achievements: game.achievements.hide()
	if "day_night" in game and game.day_night:
		game.day_night.clock_seconds = 16 * 3600 + 30 * 60
		game.day_night.advance(1)
		game.day_night.set_process(false)
	game.hud.message("", 0.0)
	var bodies: Array[Zombie] = []
	var x := -7.0
	for skin in SKINS:
		if not ResourceLoader.exists("res://assets/models/%s.glb" % skin): continue
		Zombie.force_skin = skin
		game.spawn_zombie(KINDS.get(skin, "shambler"), Vector2(x, 62), 1, "east")
		Zombie.force_skin = ""
		var z: Zombie = game.zombies_root.get_children().back()
		z.set_physics_process(false)
		z.agent.avoidance_enabled = false
		z.rotation.y = PI
		bodies.append(z)
		x += 1.7
	await create_timer(1.0).timeout
	var line := "ZOMBIE_ANIM_CLIPS"
	for z in bodies:
		line += " %s=%s" % [z.model.scene_file_path.get_file().get_basename(), z.anim.get_animation_list()]
	print(line)
	for clip in SHEETS:
		var any := false
		for z in bodies:
			if not z.anim.has_animation(clip): continue
			any = true
			z.anim.play(clip)
			var length := z.anim.get_animation(clip).length
			var at: float = float(Zombie.clip_info(z.model_path).get(clip, {}).get("peak", length * 0.5)) if str(SHEETS[clip]) == "peak" else length * float(SHEETS[clip])
			z.anim.seek(at, true)
			z.anim.pause()
		if not any: continue
		look(Vector2(1.5, 52), Map.ground_pos(1.5, 62) + Vector3.UP * 1.0)
		await capture("pose_" + clip)
		look(Vector2(1.5, 58.6), Map.ground_pos(-0.5, 62) + Vector3.UP * 1.1)
		await capture("pose_%s_close" % clip)
	# head tracking: the sixth body (forester) idles 2.5 m in front of a camera standing off to its right, once
	# with the modifier and once without, so a wrong axis shows up as a twisted head
	if bodies.size() > 5 and bodies[5]._head_look:
		var subject: Zombie = bodies[5]
		var eye := Vector2(subject.global_position.x + 1.6, subject.global_position.z - 2.4)
		if subject.anim.has_animation("idle"):
			subject.anim.play("idle")
			subject.anim.seek(1.0, true)
			subject.anim.pause()
		subject.set_physics_process(true)
		look(eye, subject.global_position + Vector3.UP * 1.55)
		await create_timer(1.0).timeout
		await capture("headlook_on")
		subject.set_physics_process(false)
		subject._head_look.active = false
		await capture("headlook_off")
		subject._head_look.active = true
	# the gait in motion: unfreeze the row and let it walk for a moment, frames 0.5 s apart
	for z in bodies:
		z.anim.play(z.clip if z.anim.has_animation(z.clip) else "walk")
		z.set_physics_process(true)
	look(Vector2(1.5, 50), Map.ground_pos(1.5, 60) + Vector3.UP * 1.0)
	for i in 3:
		await create_timer(0.5).timeout
		await capture("gait_%d" % i)
	print("ZOMBIE_ANIM_VISUAL_DONE")
	quit(0)
