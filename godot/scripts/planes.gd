extends Node3D
## Starts a 25-wave survival run; exploration is an optional secondary mode.
var exploration_only := false
var player: Player
var expedition: RunDirector
var weapons: Weapons
var hud: Hud
var settings: GameSettings
var day_night: DayNightCycle
var intro: Intro
var cornfield: Node3D
var landscape: Node3D
var started := false
var over := false
var ready_for_exploration := false
var birds: Array[Node3D] = []
var menu: Control
var cheat_menu: CanvasLayer
var nature: Node3D
var quickbar: CanvasLayer
var _night_flashlight := false
var music: Node
var _flags := OS.get_cmdline_user_args()
var _preparing_navigation := false
var _combat_warmed := false
var ui: CanvasLayer
var minimap: Control
var compass: Label
var _building_cells: Dictionary = {}
var _leaving := false
var _wind: AudioStreamPlayer
var _crickets: AudioStreamPlayer
var boot: BootScreen
var campaign := Campaign.new()
var difficulty: Dictionary
var waves: Node
var weather: Weather
var zombies_root: Node3D
var nav_region: NavigationRegion3D
var survival_active := false
var preparing_survival := false
var victory := false
var secret_night: SecretNight
var fill_light: DirectionalLight3D
var progression: Progression
var stats: RunStats
var inventory: Inventory
var loots: Array = []
var sandbags: Array = []
var pumpkins: Array = []
var field_trials: Node
var fortune: Node
var _alive_count := 0
var navigation_ready := false
var classes: Node
var teleport: AssassinTeleport
var achievements: Achievements
var brewing: Node3D
var fireworks: Node3D
var forest_keys: Node3D
var grill_position := Vector3.ZERO
var ambience: Node
var shooting_range: Node3D
var hunting: Node3D
var defences: DefenceSystem
var barricades: Array = []
var hut: Node3D
var skills: Skills
var field_building: Node
var _menu_actions := {}
var _spawn_rng := RandomNumberGenerator.new()
var _nav_shape := CapsuleShape3D.new()
var _kills := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# A scene entered from a paused menu must be able to finish its physics waits.
	get_tree().paused = false
	boot = BootScreen.find(get_tree())
	if not boot:
		boot = BootScreen.new()
		add_child(boot)
	boot.step(0.04)
	await get_tree().process_frame
	Map.use_region("planes")
	Map._ensure()
	_index_buildings()
	settings = GameSettings.new()
	add_child(settings)
	settings.set_process_unhandled_input(false)
	difficulty = GameSettings.DIFFICULTIES[settings.difficulty]
	campaign.select("planes")
	_environment()
	boot.step(0.15,true)
	landscape = load("res://scripts/planes_landscape.gd").new()
	add_child(landscape)
	landscape.build()
	boot.step(0.48,true)
	player = load("res://scripts/planes_player.gd").new()
	player.name = "Explorer"
	add_child(player)
	player.camera.far = 1800
	player.flashlight.visible = false
	set_view(0)
	cornfield = load("res://scripts/planes_crops.gd").new()
	add_child(cornfield)
	cornfield.build(self)
	boot.step(0.85,true)
	day_night = DayNightCycle.new()
	day_night.clock_seconds = 12.0*3600
	day_night.set_process(false)
	add_child(day_night)
	zombies_root = Node3D.new()
	zombies_root.name = "Zombies"
	add_child(zombies_root)
	_spawn_rng.seed = 935728
	_nav_shape.radius = 0.65
	_nav_shape.height = 2.5
	player.died.connect(func():
		if NetSession.enabled:
			if NetSession.is_host():
				stats.record_death(player.peer_id)
				NetSession.world.check_team()
		else: finish_survival(false))
	player.went_down.connect(func():
		if NetSession.is_host() and NetSession.world: NetSession.world.check_team())
	stats = RunStats.new()
	add_child(stats)
	stats.register_player(1,NetSession.player_name)
	achievements = Achievements.new()
	add_child(achievements)
	inventory = Inventory.new()
	add_child(inventory)
	inventory.set_process(false)
	inventory.set_process_unhandled_input(false)
	_birds()
	nature = load("res://scripts/planes_nature.gd").new()
	add_child(nature)
	nature.build(self)
	_interface()
	var leaderboard = preload("res://scripts/leaderboard.gd").new()
	add_child(leaderboard)
	leaderboard.setup(self)
	progression = load("res://scripts/planes_progression.gd").new()
	add_child(progression)
	progression.setup(self)
	grill_position = Map.ground_pos(18,11)+Vector3.UP*0.72
	hunting = preload("res://scripts/hunting.gd").new()
	add_child(hunting)
	hunting.setup(self)
	brewing = preload("res://scripts/brewing.gd").new()
	add_child(brewing)
	brewing.setup(self)
	shooting_range = preload("res://scripts/planes_range.gd").new()
	add_child(shooting_range)
	shooting_range.setup(self)
	music = Music.new()
	add_child(music)
	music.process_mode = Node.PROCESS_MODE_ALWAYS
	weather = load("res://scripts/planes_weather.gd").new()
	add_child(weather)
	weather.setup(self)
	weather.force("clear")
	settings.apply()
	# Summer reference lighting: no Forest-specific morning fog or weather schedule.
	settings.env.volumetric_fog_enabled = false
	_wind = AudioStreamPlayer.new()
	_wind.stream = load("res://assets/audio/sfx/Forest_Wind_Ambiance.mp3")
	_wind.volume_db = -22
	_wind.finished.connect(func(): _wind.play())
	add_child(_wind)
	_wind.play()
	_crickets = AudioStreamPlayer.new()
	var cricket_loop := Ambience.CRICKETS.duplicate() as AudioStreamMP3
	cricket_loop.loop = true
	_crickets.stream = cricket_loop
	_crickets.volume_linear = 0
	add_child(_crickets)
	_crickets.play()
	for child in get_children():
		if child not in [ui,boot,hud,cheat_menu,music]: child.process_mode = Node.PROCESS_MODE_PAUSABLE
	child_entered_tree.connect(func(child: Node): child.process_mode = Node.PROCESS_MODE_PAUSABLE)
	await get_tree().physics_frame
	await get_tree().physics_frame
	started = true
	if exploration_only or "--planes-explore" in _flags:
		set_menu(false)
		boot.close()
		boot = null
	else:
		await start_survival()
	ready_for_exploration = true
	navigation_ready = nav_region != null
	var launch_coop := Array(_flags).any(func(flag): return flag in ["--host","--host-online","--planes-lobby"] or flag.begins_with("--join=") or flag.begins_with("--join-code="))
	if NetSession.enabled or get_tree().get_meta("planes_lobby",false) or launch_coop:
		get_tree().remove_meta("planes_lobby")
		started = false
		player.active = false
		waves.set_process(false)
		day_night.set_process(false)
		classes.set_process(false)
		CharacterProfile.end_match()
		set_menu(true)
		hud.show_tab("multiplayer")
	if not expedition:
		expedition = RunDirector.new()
		add_child(expedition)
		expedition.setup(self)
	NetSession.attach(self)
	print("PLANES_READY trees=%d birds=%d crops=%s" % [landscape.tree_count,birds.size(),cornfield.counts])

