class_name BarricadeMenu
extends CanvasLayer

const INK := Color(0.035, 0.048, 0.047, 0.97)
const MUTED := Color(0.61, 0.68, 0.65)
const PAPER := Color(0.93, 0.95, 0.9)
const RED := Color(1.0, 0.28, 0.22)
const GREEN := Color(0.35, 0.89, 0.66)
const GOLD := Color(0.94, 0.76, 0.43)

var main: Node
var player: Player
var selected: Barricade
var is_open := false
var panel: Control
var overview: Camera3D
var primary: Button
var repair_button: Button
var site_buttons: Array[Button] = []
var points: Label
var title: Label
var dimensions: Label
var condition: Label
var health: ProgressBar
var status: Label
var explanation: Label
var preview_title: Label
var preview_status: Label
var level_labels: Array[Label] = []
var _last_message := ""
var _saved_hud := true
var _saved_viewmodel := true
var _saved_viewmodel_update := SubViewport.UPDATE_ALWAYS
var _saved_flashlight := false
var _was_paused := false
var _saved_mouse := Input.MOUSE_MODE_CAPTURED
var _refresh_time := 0.0
var _card: PanelContainer
var _controls_hint: Label

func setup(game: Node) -> void:
	main = game
	player = main.player
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	overview = Camera3D.new()
	overview.name = "BarricadeOverview"
	overview.fov = 58.0
	overview.near = 0.1
	overview.far = 200.0
	overview.cull_mask = player.camera.cull_mask
	main.add_child(overview)
	_build_ui()
	get_viewport().size_changed.connect(_resize)
	_resize()

