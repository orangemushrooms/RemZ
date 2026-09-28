extends SceneTree
var game: Node3D
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec()-began>300000: quit(1)
	return false
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",description)
func key(code: Key, ctrl := false, shift := false) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.ctrl_pressed = ctrl
	event.shift_pressed = shift
	event.pressed = true
	root.push_input(event)
	await process_frame
	event.pressed = false
	root.push_input(event)
func shot(id: String) -> void:
	if "--render-life" not in OS.get_cmdline_user_args(): return
	for i in 10: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/planes/life/")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder+id+".png")
func run() -> void:
	game = load("res://scenes/planes.tscn").instantiate()
	game.exploration_only = true
	root.add_child(game)
	current_scene = game
	while not game.ready_for_exploration: await process_frame
	check(game.weapons==null and not game.survival_active,"Nature and shared menus preserve peaceful entry")
	var nature: Node3D = game.nature
	check(nature.counts.flowers>500 and nature.counts.mushrooms>80,"Meadows and woods contain existing flower and mushroom models")
	var placement_ok := true
	for plant: Dictionary in nature.plants:
		placement_ok = placement_ok and nature.clear_ground(plant.at,plant.woodland)
	check(placement_ok,"Plant clusters remain on suitable terrain away from roads, crops and buildings")
	check(nature.counts.deer==6 and nature.counts.stags==2,"Six deer and two stags populate the map")
	check(nature.deer.all(func(animal): return animal.animation!=null and animal.animation.has_animation("graze") and animal.animation.has_animation("run")),"All deer retain the existing skeletal grazing and running animations")
	var spread := 0.0
	for bird in game.birds: spread = maxf(spread,bird.home.distance_to(game.birds[0].home))
	check(game.birds.size()==14 and spread>200,"Ravens and owls are spread across the map")
	for woodland in [false,true]:
		var chosen := Vector2.ZERO
		var closest := INF
		for plant: Dictionary in nature.plants:
			if plant.woodland!=woodland: continue
			var distance: float = plant.at.length_squared()
			if distance<closest:
				closest = distance
				chosen = plant.at
		game.player.position = Map.ground_pos(chosen.x+3,chosen.y+3)+Vector3.UP*0.08
		game.player.rotation.y = PI/4
		game.player.pitch = -0.22
		game.player.head.rotation.x = game.player.pitch
		game.player.velocity = Vector3.ZERO
		game.player.reset_physics_interpolation()
		await shot("mushrooms" if woodland else "flowers")
	var animal: Deer = nature.deer[0]
	game.player.position = animal.position+Vector3(3,0,3)
	nature._update_distance()
	for i in 12: await physics_frame
	check(animal.state=="flee" and animal.velocity.length()>1,"A nearby stag reacts to the actual player and flees")
	await shot("stag")
	game.set_view(0)
	await key(KEY_ESCAPE)
	check(paused and game.hud.overlay.visible and not game.player.active,"Escape opens the shared Forest pause shell")
	check(game.hud._tabs.has("settings") and game.hud.settings_box.get_child_count()>1,"Shared settings controls are attached to the pause menu")
	var original_size := root.size
	root.size = Vector2i(1280,720)
	await shot("pause-720p")
	game.hud._fit_menu_card()
	check(root.get_visible_rect().encloses(game.hud._card.get_global_rect()),"Pause card fits inside 720p")
	game.hud.show_tab("settings")
	await shot("settings")
	await key(KEY_ESCAPE)
	check(not paused and game.player.active and not game.menu.visible,"Escape closes the shared menu and restores control")
	await key(KEY_D,true,true)
	var cheats: CanvasLayer = game.cheat_menu
	check(cheats.is_open and paused and not game.player.active,"Ctrl+Shift+D opens the actual shared cheat menu in exploration")
	check(not cheats.keys_button.visible and not cheats.secret_toggle.visible,"Forest-only objectives are absent from Planes cheats")
	var score: int = game.player.score
	cheats.points_button.pressed.emit()
	check(game.player.score==score+1000,"Cheat points work while paused")
	cheats.weapon_buttons.minigun.pressed.emit()
	check(game.weapons.current=="minigun" and game.weapons.cur().ammo==game.weapons.cur().def.mag,"Weapon cheat equips a loaded minigun during exploration")
	cheats.all_weapons_button.pressed.emit()
	check(Weapons.ORDER.all(func(id): return game.weapons.unlocked[id]),"Every shared weapon can be unlocked")
	cheats._set_weather("rain")
	check(game.weather.forced=="rain","Weather cheats work before survival starts")
	cheats._set_weather("clear")
	await shot("cheats-720p")
	await key(KEY_ESCAPE)
	check(not cheats.is_open and not game.menu.visible and not paused and game.player.active,"Escape closes only the cheat modal and restores gameplay")
	root.size = original_size
	await key(KEY_D,true,true)
	await cheats._spawn("soldier",true)
	check(game.alive_zombies()==1 and game.zombies_root.get_child(0).armored,"Cheat spawn creates an armored enemy on Planes navigation")
	cheats.close()
	game._clear_combat()
	await process_frame
	await game.start_survival()
	game.waves.set_process(false)
	await key(KEY_D,true,true)
	cheats.skip_button.pressed.emit()
	check(game.waves.wave==1 and not cheats.is_open and game.player.active,"Wave cheat starts the next survival wave and closes cleanly")
	game.waves.skip_current_wave()
	check(game.waves.completed==1 and game.waves.wave==2,"Skipping a live wave records its completion before advancing")
	game.stop_survival()
	check(not game.survival_active and game.player.active and not paused,"Returning to exploration restores normal controls")
	await key(KEY_ESCAPE)
	check(game.menu.visible and paused,"Shared pause menu still works after leaving survival")
	game.set_menu(false)
	game.player.damage(10000)
	game.player._bleed_out()
	check(game.over and game.menu.visible,"Lethal cheat encounters also open a recovery menu during exploration")
	game.hud.overlay_button.pressed.emit()
	check(game.player.active and game.player.alive and not game.over and not paused,"Continue after an exploration death restores a playable explorer")
	print("PLANES_LIFE_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