func _index_buildings() -> void:
	for building: Dictionary in Map.VILLAGE:
		var rect := Rect2(Vector2(building.poly[0][0],building.poly[0][1]),Vector2.ZERO)
		for p in building.poly: rect = rect.expand(Vector2(p[0],p[1]))
		rect = rect.grow(4)
		for z in range(floori(rect.position.y/32),floori(rect.end.y/32)+1):
			for x in range(floori(rect.position.x/32),floori(rect.end.x/32)+1):
				var key := Vector2i(x,z)
				if not _building_cells.has(key): _building_cells[key] = []
				_building_cells[key].append(rect)

func near_building(p: Vector2) -> bool:
	for rect: Rect2 in _building_cells.get(Vector2i(floori(p.x/32),floori(p.y/32)),[]):
		if rect.has_point(p): return true
	return false

func _environment() -> void:
	RenderingServer.global_shader_parameter_set("remz_wetness",0.0)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	AlpineAtmosphere.apply(environment)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.ambient_light_energy = 0.7
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.1
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.68,0.77,0.85)
	environment.fog_density = 0.00018
	environment.fog_sky_affect = 0.12
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-56,-32,0)
	sun.light_color = Color(1.0,0.97,0.88)
	sun.light_energy = 1.65
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 140
	add_child(sun)
	settings.env = environment
	settings.sun = sun
	fill_light = DirectionalLight3D.new()
	fill_light.rotation_degrees = Vector3(-35,145,0)
	fill_light.shadow_enabled = false
	add_child(fill_light)