static func _style(bg: Color, border := Color(0.2, 0.27, 0.25), pad := 18.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = pad
	box.content_margin_bottom = pad
	return box

static func _label(text: String, size: int, color := PAPER) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

static func _button(text: String, accent := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 47
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_stylebox_override("normal", _style(Color(0.19, 0.25, 0.22) if accent else Color(0.08, 0.11, 0.10), GOLD if accent else Color(0.23, 0.3, 0.27), 12))
	button.add_theme_stylebox_override("hover", _style(Color(0.22, 0.28, 0.24), GOLD, 12))
	button.add_theme_stylebox_override("pressed", _style(Color(0.1, 0.22, 0.17), GREEN, 12))
	button.add_theme_stylebox_override("disabled", _style(Color(0.065, 0.08, 0.075), Color(0.15, 0.19, 0.17), 12))
	button.add_theme_stylebox_override("focus", _style(Color(0, 0, 0, 0), GOLD, 0))
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_disabled_color", MUTED)
	return button

func _build_ui() -> void:
	panel = Control.new()
	panel.name = "DefencePlanner"
	add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.hide()
	var shade := TextureRect.new()
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.014, 0.023, 0.02, 0.8))
	gradient.set_color(1, Color(0.014, 0.023, 0.02, 0.0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	shade.texture = texture
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	panel.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 26)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 14)
	layout.add_child(header)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	heading.add_child(_label("REMETSCHWIL SENNHOF   /   DEFENSE", 12, GOLD))
	heading.add_child(_label("BARRICADES", 32))
	var wallet := PanelContainer.new()
	wallet.add_theme_stylebox_override("panel", _style(INK, Color(0.3, 0.36, 0.29), 14))
	header.add_child(wallet)
	points = _label("", 20, GOLD)
	var wallet_row := HBoxContainer.new()
	wallet.add_child(wallet_row)
	wallet_row.add_child(preload("res://scripts/currency.gd").icon(32.0, GOLD))
	wallet_row.add_child(points)
	var back := _button("Back to the game  [Esc]")
	back.pressed.connect(close)
	header.add_child(back)
	var sites := HBoxContainer.new()
	sites.add_theme_constant_override("separation", 10)
	layout.add_child(sites)
	for i in main.barricades.size():
		var site := _button("")
		site.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		site.alignment = HORIZONTAL_ALIGNMENT_LEFT
		site.add_theme_font_size_override("font_size", 14)
		site.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		site.pressed.connect(func(): select_site(main.barricades[i]))
		sites.add_child(site)
		site_buttons.append(site)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 24)
	layout.add_child(content)
	_card = PanelContainer.new()
	_card.add_theme_stylebox_override("panel", _style(INK))
	content.add_child(_card)
	var card_content := VBoxContainer.new()
	card_content.add_theme_constant_override("separation", 12)
	_card.add_child(card_content)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card_content.add_child(scroll)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	scroll.add_child(details)
	details.add_child(_label("BUILD PLAN   /   WHOLE LINE", 12, GOLD))
	title = _label("", 23)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(title)
	details.add_child(ItemIcons.view("barricade", Vector2(200, 80)))
	dimensions = _label("", 14, MUTED)
	details.add_child(dimensions)
	var levels := HBoxContainer.new()
	levels.add_theme_constant_override("separation", 6)
	details.add_child(levels)
	for i in 3:
		var step := PanelContainer.new()
		step.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		step.add_theme_stylebox_override("panel", _style(Color(0.08, 0.12, 0.10), Color(0.19, 0.25, 0.22), 9))
		levels.add_child(step)
		var spec: Dictionary = Barricade.TIERS[i]
		var label := _label(Lang.t("0%d  %s\n%d HP · %d%% armor · %d R", [i + 1, Lang.t(String(spec["name"])), roundi(float(spec["hp"])), roundi(float(spec["armor"]) * 100.0), int(spec["cost"])]), 13)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		step.add_child(label)
		level_labels.append(label)
	condition = _label("", 14)
	details.add_child(condition)
	health = ProgressBar.new()
	health.show_percentage = false
	health.custom_minimum_size.y = 6
	health.add_theme_stylebox_override("background", _style(Color(0.12, 0.17, 0.14), Color.TRANSPARENT, 0))
	health.add_theme_stylebox_override("fill", _style(GREEN, Color.TRANSPARENT, 0))
	details.add_child(health)
	explanation = _label("", 14, MUTED)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(explanation)
	card_content.add_child(HSeparator.new())
	card_content.add_child(_label("BUILD & MAINTAIN", 12, GOLD))
	primary = _button("", true)
	primary.icon = ItemIcons.texture("barricade")
	primary.expand_icon = true
	primary.add_theme_constant_override("icon_max_width", 42)
	primary.pressed.connect(_purchase.bind("build"))
	card_content.add_child(primary)
	repair_button = _button("")
	repair_button.icon = ItemIcons.texture("skill_regen")
	repair_button.expand_icon = true
	repair_button.add_theme_constant_override("icon_max_width", 32)
	repair_button.pressed.connect(_purchase.bind("repair"))
	card_content.add_child(repair_button)
	status = _label("", 14, MUTED)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card_content.add_child(status)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(right)
	preview_title = _label("", 24)
	preview_title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	preview_title.add_theme_constant_override("shadow_offset_y", 2)
	right.add_child(preview_title)
	preview_status = _label("", 15, RED)
	preview_status.add_theme_color_override("font_shadow_color", Color.BLACK)
	preview_status.add_theme_constant_override("shadow_offset_y", 2)
	right.add_child(preview_status)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(spacer)
	var legend := PanelContainer.new()
	legend.add_theme_stylebox_override("panel", _style(INK, Color(0.2, 0.27, 0.25), 16))
	right.add_child(legend)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 7)
	legend.add_child(text)
	text.add_child(_label("ONE CLICK. THE WHOLE BARRIER.", 16, GOLD))
	var hint := _label("Red shows the planned line. Green shows the built barrier.\nAll segments are placed, reinforced or repaired together.", 14)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.add_child(hint)
	_controls_hint = _label("", 13, MUTED)
	layout.add_child(_controls_hint)

func _resize() -> void:
	if not _card:
		return
	_card.custom_minimum_size.x = clampf(get_viewport().get_visible_rect().size.x * 0.29, 330, 430)
	if is_open:
		_position_camera()

