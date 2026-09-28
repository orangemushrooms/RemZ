extends Hud
## Shared Forest HUD, with the field map briefing and survival actions.
func _ready() -> void:
	super._ready()
	# Keep exactly one map: Forest's HUD creates its own default minimap.
	minimap.free()
	minimap = game.minimap
	game.settings.add_controls(settings_box, false)
	set_difficulties(GameSettings.DIFFICULTIES,game.settings.difficulty,func(index: int):
		game.settings.difficulty = index
		game.difficulty = GameSettings.DIFFICULTIES[index]
		game.settings._changed())
	start_pressed.connect(func():
		if NetSession.enabled:
			if game.over and NetSession.is_host(): NetSession.restart()
			elif not game.started: NetSession.start_game()
			elif not game.over: game.set_menu(false)
		elif game.over and game.survival_active: game.start_survival()
		elif game.over: game.stop_survival()
		else: game.set_menu(false))
	main_menu_pressed.connect(game.return_to_map.bind(false))
	map_selected.connect(func(id: String):
		if NetSession.enabled:
			if id=="planes": NetSession.start_game()
			else: NetSession.select_region(id)
		else: game.start_survival())
	overlay.hide()
	refresh_mode()


func _build_multiplayer_tab() -> void: super._build_multiplayer_tab()
func _fill_pause_stats() -> void:
	if not game.waves:
		if _pause_stats: _pause_stats.text = ""
		return
	super._fill_pause_stats()
func _build_character_widgets() -> void:
	var character_hud = preload("res://scripts/character_hud.gd").new()
	character_hud.name = "CharacterHud"
	_root.add_child(character_hud)
	character_hud.setup(self)

func _build_briefing(box: VBoxContainer) -> void:
	_briefing_box = box
	overlay_text = _label("",15)
	overlay_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(overlay_text)
	_pause_stats = _label("",14,MUTED)
	box.add_child(_pause_stats)
	box.add_child(_heading("THE PLANES"))
	var coop := _menu_button("Multiplayer",false)
	coop.pressed.connect(game.open_coop_lobby)
	box.add_child(coop)
	for spec in [["Start 25-wave survival",4],["Back to exploration",5],["Map selection",3]]:
		var action: int = spec[1]
		var button := _menu_button(spec[0],false)
		button.pressed.connect(func():
			if action==4: game.start_survival()
			elif action==5: game.stop_survival()
			else: game.return_to_map())
		box.add_child(button)
		game._menu_actions[action] = button

func _build_controls(box: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation",22)
	grid.add_theme_constant_override("v_separation",8)
	box.add_child(grid)
	for pair in [["WASD","Move"],["Mouse","Look around"],["Shift","Sprint"],["Hold Ctrl","Crouch / aim more precisely"],["Space","Jump"],["Left click","Shoot / strike"],["Right click","Aim (ADS)"],["R","Reload"],["1 - 9 / 0","Quick slots"],["Mouse wheel","Switch weapon"],["G","Throw grenade"],["H","Melee / rifle butt"],["Enter","Next wave now"],["Q","Quests"],["J","Field journal"],["I","Inventory"],["B","Portable fortification kits"],["T","Tower planner"],["E","Trade / collect / repair"],["M","Minimap large / small"],["F","Flashlight"],["Ctrl+Shift+D","CHEAT MENU"],["Esc","Pause / menu"],["F11","Fullscreen"]]:
		grid.add_child(_label(pair[0],14,GOLD))
		grid.add_child(_label(pair[1],14))

func _fit_menu_card() -> void:
	if not is_instance_valid(_card): return
	_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	var natural := _card.get_combined_minimum_size()
	var available := (get_viewport().get_visible_rect().size-Vector2(32,32)).max(Vector2.ONE)
	var factor := minf(1.0,minf(available.x/natural.x,available.y/natural.y))
	_card.size = natural
	_card.scale = Vector2.ONE*factor
	_card.position = (get_viewport().get_visible_rect().size-natural*factor)*0.5

func _process(delta: float) -> void:
	if not game or not game.player: return
	super._process(delta)
	fps_label.visible = game.settings.show_fps
	set_weather(game.weather.label() if game.weather else "")
	var watching: String = NetSession.world.spectating_name() if NetSession.enabled and NetSession.world else ""
	set_downed(game.player.downed or not watching.is_empty(),game.player.down_time,game.player.hold_fraction(),game.player.self_revives>0,NetSession.enabled,watching,not game.player.alive)
	refresh_mode()

func _update_prompt() -> void:
	if game and game.defences: super._update_prompt()

func refresh_mode() -> void:
	hp_bar.get_parent().visible = game.survival_active
	ammo_label.get_parent().visible = game.survival_active
	for part in crosshair_parts: part.visible = game.survival_active and game.player.active
	wave_label.visible = game.survival_active
	wave_info.visible = game.survival_active
	wave_bar.visible = game.survival_active
	hut_label.hide()
	hut_alarm.hide()
