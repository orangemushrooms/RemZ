# Validate the imported skin, not just the asset generation formulas.
extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func pose(anim: AnimationPlayer, clip: String, time: float) -> void:
	anim.play(clip, 0)
	anim.seek(time, true)
	anim.pause()
	await process_frame

func run() -> void:
	var scene := Node3D.new()
	root.add_child(scene)
	current_scene = scene
	for asset in ["zombie_earthworm", "zombie_earthworm_ancient"]:
		var model: Node3D = load("res://assets/models/%s.glb" % asset).instantiate()
		scene.add_child(model)
		var rig: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
		var anim := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		var connected := rig.get_bone_count() == 22
		for bone in range(1, rig.get_bone_count()): connected = connected and rig.get_bone_parent(bone) == bone - 1
		check(connected, asset + " has one connected 22-bone chain")
		var weights_ok := true
		var geometry_ok := true
		var maps_ok := true
		var triangles := 0
		var rigid_vertices := 0
		var head := rig.find_bone("head_maw_21")
		if head < 0:
			check(false, asset + " missing the expected rigid maw bone")
			model.queue_free()
			await process_frame
			continue
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for surface in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
				var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
				var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				triangles += indices.size() / 3
				var influences := bones.size() / vertices.size()
				for vertex in vertices.size():
					geometry_ok = geometry_ok and vertices[vertex].is_finite() and normals[vertex].is_finite() and normals[vertex].length() > 0.8 and uv[vertex].is_finite()
					var total := 0.0
					for influence in influences:
						var index := vertex * influences + influence
						var weight := weights[index]
						weights_ok = weights_ok and is_finite(weight) and weight >= 0 and weight <= 1
						total += weight
						var bind := bones[index]
						var bone := mesh.skin.get_bind_bone(bind)
						if bone < 0: bone = rig.find_bone(mesh.skin.get_bind_name(bind))
						weights_ok = weights_ok and bone >= 0 and bone < rig.get_bone_count()
						if bone == head and weight > 0.999: rigid_vertices += 1
					weights_ok = weights_ok and absf(total - 1) < 0.0001
				var material := mesh.get_active_material(surface) as StandardMaterial3D
				maps_ok = maps_ok and material != null and material.albedo_texture != null and material.normal_texture != null
				if material and material.albedo_texture and material.normal_texture:
					maps_ok = maps_ok and material.albedo_texture.get_width() == 4096 and material.normal_texture.get_width() == 4096 and material.metallic == 0
					print("MESH_TEXTURES ", asset, ": ", material.albedo_texture.resource_path, " | ", material.normal_texture.resource_path, " | ", material.roughness_texture.resource_path if material.roughness_texture else "none")
		check(weights_ok, asset + " every skin weight is finite, normalized and bound")
		check(geometry_ok and triangles >= 50000, asset + " valid UVs/normals and detailed mesh (%d triangles)" % triangles)
		check(maps_ok, asset + " retains imported 4K colour/normal maps and non-metal skin")
		check(rigid_vertices > 1000, asset + " maw and teeth have a rigid head attachment")
		var maximum_length_error := 0.0
		var finite := true
		for clip in ["walk", "burrow", "emerge", "attack", "recovery", "dive", "death"]:
			check(anim.has_animation(clip), asset + " imports " + clip)
			if not anim.has_animation(clip): continue
			for fraction in [0.0, 0.25, 0.5, 0.75, 1.0]:
				await pose(anim, clip, anim.get_animation(clip).length * fraction)
				for bone in rig.get_bone_count():
					var actual := rig.get_bone_global_pose(bone)
					finite = finite and actual.is_finite() and absf(actual.basis.determinant() - 1.0) < 0.0001
					var parent := rig.get_bone_parent(bone)
					if parent < 0: continue
					var rest_distance := rig.get_bone_global_rest(bone).origin.distance_to(rig.get_bone_global_rest(parent).origin)
					var pose_distance := actual.origin.distance_to(rig.get_bone_global_pose(parent).origin)
					maximum_length_error = maxf(maximum_length_error, absf(rest_distance - pose_distance))
		check(finite and maximum_length_error < 0.00001, asset + " all seven clips preserve bone lengths and avoid singular poses")
		await pose(anim, "attack", 0)
		var upright := rig.get_bone_global_pose(head)
		await pose(anim, "attack", 2.6)
		var impact := rig.get_bone_global_pose(head)
		check(upright.origin.y - impact.origin.y > 0.45 and impact.origin.z - upright.origin.z > 0.4, asset + " strike moves the head down and forwards")
		if anim.has_animation("recovery"):
			await pose(anim, "recovery", 0)
			var recovery := rig.get_bone_global_pose(head)
			check(impact.origin.distance_to(recovery.origin) < 0.0001 and impact.basis.is_equal_approx(recovery.basis), asset + " impact and recovery meet without a pose snap")
		print("MESH_POSE ", asset, " idle=", upright.origin, " impact=", impact.origin)
		model.queue_free()
		await process_frame
	print("EARTHWORM_MESH_QUALITY_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
