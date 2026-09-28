extends Control
const Classes = preload("res://scripts/character_classes.gd")
const Icon = preload("res://scripts/class_icon.gd")
var hud: Node
var summary: PanelContainer
var modal: PanelContainer
var body: VBoxContainer
var selected := "gunslinger"
var page := "skills"
var _signature := ""
var _profile_ids: Array = []
var _refresh_t := 0.0

func setup(owner_hud: Node) -> void:
	hud = owner_hud
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary = PanelContainer.new()
	summary.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	summary.offset_left = -384
	summary.offset_right = -48
	summary.offset_top = -275
	summary.offset_bottom = 275
	summary.add_theme_stylebox_override("panel", style(Color("0d1d18"), Color("776443"), 22))
	add_child(summary)
	modal = PanelContainer.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	modal.add_theme_stylebox_override("panel", style(Color("0b1513"), Color("776443"), 24))
	modal.hide()
	add_child(modal)
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	modal.add_child(body)
	CharacterProfile.changed.connect(refresh)
	NetSession.changed.connect(refresh)
	refresh()

static func style(bg: Color, border: Color, margin: int = 14) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	box.set_content_margin_all(margin)
	return box

func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func label(parent: Node, text: String, size: int = 16, colour: Color = Color("e9ede6")) -> Label:
	var node: Label = hud._label(text, size, colour)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

func button(parent: Node, text: String, action: Callable, primary: bool = false) -> Button:
	var node: Button = hud._menu_button(text, primary)
	parent.add_child(node)
	node.pressed.connect(action)
	return node

func icon(parent: Node, id: String, height: float) -> Control:
	var node := Icon.new()
	node.class_id = id
	node.custom_minimum_size = Vector2(height, height)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

func xp(parent: Node, id: String) -> void:
	var total := int(CharacterProfile.data.classes[id].total_xp)
	var progress := Classes.progress(total)
	label(parent, Lang.t("LEVEL %d", [progress.level]), 21, Classes.CLASSES[id].color)
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = 9
	bar.show_percentage = false
	bar.max_value = maxi(1, progress.required)
	bar.value = progress.xp if progress.required > 0 else 1
	bar.add_theme_stylebox_override("background", style(Color("23342d"), Color.TRANSPARENT, 0))
	bar.add_theme_stylebox_override("fill", style(Classes.CLASSES[id].color, Color.TRANSPARENT, 0))
	parent.add_child(bar)
	label(parent, Lang.t("%d / %d XP · %d to next level", [progress.xp, progress.required, progress.required - progress.xp]) if progress.required > 0 else Lang.t("MAX LEVEL · %d total XP", [total]), 13, Hud.MUTED)

func refresh() -> void:
	if not is_instance_valid(summary) or CharacterProfile.data.is_empty(): return
	if hud.game.started: return
	selected = selected if selected in Classes.ORDER else CharacterProfile.selected()
	clear(summary)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	summary.add_child(column)
	label(column, "YOUR CHARACTER", 12, Hud.MUTED)
	var id := CharacterProfile.selected()
	icon(column, id, 86)
	label(column, str(Classes.CLASSES[id].name), 27, Classes.CLASSES[id].color)
	xp(column, id)
	button(column, "Change class", func(): open_page("classes"), true)
	button(column, "Class skills", func(): open_page("skills"))
	button(column, "Class progress", func(): open_page("progress"))
	var profiles := CharacterProfile.profiles()
	_profile_ids = profiles.keys()
	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 34
	picker.tooltip_text = "Local character profile"
	for pid in _profile_ids: picker.add_item(Lang.t("%s", [Lang.raw(str(profiles[pid]))]))
	picker.select(_profile_ids.find(CharacterProfile.profile_id))
	picker.disabled = not CharacterProfile.can_edit()
	picker.item_selected.connect(func(index: int):
		if CharacterProfile.can_edit(): CharacterProfile.load_profile(str(_profile_ids[index])))
	column.add_child(picker)
	var create := HBoxContainer.new()
	column.add_child(create)
	var name_field := LineEdit.new()
	name_field.placeholder_text = "New profile name"
	name_field.max_length = 24
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create.add_child(name_field)
	var add := Button.new()
	add.text = "+"
	add.tooltip_text = "Create profile"
	add.disabled = not CharacterProfile.can_edit()
	add.pressed.connect(func(): CharacterProfile.create_profile(name_field.text))
	create.add_child(add)
	if not CharacterProfile.save_error.is_empty(): label(column, CharacterProfile.save_error, 12, Color("f6a990"))
	if modal.visible: _render_page()

func open_page(value: String) -> void:
	if not CharacterProfile.can_edit() or not hud.overlay.visible or hud.overlay_mode != "start" or hud.game.started: return
	selected = CharacterProfile.selected()
	page = value
	modal.show()
	hud._card.hide()
	summary.hide()
	_render_page()

func close() -> void:
	modal.hide()
	hud._card.show()
	CharacterProfile.save()