func open(site: Barricade = null) -> void:
	if is_open or not main.started or main.over or not player.alive or not player.active:
		return
	if not site:
		var nearest := INF
		for candidate: Barricade in main.barricades:
			var distance := candidate.distance_to_line(player.global_position)
			if distance < nearest:
				nearest = distance
				site = candidate
	if not site:
		return
	_was_paused = get_tree().paused
	_saved_mouse = Input.mouse_mode
	_saved_hud = main.hud.visible
	_saved_viewmodel = main.weapons.viewmodel.visible
	_saved_viewmodel_update = main.weapons.viewmodel.viewport.render_target_update_mode
	_saved_flashlight = player.flashlight.visible
	is_open = true
	_controls_hint.text = "1–4  Choose building site     ·     R  Repair     ·     V / Esc  Back     ·     Co-op keeps running while you plan" if NetSession.enabled else "1–4  Choose building site     ·     R  Repair     ·     V / Esc  Back     ·     The game is paused while you plan"
	player.active = false
	get_tree().paused = not NetSession.enabled
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main.hud.hide()
	main.weapons.viewmodel.hide()
	main.weapons.viewmodel.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	player.flashlight.hide()
	panel.show()
	select_site(site)

func close() -> void:
	if not is_open:
		return
	is_open = false
	panel.hide()
	for bar: Barricade in main.barricades:
		bar.set_preview(false)
	player.camera.make_current()
	main.hud.visible = _saved_hud
	main.weapons.viewmodel.visible = _saved_viewmodel
	main.weapons.viewmodel.viewport.render_target_update_mode = _saved_viewmodel_update
	player.flashlight.visible = _saved_flashlight
	get_tree().paused = not NetSession.enabled and (_was_paused or main.over)
	player.active = player.alive and not main.over and not get_tree().paused
	Input.mouse_mode = _saved_mouse if player.active else Input.MOUSE_MODE_VISIBLE
	main.hud.set_prompt("")

func select_site(site: Barricade) -> void:
	selected = site
	_last_message = ""
	for bar: Barricade in main.barricades:
		bar.set_preview(bar == selected)
	_position_camera()
	_refresh()

func _position_camera() -> void:
	var normal := Vector3(selected.normal2.x, 0, selected.normal2.y)
	if normal.dot(player.global_position - selected.center) < 0:
		normal = -normal
	var distance := maxf(9.5, selected.half_len * 2.8)
	overview.global_position = selected.center + normal * distance + Vector3.UP * 5.2
	overview.look_at(selected.center + Vector3.UP * 0.65)
	# Shift the line into the open area beside the controls, without an extra viewport.
	var aspect := get_viewport().get_visible_rect().size.aspect()
	overview.h_offset = -distance * tan(deg_to_rad(overview.fov * 0.5)) * aspect * 0.29
	overview.make_current()

