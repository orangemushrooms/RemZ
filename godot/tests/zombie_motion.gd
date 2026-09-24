# The animation layer of the zombies (headless):
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=zombie_motion
# Clip metrics of every skin (gait speeds, strike moments), stride matching against the real displacement,
# idle when standing, swing and death variants, the flinch and scream states with their fallbacks on rigs
# that lack the clips, the co-op replica mirroring logical states, and the animation LOD of distant actors.
extends SceneTree

var checks := 0
var failures := 0
var scene: Node3D

func _initialize() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

# Replicas follow net_position: move both so the lerp leaves the body where the test put it.
func place(z: Zombie, pos: Vector3) -> void:
	z.global_position = pos
	z.net_position = pos

func step(z: Zombie, velocity: Vector3, ticks: int) -> void:
	for i in ticks:
		place(z, z.global_position + velocity / 60.0)
		z._physics_process(1.0 / 60.0)

func actor(kind: String, skin := "") -> Zombie:
	Zombie.force_skin = skin
	var zombie := Zombie.new()
	zombie.setup(kind, null, [], 1.0, Callable())
	Zombie.force_skin = ""
	zombie.replica = true            # no navigation: the test moves the body itself
	scene.add_child(zombie)
	return zombie

func run() -> void:
	scene = Node3D.new()
	root.add_child(scene)
	current_scene = scene
	Zombie.preload_models(scene)
	var measured := 0
	for spec: Dictionary in Zombie.TYPES.values():
		if spec.get("worm", false): continue
		for skin in Zombie.skin_names(spec):
			var path := "res://assets/models/%s.glb" % skin
			if not ResourceLoader.exists(path): continue
			var info := Zombie.clip_info(path)
			if info.is_empty(): continue
			measured += 1
			var line := "ZOMBIE_CLIPS %s:" % skin
			for clip in info:
				line += " %s(len %.2f, %.2f m/s, peak %.2f)" % [clip, info[clip].length, info[clip].speed, info[clip].peak]
			print(line)
			var walk: Dictionary = info.get("walk", {})
			check(not walk.is_empty() and walk.speed > 0.15 and walk.speed < 3.5, "%s walk clip implies a plausible ground speed (%.2f m/s)" % [skin, walk.get("speed", 0.0)])
			if info.has("run"):
				check(info.run.speed > walk.speed, "%s run clip is faster than its walk (%.2f > %.2f m/s)" % [skin, info.run.speed, walk.speed])
			var attack: Dictionary = info.get("attack", {})
			check(not attack.is_empty() and attack.peak > 0.05 and attack.peak < attack.length, "%s attack clip has its strike inside the clip (%.2f of %.2f s)" % [skin, attack.get("peak", 0.0), attack.get("length", 0.0)])
	check(measured >= 10, "clip metrics measured for %d skins" % measured)

	# stride matching: a shambler walking at its own speed plays its gait near 1x, a crawl slows the clip
	var z := actor("shambler", "zombie_shambler")
	place(z, Vector3(0, 0, 0))
	await physics_frame
	check(z.state == "walk" and z.clip.begins_with("walk") and z.anim.is_playing(), "shambler starts in its gait clip (%s)" % z.clip)
	var natural := z._natural_speed(z.clip)
	check(natural > 0.1, "natural speed of the gait in world units is known (%.2f m/s)" % natural)
	var speed := 1.6
	step(z, Vector3(0, 0, speed), 90)
	var expected := clampf(speed / natural, 0.35, 2.4)
	check(absf(z.anim.speed_scale - expected) < 0.12, "speed_scale follows the displacement: %.2f for %.1f m/s (expected %.2f)" % [z.anim.speed_scale, speed, expected])
	step(z, Vector3(0, 0, 0.5), 90)
	check(z.anim.speed_scale < expected * 0.5, "a slower body slows its clip (%.2f)" % z.anim.speed_scale)
	# standing: idle when the rig has one, otherwise the gait keeps its slowest pace
	step(z, Vector3.ZERO, 60)
	if z.anim.has_animation("idle"):
		check(z.clip == "idle" and z.state == "walk" and z.anim.current_animation == "idle", "standing still plays idle while the logical state stays walk")
		step(z, Vector3(0, 0, 30.0), 1)
		check(z.clip.begins_with("walk"), "moving again leaves idle for the gait (%s)" % z.clip)
	else:
		check(z.clip.begins_with("walk") and z.anim.speed_scale <= 0.4, "rig without idle stands in its gait at the slowest pace (%.2f)" % z.anim.speed_scale)

	# swings alternate between the variants, the strike lands on the damage tick
	var seen := {}
	for i in 6:
		z.state = "walk"
		z.play("attack")
		var info: Dictionary = Zombie.clip_info(z.model_path).get(z.clip, {})
		if not info.is_empty() and not seen.has(z.clip):
			var strike: float = (float(info.peak) - z.anim.current_animation_position) / z.anim.speed_scale
			check(absf(strike - z.attack_lead()) < 0.06, "%s strike lands %.2f s after the call (damage tick at %.2f)" % [z.clip, strike, z.attack_lead()])
		seen[z.clip] = true
	var variants := 0
	for n in ["attack", "attack2", "attack3"]:
		if z.anim.has_animation(n): variants += 1
	check(seen.size() == variants, "all %d swing variants are used (%s)" % [variants, seen.keys()])

	# flinch and scream: with the clips they play, without them the gait stands in
	z.state = "walk"
	z.play("hit")
	if z.anim.has_animation("hit") or z.anim.has_animation("hit2"):
		check(z.state == "hit" and z.clip.begins_with("hit"), "hit plays a flinch clip (%s)" % z.clip)
	else:
		check(z.state == "hit" and z.clip.begins_with("walk"), "hit without a flinch clip keeps the gait")
	z.state = "walk"
	z.play("scream")
	check(z.state == "scream" and (z.clip == "scream" or not z.anim.has_animation("scream")), "scream state on every rig, clip when present (%s)" % z.clip)
	z.state = "walk"
	var deaths := {}
	for i in 12:
		z.alive = true
		z.state = "walk"
		z.play("death")
		deaths[z.clip] = true
	var death_variants := 0
	for n in ["death", "death2", "death3"]:
		if z.anim.has_animation(n): death_variants += 1
	check(deaths.size() == death_variants, "all %d death variants are used (%s)" % [death_variants, deaths.keys()])

	# a runner sprints, and drops to its walk clip when slowed down
	var r := actor("runner", "zombie_runner")
	await physics_frame
	if r.anim.has_animation("run"):
		check(r._locomotion == "run" and r.clip == "walk", "a standing runner waits in its walk clip, its gait is the run")
		step(r, Vector3(0, 0, 4.2), 90)
		check(r.clip == "run" and r.anim.speed_scale > 0.5, "sprinting runner keeps the run clip at %.2f" % r.anim.speed_scale)
		step(r, Vector3(0, 0, 1.2), 120)
		check(r.clip == "walk", "a slowed runner walks instead of a slow-motion sprint (%s)" % r.clip)
	else:
		check(r.clip == "walk", "runner without a run clip walks")

	# animation LOD: far actors switch the mixer to manual and still advance their pose
	var far := actor("shambler", "zombie_shambler")
	var p := Player.new()
	scene.add_child(p)
	p.global_position = Vector3(0, 0, 0)
	far.player = p
	place(far, Vector3(0, 0, 60))
	await physics_frame
	for i in 4: far._physics_process(1.0 / 60.0)
	check(far._anim_lod == 2 and far.anim.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL, "60 m away the rig updates every second tick")
	var before := far.anim.current_animation_position
	for i in 4: far._physics_process(1.0 / 60.0)
	check(far.anim.current_animation_position != before, "manual mode still advances the clip")
	place(far, Vector3(0, 0, 100))
	for i in 6: far._physics_process(1.0 / 60.0)
	check(far._anim_lod == 3, "100 m away every third tick")
	place(far, Vector3(0, 0, 10))
	for i in 2: far._physics_process(1.0 / 60.0)
	check(far._anim_lod == 1 and far.anim.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE, "close again: every frame")
	place(far, Vector3(0, 0, 100))
	for i in 6: far._physics_process(1.0 / 60.0)
	far.die(Vector3.FORWARD)
	check(far._anim_lod == 1 and far.state == "death" and far.anim.callback_mode_process == AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE, "a distant corpse falls at full rate")

	# head tracking: the modifier sits on the Head bone with axes read off the rest pose
	var tracked := actor("shambler", "zombie_shambler")
	tracked.player = p
	place(tracked, Vector3(0, 0, 5))
	await physics_frame
	if tracked._head_look:
		var rig: Skeleton3D = tracked.model.find_child("Skeleton3D", true, false)
		var rest := rig.get_bone_global_rest(rig.find_bone("Head")).basis
		var axes := {SkeletonModifier3D.BONE_AXIS_PLUS_X: rest.x, SkeletonModifier3D.BONE_AXIS_MINUS_X: -rest.x, SkeletonModifier3D.BONE_AXIS_PLUS_Y: rest.y,
			SkeletonModifier3D.BONE_AXIS_MINUS_Y: -rest.y, SkeletonModifier3D.BONE_AXIS_PLUS_Z: rest.z, SkeletonModifier3D.BONE_AXIS_MINUS_Z: -rest.z}
		var forward: Vector3 = axes[tracked._head_look.forward_axis]
		check(forward.normalized().dot(Vector3(0, 0, 1)) > 0.7, "head forward axis points along the rig's facing (%s, dot %.2f)" % [tracked._head_look.forward_axis, forward.normalized().dot(Vector3(0, 0, 1))])
		for i in 30: tracked._physics_process(1.0 / 60.0)
		check(tracked._head_look.influence > 0.5 and tracked._head_look.active, "5 m from the player the head tracks (influence %.2f)" % tracked._head_look.influence)
		place(tracked, Vector3(0, 0, 40))
		for i in 90: tracked._physics_process(1.0 / 60.0)
		check(tracked._head_look.influence < 0.05, "40 m away the head tracking fades out (%.2f)" % tracked._head_look.influence)
	else:
		check(false, "common zombie has head tracking")
	# titan: strike lands on the end of the wind-up, the roar roots it
	var t := Titan.new()
	t.setup("titan", null, [], 1.0, Callable())
	t.replica = true
	scene.add_child(t)
	await physics_frame
	check(t.state == "walk" and t.clip.begins_with("walk"), "titan starts walking (%s)" % t.clip)
	t.play("attack")
	var tinfo: Dictionary = Zombie.clip_info(t.model_path).get(t.clip, {})
	if not tinfo.is_empty():
		var strike: float = (float(tinfo.peak) - t.anim.current_animation_position) / t.anim.speed_scale
		check(absf(strike - t.windup()) < 0.15, "titan slam lands after %.2f s of a %.2f s wind-up" % [strike, t.windup()])
	print("ZOMBIE_MOTION_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
