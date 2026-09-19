# Delay loading SceneTree test suites until project autoloads are registered.
# godot --headless --path godot --script res://tests/run.gd -- --suite=multiplayer
extends SceneTree

func _initialize() -> void:
	call_deferred("_load_suite")

func _load_suite() -> void:
	var suite := "smoke"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suite="): suite = arg.trim_prefix("--suite=")
	if not suite.is_valid_identifier():
		quit(1)
		return
	var script: Script = load("res://tests/%s.gd" % suite)
	if not script or not script.can_instantiate():
		quit(1)
		return
	set_script(script)
	call("_initialize")
