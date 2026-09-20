extends SceneTree

var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if ok: print("PASS: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.weapons.set_process(false)
	var p: Player = game.player
	var w: Weapons = game.weapons
	p.set_physics_process(false)
	p.global_position = Map.ground_pos(20, 105)
	p.velocity = Vector3.ZERO
	w.unlocked.smg = true
	w.set_weapon("smg")
	w.ads = 0
	var hip := w.effective_spread()
	w.ads = 1
	var aimed := w.effective_spread()
	check(aimed < hip * 0.4, "Aimed stationary fire is much more precise than hip fire")
	p.velocity = Vector3(4.5, 0, 0)
	check(w.effective_spread() > aimed * 1.3, "Walking worsens actual aimed dispersion")
	p.velocity = Vector3(7, 5, 0)
	check(w.effective_spread() > aimed * 2, "Sprinting and jumping strongly reduce precision")
	p.velocity = Vector3.ZERO
	w.ads = 0
	var before := w.aim_direction()
	for i in 8:
		w.cur().cooldown = 0
		w.try_fire()
		w._tick_ammo(0.08)
	check(w._bloom > 0.8 and w.effective_spread() > hip * 1.6, "Sustained fire builds a wider ballistic cone")
	check(w.aim_direction().distance_to(before) > 0.005 and w._aim_kick.x > 0 and absf(w._aim_kick.y) > 0.0001, "Burst recoil displaces true aim upwards and sideways")
	w.update_reticle()
	var reticle = game.hud.crosshair_parts[0]
	var projection := p.camera.unproject_position(p.camera.global_position + w.aim_direction() * 10)
	check(reticle.aim_position.distance_to(projection) < 0.01, "Visible crosshair centre is the projected ballistic aim direction")
	var edge := p.camera.unproject_position(p.camera.global_position + w.aim_direction() * 10 + p.camera.global_basis.x * w.effective_spread() * 10)
	check(is_equal_approx(reticle.cone_radius, projection.distance_to(edge)), "Displayed radius matches the actual spread cone")
	var spread_firing := w.effective_spread()
	for i in 150: w._tick_ammo(1.0 / 60)
	check(w._bloom == 0 and w._aim_kick.length() < 0.00001 and w.effective_spread() < spread_firing, "Fire pause settles dispersion and free aim without drift")
	p.score = 10000
	p.global_position = game.progression.npcs.mechanic.global_position + Vector3(0, 0, 1)
	var trained_before := w.effective_spread()
	game.progression.transact(p, "mechanic", "training", "steady")
	check(is_equal_approx(w.effective_spread(), trained_before * 0.85), "Purchased precision training reduces real dispersion by fifteen percent")
	w.mod_owned["smg:match_barrel"] = true
	w.equip_mod("smg", Weapons.Mods.DEFS.match_barrel.slot, "match_barrel")
	check(w.effective_spread() < trained_before * 0.7, "Precision barrel combines with purchased training")
	p.relic = "hawk"
	check(w.effective_spread() < trained_before * 0.5, "Precision talisman supplies a further tangible accuracy improvement")
	p.relic = ""
	var farthest := 0.0
	var sum := Vector2.ZERO
	for i in 2000:
		var angle := float(i) * 2.3999632297
		var radius := float(i) / 1999.0
		var direction := Weapons.Aim.sample_direction(Vector3.FORWARD, Vector3.RIGHT, Vector3.UP, 0.04, radius, angle)
		var projected := Vector2(direction.x, direction.y) / -direction.z
		farthest = maxf(farthest, projected.length())
		sum += projected
	check(farthest <= 0.04001 and farthest > 0.039, "All sampled bullets remain inside the displayed circular cone")
	check(sum.length() / 2000 < 0.0001, "Circular sampling has no sideways or vertical bias")
	w._bloom = 1
	w._aim_kick = Vector2(0.1, 0.1)
	w.unlocked.marksman = true
	w.set_weapon("marksman")
	w.ads = 1
	check(w._bloom == 0 and w._aim_kick == Vector2.ZERO, "Switching weapons removes inherited recoil")
	w._aim_kick = Vector2(0.04, 0.02)
	check(w.aim_direction().distance_to(-p.camera.global_basis.z) < 0.0001, "Scoped shot remains aligned with the optic centre")
	NetSession.enabled = true
	NetSession.world.add_player(1)
	NetSession.world.add_player(2)
	var proxy: Weapons = NetSession.world.weapons[2]
	proxy.player.set_physics_process(false)
	proxy.set_process(false)
	proxy.unlocked.smg = true
	proxy.set_weapon("smg")
	proxy.ads = 0.5
	proxy.player.velocity = Vector3(4, 0, 0)
	w.set_weapon("smg")
	w.apply_mod_snapshot({}, {})
	w.spread_mul = 1
	w.ads = 0.5
	p.velocity = proxy.player.velocity
	check(is_equal_approx(w.effective_spread(), proxy.effective_spread()), "Host proxy uses the same movement and accuracy model")
	proxy._bloom = 1
	check(proxy.effective_spread() > w.effective_spread(), "Host independently accounts for sustained-fire bloom")
	NetSession.enabled = false
	if "--render-aim" in OS.get_cmdline_user_args():
		p.global_position = Map.ground_pos(20, 105)
		p.camera.rotation = Vector3.ZERO
		p.rotation.y = 0
		p.pitch = 0
		p.head.rotation.x = 0
		p.velocity = Vector3.ZERO
		w.ads = 0
		w._aim_kick = Vector2(0.045, -0.012)
		w._bloom = 0.9
		w.update_reticle()
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/aiming"))
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../artifacts/aiming/burst.png"))
	print("AIMING_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
