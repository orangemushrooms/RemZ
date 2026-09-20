extends SceneTree
func _initialize() -> void:
	var builder = load("res://scripts/corn_meshes.gd")
	for kind in ["corn_distant","corn_far","corn_a","corn_b","scarecrow","raven_body","raven_wing","owl_body","owl_wing"]:
		ResourceSaver.save(builder.make(kind), "res://assets/cornfield/%s.res" % kind)
	quit()
