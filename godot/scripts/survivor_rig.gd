extends Node3D

# Meshy character in metres, facing -Z. Arms are solved after locomotion so
# wrists follow the equipped weapon, including aiming and recoil.
const MODEL := "res://assets/models/player_survivor_v2.glb"
var skeleton: Skeleton3D
var animation: AnimationPlayer
var bones: Dictionary = {}
var rest_rotations: Array[Quaternion] = []
var hip_origin := Vector3.ZERO
var walk_weight := 0.0
var clock := 0.0
var model: Node3D
var resting_foot_height := 0.0

func setup() -> void:
	model = (load(MODEL) as PackedScene).instantiate()
	add_child(model)
	model.rotation.y = PI
	skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	animation = model.find_child("AnimationPlayer", true, false)
	for i in skeleton.get_bone_count():
		bones[skeleton.get_bone_name(i)] = i
		rest_rotations.append(skeleton.get_bone_rest(i).basis.get_rotation_quaternion())
	hip_origin = skeleton.get_bone_rest(bones.Hips).origin
	resting_foot_height = _lowest_foot()
	if animation and animation.has_animation("walk"):
		animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for clip in ["walk", "run"]:
			if animation.has_animation(clip): animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
		animation.play("walk")
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		# Keep animated limbs from disappearing at the edge of the camera.
		mesh.extra_cull_margin = 1.0
		for i in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(i) as BaseMaterial3D
			if material:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

func pose(delta: float, speed: float, pitch: float, right_wrist: Vector3, left_wrist: Vector3, alive: bool) -> void:
	clock += delta
	walk_weight = move_toward(walk_weight, clampf(speed / 1.2, 0.0, 1.0) if alive else 0.0, delta * 6.0)
	skeleton.reset_bone_poses()
	if animation and animation.has_animation("walk"):
		var clip := "run" if speed > 5.0 and animation.has_animation("run") else "walk"
		if animation.current_animation != clip: animation.play(clip, 0.18)
		animation.speed_scale = clampf(speed / (4.5 if clip == "run" else 2.2), 0.6, 2.0)
		animation.advance(delta)
		for i in skeleton.get_bone_count():
			var bone_name := skeleton.get_bone_name(i)
			# Locomotion drives the lower body. Running's arm swing must not
			# rotate the shoulders/neck away from the two-handed weapon pose.
			var lower_body := "Leg" in bone_name or "Foot" in bone_name or "Toe" in bone_name
			var weight := walk_weight if lower_body else walk_weight * 0.15 if bone_name == "Hips" else 0.0
			skeleton.set_bone_pose_rotation(i, rest_rotations[i].slerp(skeleton.get_bone_pose_rotation(i), weight))
		# Remove horizontal root motion: the network actor owns displacement.
		var hip := skeleton.get_bone_pose_position(bones.Hips)
		hip.x = hip_origin.x
		hip.z = hip_origin.z
		hip.y = lerpf(hip_origin.y, hip.y, walk_weight)
		skeleton.set_bone_pose_position(bones.Hips, hip)
	_rotate_in_body("Spine", Vector3.RIGHT, pitch * 0.22 + sin(clock * 1.7) * 0.008)
	_rotate_in_body("Head", Vector3.RIGHT, pitch * 0.35)
	# Keep the lower boot on the ground as the imported hips bob.
	model.position.y += resting_foot_height - _lowest_foot()
	_solve_arm("Right", right_wrist, Vector3(0.40, 1.05, -0.04))
	_solve_arm("Left", left_wrist, Vector3(-0.40, 1.02, -0.12))

func _lowest_foot() -> float:
	var left := to_local(skeleton.to_global(skeleton.get_bone_global_pose(bones.LeftFoot).origin))
	var right := to_local(skeleton.to_global(skeleton.get_bone_global_pose(bones.RightFoot).origin))
	return minf(left.y, right.y)

func _rotate_in_body(bone_name: String, axis: Vector3, angle: float) -> void:
	if not bones.has(bone_name): return
	var bone: int = bones[bone_name]
	var local_axis := skeleton.global_basis.inverse() * global_basis * axis
	var current := skeleton.get_bone_global_pose(bone).basis.orthonormalized()
	_set_global_rotation(bone, Basis(local_axis.normalized(), angle) * current)

func _set_global_rotation(bone: int, rotation_basis: Basis) -> void:
	var parent := skeleton.get_bone_parent(bone)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis.orthonormalized() if parent >= 0 else Basis.IDENTITY
	skeleton.set_bone_pose_rotation(bone, (parent_basis.inverse() * rotation_basis).get_rotation_quaternion().normalized())

func _point_bone(bone: int, child: int, target: Vector3) -> void:
	var pose_now := skeleton.get_bone_global_pose(bone)
	var from := skeleton.get_bone_global_pose(child).origin - pose_now.origin
	var toward := target - pose_now.origin
	if from.length_squared() < 0.00001 or toward.length_squared() < 0.00001: return
	_set_global_rotation(bone, Basis(Quaternion(from.normalized(), toward.normalized())) * pose_now.basis.orthonormalized())

func _solve_arm(side: String, wrist_world: Vector3, elbow_body: Vector3) -> void:
	var upper: int = bones[side + "Arm"]
	var lower: int = bones[side + "ForeArm"]
	var hand: int = bones[side + "Hand"]
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var elbow := skeleton.get_bone_global_pose(lower).origin
	var wrist := skeleton.get_bone_global_pose(hand).origin
	var target := skeleton.to_local(wrist_world)
	var pole := skeleton.to_local(to_global(elbow_body))
	var length_a := shoulder.distance_to(elbow)
	var length_b := elbow.distance_to(wrist)
	var direction := (target - shoulder).normalized()
	var distance := clampf(shoulder.distance_to(target), absf(length_a - length_b) + 0.001, length_a + length_b - 0.001)
	var along := (length_a * length_a - length_b * length_b + distance * distance) / (2.0 * distance)
	var bend := pole - shoulder
	bend = (bend - direction * bend.dot(direction)).normalized()
	var solved_elbow := shoulder + direction * along + bend * sqrt(maxf(0.0, length_a * length_a - along * along))
	_point_bone(upper, lower, solved_elbow)
	_point_bone(lower, hand, target)
