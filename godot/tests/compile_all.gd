# Loads every script under res://scripts and res://tests and fails on the first that does not compile.
# Cheap enough to run after every edit (a few seconds, no world is built):
# Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=compile_all
extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var broken: Array[String] = []
	var count := 0
	for folder in ["res://scripts", "res://tests"]:
		for file in DirAccess.get_files_at(folder):
			if not file.ends_with(".gd"):
				continue
			var path: String = folder.path_join(file)
			var script: Script = load(path)
			count += 1
			if script == null or not script.can_instantiate():
				broken.append(path)
	for path in broken:
		print("FAIL: does not compile: ", path)
	print("COMPILE_ALL scripts=%d broken=%d" % [count, broken.size()])
	quit(1 if not broken.is_empty() else 0)
