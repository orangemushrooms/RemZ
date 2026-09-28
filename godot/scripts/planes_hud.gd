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
	ammo_label = _text(container,Vector2(28,-86),Control.PRESET_BOTTOM_LEFT,20)
	weapon_label = _text(container,Vector2(28,-62),Control.PRESET_BOTTOM_LEFT,14)
	wave_label = _text(container,Vector2(-135,60),Control.PRESET_CENTER_TOP,23)
	wave_info = _text(container,Vector2(-135,88),Control.PRESET_CENTER_TOP,17)
	msg_label = _text(container,Vector2(-340,130),Control.PRESET_CENTER_TOP,18)
	msg_label.custom_minimum_size.x = 680
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_text = _text(container,Vector2(28,56),Control.PRESET_TOP_LEFT,16)
	fps_label = _text(container,Vector2(-120,28),Control.PRESET_TOP_RIGHT,14)
	cross = _text(container,Vector2(-6,-12),Control.PRESET_CENTER,20)
	cross.text = "+"
	flash_panel = ColorRect.new()
	flash_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_panel.color = Color(0.5,0,0,0)
	container.add_child(flash_panel)
	set_health(100)
	_build_overlay()
	_tab_buttons["multiplayer"].hide()
	_tab_buttons["achievements"].hide()
	game.settings.add_controls(settings_box, false)
	set_difficulties(GameSettings.DIFFICULTIES,game.settings.difficulty,func(index: int):
		game.settings.difficulty = index
		game.difficulty = GameSettings.DIFFICULTIES[index]
		game.settings._changed())
	start_pressed.connect(func():
		if game.over and game.survival_active: game.start_survival()
		elif game.over: game.stop_survival()
		else: game.set_menu(false))
	main_menu_pressed.connect(game.return_to_map.bind(false))
	overlay.hide()
	refresh_mode()

func _build_multiplayer_tab() -> void: pass
func _build_character_widgets() -> void: pass

func _build_briefing(box: VBoxContainer) -> void:
	_briefing_box = box
	overlay_text = _label("",15)
	overlay_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(overlay_text)
	_pause_stats = _label("",14,MUTED)
	box.add_child(_pause_stats)
	box.add_child(_heading("THE PLANES"))
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
	for pair in [["WASD","Move"],["Mouse","Look around"],["Shift","Sprint"],["Hold Ctrl","Crouch / aim more precisely"],["Space","Jump"],["Left click","Shoot / strike"],["Right click","Aim (ADS)"],["R","Reload"],["1 / 2 / 3","Pistol / AK-47 / Shotgun"],["Mouse wheel","Switch weapon"],["G","Throw grenade"],["H","Melee / rifle butt"],["Enter","Next wave now"],["M","Minimap large / small"],["F","Flashlight"],["Ctrl+Shift+D","CHEAT MENU"],["Esc","Pause / menu"],["F11","Fullscreen"]]:
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
	if game.player.downed:
		status_text.text = Lang.t("Downed: hold E to revive")+"  %ds" % ceili(game.player.down_time)
	else: status_text.text = Lang.t(game.weather.label()) if game.weather else ""

func refresh_mode() -> void:
	var armed: bool = game.weapons!=null and game.weapons.process_mode!=Node.PROCESS_MODE_DISABLED
	cross.visible = armed and game.player.active and game.player.alive
	for label in [health_text,ammo_label,weapon_label]: label.visible = armed
	wave_label.visible = game.survival_active
	wave_info.visible = game.survival_active

func set_health(value: float) -> void:
	health_text.text = Lang.t("Health: %d",[maxi(0,ceili(value))])
func set_score(_value: int) -> void: pass
func set_wave_progress(_remaining: int, _total: int) -> void: pass
func set_reload(remaining: float, _duration: float) -> void:
	if remaining>0: ammo_label.text = Lang.t("Reloading ...")
func set_charge(_text: String, _value: float, _colour: Color = Color.WHITE) -> void: pass
func message(text: String, seconds: float = 2.5) -> void:
	msg_label.text = text
	remaining_message = seconds
func hitmarker(_head: bool) -> void: hit_time = 0.15
func damage_flash(_angle: float = NAN) -> void: flash_time = 0.3
