extends SceneTree
# Run with a renderer: Godot's headless dummy renderer cannot read MultiMesh transforms.

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", text)

func run() -> void:
	for direction: Vector3 in [Vector3(6, 0, 0), Vector3(0, 0, 6), Vector3(4, 1.2, 5), Vector3(-3, -2, 7)]:
		var start := Vector3(8, 2, -4)
		var end := start + direction
		var beam := Perimeter.beam_transform(start, end, 0.28, 0.14)
		check((beam * Vector3(0, 0, 0.5)).is_equal_approx(start) and (beam * Vector3(0, 0, -0.5)).is_equal_approx(end), "Beam connects both endpoints: " + str(direction))
		check(is_equal_approx(beam.basis.x.length(), 0.28) and is_equal_approx(beam.basis.y.length(), 0.14), "Beam thickness stays constant after rotation")
	Map._ensure()
	var scene := Node3D.new()
	root.add_child(scene)
	var bars: Array = []
	for slot in Map.BARRICADES:
		var bar := Barricade.new()
		bar.setup(slot, null)
		bars.append(bar)
	var ring := Perimeter.new()
	scene.add_child(ring)
	ring.setup(bars)
	for section in ring.sections:
		var logs: MultiMesh = section.get_node("Logs").multimesh
		var tips: MultiMesh = section.get_node("Tips").multimesh
		var attached := logs.instance_count == tips.instance_count
		for i in logs.instance_count:
			var top := logs.get_instance_transform(i) * Vector3(0, 0.5, 0)
			var tip_base := tips.get_instance_transform(i) * Vector3(0, -0.16, 0)
			attached = attached and top.distance_to(tip_base) < 0.02
		check(attached, "Pointed tips stay attached to tilted logs: " + section.name)
		var rails: MultiMesh = section.get_node("Rails").multimesh
		var intact := true
		for i in rails.instance_count:
			var basis := rails.get_instance_transform(i).basis
			intact = intact and absf(basis.x.length() - 0.09) < 0.0001 and absf(basis.y.length() - 0.14) < 0.0001 and basis.z.length() > 0.5
		check(intact, "All wall rails keep their intended dimensions: " + section.name)
		var posts: MultiMesh = section.get_node("Posts").multimesh
		var lintel: Transform3D = section.get_node("Lintels").multimesh.get_instance_transform(0)
		for i in posts.instance_count:
			var post := posts.get_instance_transform(i)
			var joint := post.origin + Vector3.UP * (Perimeter.POST_HEIGHT * 0.5 - 0.25)
			var local_joint := lintel.affine_inverse() * joint
			check(absf(local_joint.x) < 0.001 and absf(local_joint.y) < 0.001 and absf(local_joint.z) < 0.5, "Lintel rests on gate post %d: %s" % [i, section.name])
	for bar in bars: bar.free()
	scene.queue_free()
	await process_frame
	print("PERIMETER_BEAMS_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
