# Load only after project autoloads (especially NetSession) exist.
extends SceneTree

func _initialize() -> void:
	call_deferred("_start_director")

func _start_director() -> void:
	var script: Script = load("res://cinematics/trailer_director.gd")
	if not script or not script.can_instantiate():
		quit(1)
		return
	var director: Node = script.new()
	director.name = "TrailerDirector"
	root.add_child(director)
