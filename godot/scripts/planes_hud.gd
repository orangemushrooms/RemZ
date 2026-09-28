extends Hud
## Planes readouts with the same pause/settings shell used by the Forest HUD.
var cross: Label
var health_text: Label
var status_text: Label
var flash_panel: ColorRect
var remaining_message := 0.0
var hit_time := 0.0
var flash_time := 0.0

func _ready() -> void:
	layer = 2
	var container := Control.new()
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root = container
	health_text = _text(container,Vector2(28,-112),Control.PRESET_BOTTOM_LEFT,20)
	hp_bar = ProgressBar.new()
	container.add_child(hp_bar)
	hp_bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	hp_bar.position = Vector2(28,-124)
	hp_bar.size = Vector2(180,10)
	hp_bar.show_percentage = false
	hp_bar.max_value = 100
	hp_bar.add_theme_stylebox_override("fill",_flat(Color(0.7,0.07,0.1),4))
	hp_bar.add_theme_stylebox_override("background",_flat(Color(1,1,1,0.12),4))
	ammo_label = _text(container,Vector2(28,-86),Control.PRESET_BOTTOM_LEFT,20)
	weapon_label = _text(container,Vector2(28,-62),Control.PRESET_BOTTOM_LEFT,14)
	wave_label = _text(container,Vector2(-135,60),Control.PRESET_CENTER_TOP,23)
	wave_info = _text(container,Vector2(-135,88),Control.PRESET_CENTER_TOP,17)
	wave_bar = ProgressBar.new()
	container.add_child(wave_bar)
	wave_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	wave_bar.position = Vector2(-135,114)
	wave_bar.size = Vector2(220,4)
	wave_bar.max_value = 1.0
	wave_bar.show_percentage = false
	wave_bar.add_theme_stylebox_override("fill",_flat(Color(0.85,0.3,0.22),2))
	wave_bar.add_theme_stylebox_override("background",_flat(Color(1,1,1,0.1),2))
	msg_label = _text(container,Vector2(-340,130),Control.PRESET_CENTER_TOP,18)
	msg_label.custom_minimum_size.x = 680
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_text = _text(container,Vector2(28,56),Control.PRESET_TOP_LEFT,16)
	fps_label = _text(container,Vector2(-120,158),Control.PRESET_TOP_RIGHT,14)
	cross = _text(container,Vector2(-6,-12),Control.PRESET_CENTER,20)
	cross.text = "+"
	flash_panel = ColorRect.new()
	flash_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_panel.color = Color(0.5,0,0,0)
	container.add_child(flash_panel)
	prompt_label = Label.new()
	prompt_label.hide()
	container.add_child(prompt_label)
	prompt_card = InteractionPrompt.new()
	container.add_child(prompt_card)
	# world clock
	var clock := _panel(container, Control.PRESET_TOP_RIGHT, Vector2(-16, 16))
	clock.custom_minimum_size.x = 156
	clock.add_child(_label("LOCAL TIME", 10))
	var clock_row := HBoxContainer.new()
	clock_row.add_theme_constant_override("separation", 16)
	clock.add_child(clock_row)
	clock_label = _label("06:00", 30)
	clock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock_row.add_child(clock_label)
	clock_phase = _label("Morning", 13)
	clock_phase.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clock_row.add_child(clock_phase)
	clock_progress = ProgressBar.new()
	clock_progress.custom_minimum_size.y = 3
	clock_progress.max_value = 24.0 * 3600.0
	clock_progress.show_percentage = false
	clock_progress.add_theme_stylebox_override("background", _flat(Color(1.0, 1.0, 1.0, 0.1), 0))
	clock_progress.add_theme_stylebox_override("fill", _flat(Color(0.94, 0.67, 0.34), 0))
	clock.add_child(clock_progress)
	clock_rate = _label(Lang.t("%d× · game time", [96]), 11)
	clock_rate.modulate.a = 0.6
	clock.add_child(clock_rate)
	weather_label = _label("", 12, Color(0.75, 0.85, 1.0))
	weather_label.visible = false
	clock.add_child(weather_label)

	downed_panel = PanelContainer.new()
	container.add_child(downed_panel)
	downed_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	downed_panel.offset_left = -260
	downed_panel.offset_right = 260
	downed_panel.offset_top = -286
	downed_panel.offset_bottom = -196
	downed_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var down_style := StyleBoxFlat.new()
	down_style.bg_color = Color(0.14, 0.01, 0.01, 0.92)
	down_style.border_color = Color(1, 0.2, 0.15)
	down_style.set_border_width_all(2)
	down_style.set_corner_radius_all(8)
	down_style.set_content_margin_all(10)
	downed_panel.add_theme_stylebox_override("panel", down_style)
	var down_box := VBoxContainer.new()
	down_box.add_theme_constant_override("separation", 4)
	downed_panel.add_child(down_box)
	downed_text = _label("", 16, Color(1, 0.35, 0.3))
	downed_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	down_box.add_child(downed_text)
	bleed_bar = ProgressBar.new()
	bleed_bar.custom_minimum_size = Vector2(480, 6)
	bleed_bar.max_value = 1.0
	bleed_bar.show_percentage = false
	bleed_bar.add_theme_stylebox_override("fill", _flat(Color(0.9, 0.12, 0.1), 3))
	bleed_bar.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.12), 3))
	down_box.add_child(bleed_bar)
	hold_bar = ProgressBar.new()
	hold_bar.custom_minimum_size = Vector2(480, 6)
	hold_bar.max_value = 1.0
	hold_bar.show_percentage = false
	hold_bar.add_theme_stylebox_override("fill", _flat(GOLD, 3))
	hold_bar.add_theme_stylebox_override("background", _flat(Color(1, 1, 1, 0.12), 3))
	down_box.add_child(hold_bar)
	downed_panel.hide()
	set_health(100)
	_build_overlay()

	_tab_buttons["achievements"].hide()
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

