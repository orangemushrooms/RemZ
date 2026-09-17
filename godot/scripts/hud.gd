# In-game HUD and the start / pause / game-over overlay.
class_name Hud
extends CanvasLayer

signal start_pressed

var hp_bar: ProgressBar
var score_label: Label
var ammo_label: Label
var weapon_label: Label
var wave_label: Label
var wave_info: Label
var msg_label: Label
var prompt_label: Label
var damage_rect: ColorRect
var overlay: Control
var overlay_title: Label
var overlay_text: Label
var overlay_button: Button
var overlay_status: Label
var _msg_timer := 0.0
var _damage_t := 0.0
var _hit_t := 0.0
var hit_marks: Array = []

func _ready() -> void:
	layer = 10
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	damage_rect = ColorRect.new()
	damage_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	damage_rect.color = Color(0.7, 0.07, 0.1, 0.0)
	damage_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(damage_rect)

	# crosshair
	for size in [Vector2(2, 18), Vector2(18, 2)]:
		var c := ColorRect.new()
		c.color = Color(1, 1, 1, 0.85)
		c.custom_minimum_size = size
		c.set_anchors_preset(Control.PRESET_CENTER)
		c.position = -size / 2.0
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(c)

	# hitmarker: four short diagonal ticks around the crosshair
	for k in 4:
		var m := ColorRect.new()
		m.color = Color(1, 1, 1, 0.0)
		m.custom_minimum_size = Vector2(10, 2)
		m.set_anchors_preset(Control.PRESET_CENTER)
		m.pivot_offset = Vector2(5, 1)
		m.position = Vector2(-5, -1) + Vector2(cos(k * PI / 2.0 + PI / 4.0), sin(k * PI / 2.0 + PI / 4.0)) * 14.0
		m.rotation = k * PI / 2.0 + PI / 4.0
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(m)
		hit_marks.append(m)
	# stats bottom-left
	var stats := _panel(root, Control.PRESET_BOTTOM_LEFT, Vector2(16, -16))
	stats.add_child(_label("Leben", 14))
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(180, 12)
	hp_bar.show_percentage = false
	hp_bar.max_value = 100
	hp_bar.value = 100
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.7, 0.07, 0.1)
	sb.corner_radius_top_left = 4; sb.corner_radius_top_right = 4; sb.corner_radius_bottom_left = 4; sb.corner_radius_bottom_right = 4
	hp_bar.add_theme_stylebox_override("fill", sb)
	var sbg := StyleBoxFlat.new()
	sbg.bg_color = Color(1, 1, 1, 0.12)
	sbg.corner_radius_top_left = 4; sbg.corner_radius_top_right = 4; sbg.corner_radius_bottom_left = 4; sbg.corner_radius_bottom_right = 4
	hp_bar.add_theme_stylebox_override("background", sbg)
	stats.add_child(hp_bar)
	score_label = _label("Punkte 0", 15)
	stats.add_child(score_label)

	# ammo bottom-right
	var ammo := _panel(root, Control.PRESET_BOTTOM_RIGHT, Vector2(-16, -16))
	ammo_label = _label("12 / 72", 22)
	ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo.add_child(ammo_label)
	weapon_label = _label("Pistole", 12)
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.modulate.a = 0.7
	ammo.add_child(weapon_label)

	# wave top-center
	var wave := _panel(root, Control.PRESET_CENTER_TOP, Vector2(0, 16))
	wave_label = _label("Welle 1", 18)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.28))
	wave.add_child(wave_label)
	wave_info = _label("Bereit", 14)
	wave_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wave.add_child(wave_info)

	# message center, prompt lower center
	msg_label = _label("", 24)
	msg_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_label.set_anchors_preset(Control.PRESET_CENTER)
	msg_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	msg_label.position.y = -80
	msg_label.modulate.a = 0.0
	root.add_child(msg_label)
	prompt_label = _label("", 15)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_label.position.y = -170
	root.add_child(prompt_label)

	# overlay
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.02, 0.03, 0.92)
	overlay.add_child(dim)
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.043, 0.06, 0.08)
	cs.border_color = Color(1, 1, 1, 0.15)
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(10)
	cs.content_margin_left = 36; cs.content_margin_right = 36; cs.content_margin_top = 28; cs.content_margin_bottom = 28
	card.add_theme_stylebox_override("panel", cs)
	overlay.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(520, 0)
	card.add_child(v)
	overlay_title = _label("BIRKENHOF", 36)
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.28))
	v.add_child(overlay_title)
	var sub := _label("NACHT AM WALDRAND", 12)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate.a = 0.6
	v.add_child(sub)
	overlay_text = _label("Der Wendeplatz oben am Birkenhof ist der letzte sichere Ort. Die Zombies kommen den Weg herauf und aus dem Wald. Halte die Barrikaden, überlebe die Wellen.", 15)
	overlay_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(overlay_text)
	var keys := _label("WASD bewegen · Shift sprinten · Maus zielen und schiessen · R nachladen\n1 / 2 Pistole / Schrotflinte · E Barrikade bauen · F Taschenlampe · Esc Pause", 13)
	keys.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	keys.modulate.a = 0.85
	v.add_child(keys)
	overlay_button = Button.new()
	overlay_button.text = "Spiel starten"
	overlay_button.custom_minimum_size = Vector2(0, 44)
	overlay_button.pressed.connect(func(): start_pressed.emit())
	v.add_child(overlay_button)
	overlay_status = _label("", 12)
	overlay_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_status.modulate.a = 0.6
	v.add_child(overlay_status)

