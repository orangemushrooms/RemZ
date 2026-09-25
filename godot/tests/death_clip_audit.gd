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
		var info: Dictionary = preload("res://scripts/zombie_animation.gd").measure(load(path))
		for clip in info:
			if not str(clip).begins_with("death"): continue
			var m: Dictionary = info[clip]
			print("DEATH_CLIP %s %s len=%.2f travel_z=%.3f spread_mid=%.2f spread_end=%.2f plank=%s" % [skin, clip, m.length, m.travel_z, m.spread_mid, m.spread_end, Zombie.is_plank(m)])
		if hips < 0 or lh < 0 or rh < 0 or ls < 0 or rs < 0: pass
		root.queue_free()
	print("DEATH_CLIP_AUDIT_DONE")
	quit(0)
