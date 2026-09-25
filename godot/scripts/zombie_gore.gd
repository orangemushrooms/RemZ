# Dismemberment for the Meshy zombie rigs (25 Sep 2026). At load every skinned mesh of a model is cut into
# a body mesh and one mesh per part (head, arms, legs) by the dominant bone weight of its triangles - once
# per model, cached. Every zombie then carries the body mesh on its original MeshInstance3D plus one
# skinned instance per part on the same skeleton, so a severed part simply disappears (no pinched
# vertices), a dark stump follows the joint through a BoneAttachment3D, and the part itself flies off as
# a RigidBody3D chunk showing the part's rest-pose geometry, tumbling, bleeding and settling on the
# ground. Replicas run the same code from the host's mask.
class_name ZombieGore
extends RefCounted

const PARTS := {
	"head": {"bones": ["Head", "head_end", "headfront"], "root": "Head", "stump": 0.055},
	"left_arm": {"bones": ["LeftArm", "LeftForeArm", "LeftHand"], "root": "LeftArm", "stump": 0.042},
	"right_arm": {"bones": ["RightArm", "RightForeArm", "RightHand"], "root": "RightArm", "stump": 0.042},
	"left_leg": {"bones": ["LeftUpLeg", "LeftLeg", "LeftFoot", "LeftToeBase"], "root": "LeftUpLeg", "stump": 0.065},
	"right_leg": {"bones": ["RightUpLeg", "RightLeg", "RightFoot", "RightToeBase"], "root": "RightUpLeg", "stump": 0.065},
}
const CHUNK_SECONDS := 14.0
const CHUNK_FREEZE := 6.0
static var _split_cache := {}     # model_path:mesh_path -> {"body": ArrayMesh, "parts": {part: ArrayMesh}, "surfaces": {part: [orig surface]}, "body_surfaces": [orig]}
static var _stump_material: StandardMaterial3D

static func part_of_bone(bone_name: String) -> String:
	for part in PARTS:
		if bone_name in PARTS[part].bones: return part
	return ""

static func stump_material() -> StandardMaterial3D:
	if _stump_material == null:
		_stump_material = StandardMaterial3D.new()
		_stump_material.albedo_color = Color(0.2, 0.015, 0.015)
		_stump_material.roughness = 0.92
		_stump_material.metallic = 0.0
	return _stump_material

# ---- the cut, once per model
static func prepare(model: Node3D, model_path: String) -> void:
	for mesh_node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		if not mesh.skin or mesh.skeleton.is_empty() or not mesh.mesh: continue
		var rig := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
		if not rig: continue
		var key := model_path + ":" + str(model.get_path_to(mesh))
		if _split_cache.has(key): continue
		_split_cache[key] = _split(mesh.mesh, mesh.skin, rig)

static func _split(source: Mesh, skin: Skin, rig: Skeleton3D) -> Dictionary:
	var result := {"body": ArrayMesh.new(), "parts": {}, "surfaces": {}, "body_surfaces": []}
	# bind index -> part name ("" = body)
	var bind_part := PackedStringArray()
	for bind in skin.get_bind_count():
		var bone := skin.get_bind_bone(bind)
		if bone < 0: bone = rig.find_bone(skin.get_bind_name(bind))
		bind_part.append(part_of_bone(rig.get_bone_name(bone)) if bone >= 0 else "")
	for surface in source.get_surface_count():
		var arrays := source.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var material := source.surface_get_material(surface)
		if vertices.is_empty() or bones.is_empty():
			_add_surface(result.body, arrays, material)
			result.body_surfaces.append(surface)
			continue
		var influences := bones.size() / vertices.size()
		# dominant part per vertex
		var vertex_part := PackedStringArray()
		vertex_part.resize(vertices.size())
		for v in vertices.size():
			var best := -1.0
			var part := ""
			for i in influences:
				var w := weights[v * influences + i]
				if w > best:
					best = w
					part = bind_part[bones[v * influences + i]] if bones[v * influences + i] < bind_part.size() else ""
			vertex_part[v] = part
		# triangles: a part owns a triangle when two of its corners belong to it
		var groups := {"": PackedInt32Array()}
		var use_index := not indices.is_empty()
		var count := indices.size() if use_index else vertices.size()
		for t in range(0, count - 2, 3):
			var corners := [indices[t] if use_index else t, indices[t + 1] if use_index else t + 1, indices[t + 2] if use_index else t + 2]
			var tally := {}
			for c in corners: tally[vertex_part[c]] = int(tally.get(vertex_part[c], 0)) + 1
			var owner := ""
			for part in tally:
				if part != "" and int(tally[part]) >= 2: owner = part
			if not groups.has(owner): groups[owner] = PackedInt32Array()
			for c in corners: groups[owner].append(c)
		for owner in groups:
			var sub := _subset(arrays, groups[owner])
			if sub.is_empty(): continue
			if owner == "":
				_add_surface(result.body, sub, material)
				result.body_surfaces.append(surface)
			else:
				if not result.parts.has(owner):
					result.parts[owner] = ArrayMesh.new()
					result.surfaces[owner] = []
				_add_surface(result.parts[owner], sub, material)
				result.surfaces[owner].append(surface)
	return result