func _panel(parent: Control, preset: int, offset: Vector2) -> VBoxContainer:
	var p := PanelContainer.new()
	p.set_anchors_preset(preset)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.45)
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14; sb.content_margin_right = 14; sb.content_margin_top = 8; sb.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	p.position += offset
	match preset:
		Control.PRESET_BOTTOM_LEFT, Control.PRESET_BOTTOM_RIGHT:
			p.grow_vertical = Control.GROW_DIRECTION_BEGIN
	match preset:
		Control.PRESET_BOTTOM_RIGHT:
			p.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		Control.PRESET_CENTER_TOP:
			p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	return v

func _label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _process(delta: float) -> void:
	if _msg_timer > 0.0:
		_msg_timer -= delta
		if _msg_timer <= 0.0:
			var tw := create_tween()
			tw.tween_property(msg_label, "modulate:a", 0.0, 0.3)
	if _damage_t > 0.0:
		_damage_t -= delta
		damage_rect.color.a = clampf(_damage_t * 3.0, 0.0, 0.45)
	if _hit_t > 0.0:
		_hit_t -= delta
		if _hit_t <= 0.0:
			for m in hit_marks:
				m.color.a = 0.0

func set_health(v: float) -> void:
	hp_bar.value = v

func set_score(v: int) -> void:
	score_label.text = "Punkte %d" % v

func set_ammo(now: int, reserve: int, weapon: String) -> void:
	ammo_label.text = "%d / %d" % [now, reserve]
	weapon_label.text = weapon

func set_wave(n: int, info: String) -> void:
	wave_label.text = "Welle %d" % n
	wave_info.text = info

func message(text: String, seconds: float = 2.5) -> void:
	msg_label.text = text
	msg_label.modulate.a = 1.0
	_msg_timer = seconds

func set_prompt(text: String) -> void:
	prompt_label.text = text

func hitmarker(head: bool) -> void:
	_hit_t = 0.12
	for m in hit_marks:
		m.color = Color(1.0, 0.25, 0.2, 1.0) if head else Color(1, 1, 1, 1)

func damage_flash() -> void:
	_damage_t = 0.25

func show_overlay(title: String, text: String, button: String, status: String = "") -> void:
	overlay_title.text = title
	overlay_text.text = text
	overlay_button.text = button
	overlay_status.text = status
	overlay.visible = true

func hide_overlay() -> void:
	overlay.visible = false