func _birds() -> void:
	for i in 24:
		var bird := load("res://scripts/field_bird.gd").new() as Node3D
		bird.game = self
		bird.index = i
		bird.owl = i>=20
		var at := Vector2(-94+(i%6)*18,28+(i/6)*18)
		bird.home = Map.ground_pos(at.x,at.y)+Vector3.UP*(4 if bird.owl else 0.2)
		bird.position = bird.home
		add_child(bird)
		birds.append(bird)

func set_view(index: int) -> void:
	var view: Dictionary = Map._d.views[clampi(index,0,2)]
	var p := Vector2(view.pos[0],view.pos[1])
	var target := Vector2(view.target[0],view.target[1])
	player.position = Map.ground_pos(p.x,p.y)+Vector3.UP*0.08
	player.velocity = Vector3.ZERO
	player.rotation.y = atan2(-(target.x-p.x),-(target.y-p.y))
	player.pitch = 0.015
	player.head.rotation.x = player.pitch
	player.reset_physics_interpolation()
	player._motion_ready = false
	if cornfield: cornfield.update_lod()

func _interface() -> void:
	ui = CanvasLayer.new()
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	var title := Label.new()
	title.text = "THE PLANES  /  REMETSCHWIL"
	title.position = Vector2(28,24)
	title.add_theme_font_size_override("font_size",22)
	ui.add_child(title)
	title.hide()
	var controls := Label.new()
	controls.text = "WASD Walk · Shift Sprint · Space Jump · Ctrl Crouch · M Map · Esc Menu"
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	controls.position = Vector2(28,-145)
	controls.add_theme_color_override("font_shadow_color",Color.BLACK)
	controls.add_theme_constant_override("shadow_offset_x",1)
	controls.add_theme_constant_override("shadow_offset_y",1)
	ui.add_child(controls)
	controls.hide()
	compass = Label.new()
	compass.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	compass.position = Vector2(-80,116)
	compass.custom_minimum_size.x = 160
	compass.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ui.add_child(compass)
	minimap = load("res://scripts/planes_minimap.gd").new()
	minimap.game = self
	var map_layer := Control.new()
	map_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(map_layer)
	map_layer.add_child(minimap)
	hud = load("res://scripts/planes_hud.gd").new()
	hud.game = self
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)
	player.hud = hud
	hud.minimap = minimap
	menu = hud.overlay
	cheat_menu = load("res://scripts/cheat_menu.gd").new()
	cheat_menu.main = self
	cheat_menu.forest_features = false
	add_child(cheat_menu)

func set_menu(open: bool) -> void:
	if cheat_menu.is_open: cheat_menu.close()
	if open:
		if progression and progression.is_open: progression.close()
		if inventory and inventory.is_open: inventory.close()
		if brewing and brewing.menu.is_open: brewing.menu.close()
		if field_building: field_building.cancel()
		if defences: defences.close()
	player.active = not open and not over and (started or not NetSession.enabled)
	player.velocity = Vector3.ZERO
	get_tree().paused = open and not NetSession.enabled
	if open:
		hud.show_overlay("REGION SECURED" if victory else "YOU DIED" if over else "PAUSED",
			"THE PLANES / REMETSCHWIL", "Play again" if over else "Continue", "", "over" if over else "pause")
		hud.set_difficulty_locked(survival_active and not over)
		_menu_actions[4].disabled = survival_active and not over
		_menu_actions[5].visible = survival_active or over
		hud.overlay_button.grab_focus()
	else:
		hud.hide_overlay()
		# hide_overlay() restores focus to its menu button before hiding it.
		# A hidden menu must not keep keyboard focus once gameplay resumes.
		get_viewport().gui_release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED

func _pause() -> void:
	if ready_for_exploration and not preparing_survival: set_menu(true)