func _refresh() -> void:
	if not is_open or not selected:
		return
	points.text = "%d  REM DOLLARS" % player.score
	for i in site_buttons.size():
		var bar: Barricade = main.barricades[i]
		var distance := bar.distance_to_line(player.global_position)
		site_buttons[i].text = Lang.t("%02d  %s\n       OPEN  ·  %d m", [i + 1, bar.slot["name"], ceili(distance)]) if bar.level == 0 else Lang.t("%02d  %s\n       TIER %d  ·  %d m", [i + 1, bar.slot["name"], bar.level, ceili(distance)])
		site_buttons[i].add_theme_color_override("font_color", GOLD if bar == selected else PAPER)
		site_buttons[i].add_theme_stylebox_override("normal", _style(Color(0.13, 0.18, 0.14) if bar == selected else Color(0.08, 0.11, 0.10), GOLD if bar == selected else Color(0.23, 0.3, 0.27), 12))
	title.text = selected.slot["name"]
	dimensions.text = Lang.t("%.1f m  ·  %d connected segments", [selected.half_len * 2.0, selected.slot["segments"]])
	condition.text = "Open approach  ·  no barrier" if selected.level == 0 else Lang.t("Tier %d  ·  %s  ·  %d / %d hit points", [selected.level, Lang.t(selected.tier_name()), ceili(selected.hp), int(selected.max_hp())])
	health.max_value = maxf(selected.max_hp(), 1)
	health.value = selected.hp
	for i in 3:
		level_labels[i].modulate = GREEN if i < selected.level else MUTED
	var build_error := selected.action_error(player, "build")
	var repair_error := selected.action_error(player, "repair")
	primary.text = Lang.t("Build whole line  ·  %d R", [Barricade.build_cost(1)]) if selected.level == 0 else (Lang.t("Upgrade to tier %d · %s  ·  %d R", [selected.level + 1, Lang.t(String(Barricade.tier(selected.level + 1)["name"])), selected.next_cost()]) if selected.level < Barricade.MAX_LEVEL else "Fully reinforced")
	repair_button.text = Lang.t("Repair whole line  ·  %d R", [Barricade.repair_cost(selected.level)])
	primary.disabled = not build_error.is_empty()
	primary.tooltip_text = build_error
	repair_button.disabled = not repair_error.is_empty()
	repair_button.tooltip_text = repair_error
	repair_button.visible = selected.level > 0
	if selected.level == 0:
		explanation.text = Lang.t("%d Rem Dollars for the timber palisade along the whole line. It only appears once you build.", [Barricade.build_cost(1)])
	elif selected.level < Barricade.MAX_LEVEL:
		var next: Dictionary = Barricade.tier(selected.level + 1)
		explanation.text = Lang.t("Upgrading replaces the wall with the %s: %d HP and %d%% of every hit shrugged off. The whole line is restored. Repairing refills its current HP.", [Lang.t(String(next["name"])), roundi(float(next["hp"])), roundi(float(next["armor"]) * 100.0)])
	else:
		explanation.text = "The steel bulwark is the strongest wall. Repairing refills its HP."
	preview_title.text = Lang.t("%02d   /   %s", [main.barricades.find(selected) + 1, selected.slot["name"]])
	preview_status.text = Lang.t("RED BUILD PREVIEW   ·   %.1f M TOTAL LENGTH", [selected.half_len * 2.0]) if selected.level == 0 else Lang.t("LINE SECURED   ·   TIER %d / 3", [selected.level])
	preview_status.add_theme_color_override("font_color", RED if selected.level == 0 else GREEN)
	if not _last_message.is_empty():
		status.text = _last_message
		status.add_theme_color_override("font_color", GREEN)
	else:
		status.text = build_error if not build_error.is_empty() else "Ready. One click places the whole line."
		if selected.level > 0 and selected.hp < selected.max_hp() and repair_error.is_empty():
			status.text = "Damaged. Repair it or reinforce it right away."
		elif selected.level > 0 and build_error.is_empty():
			status.text = "Ready to reinforce the whole line."
		status.add_theme_color_override("font_color", GOLD if not build_error.is_empty() else MUTED)

func _purchase(action: String) -> void:
	if NetSession.enabled:
		if selected: NetSession.command(action, [main.barricades.find(selected)])
		return
	if not is_open:
		return
	var error := selected.action_error(player, action)
	if not error.is_empty():
		_last_message = ""
		_refresh()
		status.text = error
		status.add_theme_color_override("font_color", RED)
		return
	var old_level := selected.level
	if selected.purchase(player, action):
		_last_message = "Whole line repaired." if action == "repair" else ("Whole line built. Approach secured." if old_level == 0 else Lang.t("Whole line reinforced to tier %d.", [selected.level]))
		_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("build_menu") and not event.is_echo():
		if is_open:
			close()
		else:
			if main.progression.close_enough(player, "mechanic"):
				main.progression.interact("mechanic")
				main.progression.page = "Towers"
				main.progression._render()
			else: main.hud.message("Defense advice at Mechanic. Right at a barricade, E builds or repairs the line.", 3)
		get_viewport().set_input_as_handled()
	elif is_open and event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_4:
			var index: int = event.physical_keycode - KEY_1
			if index < main.barricades.size():
				select_site(main.barricades[index])
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("reload"):
			_purchase("repair")
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not is_open:
		return
	_refresh_time += delta
	if _refresh_time >= 0.3:
		_refresh_time = 0.0
		_refresh()
