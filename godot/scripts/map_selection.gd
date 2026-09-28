class_name MapSelection
extends Control
signal launch_requested(id: String)
signal back_requested
var campaign: Campaign
var atlas: LiveMap
var _title: Label
var _status: Label
var _description: Label
var _progress: Label
var _join: Button
var _rows: Array[Button] = []
var _selected := ""
var _preview_id := ""
var _entry: VBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0.018, 0.027, 0.026, 1.0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margins := MarginContainer.new()
	margins.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]: margins.add_theme_constant_override("margin_" + edge, 24)
	add_child(margins)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 20)
	margins.add_child(columns)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = 310
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	columns.add_child(scroll)
	_entry = VBoxContainer.new()
	_entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entry.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_entry.add_theme_constant_override("separation", 8)
	scroll.add_child(_entry)
	var back := _button("‹  Back to main menu")
	back.pressed.connect(func(): back_requested.emit())
	_entry.add_child(back)
	_entry.add_child(_label("REMZ  /  CAMPAIGN", 13, Color(0.68,0.75,0.69)))
	_entry.add_child(_label("SELECT A REGION", 28, Color(0.92,0.92,0.84)))
	_progress = _label("", 14, Color(0.63,0.71,0.65))
	_entry.add_child(_progress)
	_entry.add_child(HSeparator.new())
	for data: Dictionary in Campaign.REGIONS:
		var row := _button(data.title)
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.add_theme_color_override("font_color", Color(0.77,0.89,0.80) if data.available else Color(0.46,0.5,0.5))
		row.pressed.connect(func(): choose(data.id))
		row.focus_entered.connect(func(): _preview(data.id))
		row.mouse_entered.connect(func(): atlas._hover(data.id); _preview(data.id))
		row.mouse_exited.connect(func(): atlas._hover(""); _preview(_selected))
		_entry.add_child(row)
		_rows.append(row)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_entry.add_child(spacer)
	_status = _label("", 12, Color(0.62,0.8,0.69))
	_entry.add_child(_status)
	_title = _label("", 30, Color(0.94,0.94,0.86))
	_entry.add_child(_title)
	_description = _label("", 15, Color(0.67,0.72,0.69))
	_description.custom_minimum_size = Vector2(290, 88)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_entry.add_child(_description)
	_join = _button("Select a region")
	_join.custom_minimum_size.y = 48
	_join.pressed.connect(func(): choose(_preview_id))
	_entry.add_child(_join)
	var hint := _label("Survival: 25 rounds. Exploration regions can be visited freely.", 13, Color(0.5,0.58,0.54))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 290
	_entry.add_child(hint)
	atlas = LiveMap.new()
	atlas.interactive = true
	atlas.campaign = campaign
	atlas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	atlas.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(atlas)
	atlas.region_hovered.connect(func(id: String): _preview(id if not id.is_empty() else _selected))
	atlas.region_pressed.connect(choose)
	refresh()

func refresh() -> void:
	# Opening the atlas never chooses a region on the player's behalf.
	_selected = ""
	atlas.selected = _selected
	atlas._hover("")
	_progress.text = Lang.t("%d / %d regions secured", [campaign.cleared_count(), Campaign.REGIONS.size()])
	for i in _rows.size():
		var entry: Dictionary = Campaign.REGIONS[i]
		_rows[i].text = ("✓  " if campaign.cleared(entry.id) else ("●  " if entry.available else "–  ")) + Lang.t(entry.title)
		_rows[i].tooltip_text = Lang.t("Explore the fields of Remetschwil.") if entry.get("exploration", false) and not entry.get("survival", false) else (Lang.t("Under construction") if not entry.available else Lang.t("Best run: %d / %d rounds", [campaign.best_wave(entry.id), Campaign.ROUNDS]))
	_preview(_selected)

func choose(id: String) -> void:
	_selected = id
	atlas.selected = id
	_preview(id)
	if NetSession.is_client() or (NetSession.enabled and Campaign.region(id).get("exploration", false)): return
	if campaign.select(id):
		Sfx.play(self, "click", -6.0)
		launch_requested.emit(id)

func _preview(id: String) -> void:
	if not _title: return
	var entry := Campaign.region(id)
	if entry.is_empty():
		_preview_id = ""
		_title.text = "SELECT A REGION"
		_status.text = ""
		_description.text = "Choose a region on the map or in the list."
		_join.text = "Select a region"
		_join.disabled = true
		return
	_preview_id = id
	_title.text = entry.title
	_status.text = "REGION SECURED" if campaign.cleared(id) else ("AVAILABLE  /  25 ROUNDS" if entry.available else "UNDER CONSTRUCTION")
	_status.modulate = Color.WHITE if entry.available else Color(0.65,0.65,0.65)
	_description.text = Lang.t("Defend the forest hut. Survive all 25 rounds to secure Forest.") + "\n\n" + Lang.t("Best run: %d / %d rounds", [campaign.best_wave(id), Campaign.ROUNDS]) if entry.available else "This region is under construction. It will join the campaign in a future update."
	_join.text = "Replay Forest  →" if campaign.cleared(id) else ("Enter Forest  →" if entry.available else "Under construction")
	_join.disabled = not entry.available or NetSession.is_client()
	if entry.get("exploration", false):
		_status.text = "SURVIVAL / 25 ROUNDS"
		_description.text = "Survive 25 waves in the fields. Choose where to build your defences."
		_join.text = "Enter The Planes  →"
		_join.disabled = NetSession.enabled
		if NetSession.enabled: _description.text = "The Planes is available in solo play."

func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("pause"):
		back_requested.emit()
		get_viewport().set_input_as_handled()

func _label(value: String, pixels: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", colour)
	return label

func _button(value: String) -> Button:
	var button := Button.new()
	button.text = value
	button.custom_minimum_size.y = 38
	button.add_theme_font_size_override("font_size", 15)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.13,0.21,0.18,0.9) if state in ["hover", "focus"] else Color(0.055,0.085,0.074,0.88)
		style.border_color = Color(0.51,0.73,0.60,0.8) if state in ["hover", "focus"] else Color(0.37,0.48,0.42,0.25)
		style.set_border_width_all(1)
		style.content_margin_left = 14
		style.content_margin_right = 14
		button.add_theme_stylebox_override(state, style)
	return button