func return_to_map(select_region := true) -> void:
	if NetSession.enabled:
		NetSession.leave()
		return
	if _leaving: return
	_leaving = true
	player.active = false
	get_tree().set_meta("open_campaign_map",select_region)
	BootScreen.cover(get_tree())
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _unhandled_input(event: InputEvent) -> void:
	if not ready_for_exploration or preparing_survival: return
	if event.is_action_pressed("next_wave", false, true) and waves and waves.phase=="idle" and started and not over and player.active and player.alive and not get_tree().paused and not hud.overlay.visible:
		if NetSession.enabled: NetSession.command("next_wave",[])
		else: waves.timer = minf(waves.timer,0.1)
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("pause"):
		if inventory and inventory.is_open:
			inventory.close(); get_viewport().set_input_as_handled(); return
		if brewing and brewing.menu.is_open:
			brewing.menu.close(); get_viewport().set_input_as_handled(); return
		if progression and progression.is_open:
			progression.close()
			get_viewport().set_input_as_handled()
			return
		if field_building and (field_building.placing or field_building.kit_menu.visible):
			field_building.cancel()
			get_viewport().set_input_as_handled()
			return
		if defences and (defences.placing or defences.is_open):
			defences.close()
			get_viewport().set_input_as_handled()
			return
		set_menu(not menu.visible)
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_F11:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)

func _process(_delta: float) -> void:
	if not ready_for_exploration: return
	if started and not over and not NetSession.is_client() and not get_tree().paused and (player.active or NetSession.is_host()): stats.tick(_delta)
	_update_music()
	_crickets.volume_linear = lerpf(_crickets.volume_linear,db_to_linear(Ambience.CRICKETS_VOLUME_DB)*Ambience.cricket_level_at(day_night.clock_seconds/3600),1-exp(-_delta/2))
	if survival_active and not over and player.active:
		if day_night.is_night() and not _night_flashlight:
			player.flashlight.visible = true
			_night_flashlight = true
		elif not day_night.is_night(): _night_flashlight = false
	var heading := fposmod(-rad_to_deg(player.rotation.y),360)
	var dirs := ["N","NE","E","SE","S","SW","W","NW"]
	compass.text = "%s  %03d°" % [dirs[roundi(heading/45)%8],heading]

