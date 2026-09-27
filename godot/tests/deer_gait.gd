extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func measure_hooves(model: Node3D, animation: AnimationPlayer, kind: String) -> void:
	var rig := model.find_child("Skeleton3D", true, false) as Skeleton3D
	check(rig != null and animation.has_animation("run"), kind + " has an articulated gallop")
	if not rig: return
	for id in [3, 6, 9, 12]:
		var hoof := rig.find_bone("Hoof%d" % id)
		var low := Vector3(INF, INF, INF)
		var high := -low
		animation.play("run", 0)
		for sample in 49:
			animation.seek(animation.get_animation("run").length * sample / 48.0, true)
			rig.force_update_all_bone_transforms()
			var point := rig.get_bone_global_pose(hoof).origin * model.scale.y
			low = low.min(point)
			high = high.max(point)
		check(high.y - low.y > 0.20 and high.z - low.z > 0.50,
			"%s hoof %d visibly lifts and reaches (lift %.2fm, stride %.2fm)" % [kind, id, high.y - low.y, high.z - low.z])

func move_animal(animal: Deer, speed: float, fps: int) -> void:
	var start := animal.position
	# Render rates differ from the 60 Hz physics movement. The gait must keep
	# advancing even on render frames with no new physics displacement.
	for frame in fps * 2:
		animal.position = start + Vector3(speed * floorf((frame + 1) * 60.0 / fps) / 60.0, 0, 0)
		animal._process(1.0 / fps)
		animal.animation.advance(1.0 / fps)

func run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	current_scene = world
	for kind in ["deer", "stag"]:
		var animal := Deer.new()
		animal.setup(null, kind, load("res://assets/models/%s_animated.glb" % kind), 100)
		world.add_child(animal)
		animal.set_process(false)
		animal.set_physics_process(false)
		animal.animation.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		measure_hooves(animal.model, animal.animation, kind)
		for fps in [30, 60, 144, 240, 360]:
			move_animal(animal, 10.8 if kind == "stag" else 9.0, fps)
			check(animal.animation.current_animation == "run" and animal.animation.speed_scale > 1.5, "%s gallops at flight speed (%d FPS)" % [kind, fps])
			var rig := animal.model.find_child("Skeleton3D", true, false) as Skeleton3D
			var joint := rig.find_bone("Knee3")
			var first_pose := rig.get_bone_pose_rotation(joint)
			var bend := 0.0
			for frame in 30:
				animal.animation.advance(1.0 / 60.0)
				bend = maxf(bend, first_pose.angle_to(rig.get_bone_pose_rotation(joint)))
			check(bend > 0.4, "%s knee keeps bending during playback (%d FPS)" % [kind, fps])
			move_animal(animal, 0.7, fps)
			check(animal.animation.current_animation == "walk", "%s walks at grazing speed (%d FPS)" % [kind, fps])
			move_animal(animal, 0.0, fps)
			check(animal.animation.current_animation == "graze", "%s stops stepping at rest (%d FPS)" % [kind, fps])
		animal.position.x += 20.0
		animal._process(1.0 / 240.0)
		check(animal.animation.current_animation == "graze" and is_zero_approx(animal._ground_speed), kind + " ignores a real teleport")
		animal.free()
	var stag := ZombieBeast.new()
	stag.setup("zombie_stag", null, [], 1.0, Callable())
	world.add_child(stag)
	stag.set_physics_process(false)
	stag.agent.avoidance_enabled = false
	stag.anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	measure_hooves(stag.model, stag.anim, "zombie_stag")
	for remote in [false, true]:
		stag.replica = remote
		stag.net_position = stag.position
		for frame in 90:
			if remote:
				stag.net_position.x += 11.5 / 60.0
				stag._physics_process(1.0 / 60.0)
			else:
				stag.position.x += 11.5 / 60.0
				stag._update_animation(1.0 / 60.0)
			stag.anim.advance(1.0 / 60.0)
		check(stag.anim.current_animation == "run" and stag.anim.speed_scale > 1.5, "Zombie stag gallops during a charge (replica=%s)" % remote)
	stag.free()
	print("DEER_GAIT_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
