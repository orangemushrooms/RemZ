# Boss songs (music.gd, waves.gd): one of the four at random for every boss fight, never the same
# twice in a row, handed over to another one when a fight outlasts its song, and back to the combat
# loop when the boss falls / to the pause track when the wave is over.
# Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=boss_music --smoke-test --no-intro --no-foliage
extends SceneTree

var checks := 0
var failures := 0
var began := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_dt: float) -> bool:
	if Time.get_ticks_msec() - began > 240000:
		push_error("BOSS_MUSIC_TIMEOUT")
		quit(1)
	return false

func check(ok: bool, text: String) -> void:
	checks += 1
	if ok: print("PASS: ", text)
	else:
		failures += 1
		push_error("FAIL: " + text)

func run() -> void:
	await _music_alone()
	await _waves_drive_the_music()
	print("BOSS_MUSIC_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _music_alone() -> void:
	var music := Music.new()
	root.add_child(music)
	await process_frame
	for name: String in Music.BOSS_TRACKS:
		var p: AudioStreamPlayer = music._players.get(name)
		check(p != null and p.stream.resource_path == "res://assets/audio/music/%s.mp3" % name and p.stream.get_length() > 100.0, "Boss song loads: " + name)
		check(p != null and not p.stream.loop, name + " does not loop (it stops dead at full volume)")
	music.play("night")
	music.fight(false)
	check(music.current == "combat", "A wave without a boss opens on the combat loop")
	music.fight(true)
	var first := music.current
	check(Music.is_boss(first), "A boss fight switches to a boss song")
	music.fight(true)
	check(music.current == first, "The running fight keeps its song")
	music.fight(false)
	check(music.current == "combat", "After the boss fight the combat loop comes back")
	music.fight(true)
	check(Music.is_boss(music.current) and music.current != first, "The next fight picks another song")
	var picked := {}
	var repeats := 0
	var last := music.current
	for i in 200:
		var next := music.boss_track()
		if next == last: repeats += 1
		picked[next] = true
		last = next
	check(repeats == 0, "Never the same boss song twice in a row (200 picks)")
	check(picked.size() == Music.BOSS_TRACKS.size(), "All four boss songs come up (%d of 4)" % picked.size())
	# A fight that outlasts its song moves on to another boss song instead of restarting the same one.
	music.play("combat")
	music.fight(true)
	var ending := music.current
	var song: AudioStreamPlayer = music._players[ending]
	song.play(song.stream.get_length() - 1.0)
	music._process(0.016)
	check(Music.is_boss(music.current) and music.current != ending, "A song running out hands over to another boss song (%s -> %s)" % [ending, music.current])
	check(music._target[ending] == 0.0 and music._target[music.current] > 0.0, "The old song fades out while the new one fades in")
	music.play("gameover")
	check(not music.in_fight(), "Game over is not a fight")
	music.queue_free()
	await process_frame

func _waves_drive_the_music() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	var waves: Waves = game.waves
	var music: Music = game.music
	waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	waves.start(1)
	check(not waves.boss_fight and music.current == "combat", "Wave 1 opens on the combat loop")
	waves.queue.clear()
	check(game.spawn_zombie("shambler", Vector2(30, 30), 1.0), "An ordinary zombie keeps the wave alive")
	var shambler: Zombie = game.zombies_root.get_child(game.zombies_root.get_child_count() - 1)
	shambler.set_physics_process(false)
	check(game.spawn_zombie("titan", Vector2(10, 126), 1.0, "east"), "A titan comes onto the field")
	var titan: Zombie = game.zombies_root.get_child(game.zombies_root.get_child_count() - 1)
	titan.set_physics_process(false)
	await process_frame
	waves._process(0.3)
	check(waves.boss_fight and Music.is_boss(music.current), "The titan starts a boss song (%s)" % music.current)
	var fight_song := music.current
	waves._process(0.3)
	check(music.current == fight_song, "The song stays while the titan lives")
	titan.die(Vector3.ZERO)
	await process_frame
	waves._process(0.3)
	check(not waves.boss_fight and music.current == "combat" and waves.phase == "spawning", "When the titan falls the wave goes on with the combat loop")
	# a titan still waiting in the queue already counts: its song must not flicker on and off
	waves.queue.append({"type": "titan", "lane": "east", "point": Vector2(10, 126)})
	waves.spawn_t = 99.0
	waves._process(0.3)
	check(waves.boss_fight and Music.is_boss(music.current) and music.current != fight_song, "A queued titan is a boss fight too, with a new song")
	waves.queue.clear()
	shambler.die(Vector3.ZERO)
	await process_frame
	waves._process(0.3)
	check(waves.phase == "idle" and not waves.boss_fight and music.current in ["night", "morning"], "The cleared wave hands over to the pause track (%s)" % music.current)
	# every fifth wave is a boss wave from its first second to its last zombie
	waves.start(5)
	check(waves.boss_wave and waves.boss_fight and Music.is_boss(music.current), "Wave 5 opens on a boss song (%s)" % music.current)
	var boss_song := music.current
	waves.queue = waves.queue.filter(func(entry: Dictionary): return not Waves._boss_kind(entry["type"]))
	waves.spawn_t = 99.0
	waves._process(0.3)
	check(waves.boss_fight and music.current == boss_song, "The boss wave keeps its song with no titan in sight")
	waves._complete_wave()
	check(not waves.boss_fight and music.current in ["night", "morning"], "After the boss wave the pause track returns (%s)" % music.current)
	game.queue_free()
	await process_frame
