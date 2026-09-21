extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	for name in Sfx.EVENTS:
		for stem in Sfx.FILES[name]:
			var stream := Sfx._file(stem)
			check(stream != null and stream.resource_path.begins_with(Sfx.DIR) and stream.get_length() > 0, "Recorded clip loads: " + stem)
			if stream: print("AUDIO_LENGTH ", stem, " ", stream.get_length())
	var first := Sfx.get_stream("quest_accept")
	check(first != Sfx.get_stream("quest_accept"), "Accept variants do not repeat immediately")
	paused = true
	Sfx.event(root, 1, "quest_complete")
	var sound: AudioStreamPlayer = Sfx._voices["quest_complete"].back()
	check(sound.playing and sound.process_mode == Node.PROCESS_MODE_ALWAYS, "Quest feedback plays while solo shop is paused")
	check(sound.pitch_scale == 1.0, "Feedback preserves the recorded pitch")
	paused = false
	var scene := Node3D.new()
	root.add_child(scene)
	NetSession.game = scene
	NetSession.enabled = true
	var before: Array = Sfx._voices["quest_complete"].duplicate()
	Sfx.event(root, 2, "quest_complete")
	check(Sfx._voices["quest_complete"] == before, "Remote player feedback does not play on host")
	NetSession._feedback(NetSession.epoch + 1, "sfx", ["weapon_pickup"])
	check(not Sfx._voices.has("weapon_pickup"), "Old session sound feedback is ignored")
	NetSession._feedback(NetSession.epoch, "sfx", ["weapon_pickup"])
	check(Sfx._voices.has("weapon_pickup"), "Authoritative feedback plays the recipient sound")
	NetSession.enabled = false
	NetSession.game = null
	# Between waves the music follows the clock, so a long round does not loop the same track.
	var music := Music.new()
	root.add_child(music)
	await process_frame
	check(music._players.has("morning") and music._players.morning.stream.resource_path.ends_with("survived_the_night.mp3"),
		"Daylight track loads under its own file name")
	check(music.intermission_track(6.0) == "morning" and music.intermission_track(11.0) == "morning",
		"Morning and daytime pauses use the daylight track")
	check(music.intermission_track(18.5) == "night" and music.intermission_track(2.0) == "night",
		"Evening and night pauses keep the night loop")
	music.queue_free()
	scene.queue_free()
	for node in root.get_children():
		if node is AudioStreamPlayer: node.queue_free()
	await process_frame
	print("AUDIO_EVENTS_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
