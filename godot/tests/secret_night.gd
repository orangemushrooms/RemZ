extends SceneTree

var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func run() -> void:
	if "--visual" in OS.get_cmdline_user_args():
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1600, 900)
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.secret_night.set_process(false)
	game.waves.wave = 4
	game.waves.completed = 4
	var night: SecretNight = game.secret_night
	var clock_before: float = game.day_night.clock_seconds
	game.player.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y)
	game.waves.start(5)
	check(night.song.stream.resource_path == SecretNight.SONG and night.song.stream.loop, "User Goa track is loaded and loops")
	check(night.song.volume_db < -25 and night.song_filter.cutoff_hz < 2000, "At the camp the first note is distant and muffled")
	check(night.song.bus == night.song_bus and AudioServer.get_bus_index(night.song_bus) >= 0, "Distance filter is routed through a private music bus")
	check(night.active and game.waves.phase == "secret_night", "Wave 5 enters the mandatory sidequest")
	check(game.waves.queue.is_empty() and game.waves.wave == 4, "Combat and wave event are deferred")
	game.waves.start(6)
	check(game.waves.wave == 4 and not game.waves.skip_current_wave(), "Direct start and cheat cannot bypass the quest")
	game.day_night.advance(120)
	check(is_equal_approx(game.day_night.clock_seconds, 1800), "Time stays at night")
	check(not night.interact(game.player), "Remote interactions are rejected")
	game.player.global_position = Map.ground_pos(SecretNight.DANCE.x, SecretNight.DANCE.y)
	night._process(0.1)
	check(night.step == 1, "Reaching the party reveals the totems")
	if "--visual" in OS.get_cmdline_user_args():
		# the dance floor from the south (the dancers must stand in front of the stage, not inside it)
		game.player.global_position = Map.ground_pos(SecretNight.DANCE.x, SecretNight.DANCE.y + 11) + Vector3.UP * 0.5
		game.player.camera.look_at(Map.ground_pos(SecretNight.SITE.x, SecretNight.SITE.y) + Vector3.UP * 1.5)
		await capture(game, "floor")
		game.player.global_position = Map.ground_pos(SecretNight.DANCE.x + 12, SecretNight.DANCE.y + 3) + Vector3.UP * 0.5
		game.player.camera.look_at(Map.ground_pos(SecretNight.SITE.x, SecretNight.SITE.y) + Vector3.UP * 1.5)
		await capture(game, "side")
	night._update_song_distance(2.0)
	check(night.song.volume_db > -10 and night.song_filter.cutoff_hz > 15000, "Dance floor reveals the loud, clear track")
	game.player.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y)
	night._update_song_distance(2.0)
	check(night.song.volume_db < -25 and night.song_filter.cutoff_hz < 2100, "Walking away makes the same track distant again")
	game.player.global_position = Map.ground_pos(SecretNight.TOTEMS[2].x, SecretNight.TOTEMS[2].y)
	check(not night.interact(game.player), "Wrong totem cannot advance progression")
	for point: Vector2 in SecretNight.TOTEMS:
		game.player.global_position = Map.ground_pos(point.x, point.y)
		check(night.interact(game.player), "Nearby correct totem activates")
	check(night.step == SecretNight.HARVEST and night.tuned == 3, "Three totems send the team mushroom picking")
	check(night.glow_props.size() == 3 and night.glow_props[0].visible, "The glowing mushrooms stand ready around the floor")
	for i in 3:
		var spot: Vector2 = SecretNight.GLOW_SPOTS[i]
		game.player.global_position = Map.ground_pos(spot.x, spot.y)
		check(night.interact(game.player), "Glowing mushroom %d can be picked" % (i + 1))
		night._update_ending(0.0)
		check(not night.glow_props[i].visible, "Picked mushroom %d disappears" % (i + 1))
	check(night.step == SecretNight.TRIP and night.harvested() == 3, "Three mushrooms unlock the DJ's mushroom at the bar")
	var target: Vector2 = night.target()
	game.player.global_position = Map.ground_pos(target.x, target.y)
	check(night.interact(game.player) and night.step == SecretNight.COLOUR_RUN and game.hud.tripping(), "The DJ's mushroom starts the colour run and the hallucination")
	night._process(0.1)
	check(night.run_target == SecretNight.RUN_SEQUENCE[0], "The first colour is called")
	game.player.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y)
	night._process(SecretNight.RUN_SECONDS + 0.5)
	check(night.run_round == 0 and night.run_target == -1, "Too slow starts the colour run over")
	for round in SecretNight.RUN_SEQUENCE.size():
		night._process(0.1)
		var totem: Vector2 = SecretNight.TOTEMS[night.run_target]
		game.player.global_position = Map.ground_pos(totem.x, totem.y)
		night._process(0.1)
	check(night.step == SecretNight.CLEAR and night.run_round == SecretNight.RUN_SEQUENCE.size(), "Four totems reached in time unlock the Clear Head")
	target = night.target()
	game.player.global_position = Map.ground_pos(target.x, target.y)
	night.interact(game.player)
	check(night.step == SecretNight.DANCE_STEP and game.hud._trip_t <= 1.5, "Clear-head drink unlocks the finale and ends the trip")
	var remote := Player.new()
	remote.remote_actor = true
	root.add_child(remote)
	remote.set_physics_process(false)
	var world = preload("res://scripts/coop_world.gd").new()
	world.game = game
	world.actors = {1: game.player, 2: remote}
	NetSession.world = world
	NetSession.enabled = true
	game.player.global_position = Map.ground_pos(SecretNight.DANCE.x, SecretNight.DANCE.y)
	remote.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y)
	check(not night._team_near(SecretNight.DANCE, 7, true), "Co-op finale waits for every living teammate")
	remote.global_position = game.player.global_position
	check(night._team_near(SecretNight.DANCE, 7, true), "Co-op finale accepts the gathered team")
	remote.alive = false
	remote.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y)
	check(night._team_near(SecretNight.DANCE, 7, true), "Downed teammate does not deadlock finale")
	NetSession.enabled = false
	NetSession.world = null
	game.player.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y)
	night._process(20)
	check(night.dance_time == 0, "Finale does not progress away from dance floor")
	game.player.global_position = Map.ground_pos(SecretNight.DANCE.x, SecretNight.DANCE.y)
	night._process(16)
	check(night.step == SecretNight.GUESTS and night.ravers_spawned and game.alive_zombies() >= 6, "The final dance wakes the ravers")
	for z in game.zombies_root.get_children():
		if z is Zombie and z.alive: z.die(Vector3.FORWARD)
	night._process(0.1)
	check(night.step == SecretNight.CLOSING and night.closing_time == 0, "Clearing the floor begins the last track instead of ending abruptly")
	game.player.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y)
	check(not night.interact(game.player), "The ending cannot be skipped at the campfire")
	game.player.global_position = Map.ground_pos(SecretNight.DANCE.x, SecretNight.DANCE.y)
	var full_volume: float = night.song.volume_db
	night._process(9)
	check(night.party_energy() > 0 and night.party_energy() < 1 and night.song.volume_db < full_volume, "Last track and lights fade together")
	check(not night.guest_meshes.is_empty() and night.guest_meshes[0].transparency > 0, "Party guests dissolve during the farewell")
	var paused_time := night.closing_time
	paused = true
	night._process(5)
	paused = false
	check(night.closing_time == paused_time, "Solo pause freezes the ending")
	var state := night.snapshot()
	night._leave_presentation()
	night.active = false
	night.apply_snapshot(state)
	check(night.active and night.step == SecretNight.CLOSING and night.closing_time == paused_time and night._announced_step == SecretNight.CLOSING, "Late join restores the current farewell without replaying the opening")
	check(is_equal_approx(night.saved_clock, clock_before), "Late join retains the original world time")
	if "--visual" in OS.get_cmdline_user_args():
		game.player.global_position = Map.ground_pos(-106, -180) + Vector3.UP * 0.5
		game.player.camera.look_at(Map.ground_pos(-108, -201) + Vector3.UP * 2)
		await capture(game, "farewell")
	night._process(SecretNight.CLOSING_SECONDS - night.closing_time)
	check(night.step == SecretNight.ECHO and night.active and night.echo_prop.visible, "Final track reveals the physical quest relic")
	check(not night.song.playing and not night.rain_sound.playing and not night.rain.emitting, "Music and rain actually end before the return journey")
	check(night.lights[0].light_energy == 0 and not night.beams[0].visible and not night.guest_meshes[0].visible, "Disco lights and guests are gone")
	check(float(night.haze_material.get_shader_parameter("strength")) == 0, "Mushroom haze clears with the farewell")
	game.player.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y)
	check(not night.interact(game.player) and not night.echo_collected, "Returning without the echo cannot complete the quest")
	var echo_state := night.snapshot()
	night._leave_presentation()
	night.active = false
	night.apply_snapshot(echo_state)
	check(night.echo_prop.visible and not night.echo_collected and not night.song.playing, "Late join sees the uncollected relic without restarting the party")
	if "--visual" in OS.get_cmdline_user_args():
		game.player.global_position = Map.ground_pos(-106, -191)
		game.player.camera.look_at(Map.ground_pos(SecretNight.ECHO_POINT.x, SecretNight.ECHO_POINT.y) + Vector3.UP)
		await capture(game, "echo")
	var collection_score: int = game.player.score
	game.player.global_position = Map.ground_pos(SecretNight.ECHO_POINT.x, SecretNight.ECHO_POINT.y)
	check(night.interact(game.player) and night.echo_collected and night.step == SecretNight.RETURN, "E collects the nearby echo for the whole team")
	check(not night.echo_prop.visible and game.player.score == collection_score, "Pickup removes the relic without granting the completion reward early")
	check(not night.interact(game.player), "Relic cannot be collected twice")
	var return_state := night.snapshot()
	night._leave_presentation()
	night.active = false
	night.apply_snapshot(return_state)
	check(night.echo_collected and not night.echo_offered and not night.echo_prop.visible and not night.song.playing, "Team possession survives reconnect without spawning another relic")
	game.player.global_position = Map.ground_pos(Map.FIRE.x, Map.FIRE.y)
	remote.alive = true
	remote.hud = game.hud
	remote.global_position = Map.ground_pos(SecretNight.DANCE.x, SecretNight.DANCE.y)
	NetSession.world = world
	NetSession.enabled = true
	check(not night.interact(game.player) and night.step == SecretNight.RETURN, "A player left at the party blocks premature wave release")
	remote.global_position = game.player.global_position
	check(night.interact(game.player) and night.step == SecretNight.WAKING, "Gathered team begins a shared awakening")
	check(night.echo_offered and night.echo_prop.visible and night.echo_prop.position.distance_to(Map.ground_pos(Map.FIRE.x, Map.FIRE.y)) < 2, "Offering puts the echo into the campfire")
	check(not night.interact(game.player), "Repeated interaction cannot skip awakening")
	night._process(4)
	check(night.active and game.waves.phase == "secret_night", "Wave stays locked throughout awakening")
	check(night.echo_prop.scale.x < 1 and night.echo_meshes[0].transparency > 0, "Offered echo visibly burns away")
	var waking_state := night.snapshot()
	night.apply_snapshot(waking_state)
	check(night.step == SecretNight.WAKING and night.waking_time == 4, "Awakening progress survives snapshots")
	remote.global_position = Map.ground_pos(SecretNight.DANCE.x, SecretNight.DANCE.y)
	night._process(4)
	check(night.waking_time == 4, "Awakening waits if a teammate leaves the camp")
	remote.global_position = game.player.global_position
	var score_before: int = game.player.score
	var remote_score_before: int = remote.score
	night._process(4)
	check(night.completed and not night.active and game.waves.timer == SecretNight.PREPARATION_SECONDS and SecretNight.PREPARATION_SECONDS >= 30.0, "Completion releases thirty seconds to prepare")
	check(game.player.score == score_before + SecretNight.REWARD and remote.score == remote_score_before + SecretNight.REWARD, "Every teammate receives the reward exactly once")
	night._complete()
	night.apply_snapshot(night.snapshot())
	check(game.player.score == score_before + SecretNight.REWARD and remote.score == remote_score_before + SecretNight.REWARD, "Repeated completion or snapshot cannot duplicate rewards")
	NetSession.enabled = false
	NetSession.world = null
	remote.queue_free()
	check(is_equal_approx(game.day_night.clock_seconds, SecretNight.MORNING_SECONDS), "The quest ends at the next morning")
	check(night._morning_left > 0 and game.settings.env.volumetric_fog_density > night.saved_fog, "The morning haze lets the sun shaft through the trees")
	check(night.haze.visible and float(night.haze_material.get_shader_parameter("awakening")) > 0.5, "A warm wake-up flash fades in")
	night._update_morning(SecretNight.WAKE_SECONDS + 0.1)
	check(not night.haze.visible, "The wake-up flash fades out again")
	night._update_morning(SecretNight.MORNING_GLOW_SECONDS)
	check(is_equal_approx(game.settings.env.volumetric_fog_density, night.saved_fog), "The morning haze clears")
	check(not night.scenery.visible and not night.haze.visible and not night.song.playing, "No party effects remain after completion")
	check(not night.interact(game.player), "Completion cannot be replayed")
	game.waves.start(5)
	check(game.waves.wave == 5 and game.waves.phase == "spawning" and not game.waves.queue.is_empty(), "Original fifth wave resumes once")
	print("SECRET_NIGHT_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func capture(game: Node, label: String) -> void:
	game.secret_night._process(0.0)
	game.hud.message("", 0.0)
	game.achievements.hide()
	await create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/secret-night-%s.png" % label))
	game.achievements.show()
