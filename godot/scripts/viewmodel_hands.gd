class_name ViewmodelHands
extends Node3D

# Authored, skinned glove meshes; see assets/viewmodel/VALVE-LICENSE.txt.
const RIGHT: PackedScene = preload("res://assets/viewmodel/right_glove.fbx")
const LEFT: PackedScene = preload("res://assets/viewmodel/left_glove.fbx")
const SLEEVE: PackedScene = preload("res://assets/viewmodel/meshy_sleeve.glb")
const CLOTH_SHADER = preload("res://shaders/sleeve_cloth.gdshader")
const HAND_SCALE := 0.64
const GRIPS := {
	"pistol": Vector4(0.29, 0.78, 0.24, 0.70),
	"revolver": Vector4(0.27, 0.86, 0.22, 0.79),
	"smg": Vector4(0.30, 0.70, 0.53, 0.24),
	"ak47": Vector4(0.40, 0.49, 0.65, 0.19),
	"shotgun": Vector4(0.49, 0.56, 0.56, 0.32),
}
var support: Node3D
var trigger_grip := Vector3.ZERO
var support_grip := Vector3.ZERO
static var _glove: StandardMaterial3D
static var _fabric: StandardMaterial3D
static var _cloth: ShaderMaterial
static var _sleeve_mesh: Mesh
var _sleeves: Array[MeshInstance3D] = []
var _cloth_clock := 0.0
var _shot_age := 10.0
var _shot_strength := 0.0
var _stride := 0.0

static func weapon_bounds(holder: Node3D) -> AABB:
	var bounds := AABB()
	var first := true
	for node in holder.find_children("*", "MeshInstance3D", true, false):
		var transform := Transform3D.IDENTITY
		var current: Node3D = node
		while current != holder:
			transform = current.transform * transform
			current = current.get_parent() as Node3D
		var aabb: AABB = transform * node.get_aabb()
		bounds = aabb if first else bounds.merge(aabb)
		first = false
	return bounds

static func _materials() -> void:
	if _glove:
		return
	_glove = StandardMaterial3D.new()
	_glove.albedo_texture = preload("res://assets/viewmodel/glove_albedo.jpg")
	_glove.normal_enabled = true
	_glove.normal_texture = preload("res://assets/viewmodel/glove_normal.png")
	_glove.albedo_color = Color(0.72, 0.68, 0.59)
	_glove.normal_scale = 0.8
	_glove.roughness = 0.82
	_glove.metallic_specular = 0.25
	_glove.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	var sleeve_source := SLEEVE.instantiate()
	for mesh in sleeve_source.find_children("*", "MeshInstance3D", true, false):
		_sleeve_mesh = mesh.mesh
		_fabric = mesh.get_active_material(0).duplicate()
		_fabric.albedo_color = Color(0.72, 0.79, 0.59)
		_fabric.metallic = 0.0
		_fabric.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		break
	sleeve_source.free()
	_cloth = ShaderMaterial.new()
	_cloth.shader = CLOTH_SHADER
	_cloth.set_shader_parameter("albedo_tex", _fabric.albedo_texture)
	_cloth.set_shader_parameter("normal_tex", _fabric.normal_texture)
	_cloth.set_shader_parameter("roughness_tex", _fabric.roughness_texture)
	_cloth.set_shader_parameter("tint", _fabric.albedo_color)
	_cloth.set_shader_parameter("normal_strength", _fabric.normal_scale)
	_cloth.set_shader_parameter("roughness_factor", _fabric.roughness)

static func build(weapon_id: String, bounds: AABB) -> ViewmodelHands:
	_materials()
	var rig := ViewmodelHands.new()
	rig.name = "Hands"
	var pistol := weapon_id in ["pistol", "revolver"]
	var landmarks: Vector4 = GRIPS[weapon_id]
	rig.trigger_grip = Vector3(bounds.end.x + 0.012, bounds.position.y + bounds.size.y * landmarks.x, bounds.position.z + bounds.size.z * landmarks.y)
	rig.support_grip = Vector3(bounds.position.x - 0.011, bounds.position.y + bounds.size.y * landmarks.z, bounds.position.z + bounds.size.z * landmarks.w)
	var right_basis := Basis(Vector3.UP, PI)
	var right_wrist := rig.trigger_grip + Vector3(0.012, -0.008, 0.059)
	var right := rig._arm(true, false, Transform3D(right_basis, right_wrist), Vector3(0.18, -0.27, 0.40))
	right.name = "TriggerHand"
	rig.add_child(right)
	var left_basis := Basis(Vector3.UP, PI)
	var left_wrist := rig.support_grip + Vector3(-0.012, -0.006, 0.06)
	if pistol:
		# Support palm wraps below the trigger hand instead of mirroring its fist.
		left_basis = Basis(Vector3.BACK, -0.25) * left_basis
		left_wrist += Vector3(0.008, -0.018, -0.014)
	else:
		left_basis = Basis(Vector3.BACK, PI * 0.5) * left_basis
		left_wrist = rig.support_grip + Vector3(0.012, -0.03, 0.060)
	rig.support = rig._arm(false, not pistol, Transform3D(left_basis, left_wrist), Vector3(-0.30, -0.27, 0.40))
	rig.support.name = "SupportHand"
	rig.add_child(rig.support)
	return rig