func start_survival() -> void:
	if NetSession.enabled and ready_for_exploration:
		if over and NetSession.is_host(): NetSession.restart()
		return
	if preparing_survival or (survival_active and not over) or _leaving: return
	preparing_survival = true
	set_menu(false)
	player.active = false
	if not boot: boot = BootScreen.cover(get_tree())
	boot.step(0.1)
	await get_tree().process_frame
	await ensure_navigation()
	if nav_region.navigation_mesh.get_polygon_count()==0:
		preparing_survival = false
		boot.close()
		boot = null
		nav_region.queue_free()
		nav_region = null
		set_menu(true)
		push_error("Planes navigation could not be prepared")
		return
	boot.step(0.4,true)
	ensure_weapons()
	boot.step(0.6,true)
	if not _combat_warmed:
		Zombie.preload_models(self,load("res://scripts/planes_waves.gd").KINDS)
		await Zombie.prewarm_visuals(self,false)
		_combat_warmed = true
	_clear_combat()
	progression.reset_run()
	inventory.mushrooms.clear()
	hunting.reset_run()
	brewing.stocks.clear()
	brewing.jobs.clear()
	shooting_range.reset_run()
	cornfield.fires.reset_run()
	if defences:
		defences.close()
		for tower in defences.towers.values(): tower.queue_free()
		defences.towers.clear()
	else:
		defences = DefenceSystem.new()
		add_child(defences)
		defences.setup(self)
	if not field_building:
		field_building = load("res://scripts/planes_building.gd").new()
		add_child(field_building)
		field_building.setup(self)
	defences.process_mode = Node.PROCESS_MODE_PAUSABLE
	field_building.reset_run()
	player.score = 150
	player.max_hp = 100
	player.speed_mul = 1.0
	weapons.damage_mul = 1.0
	weapons.reload_mul = 1.0
	weapons.spread_mul = 1.0
	weapons.mod_owned.clear()
	weapons.mod_loadout.clear()
	for wid in weapons.state:
		weapons.state[wid].def = Weapons.DEFS[wid].duplicate(true)
		weapons.refresh_attachments(wid)
	weapons.grenades_max = 6
	if not skills:
		skills = Skills.new()
		add_child(skills)
	skills.setup(player,weapons,hud,self)
	# Reuse the persistent Forest profile and reward rules for every fresh run.
	if classes: classes.free()
	classes = preload("res://scripts/class_progression.gd").new()
	add_child(classes)
	classes.setup(self)
	if not NetSession.enabled: classes.begin()
	player.set_meta("class_mission_from_start",true)
	if not teleport:
		teleport = AssassinTeleport.new()
		add_child(teleport)
		teleport.setup(self)
	if waves: waves.queue_free()
	waves = load("res://scripts/planes_waves.gd").new()
	waves.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(waves)
	waves.setup(self)
	day_night.night_index = 0
	day_night.blood_moon_active = false
	Zombie.horde_pace = 1.0
	for entry in day_night._lamps:
		if is_instance_valid(entry.light): entry.light.light_energy = entry.energy
	day_night.weather_dim = 1.0
	day_night.overcast = 0.0
	day_night._lamps.clear()
	day_night._flames.clear()
	day_night.setup(self,fill_light)
	day_night.set_process(true)
	_night_flashlight = false
	if not weather:
		weather = load("res://scripts/planes_weather.gd").new()
		weather.process_mode = Node.PROCESS_MODE_PAUSABLE
		add_child(weather)
		weather.setup(self)
	weather.elapsed = 0.0
	weather.force("clear")
	weather.release()
	weapons.process_mode = Node.PROCESS_MODE_PAUSABLE
	weapons.viewmodel.show()
	weapons.viewmodel.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	for id in weapons.unlocked: weapons.unlocked[id] = id in ["pistol", "knife"]
	weapons.set_weapon("pistol")
	weapons.refill_all()
	weapons.grenades = 3
	weapons.update_hud()
	if not quickbar:
		quickbar = preload("res://scripts/quickbar.gd").new()
		add_child(quickbar)
		quickbar.setup(self)
	quickbar.bindings.assign(["pistol","","","","","","","","grenade","knife"])
	# Retries reset run counters and toast timers; saved achievements stay loaded.
	achievements.free()
	achievements = Achievements.new()
	add_child(achievements)
	achievements.setup(player,weapons,hud,self)
	inventory.setup(player,weapons,hud,self)
	inventory.set_process(true)
	inventory.set_process_unhandled_input(true)
	inventory.process_mode = Node.PROCESS_MODE_ALWAYS
	quickbar.refresh()
	hud.show()
	over = false
	victory = false
	survival_active = true
	if expedition:
		expedition.enabled = not "--classic-run" in _flags
		expedition.set_process(expedition.enabled)
		expedition.set_process_unhandled_input(expedition.enabled)
		expedition.reset()
	stats._finished = false
	for key in preload("res://scripts/expedition_checkpoint.gd").STATS: stats.set(key, 0)
	_kills = 0
	player.alive = true
	player.downed = false
	player.self_revives = 1
	player.revive_protection = 0.0
	player.hp = player.max_hp
	hud.set_score(player.score)
	player.regen_timer = 0
	player.regen_mul = float(difficulty.regen)
	player.set_crouching(false,false)
	hud.set_health(player.hp)
	hud.message(Lang.t("Meet Vendor at the fork. He will help you prepare for the first wave."),5)
	set_view(0)
	await get_tree().physics_frame
	preparing_survival = false
	boot.close()
	boot = null
	# Setup can change input and UI state after the initial set_menu(false).
	# Apply the playable state at the actual end of the loading transition.
	set_menu(false)
	print("PLANES_SURVIVAL_READY")

