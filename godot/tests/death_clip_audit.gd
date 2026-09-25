# Measures every death clip of every zombie skin: where the hips travel (rig-local, +Z is the rig's
# front), how far the hands end up apart (spread arms = the stiff mannequin fall) and how long it lasts.
#   --suite=death_clip_audit   (headless)  -> DEATH_CLIP lines, used to pick a fall that matches the shot
extends SceneTree

const SKINS := ["zombie_shambler", "zombie_farmer", "zombie_hiker", "zombie_grandma", "zombie_runner", "zombie_jogger", "zombie_nurse", "zombie_soldier", "zombie_forester", "zombie_bloater"]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for skin in SKINS:
		var path := "res://assets/models/%s.glb" % skin
		if not ResourceLoader.exists(path): continue
		var root: Node3D = (load(path) as PackedScene).instantiate()
		get_root().add_child(root)
		var rig := root.find_child("Skeleton3D", true, false) as Skeleton3D
		var anim := root.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if not rig or not anim: continue
		var hips := rig.find_bone("Hips")
		var lh := rig.find_bone("LeftHand")
		var rh := rig.find_bone("RightHand")
		var ls := rig.find_bone("LeftShoulder")
		var rs := rig.find_bone("RightShoulder")
		for clip in ["death", "death2", "death3"]:
			if not anim.has_animation(clip): continue
			var a := anim.get_animation(clip)
			anim.play(clip)
			anim.seek(0.0, true)
			var start: Vector3 = rig.get_bone_global_pose(hips).origin
			anim.seek(a.length - 0.01, true)
			var end: Vector3 = rig.get_bone_global_pose(hips).origin
			var travel := end - start
			var spread: float = rig.get_bone_global_pose(lh).origin.distance_to(rig.get_bone_global_pose(rh).origin)
			var shoulders: float = rig.get_bone_global_pose(ls).origin.distance_to(rig.get_bone_global_pose(rs).origin)
			var head_y: float = rig.get_bone_global_pose(rig.find_bone("Head")).origin.y
			print("DEATH_CLIP %s %s len=%.2f travel=(%.0f, %.0f, %.0f) spread=%.2f head_y=%.0f" % [skin, clip, a.length, travel.x, travel.y, travel.z, spread / maxf(shoulders, 0.01), head_y])
		root.queue_free()
	print("DEATH_CLIP_AUDIT_DONE")
	quit(0)
