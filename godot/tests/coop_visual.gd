extends SceneTree

var game: Node3D
var net: Node
var started_at := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_at > 150000: quit(1)
	return false

func capture(file: String) -> void:
	for i in 8: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/multiplayer/" + file))

func run() -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1600, 900)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	net = root.get_node("NetSession")
	net.host("Michael", 24689)
	net.set_process(false)
	for i in 3:
		net.roster[i+2] = ["Luca", "Sarah", "Nico"][i]
		net.ready_peers[i+2] = true
		net.world.add_player(i+2)
	game.hud.show_tab("multiplayer")
	net.changed.emit()
	await capture("lobby-1600.png")
	root.size = Vector2i(1280, 720)
	await capture("lobby-1280.png")
	root.size = Vector2i(1600, 900)
	net._applying = true
	game._on_start(false)
	net._applying = false
	net.phase = "running"
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.achievements.hide()
	game.day_night.clock_seconds = 10.0 * 3600.0
	game.day_night.advance(1.0)
	game.day_night.set_process(false)
	game.player.global_position = Map.ground_pos(-5, -8)
	game.player.rotation.y = 0.0
	game.player.pitch = 0.0
	for i in 3:
		var actor: Player = net.world.actor(i+2)
		actor.global_position = Map.ground_pos(-7+i*2, -13)
		actor.rotation.y = PI
		net.world.avatars[i+2].set_weapon(["pistol", "ak47", "shotgun"][i])
	game.hud.message("Gemeinsam die Waldhütte verteidigen", 3)
	await create_timer(0.7).timeout
	await capture("teammates.png")
	net.world.actor(3).alive = false
	net.world.actor(3).hp = 0
	for i in 60: await process_frame
	await capture("revive-avatar.png")
	print("COOP_VISUAL_DONE 4")
	quit()
