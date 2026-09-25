# Isolates how the process ends after the EOS platform ran (autoloads only, no world):
# --suite=eos_exit_probe --probe=none|init|login|lobby|release   (prints PROBE lines, then quit())
extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var online := root.get_node("Online")
	var mode := "init"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probe="): mode = arg.trim_prefix("--probe=")
	print("PROBE mode=%s available=%s" % [mode, online.available()])
	if mode != "none" and online.available():
		var started: bool = await online._start_platform()
		print("PROBE platform=", started)
		if started and mode in ["login", "lobby", "release"]:
			var login: Dictionary = await online._login("Probe")
			print("PROBE login=", login.ok)
			if mode == "lobby":
				var created: Dictionary = await online.create_lobby("Probe", online.version_tag())
				print("PROBE lobby=", created.ok)
				online.leave()
				await create_timer(2.0, true).timeout
			if mode == "release":
				online._eos.Platform.PlatformInterface.release()
				print("PROBE released")
				print("PROBE shutdown=", online._eos.Platform.PlatformInterface.shutdown())
	print("PROBE quitting t=%d" % Time.get_ticks_msec())
	quit(0)
