extends SceneTree

var game: Node
var checks := 0
var failures := 0
var started_at := Time.get_ticks_msec()
var capture := false

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - started_at > 150000:
		push_error("EFFECTS_TIMEOUT")
		quit(1)
	return false

func check(condition: bool, description: String) -> void:
	checks += 1
	if condition:
		print("PASS: " + description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func run() -> void:
	capture = "--render-effects" in OS.get_cmdline_user_args()
	if capture:
		root.mode = Window.MODE_WINDOWED
		root.size = Vector2i(1920, 1080)
	game = load("res://scenes/main.tscn").instantiate()
	if not game.get_script():
		quit(1)
		return
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready:
		await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.player.set_process_unhandled_input(false)
	game.player.global_position = Map.ground_pos(-1, 13) + Vector3.UP * 0.3
	game.player.rotation.y = 0
	game.player.head.rotation.x = -0.07
	var weapon: Weapons = game.weapons
	weapon.set_process(false)
	var fx: WeaponEffects = weapon.effects
	for id in Weapons.ORDER:
		if Weapons.DEFS[id].get("melee", false): continue  # Melee weapons have no muzzle flash, smoke or recoil kick.
		weapon.unlock(id)
		weapon.set_weapon(id)
		weapon.cur().cooldown = 0.0
		weapon._process(0.1)
		var count := fx.emitted_puffs
		var pitch_before := weapon.kick_pitch
		weapon.try_fire()
		check(fx.front.visible and fx.world_light.light_energy > 0 and fx.hand_light.light_energy > 0, id + " flashes and illuminates both hands and world")
		check(fx.emitted_puffs == count + 3 and fx.active_smoke_count() > 0, id + " emits muzzle smoke")
		check(weapon.kick_pitch > pitch_before, id + " applies upward camera recoil")
		weapon._process(1.0 / 240.0)
		var holder: Node3D = weapon.cur().node
		check(holder.rotation.x > 0.0 and holder.position.z > weapon.cur().def.pos.z, id + " kicks upward and backward")
		check(fx.flash_root.transform.is_equal_approx(weapon.muzzle_transform()), id + " flash follows the recoiling muzzle")
		var hands: ViewmodelHands = weapon.cur().hands
		check(float(hands.get_node("TriggerHand/Sleeve").get_instance_shader_parameter("shot_strength")) > 0.0, id + " sends shot impulse to the sleeve")
		await screenshot(id + "-flash")
		for i in 15:
			weapon._process(1.0 / 60.0)
		check(not fx.front.visible and fx.active_smoke_count() > 0, id + " smoke outlasts the flash")
		await screenshot(id + "-smoke")
		for i in 150:
			weapon._process(1.0 / 60.0)
		check(fx.active_smoke_count() == 0 and absf(holder.rotation.x) < 0.0001, id + " smoke dissipates and recoil settles")
	# A cooldown, empty magazine or reload must not create extra visual shots.
	weapon.set_weapon("pistol")
	weapon.cur().cooldown = 0.0
	weapon.try_fire()
	var emitted := fx.emitted_puffs
	weapon.try_fire()
	check(fx.emitted_puffs == emitted, "Cooldown blocks extra flash/smoke bursts")
	weapon.cur().ammo = 0
	weapon.cur().reserve = 0
	weapon.cur().cooldown = 0.0
	weapon.try_fire()
	check(fx.emitted_puffs == emitted, "Empty magazine emits no fire or smoke")
	weapon.cur().ammo = 3
	weapon.cur().reserve = 12
	weapon.cur().cooldown = 0.0
	weapon.reload()
	weapon.try_fire()
	check(fx.emitted_puffs == emitted, "Reload blocks fire and smoke")
	weapon.set_weapon("smg")
	weapon.cur().ammo = 100
	Input.action_press("fire")
	for i in 180:
		weapon._process(1.0 / 60.0)
	Input.action_release("fire")
	check(fx.active_smoke_count() <= WeaponEffects.SMOKE_CAPACITY and weapon.cur().ammo < 70, "Sustained automatic fire keeps the smoke pool bounded")
	check(absf(weapon.cur().node.rotation.x) <= 0.32 and weapon.cur().node.position.z - weapon.cur().def.pos.z <= 0.12, "Automatic recoil stays bounded")
	weapon.set_weapon("revolver")
	check(not fx.front.visible and fx.heat == 0.0 and weapon.cur().node.rotation.is_zero_approx(), "Weapon switch clears flash, barrel trail and model recoil")
	weapon.cur().cooldown = 0.0
	weapon.try_fire()
	weapon._process(1.0 / 60.0)
	game.player.velocity = Vector3(4.4, 0, 0)
	for i in 30:
		weapon._process(1.0 / 60.0)
	check(float(weapon.cur().hands.get_node("SupportHand/Sleeve").get_instance_shader_parameter("movement")) > 0.3, "Walking produces independent sleeve movement")
	game.player.velocity = Vector3.ZERO
	weapon.set_process(true)
	game._pause()
	var flash_age := fx.flash_age
	var hands: ViewmodelHands = weapon.cur().hands
	var cloth_time: float = hands.get_node("TriggerHand/Sleeve").get_instance_shader_parameter("cloth_clock")
	await create_timer(0.1, true).timeout
	check(fx.flash_age == flash_age and hands.get_node("TriggerHand/Sleeve").get_instance_shader_parameter("cloth_clock") == cloth_time, "Pause freezes smoke, flash and cloth animation")
	game._on_start()
	weapon.set_process(false)
	# Check a late frame cannot swallow a newly fired flash.
	weapon.set_weapon("smg")
	weapon.cur().ammo = 10
	weapon.cur().cooldown = 0.0
	Input.action_press("fire")
	weapon._process(0.2)
	Input.action_release("fire")
	check(fx.front.visible and fx.flash_age == 0.0, "A slow frame still presents each new muzzle flash")
	Input.action_press("aim")
	for i in 30:
		weapon._process(1.0 / 60.0)
	weapon.cur().cooldown = 0.0
	weapon.try_fire()
	weapon._process(1.0 / 240.0)
	check(fx.flash_root.transform.is_equal_approx(weapon.muzzle_transform()) and fx.front.visible, "Flash stays on the muzzle while aiming down sights")
	await screenshot("smg-ads-flash")
	Input.action_release("aim")
	print("EFFECTS_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

func screenshot(label: String) -> void:
	if not capture:
		return
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("artifacts/weapon-effects")
	DirAccess.make_dir_recursive_absolute(folder)
	var result := root.get_texture().get_image().save_png(folder.path_join(label + ".png"))
	check(result == OK, "Saved " + label)