static func _add_surface(mesh: ArrayMesh, arrays: Array, material: Material) -> void:
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if material: mesh.surface_set_material(mesh.get_surface_count() - 1, material)

# the vertices referenced by the corner list, re-indexed, every attribute array kept
static func _subset(arrays: Array, corners: PackedInt32Array) -> Array:
	if corners.is_empty(): return []
	var remap := {}
	var order := PackedInt32Array()
	var new_index := PackedInt32Array()
	for c in corners:
		if not remap.has(c):
			remap[c] = order.size()
			order.append(c)
		new_index.append(remap[c])
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var vertex_count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	for a in Mesh.ARRAY_MAX:
		if a == Mesh.ARRAY_INDEX:
			out[a] = new_index
			continue
		var data = arrays[a]
		if data == null: continue
		var stride: int = 1
		match a:
			Mesh.ARRAY_TANGENT: stride = 4
			Mesh.ARRAY_BONES, Mesh.ARRAY_WEIGHTS: stride = data.size() / maxi(vertex_count, 1)
		var picked = data.duplicate()
		picked.resize(order.size() * stride)
		for i in order.size():
			for s in stride:
				picked[i * stride + s] = data[order[i] * stride + s]
		out[a] = picked
	return out

# ---- per zombie: swap the body mesh in, add one skinned instance per part
# Returns {part: MeshInstance3D}; the original instance keeps its node path (the hit shapes are keyed on it).
static func attach(model: Node3D, model_path: String, materials_by_surface: Dictionary) -> Dictionary:
	var parts := {}
	for mesh_node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		var key := model_path + ":" + str(model.get_path_to(mesh))
		if not _split_cache.has(key): continue
		var cut: Dictionary = _split_cache[key]
		var overrides: Array = materials_by_surface.get(mesh, [])
		for part in cut.parts:
			var instance := MeshInstance3D.new()
			instance.name = "Part_" + part
			instance.mesh = cut.parts[part]
			instance.skin = mesh.skin
			instance.lod_bias = mesh.lod_bias
			instance.cast_shadow = mesh.cast_shadow
			mesh.get_parent().add_child(instance)
			instance.transform = mesh.transform
			instance.skeleton = instance.get_path_to(mesh.get_node(mesh.skeleton))
			for i in (cut.surfaces[part] as Array).size():
				var original: int = cut.surfaces[part][i]
				if original < overrides.size() and overrides[original]: instance.set_surface_override_material(i, overrides[original])
			parts[part] = instance
		# the body last: the override materials move onto the body surfaces
		var body_overrides: Array = []
		for original in cut.body_surfaces:
			body_overrides.append(overrides[original] if original < overrides.size() else null)
		mesh.mesh = cut.body
		for i in body_overrides.size():
			mesh.set_surface_override_material(i, body_overrides[i])
	return parts

