extends SceneTree
const Impacts = preload("res://scripts/bullet_impacts.gd")
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, title: String) -> void:
	print("PASS: " if ok else "FAIL: ", title)
	if not ok: failures += 1
func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	var wall := StaticBody3D.new()
	scene.add_child(wall)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4, 4, 0.2)
	shape.shape = box
	wall.add_child(shape)
	await physics_frame
	await physics_frame
	Impacts.hit(scene, {"collider": wall, "position": Vector3(0, 0, 0.1), "normal": Vector3.BACK})
	var manager = scene.get_node_or_null("BulletImpacts")
	check(manager != null, "Physics impact creates decal manager")
	if manager:
		var mark: Decal = manager.marks[0]
		check(mark.get_parent() == wall, "Mark attaches to struck surface")
		check(mark.global_basis.y.dot(Vector3.BACK) > 0.999, "Projection aligned with wall normal")
		check(mark.texture_albedo != null, "Crater texture assigned")
		var before := mark.global_position
		wall.position.x += 1
		check(mark.global_position.is_equal_approx(before + Vector3.RIGHT), "Mark follows moving surface")
		for i in 210: manager.place(wall, Vector3.ZERO, Vector3.UP)
		await process_frame
		check(manager.marks.size() == Impacts.LIMIT, "Automatic fire has bounded decal count")
		check(wall.get_child_count() == Impacts.LIMIT + 1, "Replaced decals removed from scene")
		mark = manager.marks.back()
		check(mark.global_basis.y.dot(Vector3.UP) > 0.999, "Ground impacts point outward")
	var actor := CharacterBody3D.new()
	scene.add_child(actor)
	var count: int = manager.marks.size()
	Impacts.hit(scene, {"collider": actor, "position": Vector3.ZERO, "normal": Vector3.UP})
	check(manager.marks.size() == count, "No bullet holes on characters")
	print("BULLET_IMPACTS_DONE failures=%d" % failures)
	quit(1 if failures else 0)