func stop_survival() -> void:
	if preparing_survival or NetSession.enabled: return
	if classes:
		classes.finish()
		classes.free()
		classes = null
	progression.close()
	if field_building: field_building.reset_run()
	if defences:
		defences.close()
		for tower in defences.towers.values(): tower.queue_free()
		defences.towers.clear()
		defences.process_mode = Node.PROCESS_MODE_DISABLED
	day_night.set_process(false)
	day_night.set_time_hours(12.0)
	Zombie.horde_pace = 1.0
	survival_active = false
	if expedition:
		expedition.enabled = false
		expedition.set_process(false)
		expedition.set_process_unhandled_input(false)
		if expedition.book.is_open: expedition.book.close()
		expedition.book.launch.hide()
	over = false
	victory = false
	if waves:
		waves.queue_free()
		waves = null
	_clear_combat()
	if weapons:
		weapons.process_mode = Node.PROCESS_MODE_DISABLED
		weapons.viewmodel.hide()
		weapons.viewmodel.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		weapons._reset_scope()
	if hud:
		hud.hide_overlay()
		hud.refresh_mode()
	player.alive = true
	player.downed = false
	player.hp = player.max_hp
	player.set_crouching(false,false)
	set_menu(false)

func _clear_combat() -> void:
	for enemy in zombies_root.get_children():
		discard_enemy(enemy)
	for child in get_children():
		if child is Grenade or child is Pickup: child.queue_free()
		elif child.get_script()==preload("res://scripts/tower_shell.gd"): child.queue_free()

func discard_enemy(enemy: Node3D) -> void:
	if enemy is Zombie and is_instance_valid(enemy._pool): enemy._pool.queue_free()
	zombies_root.remove_child(enemy)
	enemy.queue_free()

func finish_survival(won: bool) -> void:
	if over: return
	# Exploration encounters can be lethal even after the wave controller was removed.
	# Offer the normal recovery menu without recording an unfinished survival run.
	if not survival_active or waves == null:
		over = true
		victory = false
		set_menu(true)
		return
	if won: campaign.record_victory(expedition.round_limit() if expedition else Campaign.ROUNDS, str(difficulty.name))
	if expedition and expedition.book.is_open: expedition.book.close()
	if classes:
		if not won: stats.record_death(player.peer_id)
		classes.finish()
		CharacterProfile.end_match()
	over = true
	victory = won
	if hud: hud.message(Lang.t("THE PLANES SECURED · %d / %d", [waves.completed, expedition.round_limit() if expedition else Campaign.ROUNDS]) if won else Lang.t("Run ended. Try again or continue exploring."),3600)
	set_menu(true)
	var rank := stats.finish(player.score, waves.completed, str(difficulty.name))
	hud.show_run_summary(stats, player.score, waves.completed, rank, str(difficulty.name))

func alive_zombies() -> int:
	var count := 0
	for enemy in zombies_root.get_children():
		if enemy is Zombie and enemy.alive: count += 1
	return count

func _clear_of_trees(p: Vector2, radius: float) -> bool:
	var limit := radius * radius
	for tree: Array in Map._d.landscape_trees:
		var dx: float = p.x - float(tree[0])
		var dz: float = p.y - float(tree[1])
		if dx * dx + dz * dz < limit: return false
	return true

func _titan_entry_clear(path: PackedVector3Array, start: Vector3) -> bool:
	# The common navmesh is baked for human-sized enemies. A giant needs a
	# wider first corridor or its body collides with trunks before it can move.
	var previous := Vector2(start.x, start.z)
	var remaining := 18.0
	for point in path:
		var next := Vector2(point.x, point.z)
		var length := previous.distance_to(next)
		var covered := minf(length, remaining)
		var samples := maxi(1, ceili(covered / 2.0))
		for i in samples + 1:
			var sample := previous.lerp(next, float(i) / float(samples) * (covered / length if length > 0.001 else 0.0))
			if not _clear_of_trees(sample, 2.5): return false
		remaining -= covered
		if remaining <= 0.0: break
		previous = next
	return true

