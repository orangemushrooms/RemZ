# Real playback and weapon lifecycle checks for the supplied September 23 SFX.
extends SceneTree

const REPORTS := {"deagle": "deagle", "flare_pistol": "flare", "mac10": "mac10", "cryo_smg": "cryo", "plasma_sniper": "plasma", "lever_rifle": "lever", "minigun": "minigun", "graviton_cannon": "graviton"}
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	var w: Weapons = game.weapons
	w.set_process(false)
	game.player.active = true
	game.player.global_position = Map.ground_pos(10, 90)
	game.player.hp = 10000
	for id in REPORTS:
		var sound: String = REPORTS[id]
		var stream := Sfx.get_stream(sound) as AudioStreamWAV
		check(stream != null and stream.resource_path == "res://assets/audio/sfx/weapons/%s.wav" % sound, id + " loads its imported recording")
		if not stream: continue
		check(stream.mix_rate == 44100 and stream.get_length() > 0.5, id + " keeps the supplied recording and its tail")
		w.unlock(id)
		w.set_weapon(id)
		var state := w.cur()
		state.ammo = int(state.def.mag)
		state.cooldown = 0.0
		state.reloading = 0.0
		state.heat = 0.0
		state.vent = false
		w.try_fire()
		if id != "minigun":
			var voices: Array = Sfx._voices.get(sound, [])
			check(not voices.is_empty() and voices.back().stream == stream and voices.back().playing, id + " actually plays its new report")
		else:
			check(w.has_node("MinigunFire") and w.get_node("MinigunFire").voice.playing, "Minigun starts the sustained recording on the first shot")
	check(Sfx.get_stream("graviton") != Sfx.get_stream("graviton_impact"), "Graviton impact does not replay its muzzle recording")
	check(not w.get_node("MinigunFire").voice.playing, "Switching to the graviton stops the old minigun voice")
	w.set_weapon("minigun")
	w.cur().cooldown = 0.0
	w.try_fire()
	var sustained = w.get_node("MinigunFire")
	var voice = sustained.voice
	check(voice.stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and voice.stream.get_length() > 7.5, "Minigun loops the long supplied recording")
	check((Sfx.get_stream("minigun") as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED, "Looping does not mutate the shared source resource")
	await create_timer(0.08).timeout
	var cursor: float = voice.get_playback_position()
	for shot in 20: Sfx.play(w, "minigun", -9)
	check(sustained.voice == voice and voice.playing and voice.get_playback_position() >= cursor - 0.002, "Repeated shots reuse one voice without restarting its playback")
	check(not Sfx._voices.has("minigun"), "Long minigun reports never enter the overlapping one-shot pool")
	Input.action_release("fire")
	w._handle_weapon_input(0.016)
	sustained._process(0.05)
	check(not voice.playing, "Releasing the trigger fades the shot recording out")
	Sfx.play(w, "minigun", -9)
	w.cur().ammo = 10
	w.cur().reserve = 200
	w.reload()
	sustained._process(0.05)
	check(not voice.playing, "Reloading stops the firing recording")
	Sfx.play(w, "minigun", -9)
	game.player.active = false
	w._process(0.016)
	check(not voice.playing, "An inactive shooter cannot leave firing audio running")
	var teammate := Node3D.new()
	game.add_child(teammate)
	Sfx.play_at(teammate, "minigun", Vector3(3, 2, 1), -9)
	var remote = teammate.get_node("MinigunFire3D")
	check(remote.voice is AudioStreamPlayer3D and remote.voice.playing and remote.voice.global_position.is_equal_approx(Vector3(3, 2, 1)), "Coop uses a positional firing loop per teammate")
	Sfx.play(w, "minigun", -9)
	Sfx.stop_fire_loop(w)
	check(remote.voice.playing, "Stopping the local gun does not stop a teammate's loop")
	remote._process(0.3)
	check(not remote.voice.playing, "Missing further coop shot events end the loop automatically")
	teammate.queue_free()
	print("WEAPON_RECORDINGS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
