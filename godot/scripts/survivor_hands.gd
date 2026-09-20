extends Node3D

# The same licensed, articulated gloves as the first-person viewmodel.
# Meshy's generated body has wrist joints but no individual finger joints.
static func glove(right: bool, foregrip: bool) -> Node3D:
	ViewmodelHands._materials()
	var mesh: Node3D = (ViewmodelHands.RIGHT if right else ViewmodelHands.LEFT).instantiate()
	# World weapons use the same 1.35 scale relative to the viewmodel.
	mesh.scale = Vector3.ONE * ViewmodelHands.HAND_SCALE * 1.35
	var rig: Skeleton3D = mesh.find_child("Skeleton3D", true, false)
	for i in rig.get_bone_count():
		var bone := rig.get_bone_name(i)
		var curl := 0.0
		if "thumb_1" in bone: curl = 0.20 if right else 0.12
		elif "thumb_2" in bone: curl = 0.36
		elif "_meta_" not in bone and "thumb" not in bone:
			if "_0_" in bone: curl = 0.50 if foregrip else 0.60
			elif "_1_" in bone: curl = 0.85 if foregrip else 1.0
			elif "_2_" in bone: curl = 0.65
			if right and "index" in bone: curl *= 0.58
		if curl != 0.0:
			rig.set_bone_pose_rotation(i, rig.get_bone_rest(i).basis.get_rotation_quaternion() * Quaternion(Vector3.BACK, curl))
	for node: MeshInstance3D in mesh.find_children("*", "MeshInstance3D", true, false):
		node.material_override = ViewmodelHands._glove
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		node.extra_cull_margin = 0.3
	for simulator in mesh.find_children("*", "PhysicalBoneSimulator3D", true, false): simulator.free()
	return mesh
