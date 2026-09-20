extends CanvasLayer

var main: Node
var is_open := false
var panel: Control
var status: Label
var skip_button: Button
var secret_toggle: CheckButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 30
	panel = Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.hide()
	add_child(panel)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.65)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var box := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Hud.INK
	style.border_color = Hud.GOLD
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(24)
	box.add_theme_stylebox_override("panel", style)
	center.add_child(box)
	var items := VBoxContainer.new()
	items.add_theme_constant_override("separation", 16)
	box.add_child(items)
	var title := Label.new()
	title.text = "CHEATMENÜ"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Hud.GOLD)
	items.add_child(title)
	status = Label.new()
	items.add_child(status)
	var explanation := Label.new()
	explanation.text = "Alle Zombies sterben. Die nächste Welle startet sofort."
	items.add_child(explanation)
	skip_button = Button.new()
	skip_button.text = "Welle überspringen"
	skip_button.custom_minimum_size.y = 44
	skip_button.pressed.connect(_skip_wave)
	items.add_child(skip_button)
	secret_toggle = CheckButton.new()
	secret_toggle.text = "Geheimen Händler auf der Minimap anzeigen"
	secret_toggle.toggled.connect(func(value: bool): main.hud.minimap.reveal_secret = value)
	items.add_child(secret_toggle)
	var back := Button.new()
	back.text = "Schliessen (Esc / Strg+Shift+D)"
	back.pressed.connect(close)
	items.add_child(back)

func open() -> void:
	if not main.started or main.over or not main.player.alive or not main.player.active or main.get_tree().paused:
		return
	is_open = true
	status.text = "Aktuelle Welle: %d" % main.waves.wave
	if NetSession.is_client(): status.text += " · Nur der Host kann Wellen überspringen."
	skip_button.disabled = NetSession.is_client()
	secret_toggle.set_pressed_no_signal(main.hud.minimap.reveal_secret)
	panel.show()
	main.player.active = false
	get_tree().paused = not NetSession.enabled
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	if not is_open: return
	is_open = false
	panel.hide()
	get_tree().paused = false
	main.player.active = main.player.alive and not main.over
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if main.player.active else Input.MOUSE_MODE_VISIBLE

func _skip_wave() -> void:
	if not is_open or NetSession.is_client(): return
	close()
	main.waves.skip_current_wave()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_D and event.ctrl_pressed and event.shift_pressed:
		if is_open: close()
		else: open()
		get_viewport().set_input_as_handled()
	elif is_open and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
	elif is_open and event is InputEventKey:
		# Keep gameplay shortcuts out of this modal; GUI navigation still works.
		if event.keycode not in [KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
			get_viewport().set_input_as_handled()