func _text(parent: Control, at: Vector2, anchor: Control.LayoutPreset, pixels: int) -> Label:
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	label.set_anchors_and_offsets_preset(anchor)
	label.grow_horizontal = Control.GROW_DIRECTION_END
	label.grow_vertical = Control.GROW_DIRECTION_END
	label.offset_left = at.x
	label.offset_right = at.x
	label.offset_top = at.y
	label.offset_bottom = at.y
	label.add_theme_font_size_override("font_size",pixels)
	label.add_theme_color_override("font_shadow_color",Color.BLACK)
	label.add_theme_constant_override("shadow_offset_y",1)
	return label

func _process(delta: float) -> void:
	remaining_message = maxf(0,remaining_message-delta)
	msg_label.visible = remaining_message>0
	hit_time = maxf(0,hit_time-delta)
	cross.modulate = Color(1,0.35,0.2) if hit_time>0 else Color.WHITE
	flash_time = maxf(0,flash_time-delta)
	flash_panel.color.a = flash_time*0.8
	if not game or not game.player: return
	fps_label.visible = game.settings.show_fps
	fps_label.text = "%d FPS" % Engine.get_frames_per_second()
	refresh_mode()
	weather_label.text = game.weather.label() if game.weather else ""
	var watching: String = NetSession.world.spectating_name() if NetSession.enabled and NetSession.world else ""
	set_downed(game.player.downed or not watching.is_empty(),game.player.down_time,game.player.hold_fraction(),game.player.self_revives>0,NetSession.enabled,watching,not game.player.alive)
	weather_label.visible = not weather_label.text.is_empty()
	if game.defences: _update_prompt()
	else:
		prompt_card.visible = game.player.active and not prompt_label.text.is_empty()
		if prompt_card.visible: prompt_card.refresh(prompt_label.text)
	if game.player.downed:
		status_text.text = Lang.t("Downed: hold E to revive")+"  %ds" % ceili(game.player.down_time)
	else: status_text.text = "%d R  |  " % game.player.score + (Lang.text(game.weather.label()) if game.weather else "")

func refresh_mode() -> void:
	var armed: bool = game.weapons!=null and game.weapons.process_mode!=Node.PROCESS_MODE_DISABLED
	cross.visible = armed and game.player.active and game.player.alive and not game.player.downed and not game.player.spectating
	for label in [health_text,ammo_label,weapon_label]: label.visible = armed
	hp_bar.visible = armed
	wave_label.visible = game.survival_active
	wave_info.visible = game.survival_active

func set_health(value: float) -> void:
	health_text.text = Lang.t("Health: %d",[maxi(0,ceili(value))])
	hp_bar.value = value
func set_score(_value: int) -> void: pass
func set_wave_progress(remaining: int, total: int) -> void:
	super.set_wave_progress(remaining,total)
func set_reload(remaining: float, _duration: float) -> void:
	if remaining>0: ammo_label.text = Lang.t("Reloading ...")
func set_charge(_text: String, _value: float, _colour: Color = Color.WHITE) -> void: pass
func message(text: String, seconds: float = 2.5) -> void:
	msg_label.text = text
	remaining_message = seconds
func hitmarker(_head: bool) -> void: hit_time = 0.15
func damage_flash(_angle: float = NAN) -> void: flash_time = 0.3