func _render_page() -> void:
	clear(body)
	var heading := HBoxContainer.new()
	body.add_child(heading)
	label(heading, "CHARACTER · CLASSES & PROGRESS", 24, Hud.GOLD)
	button(heading, "Back", close)
	var tabs := HBoxContainer.new()
	body.add_child(tabs)
	for entry in [["classes", "Classes"], ["skills", "Class skills"], ["progress", "Class progress"]]:
		var key: String = entry[0]
		button(tabs, entry[1], func(): page = key; _render_page(), page == key)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 24)
	scroll.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 200
	left.add_theme_constant_override("separation", 12)
	columns.add_child(left)
	for id in Classes.ORDER:
		button(left, Lang.t("%s · Lv %d", [Classes.CLASSES[id].name, CharacterProfile.level(id)]), func(): selected = id; _render_page(), id == selected)
	var centre := VBoxContainer.new()
	centre.custom_minimum_size.x = 210
	centre.add_theme_constant_override("separation", 16)
	columns.add_child(centre)
	icon(centre, selected, 132)
	label(centre, Classes.CLASSES[selected].name, 26, Classes.CLASSES[selected].color)
	xp(centre, selected)
	label(centre, Classes.CLASSES[selected].role, 15, Hud.MUTED)
	var choose := button(centre, "Selected class" if selected == CharacterProfile.selected() else "Select class", func(): CharacterProfile.select_class(selected), true)
	choose.disabled = selected == CharacterProfile.selected() or not CharacterProfile.can_edit()
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	if page == "progress": _render_progress(right)
	else: _render_skills(right)
	label(body, "Builds can be changed freely in the main menu. One passive talent per tier. All weapons remain usable.", 13, Hud.MUTED)

func _render_skills(parent: Node) -> void:
	var level := CharacterProfile.level(selected)
	for tier in 6:
		var locked: bool = level < Classes.TIERS[tier]
		label(parent, Lang.t("LEVEL %d · %s", [Classes.TIERS[tier], "Locked" if locked else "Choose one talent"]), 12, Hud.MUTED if locked else Classes.CLASSES[selected].color)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		parent.add_child(row)
		for choice in 2:
			var talent: Array = Classes.CLASSES[selected].talents[tier][choice]
			var active: bool = int(CharacterProfile.data.classes[selected].choices[tier]) == choice
			var card := VBoxContainer.new()
			card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			card.size_flags_stretch_ratio = 1.0
			row.add_child(card)
			var pick := button(card, Lang.t("%s %s", [Lang.raw("●" if active else "○"), talent[1]]), func(): CharacterProfile.choose_skill(selected, tier, choice), active)
			pick.disabled = locked or not CharacterProfile.can_edit()
			pick.custom_minimum_size.x = 0
			pick.add_theme_font_size_override("font_size", 14)
			label(card, talent[2], 13, Hud.MUTED)

func _render_progress(parent: Node) -> void:
	var stats: Dictionary = CharacterProfile.data.classes[selected].stats
	label(parent, "LIFETIME CLASS STATISTICS", 17, Classes.CLASSES[selected].color)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 28)
	grid.add_theme_constant_override("v_separation", 12)
	parent.add_child(grid)
	for entry in [["Play time", Lang.t("%dh %dm", [int(stats.seconds) / 3600, int(stats.seconds) / 60 % 60])], ["Kills", str(int(stats.kills))], ["Headshots", str(int(stats.headshots))], ["Deaths", str(int(stats.deaths))], ["Best kill streak", str(int(stats.best_streak))], ["Completed missions", str(int(stats.missions))], ["Boss kills", str(int(stats.boss_kills))], ["Waves survived", str(int(stats.waves))], ["Multiplayer kills", str(int(stats.multiplayer_kills))], ["Multiplayer missions", str(int(stats.multiplayer_missions))]]:
		label(grid, entry[0], 15, Hud.MUTED)
		label(grid, entry[1], 17)
	var next := 0
	for tier in Classes.TIERS:
		if tier > CharacterProfile.level(selected): next = tier; break
	label(parent, Lang.t("NEXT UNLOCK · LEVEL %d\nA new passive talent tier", [next]) if next > 0 else "All six talent tiers unlocked", 18, Hud.GOLD)
	label(parent, Lang.t("Profile: %d total kills · %d quests completed · %d achievements\nFavourite class: %s", [int(CharacterProfile.data.total_kills), _quest_count(), CharacterProfile.data.achievements.size(), Classes.CLASSES[CharacterProfile.favourite()].name]), 14, Hud.MUTED)
	label(parent, Lang.t("%d cosmetic unlocks", [CharacterProfile.data.cosmetics.size()]), 14, Hud.MUTED)
	label(parent, "PROFILE ACHIEVEMENTS", 17, Hud.GOLD)
	for achievement in Classes.ACHIEVEMENTS:
		var done: bool = CharacterProfile.data.achievements.get(achievement[0], false)
		label(parent, Lang.t("%s · %s · %d XP", [Lang.raw("●" if done else "○"), achievement[1], achievement[3]]), 15, Hud.GOLD if done else Hud.MUTED)
		label(parent, achievement[2], 13, Hud.MUTED)

func _quest_count() -> int:
	var count := 0
	for value in CharacterProfile.data.quests.values(): count += int(value)
	return count

func _process(delta: float) -> void:
	if not hud: return
	var available: bool = hud.overlay.visible and hud.overlay_mode == "start" and not hud.game.started and not hud._loading and not hud.map_selection.visible
	if modal.visible and (not available or not CharacterProfile.can_edit()): close()
	summary.visible = available and not modal.visible and not hud._menu_detail.visible
	_refresh_t += delta
	if _refresh_t >= 0.5:
		_refresh_t = 0.0
		var signature := "%s:%s:%s" % [CharacterProfile.profile_id, CharacterProfile.selected(), CharacterProfile.context]
		if signature != _signature: _signature = signature; refresh()

func _input(event: InputEvent) -> void:
	if modal.visible and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
