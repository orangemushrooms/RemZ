extends SceneTree

class ListeningRoom extends Node3D:
	var player: Player
	var music: Music

var failures := 0
var checks := 0
var capture: AudioEffectCapture
var room: ListeningRoom

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func sample(seconds: float, name: String) -> Dictionary:
	var frames := PackedFloat32Array()
	capture.clear_buffer()
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until:
		await process_frame
		for frame in capture.get_buffer(capture.get_frames_available()):
			frames.append((frame.x + frame.y) * 0.5)
	var peak := 0.0
	var energy := 0.0
	for value in frames:
		peak = maxf(peak, absf(value))
		energy += value * value
	var rms := sqrt(energy / maxf(frames.size(), 1))
	print("MIX ", name, " frames=", frames.size(), " peak=", peak, " rms=", rms)
	var path := "res://../artifacts/titan-horror/" + name + ".wav"
	Sfx._wav(frames, int(AudioServer.get_mix_rate())).save_to_wav(ProjectSettings.globalize_path(path))
	return {"peak": peak, "rms": rms, "frames": frames.size()}

func run() -> void:
	Engine.max_fps = 120
	root.audio_listener_enable_3d = true
	room = ListeningRoom.new()
	root.add_child(room)
	current_scene = room
	room.player = Player.new()
	room.add_child(room.player)
	room.player.set_physics_process(false)
	room.player.active = true
	AudioServer.set_bus_volume_db(0, 0)
	capture = AudioEffectCapture.new()
	capture.buffer_length = 0.5
	AudioServer.add_bus_effect(0, capture)
	var presence := TitanPresence.for_scene(room)
	presence.receive("roar", Vector3(0, 0, -25), 27, 900, 1)
	var near := await sample(7.5, "near-roar")
	check(near.frames > 200000 and near.rms > 0.003, "Engine renders an audible spatial titan voice")
	check(near.peak < 0.9, "Near roar retains peak headroom")
	presence.receive("roar", Vector3(0, 0, -160), 27, 900, 2)
	var far := await sample(7.5, "distant-roar")
	check(far.rms > 0.00005 and far.rms < near.rms * 0.5, "Far-field cry remains audible and attenuates substantially")
	for id in 3:
		presence.receive("rage", Vector3(id * 2, 0, -10), 27, 910 + id, 1)
		presence.receive("slam", Vector3(id * 2, 0, -10), 27, 910 + id, 2)
	var crowd := await sample(8.0, "three-titans")
	check(crowd.rms > 0.01 and crowd.peak < 0.9, "Three simultaneous titans and slams remain below clipping")
	check(presence._pending.is_empty() and presence.get_child_count() == 0, "Completed sounds release all audio players")
	# Opposite corners are roughly a kilometre apart: the spawn announcement must survive that distance.
	room.player._clear_tremor() # Player physics is disabled in this listening fixture.
	for variant in 4:
		presence.receive("arrival", Vector3(780, 0, -730), 27, 1003 + variant, 1)
		await process_frame
		var expected: String = Sfx.DIR + TitanPresence.SPAWN_CLIPS[variant]
		check(presence._voices.back().stream.resource_path == expected, "Shared seed selects spawn recording %d" % (variant + 1))
		var announcement := await sample(7.0, "mapwide-spawn-%d" % (variant + 1))
		check(announcement.rms > 0.005 and announcement.peak < 0.9, "Spawn recording %d stays clearly audible across the entire map without clipping" % (variant + 1))
	check(room.player._tremor == 0, "Mapwide sound does not cause distant camera shaking")
	print("TITAN_MIX_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
