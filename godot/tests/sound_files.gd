# The user's recordings of 25 Sep 2026 evening resolve through Sfx (mp3 before wav), never the procedural fallback.
extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var failures := 0
	for name in ["thunder", "screamer_call", "acid_splash", "helmet_ping", "acid_spit", "radio", "rain"]:
		var ok := true
		for stem in Sfx.FILES[name]:
			var stream := Sfx._file(stem)
			var kind := stream.get_class() if stream else "none"
			var expected := "AudioStreamWAV" if name in ["acid_spit", "radio", "rain"] else "AudioStreamMP3"
			var good := stream != null and kind == expected and stream.get_length() > 0.5
			if not good: ok = false
			print("%s: %s -> %s %.1f s" % ["PASS" if good else "FAIL", stem, kind, stream.get_length() if stream else 0.0])
		if not ok: failures += 1
	print("SOUND_FILES_DONE failures=%d" % failures)
	quit(1 if failures else 0)