func spawn_enemy(kind: String, wave_number: int) -> Zombie:
	var focus: Player = player
	if NetSession.is_host():
		var living: Array = NetSession.world.actors.values().filter(func(p): return p.alive and not p.downed)
		if not living.is_empty(): focus = living[_spawn_rng.randi_range(0,living.size()-1)]
	var nav := nav_region.get_navigation_map()
	var target := NavigationServer3D.map_get_closest_point(nav,focus.position)
	var titan := Zombie.is_titan_kind(kind)
	for attempt in (24 if titan else 4):
		var angle := _spawn_rng.randf()*TAU
		if expedition and expedition.enabled and attempt < 2:
			var angles := {"north": -PI*0.5, "south": PI*0.5, "east": 0.0, "west": PI}
			angle = float(angles[expedition.direction])+_spawn_rng.randf_range(-0.6, 0.6)
		var distance := _spawn_rng.randf_range(60,85) if Zombie.is_boss_kind(kind) else _spawn_rng.randf_range(32,52)
		var p := Vector2(focus.position.x,focus.position.z)+Vector2(cos(angle),sin(angle))*distance
		if not Map.BOUNDS.grow(-4).has_point(p) or not preload("res://scripts/planes_boundary.gd").contains(p) or near_building(p): continue
		if titan and not _clear_of_trees(p, 6.0): continue
		if expedition and expedition.enabled and not Zombie.is_boss_kind(kind) and attempt < 2:
			if expedition.profile == 1 and _clear_of_trees(p, 9): continue
			if expedition.profile == 2 and not cornfield.in_corn(p): continue
		var surface := Map.ground_pos(p.x,p.y)
		var at := NavigationServer3D.map_get_closest_point(nav,surface)
		if at.distance_to(surface)>1.5 or at.distance_to(focus.position)<28: continue
		if titan and not _clear_of_trees(Vector2(at.x, at.z), 6.0): continue
		if NetSession.is_host() and NetSession.world.actors.values().any(func(actor): return actor.alive and actor.position.distance_to(at)<28): continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = _nav_shape
		query.transform.origin = at+Vector3.UP*1.5
		query.collision_mask = 1|2
		if not get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): continue
		var path := NavigationServer3D.map_get_path(nav,at,target,true)
		if path.is_empty() or path[-1].distance_to(target)>1.5: continue
		if titan and not _titan_entry_clear(path, at): continue
		var ordinary := not Zombie.is_boss_kind(kind) and not Zombie.is_beast_kind(kind)
		var helmet := ordinary and _spawn_rng.randf() < Waves.armor_chance(wave_number)
		var woodland := not _clear_of_trees(Vector2(at.x, at.z), 8)
		var crop: bool = cornfield.in_corn(Vector2(at.x, at.z))
		return create_enemy(kind,at,wave_number,helmet,ordinary and (woodland or crop))
	return null

func create_enemy(kind: String, at: Vector3, wave_number: int, armored := false, rise := false) -> Zombie:
	var enemy: Zombie = ForestSpirit.new() if kind=="forest_spirit" else Earthworm.new() if Zombie.is_worm_kind(kind) else Titan.new() if Zombie.is_titan_kind(kind) else ZombieBeast.new() if Zombie.is_beast_kind(kind) else Zombie.new()
	var speed := (1.0+(wave_number-1)*0.045)*float(difficulty.speed)
	enemy.setup(kind,player,barricades,EncounterBalance.heavy_speed(speed) if Zombie.is_boss_kind(kind) else speed,_enemy_killed)
	enemy.armored = armored
	enemy.rise_on_spawn = rise
	enemy.hp *= (EncounterBalance.heavy_hp(wave_number,maxi(1,NetSession.roster.size()),Zombie.is_worm_kind(kind)) if Zombie.is_boss_kind(kind) else EncounterBalance.horde_hp(wave_number)*EncounterBalance.party_hp(maxi(1,NetSession.roster.size())))*float(difficulty.hp)
	enemy.max_hp = enemy.hp
	enemy.damage_mul = float(difficulty.dmg)*(EncounterBalance.heavy_damage(wave_number,Zombie.is_worm_kind(kind)) if Zombie.is_boss_kind(kind) else EncounterBalance.party_damage(maxi(1,NetSession.roster.size())))
	enemy.position = at+Vector3.UP*0.15
	zombies_root.add_child(enemy)
	enemy.begin_hunt()
	return enemy