# ---- severing
static func sever(zombie: Node3D, rig: Skeleton3D, part_instance: MeshInstance3D, part: String, direction: Vector3, fly := true) -> void:
	var spec: Dictionary = PARTS[part]
	var root := rig.find_bone(spec.root)
	part_instance.visible = false
	var joint_pose := rig.get_bone_global_pose(root) if root >= 0 else Transform3D.IDENTITY
	var joint_world: Vector3 = rig.global_transform * joint_pose.origin
	var world_scale: float = rig.global_transform.basis.get_scale().y
	# the stump: a dark cap that stays on the joint
	if root >= 0:
		var attachment := BoneAttachment3D.new()
		attachment.name = "Stump_" + part
		attachment.bone_name = rig.get_bone_name(root)
		rig.add_child(attachment)
		var cap := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = float(spec.stump) / maxf(world_scale, 0.0001)
		sphere.height = sphere.radius * 2.0
		sphere.radial_segments = 12
		sphere.rings = 6
		cap.mesh = sphere
		cap.material_override = stump_material()
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		cap.scale = Vector3(1.0, 0.7, 1.0)   # a torn disc inside the joint, not a ball on it
		attachment.add_child(cap)
	# the wound spurts for a couple of seconds: the weapons' pooled bursts at the joint
	var scene := zombie.get_tree().current_scene
	if "weapons" in scene and scene.weapons and scene.weapons.has_method("_blood"):
		for i in 4:
			var spurt := zombie.get_tree().create_timer(0.25 + i * 0.45)
			spurt.timeout.connect(func():
				if not is_instance_valid(zombie) or not is_instance_valid(rig): return
				var at: Vector3 = rig.global_transform * rig.get_bone_global_pose(root).origin if root >= 0 else zombie.global_position
				scene.weapons._blood(at, Vector3(randf_range(-0.4, 0.4), 1.0, randf_range(-0.4, 0.4)).normalized()))
	if not fly or root < 0: return
	# the chunk: the part's rest-pose geometry on a tumbling body, joint at the body origin
	var chunk := RigidBody3D.new()
	chunk.name = "Chunk_" + part
	chunk.collision_layer = 0
	chunk.collision_mask = 1 | 8
	chunk.mass = 4.0 if part.ends_with("leg") else 2.0
	chunk.linear_damp = 0.4
	chunk.angular_damp = 1.5
	chunk.can_sleep = true
	var length_units := 0.0
	for bone_name in spec.bones:
		var b := rig.find_bone(bone_name)
		if b >= 0 and b != root: length_units = maxf(length_units, rig.get_bone_global_rest(b).origin.distance_to(rig.get_bone_global_rest(root).origin))
	var length := maxf(length_units * world_scale, 0.25)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = maxf(length * 0.16, 0.05)
	capsule.height = maxf(length, capsule.radius * 2.0 + 0.02)
	shape.shape = capsule
	shape.position = Vector3.UP * length * 0.5
	chunk.add_child(shape)
	var visual := MeshInstance3D.new()
	visual.mesh = part_instance.mesh
	for i in part_instance.mesh.get_surface_count():
		var material := part_instance.get_surface_override_material(i)
		if material: visual.set_surface_override_material(i, material)
	visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# rest pose: the part's root joint sits at get_bone_global_rest(root); shift it onto the chunk origin and
	# turn the rest limb (an arm points along +-X in the T-pose, a leg down -Y) so it lies along the capsule
	var rest_origin: Vector3 = rig.get_bone_global_rest(root).origin
	var rest_dir := Vector3.DOWN
	for bone_name in spec.bones:
		var b := rig.find_bone(bone_name)
		if b >= 0 and b != root:
			rest_dir = (rig.get_bone_global_rest(b).origin - rest_origin).normalized()
			break
	var align := Quaternion(rest_dir, Vector3.UP) if rest_dir.length() > 0.5 else Quaternion.IDENTITY
	visual.transform = Transform3D(Basis(align).scaled(Vector3.ONE * world_scale), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -rest_origin)
	chunk.add_child(visual)
	zombie.get_parent().add_child(chunk)
	chunk.global_position = joint_world
	chunk.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
	var push := (Vector3(direction.x, 0.0, direction.z).normalized() if direction.length() > 0.01 else Vector3.UP) * randf_range(2.5, 4.0) + Vector3.UP * randf_range(2.0, 3.5)
	chunk.linear_velocity = push
	chunk.angular_velocity = Vector3(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0), randf_range(-9.0, 9.0))
	var timer := zombie.get_tree().create_timer(CHUNK_FREEZE)
	timer.timeout.connect(func(): if is_instance_valid(chunk): chunk.freeze = true)
	var cleanup := zombie.get_tree().create_timer(CHUNK_SECONDS)
	cleanup.timeout.connect(func(): if is_instance_valid(chunk): chunk.queue_free())
