extends CanvasLayer

var main: Node
var is_open := false
var panel: Control
var status: Label
var skip_button: Button
var points_button: Button
var secret_toggle: CheckButton
var wanderer_toggle: CheckButton
var weapon_buttons: Dictionary = {}   # weapon id -> Button
var all_weapons_button: Button
var weapon_note: Label

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
	# Left: points, waves and map reveals. Right: every weapon of Weapons.ORDER.
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	items.add_child(columns)
	var general := VBoxContainer.new()
	general.add_theme_constant_override("separation", 16)
	columns.add_child(general)
	points_button = Button.new()
	points_button.text = "+1000 R"
	points_button.icon = preload("res://scripts/currency.gd").ICON
	points_button.add_theme_constant_override("icon_max_width", 32)
	points_button.custom_minimum_size.y = 44
	points_button.pressed.connect(_add_points)
	general.add_child(points_button)
	var explanation := Label.new()
	explanation.text = "Alle Zombies sterben. Die nächste Welle startet sofort."
	general.add_child(explanation)
	skip_button = Button.new()
	skip_button.text = "Welle überspringen"
	skip_button.custom_minimum_size.y = 44
	skip_button.pressed.connect(_skip_wave)
	general.add_child(skip_button)
	secret_toggle = CheckButton.new()
	secret_toggle.text = "Geheimen Händler auf der Minimap anzeigen"
	secret_toggle.toggled.connect(func(value: bool): main.hud.minimap.reveal_secret = value)
	general.add_child(secret_toggle)
	wanderer_toggle = CheckButton.new()
	wanderer_toggle.text = "Wanderhändler auf der Karte anzeigen (ab Welle 5)"
	wanderer_toggle.toggled.connect(func(value: bool): main.hud.minimap.reveal_wanderer = value)
	general.add_child(wanderer_toggle)
	columns.add_child(VSeparator.new())
	var arsenal := VBoxContainer.new()
	arsenal.add_theme_constant_override("separation", 10)
	columns.add_child(arsenal)
	var heading := Label.new()
	heading.text = "Waffe holen · volles Magazin und volle Reserve"
	arsenal.add_child(heading)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	arsenal.add_child(grid)
	for id: String in Weapons.ORDER:
		var button := Button.new()
		button.text = str(Weapons.DEFS[id].name)
		button.icon = ItemIcons.texture(id)
		button.add_theme_constant_override("icon_max_width", 44)
		button.add_theme_font_size_override("font_size", 14)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(196, 40)
		button.pressed.connect(_give_weapon.bind(id))
		grid.add_child(button)
		weapon_buttons[id] = button
	all_weapons_button = Button.new()
	all_weapons_button.text = "Alle Waffen mit voller Munition"
	all_weapons_button.custom_minimum_size.y = 40
	all_weapons_button.pressed.connect(_give_all_weapons)
	arsenal.add_child(all_weapons_button)
	weapon_note = Label.new()
	weapon_note.add_theme_color_override("font_color", Hud.GOLD)
	arsenal.add_child(weapon_note)
	var back := Button.new()
	back.text = "Schliessen (Esc / Strg+Shift+D)"
	back.pressed.connect(close)
	items.add_child(back)

func open() -> void:
	if not main.started or main.over or not main.player.alive or not main.player.active or main.get_tree().paused:
		return
	is_open = true
	_update_status()
	skip_button.disabled = NetSession.is_client()
	points_button.disabled = NetSession.is_client()
	all_weapons_button.disabled = NetSession.is_client()
	weapon_note.text = ""
	_refresh_weapons()
	secret_toggle.set_pressed_no_signal(main.hud.minimap.reveal_secret)
	wanderer_toggle.set_pressed_no_signal(main.hud.minimap.reveal_wanderer)
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

func _update_status() -> void:
	status.text = "Aktuelle Welle: %d · Rem Dollars: %d" % [main.waves.wave, main.player.score]
	if NetSession.is_client(): status.text += "\nRem Dollars, Wellen- und Waffen-Cheats sind nur für den Host verfügbar."

func _add_points() -> void:
	if not is_open or NetSession.is_client() or main.over or not main.player.alive: return
	main.player.add_score(1000)
	_update_status()

# The chosen weapon goes straight into the hands (unless a tower is manned); the menu stays open so
# several can be fetched in a row. In co-op the host owns every loadout, so clients cannot use it.
func _give_weapon(id: String) -> void:
	if not is_open or NetSession.is_client() or main.over or not main.player.alive: return
	var w: Weapons = main.weapons
	fill_weapon(w, id)
	if not main.player.mounted_tower: w.set_weapon(id)
	w.update_hud()
	Sfx.event(self, main.player.peer_id, "weapon_pickup")
	var st: Dictionary = w.state[id]
	weapon_note.text = "Erhalten: " + str(Weapons.DEFS[id].name) + ("" if Weapons.is_melee(id) else " · %d + %d Schuss" % [st.ammo, st.reserve])
	_refresh_weapons()

func _give_all_weapons() -> void:
	if not is_open or NetSession.is_client() or main.over or not main.player.alive: return
	var w: Weapons = main.weapons
	for id: String in Weapons.ORDER: fill_weapon(w, id)
	w.update_hud()
	Sfx.event(self, main.player.peer_id, "weapon_pickup")
	weapon_note.text = "Alle %d Waffen freigeschaltet und voll geladen." % Weapons.ORDER.size()
	_refresh_weapons()

# Owned, with a full magazine (mods included) and the reserve at its limit - the same "full" as the
# vendors' autorefill. A plasma rifle also gets a cold barrel, or its fresh cells would sit locked.
static func fill_weapon(w: Weapons, id: String) -> void:
	w.unlock(id)
	if Weapons.is_melee(id): return
	var st: Dictionary = w.state[id]
	st.ammo = int(st.def.mag)
	st.reserve = w.reserve_limit(id)
	st.reloading = 0.0
	if st.has("heat"): st.heat = 0.0
	if st.has("vent"): st.vent = false

func _refresh_weapons() -> void:
	var w: Weapons = main.weapons
	for id: String in weapon_buttons:
		var button: Button = weapon_buttons[id]
		var owned: bool = w.unlocked.get(id, false)
		button.disabled = NetSession.is_client()
		button.modulate = Color.WHITE if owned else Color(1, 1, 1, 0.62)
		if Weapons.is_melee(id):
			button.tooltip_text = "Im Besitz" if owned else "Freischalten"
		else:
			button.tooltip_text = ("Im Besitz · %d + %d Schuss · auffüllen" % [w.state[id].ammo, w.state[id].reserve]) if owned else "Freischalten mit %d + %d Schuss" % [int(w.state[id].def.mag), w.reserve_limit(id)]

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
