# A window pane that shatters when shot (weapons.gd calls shatter()); frees itself so the opening becomes passable.
class_name Breakable
extends StaticBody3D

var pane_size := Vector2(1.2, 1.0)

func setup(size: Vector2) -> void:
	pane_size = size
	collision_layer = 1
	add_to_group("breakable")
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x, size.y, 0.06)
	cs.shape = box
	add_child(cs)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x, size.y, 0.02)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.8, 0.85, 0.35)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.2
	mi.material_override = m
	add_child(mi)
	# frame
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.25, 0.14, 0.08)
	for e in [[Vector3(size.x + 0.1, 0.06, 0.08), Vector3(0, size.y / 2.0 + 0.03, 0)], [Vector3(size.x + 0.1, 0.06, 0.08), Vector3(0, -size.y / 2.0 - 0.03, 0)],
			[Vector3(0.06, size.y, 0.08), Vector3(size.x / 2.0 + 0.03, 0, 0)], [Vector3(0.06, size.y, 0.08), Vector3(-size.x / 2.0 - 0.03, 0, 0)],
			[Vector3(0.04, size.y, 0.05), Vector3.ZERO]]:
		var f := MeshInstance3D.new()
		var fb := BoxMesh.new()
		fb.size = e[0]
		f.mesh = fb
		f.material_override = fm
		f.position = e[1]
		add_child(f)

func shatter() -> void:
	if not is_in_group("breakable"):
		return
	remove_from_group("breakable")
	var p := GPUParticles3D.new()
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(pane_size.x / 2.0, pane_size.y / 2.0, 0.02)
	mat.direction = Vector3(0, 0, 1)
	mat.spread = 60.0
	mat.initial_velocity_min = 1.0
	mat.initial_velocity_max = 3.5
	mat.gravity = Vector3(0, -9.8, 0)
	mat.angular_velocity_min = -400.0
	mat.angular_velocity_max = 400.0
	mat.scale_min = 0.4
	mat.scale_max = 1.2
	p.process_material = mat
	var q := QuadMesh.new()
	q.size = Vector2(0.06, 0.06)
	var qm := StandardMaterial3D.new()
	qm.albedo_color = Color(0.85, 0.92, 1.0, 0.8)
	qm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	qm.metallic = 0.6
	qm.roughness = 0.1
	qm.cull_mode = BaseMaterial3D.CULL_DISABLED
	q.material = qm
	p.draw_pass_1 = q
	p.amount = 70
	p.lifetime = 1.4
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = true
	get_parent().add_child(p)
	p.global_transform = global_transform
	Sfx.play_at(get_parent(), "crash", global_position, -2.0)
	get_tree().create_timer(2.0).timeout.connect(p.queue_free)
	queue_free()