func _enemy_killed(enemy: Zombie) -> void:
	if expedition: expedition.killed(enemy)
	if NetSession.is_client(): return
	if classes: classes.killed(enemy)
	stats.record_kill(enemy)
	if waves: waves.trim_corpses.call_deferred()
	_kills += 1
	var streak := stats.streak()+1
	var bonus := clampf((streak-2)*0.1,0,1)
	var reward := maxi(1,roundi((1.0+bonus)*float(enemy.type.score)*float(difficulty.score)*0.6*(1.5 if enemy.last_headshot else 1.0)))
	if enemy.killer_weapon == "tower": reward = maxi(1,reward/2)
	var killer: Player = NetSession.world.actor(enemy.killer_peer) if NetSession.is_host() else player
	if not killer: killer = player
	killer.add_score(reward)
	stats.kill(enemy.last_headshot,reward)
	killer.hud.score_popup(reward,enemy.last_headshot)
	if streak>=3: killer.hud.streak(streak,roundi(bonus*100))
	achievements.event("kills")
	achievements.event("best_streak",stats.best_streak,true)
	if enemy.last_headshot: achievements.event("headshots")
	if enemy.killer_weapon=="tower": achievements.event("tower_kills")
	if enemy.killer_weapon=="melee" or Weapons.is_melee(enemy.killer_weapon): achievements.event("melee_kills")
	if streak>=10: achievements.event("streak_10")
	if Zombie.is_titan_kind(enemy.net_kind): achievements.event("titans")
	progression.peer_event(killer.peer_id,"kills")
	if enemy.last_headshot: progression.peer_event(killer.peer_id,"headshots")
	if enemy.net_kind == "brute": progression.peer_event(killer.peer_id,"brutes")
	# Modest scavenged ammunition supplements merchant supplies.
	if _kills%8==0:
		var drop := Pickup.new()
		drop.setup("ammo")
		drop._light.visible = false
		add_child(drop)
		drop.position = Map.ground_pos(enemy.position.x,enemy.position.z)

func ensure_weapons() -> void:
	if not weapons:
		weapons = Weapons.new()
		add_child(weapons)
		weapons.setup(player,hud,zombies_root)

	weapons.process_mode = Node.PROCESS_MODE_PAUSABLE
	weapons.viewmodel.show()
	weapons.viewmodel.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

func ensure_navigation() -> void:
	while _preparing_navigation: await get_tree().process_frame
	if nav_region: return
	_preparing_navigation = true
	nav_region = await load("res://scripts/planes_navigation.gd").prepare(self)
	_preparing_navigation = false

func spawn_zombie(kind: String, p: Vector2, _speed: float, _lane := "", _distance := 0.0, armor := -1, rise := false) -> bool:
	if not Map.BOUNDS.grow(-5).has_point(p) or not preload("res://scripts/planes_boundary.gd").contains(p) or near_building(p) or zombies_root.get_child_count()>=36: return false
	await ensure_navigation()
	if over or _leaving or zombies_root.get_child_count()>=36: return false
	var ground := Map.ground_pos(p.x,p.y)
	var at := NavigationServer3D.map_get_closest_point(nav_region.get_navigation_map(),ground)
	if at.distance_to(ground)>2: return false
	# Cheat entry may precede survival's normal preload. Prepare the shared rig,
	# gore surfaces and clip metrics before its first live instance is created.
	Zombie.preload_models(self,[kind])
	create_enemy(kind,at,maxi(1,waves.wave if waves else 1),armor==1,rise)
	return true

func _update_music() -> void:
	if not music or "--no-music" in _flags: return
	if over:
		music.horde = 0.0
		music.play("morning" if victory else "gameover")
	elif survival_active and waves and waves.phase in ["spawning", "finale"]:
		music.fight(waves.is_boss_fight())
		music.horde = clampf(float(alive_zombies())/24.0,0,1)
	else:
		music.horde = 0.0
		music.play(music.intermission_track(day_night.clock_seconds/3600.0))

func should_play_intro() -> bool: return false

func _on_start(_play_intro := false) -> void:
	if NetSession.enabled and not NetSession._applying:
		NetSession.start_game()
		return
	started = false
	classes.begin()
	started = true
	classes.set_process(true)
	waves.set_process(not NetSession.is_client())
	day_night.set_process(not NetSession.is_client())
	set_menu(false)

func open_coop_lobby() -> void:
	if NetSession.enabled:
		hud.show_tab("multiplayer")
		return
	get_tree().set_meta("planes_lobby",true)
	BootScreen.cover(get_tree())
	get_tree().paused = false
	get_tree().reload_current_scene()

func player_down(_actor: Player) -> void:
	if NetSession.is_host(): NetSession.world.check_team()
