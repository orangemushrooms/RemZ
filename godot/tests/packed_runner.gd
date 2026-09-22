extends Node

func _ready() -> void:
	call_deferred("run_suite")

func run_suite() -> void:
	var suite := "horde_hit_precision"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suite="): suite = arg.trim_prefix("--suite=")
	if not suite.is_valid_identifier():
		get_tree().quit(3)
		return
	print("PACKED_TEST_BEGIN ", suite)
	var script: Script = load("res://tests/%s.gd" % suite)
	if not script or not script.can_instantiate():
		get_tree().quit(3)
		return
	var tree := get_tree()
	tree.set_script(script)
	tree.call("_initialize")
	queue_free()
