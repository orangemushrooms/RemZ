extends Hud
## Small combat HUD using the shared player/weapon API, without Forest menus.
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
	cross.visible = game.player.active and game.player.alive
	if game.player.downed:
		status_text.text = Lang.t("Downed: hold E to revive")+"  %ds" % ceili(game.player.down_time)
	else: status_text.text = Lang.t(game.weather.label()) if game.weather else ""

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