func _arm(right: bool, foregrip: bool, wrist: Transform3D, elbow: Vector3) -> Node3D:
	var arm := Node3D.new()
	var glove: Node3D = (RIGHT if right else LEFT).instantiate()
	glove.name = "Glove"
	glove.transform = wrist.scaled_local(Vector3.ONE * HAND_SCALE)
	arm.add_child(glove)
	var skeleton: Skeleton3D = glove.find_child("Skeleton3D", true, false)
	# Preserve the authored skin weights and thumb webbing while posing fingers.
	for i in skeleton.get_bone_count():
		var bone := skeleton.get_bone_name(i)
		var curl := 0.0
		if "thumb_1" in bone:
			curl = 0.20 if right else 0.12
		elif "thumb_2" in bone:
			curl = 0.36
		elif "_meta_" not in bone and "thumb" not in bone:
			if "_0_" in bone:
				curl = 0.50 if foregrip else 0.60
			elif "_1_" in bone:
				curl = 0.85 if foregrip else 1.0
			elif "_2_" in bone:
				curl = 0.65
			if right and "index" in bone:
				curl *= 0.58
		if curl != 0.0:
			var rest := skeleton.get_bone_rest(i).basis.get_rotation_quaternion()
			skeleton.set_bone_pose_rotation(i, rest * Quaternion(Vector3.BACK, curl))
	for node in glove.find_children("*", "MeshInstance3D", true, false):
		node.material_override = _glove
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.extra_cull_margin = 0.3
	for simulator in glove.find_children("*", "PhysicalBoneSimulator3D", true, false):
		simulator.free()
	var cuff := wrist * Vector3(0.0, 0.0, -0.012)
	var sleeve := MeshInstance3D.new()
	sleeve.name = "Sleeve"
	sleeve.mesh = _sleeve(cuff, elbow, wrist.basis)
	sleeve.material_override = _cloth
	sleeve.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sleeve.extra_cull_margin = 0.01
	sleeve.set_instance_shader_parameter("side", 1.0 if right else -1.0)
	_sleeves.append(sleeve)
	arm.add_child(sleeve)
	return arm

static func _sleeve(start: Vector3, elbow: Vector3, hand_basis: Basis) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var arrays := _sleeve_mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var control1 := start - hand_basis.z * 0.09
	var control2 := elbow + (start - elbow).normalized() * 0.13
	for i in vertices.size():
		var v := vertices[i]
		var t := clampf(v.z, 0.0, 1.0)
		var center := start.bezier_interpolate(control1, control2, elbow, t)
		var tangent := start.bezier_derivative(control1, control2, elbow, t)
		var direction := tangent.normalized()
		var x := hand_basis.x.slide(direction).normalized()
		var y := direction.cross(x).normalized()
		var rx := lerpf(0.016, 0.041, smoothstep(0.0, 1.0, t))
		var ry := lerpf(0.026, 0.040, smoothstep(0.0, 1.0, t))
		var normal := (x * normals[i].x / rx + y * normals[i].y / ry + direction * normals[i].z / maxf(tangent.length(), 0.01)).normalized()
		surface.set_normal(normal)
		surface.set_uv(uvs[i])
		surface.set_color(Color(t, 0, 0, 1))
		surface.add_vertex(center + x * v.x * rx + y * v.y * ry)
	for index in indices:
		surface.add_index(index)
	surface.generate_tangents()
	return surface.commit()

func animate_reload(progress: float, reloading: bool) -> void:
	var reach := sin(clampf(progress, 0.0, 1.0) * PI) if reloading else 0.0
	support.position = Vector3(-0.035, -0.14, 0.07) * reach
	support.rotation.z = -0.20 * reach

func shot_impulse(strength: float) -> void:
	_shot_age = 0.0
	_shot_strength = minf(strength, 1.6)

func animate_cloth(delta: float, speed: float, aim: float) -> void:
	_cloth_clock += delta
	_shot_age = minf(_shot_age + delta, 10.0)
	_stride = lerpf(_stride, minf(speed / 7.2, 1.0) * (1.0 - aim * 0.55), 1.0 - exp(-delta * 8.0))
	for sleeve in _sleeves:
		sleeve.set_instance_shader_parameter("cloth_clock", _cloth_clock)
		sleeve.set_instance_shader_parameter("shot_age", _shot_age)
		sleeve.set_instance_shader_parameter("shot_strength", _shot_strength)
		sleeve.set_instance_shader_parameter("movement", _stride)

func reset_motion() -> void:
	_shot_age = 10.0
	_shot_strength = 0.0
	_stride = 0.0
	animate_reload(0.0, false)
	animate_cloth(0.0, 0.0, 0.0)
