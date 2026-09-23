# Hitches on flare pistol shots (and the effects built the same way): every probe runs twice, the
# second, warm round must not compile a single pipeline and must not stall the frame. Before the fix
# each flare launch cost 30-40 ms of CPU and recompiled its material's shader on every shot.
# Windowed, needs the renderer:
# Godot.exe --path godot --resolution 1600x900 --script res://tests/run.gd -- --suite=flare_hitch --no-intro --no-music
extends SceneTree

const Grenade = preload("res://scripts/grenade.gd")
const Elemental = preload("res://scripts/elemental_effects.gd")
const PROBES := ["damage", "ignite", "plant", "launch", "tracer", "explode", "shot_flare", "shot_pistol"]

var game: Node
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_dt: float) -> bool:
	if Time.get_ticks_msec() - began > 400000:
		push_error("FLARE_HITCH_TIMEOUT")
		quit(1)
	return false

func check(ok: bool, text: String) -> void:
	checks += 1
	if ok: print("PASS: ", text)
	else:
		failures += 1
		push_error("FAIL: " + text)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	for i in 90: await process_frame
	var probes: Array = PROBES.duplicate()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--probes="): probes = Array(arg.trim_prefix("--probes=").split(","))
	var warm := {}
	for pass_index in 2:
		for probe: String in probes:
			var r: Dictionary = await _probe(probe, 4)
			print("FLARE_PROBE %s %-12s worst=%6.1fms p95=%5.1fms call=%5.1fms (max %5.1fms) pipelines=%d hits=%s" % [
				"cold" if pass_index == 0 else "warm", probe, r.worst, r.p95, r.call_ms, r.call_max, r.pipelines, r.shots])
			if pass_index == 1: warm[probe] = r
	for probe: String in probes:
		var r: Dictionary = warm[probe]
		check(r.pipelines == 0, "%s compiles no pipeline once warm (%d)" % [probe, r.pipelines])
		check(r.call_ms < 8.0, "%s costs no noticeable CPU on the call itself (median %.1f ms)" % [probe, r.call_ms])
	if warm.has("shot_flare") and warm.has("shot_pistol"):
		check(warm.shot_flare.shots.count("hit") >= 2, "The flare shots really hit (%s)" % [warm.shot_flare.shots])
		check(warm.shot_flare.p95 < warm.shot_pistol.p95 + 10.0, "A flare volley runs as smooth as a pistol volley (p95 %.1f vs %.1f ms)" % [warm.shot_flare.p95, warm.shot_pistol.p95])
	print("FLARE_HITCH_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _pipelines() -> int:
	return RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SURFACE) \
		+ RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_DRAW) \
		+ RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_SPECIALIZATION) \
		+ RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_PIPELINE_COMPILATIONS_MESH)

# Four zombies 11-15 m ahead on the open south end of the Sennhofstrasse, one application each.
func _probe(probe: String, count: int) -> Dictionary:
	for z in game.zombies_root.get_children(): z.queue_free()
	# Whatever the previous probe left burning must be gone, so a cached shader is really tested.
	for f in 420: await process_frame
	var player: Player = game.player
	var w: Weapons = game.weapons
	player.global_position = Map.ground_pos(136.0, 112.0) + Vector3(0, 0.3, 0)
	player.velocity = Vector3.ZERO
	player.rotation.y = 0.0
	var targets: Array[Zombie] = []
	for i in count:
		var spot := Vector2(131.0 + i * 3.2, 99.0 - (i % 2) * 3.0)
		if game.spawn_zombie("shambler", spot, 0.05):
			var z: Zombie = game.zombies_root.get_child(game.zombies_root.get_child_count() - 1)
			z.hp = 400.0
			targets.append(z)
	var weapon := "pistol" if probe == "shot_pistol" else "flare_pistol"
	w.unlock(weapon)
	w.set_weapon(weapon)
	for i in 40: await process_frame
	var times: Array[float] = []
	var shots := []
	var worst := 0.0
	var calls: Array[float] = []
	var pipelines_before := _pipelines()
	for z in targets:
		if not is_instance_valid(z): continue
		player.hp = player.max_hp
		var eye: Vector3 = player.camera.global_position
		var chest: Vector3 = z.global_position + Vector3.UP * z.height * 0.55
		var aim: Vector3 = (chest - eye).normalized()
		player.rotation.y = atan2(-aim.x, -aim.z)
		player.pitch = asin(aim.y)
		player.head.rotation.x = player.pitch
		await process_frame
		var last := Time.get_ticks_usec()
		var hp_before := z.hp
		var t0 := Time.get_ticks_usec()
		match probe:
			"damage": z.damage(45.0, aim)
			"ignite": w.specials.ignite(z, "fire", 4.0, 1, "flare_pistol")
			"plant": w.specials.plant_flare(chest - aim * 0.6)
			"launch": w.specials._launch_flare(w, "flare_pistol", eye + aim * 0.6, aim)
			"tracer": Elemental.shot(game, eye + aim * 0.6, chest, "fire", true)
			"explode": Grenade.explosion_visuals(game, chest + Vector3(0, 0, 6))
			_:
				w.state[weapon].cooldown = 0.0
				w.state[weapon].reloading = 0.0
				w.state[weapon].ammo = int(w.state[weapon].def.mag)
				w.try_fire()
		calls.append((Time.get_ticks_usec() - t0) / 1000.0)
		for f in 30:
			await process_frame
			var now := Time.get_ticks_usec()
			var dt := (now - last) / 1000.0
			last = now
			times.append(dt)
			worst = maxf(worst, dt)
		shots.append("hit" if not is_instance_valid(z) or z.hp < hp_before or z.rare_status != "" else "miss")
	var sorted := times.duplicate()
	sorted.sort()
	calls.sort()
	# The median call: the old flare cost 30-40 ms on every shot, a stray spike from the OS does not.
	return {"worst": worst, "p95": sorted[int(sorted.size() * 0.95)] if not sorted.is_empty() else 0.0,
		"call_ms": calls[calls.size() / 2] if not calls.is_empty() else 0.0, "call_max": calls.back() if not calls.is_empty() else 0.0,
		"pipelines": _pipelines() - pipelines_before, "shots": shots}
