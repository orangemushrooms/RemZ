extends Control
const Classes = preload("res://scripts/character_classes.gd")
const Icon = preload("res://scripts/class_icon.gd")
const Palette = preload("res://scripts/character_style.gd")
const Surface = preload("res://scripts/character_surface.gd")
var hud: Node
var summary: PanelContainer
var modal: PanelContainer
var body: VBoxContainer
var notice: Control
var notice_body: VBoxContainer
var feedback: Label
var selected := "gunslinger"
var page := "skills"
var _signature := ""
var _profile_ids: Array = []
var _refresh_t := 0.0
var _feedback_t := 0.0
var _scroll: ScrollContainer
var _talent_buttons: Dictionary = {}

func setup(owner_hud: Node) -> void:
	hud = owner_hud
	theme = Palette.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary = PanelContainer.new()
	summary.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	summary.offset_left = -410
	summary.offset_right = -48
	summary.offset_top = -370
	summary.offset_bottom = 370
	summary.add_theme_stylebox_override("panel", Palette.box(Palette.INK, Palette.LINE, 0))
	add_child(summary)
	modal = PanelContainer.new()
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 24)
	var shell := Palette.box(Palette.INK, Color("59604c"), 24)
	shell.shadow_color = Color(0,0,0,0.5)
	shell.shadow_size = 14
	modal.add_theme_stylebox_override("panel", shell)
	modal.hide()
	add_child(modal)
	_surface(modal, Palette.GOLD)
	body = _vbox(modal, 16)
	_build_notice()
	CharacterProfile.changed.connect(refresh)
	NetSession.changed.connect(refresh)
	refresh()

func clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()

func _vbox(parent: Node, gap: int = 10) -> VBoxContainer:
	var node := VBoxContainer.new()
	node.add_theme_constant_override("separation", gap)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func _row(parent: Node, gap: int = 12) -> HBoxContainer:
	var node := HBoxContainer.new()
	node.add_theme_constant_override("separation", gap)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func _pad(parent: Node, amount: int = 18) -> MarginContainer:
	var node := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]: node.add_theme_constant_override("margin_" + edge, amount)
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func label(parent: Node, text: String, font_size: int = 16, colour: Color = Palette.PAPER, display: bool = false) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_font_override("font", Palette.DISPLAY if display else Palette.BODY)
	node.add_theme_color_override("font_color", colour)
	node.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(node)
	return node

func _eyebrow(parent: Node, text: String, colour: Color = Palette.GOLD) -> Label:
	var result := label(parent, text, 12, colour)
	result.add_theme_font_override("font", Palette.MEDIUM)
	result.uppercase = true
	return result

func _spacer(parent: Node, height: float = 0, expand: bool = false) -> void:
	var node := Control.new()
	node.custom_minimum_size.y = height
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if expand: node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(node)

func _line(parent: Node) -> void:
	var line := ColorRect.new()
	line.color = Palette.LINE
	line.custom_minimum_size.y = 1
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(line)

func _surface(parent: Node, accent: Color, forest: bool = false) -> Control:
	var art := Surface.new()
	art.accent = accent
	art.forest = forest
	art.clip_contents = true
	parent.add_child(art)
	return art

func button(parent: Node, text: String, action: Callable, primary: bool = false) -> Button:
	var node := Button.new()
	node.text = text
	Palette.button(node, _accent(), primary)
	parent.add_child(node)
	node.pressed.connect(action)
	node.mouse_entered.connect(func(): if not node.disabled: Sfx.play(self, "hover", -20.0))
	return node

func _accent(id: String = "") -> Color:
	return Classes.CLASSES[selected if id.is_empty() else id].color

func icon(parent: Node, id: String, height: float, decorated: bool = true) -> Control:
	var node := Icon.new()
	node.class_id = id
	node.decorated = decorated
	node.custom_minimum_size = Vector2(height, height)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(node)
	return node

static func number(value: int) -> String:
	var digits := str(value)
	var index := digits.length() - 3
	while index > 0:
		digits = digits.insert(index, " ")
		index -= 3
	return digits

func _bar(parent: Node, value: float, maximum: float, accent: Color, height: int = 5) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.custom_minimum_size.y = height
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.max_value = maxf(1, maximum)
	bar.value = value
	bar.add_theme_stylebox_override("background", Palette.box(Color("29352c"), Color.TRANSPARENT, 0, 0))
	bar.add_theme_stylebox_override("fill", Palette.box(accent, Color.TRANSPARENT, 0, 0))
	parent.add_child(bar)
	return bar

func xp(parent: Node, id: String, compact: bool = false) -> void:
	var progress := Classes.progress(int(CharacterProfile.data.classes[id].total_xp))
	var row := _row(parent)
	var rank := label(row, "%02d" % progress.level, 36 if compact else 52, _accent(id), true)
	rank.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rank.autowrap_mode = TextServer.AUTOWRAP_OFF
	var details := _vbox(row, 3)
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.alignment = BoxContainer.ALIGNMENT_CENTER
	_eyebrow(details, "Class level", Palette.MUTED)
	label(details, Lang.t("%s / %s XP", [Lang.raw(number(progress.xp)), Lang.raw(number(progress.required))]) if progress.required > 0 else "Maximum level", 15)
	_bar(parent, progress.xp if progress.required else 1, progress.required if progress.required else 1, _accent(id))
	if progress.required:
		label(parent, Lang.t("%s XP to next level", [Lang.raw(number(progress.required - progress.xp))]), 13, Palette.MUTED)

func _next_tier(id: String) -> int:
	for tier in Classes.TIERS:
		if tier > CharacterProfile.level(id): return tier
	return 0

func _milestones(parent: Node, id: String) -> void:
	var row := _row(parent, 5)
	for tier in Classes.TIERS:
		var level := CharacterProfile.level(id)
		var point := PanelContainer.new()
		point.mouse_filter = Control.MOUSE_FILTER_IGNORE
		point.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		point.add_theme_stylebox_override("panel", Palette.box(Color("26352a") if level >= tier else Color("101a16"), _accent(id) if level >= tier else Palette.LINE, 3, 1))
		row.add_child(point)
		var text := label(point, str(tier), 14, _accent(id) if level >= tier else Palette.DIM, true)
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func refresh() -> void:
	if not is_instance_valid(summary) or CharacterProfile.data.is_empty() or hud.game.started: return
	clear(summary)
	var id := CharacterProfile.selected()
	_surface(summary, _accent(id), true)
	var column := _vbox(_pad(summary, 24), 7)
	var top := _row(column)
	_eyebrow(top, "Survivor dossier", Palette.MUTED)
	var code := label(top, "R / %02d" % (Classes.ORDER.find(id) + 1), 13, Palette.DIM)
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	icon(column, id, 98)
	var title := label(column, Classes.CLASSES[id].name, 40, Palette.PAPER, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line(column)
	xp(column, id)
	_spacer(column, 3)
	_summary_action(column, "Change class", "Choose your speciality", "01", "classes")
	_summary_action(column, "Class skills", "Shape your playstyle", "02", "skills")
	_summary_action(column, "Class progress", "Your record in the field", "03", "progress")
	_spacer(column, 0, true)
	_milestones(column, id)
	_line(column)
	var profile := button(column, Lang.t("Profile · %s", [Lang.raw(str(CharacterProfile.data.name))]), _open_profiles)
	profile.alignment = HORIZONTAL_ALIGNMENT_LEFT
	profile.add_theme_font_size_override("font_size", 14)
	if not CharacterProfile.save_error.is_empty(): label(column, CharacterProfile.save_error, 13, Color("efaa83"))
	if modal.visible: _render_page()

func _interactive(parent: Node, action: Callable, accent: Color, active: bool = false, quiet: bool = false, padding: int = 16) -> Dictionary:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	parent.add_child(panel)
	var pick := Button.new()
	Palette.button(pick, accent, active, quiet)
	panel.add_child(pick)
	pick.pressed.connect(action)
	pick.mouse_entered.connect(func(): Sfx.play(self, "hover", -22.0))
	var content := _vbox(_pad(panel, padding), 8)
	return {"panel": panel, "button": pick, "content": content}

func _summary_action(parent: Node, title: String, subtitle: String, code: String, destination: String) -> void:
	var card := _interactive(parent, func(): open_page(destination), _accent(CharacterProfile.selected()), destination == "skills", false, 10)
	var row := _row(card.content, 14)
	var index := label(row, code, 25, _accent(CharacterProfile.selected()), true)
	index.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	index.autowrap_mode = TextServer.AUTOWRAP_OFF
	var words := _vbox(row, 1)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label(words, title, 18, Palette.PAPER, true)
	label(words, subtitle, 12, Palette.MUTED)
	var arrow := label(row, "›", 26, Palette.MUTED, true)
	arrow.size_flags_horizontal = Control.SIZE_SHRINK_END
	arrow.autowrap_mode = TextServer.AUTOWRAP_OFF
	card.button.tooltip_text = title

func open_page(value: String) -> void:
	if not CharacterProfile.can_edit() or not hud.overlay.visible or hud.overlay_mode != "start" or hud.game.started: return
	selected = CharacterProfile.selected()
	page = value
	modal.show()
	hud._card.hide()
	summary.hide()
	_render_page(false)
	modal.modulate.a = 0.0
	create_tween().tween_property(modal, "modulate:a", 1.0, 0.18)

func close() -> void:
	notice.hide()
	modal.hide()
	hud._card.show()
	CharacterProfile.save()

func _set_page(value: String) -> void:
	page = value
	_render_page(false)

func _render_page(keep_scroll: bool = true) -> void:
	var scroll_position := _scroll.scroll_vertical if keep_scroll and is_instance_valid(_scroll) else 0
	_scroll = null
	_talent_buttons.clear()
	clear(body)
	var header := _row(body, 24)
	var heading := _vbox(header, 1)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_eyebrow(heading, "REMZ · Survivor dossier")
	label(heading, "Choose your speciality" if page == "classes" else "Build your survivor" if page == "skills" else "Your record in the field", 36, Palette.PAPER, true)
	var tabs := _row(header, 6)
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	for entry in [["classes", "Classes"], ["skills", "Class skills"], ["progress", "Class progress"]]:
		button(tabs, entry[1], _set_page.bind(entry[0]), page == entry[0])
	var back := button(header, "Back", close)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_line(body)
	var content := _row(body, 24)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if page == "classes": _render_gallery(content)
	else:
		_render_sidebar(content)
		_scroll = ScrollContainer.new()
		_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(_scroll)
		_scroll.get_v_scroll_bar().custom_minimum_size.x = 8
		var inset := _pad(_scroll, 0)
		inset.add_theme_constant_override("margin_right", 18)
		inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var right := _vbox(inset, 14)
		right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if page == "progress": _render_progress(right)
		else: _render_skills(right)
		_scroll.set_deferred("scroll_vertical", scroll_position)
	_line(body)
	var footer := _row(body)
	feedback = label(footer, "One talent per tier. Change your choices freely in the main menu.", 14, Palette.MUTED)
	var stamp := label(footer, "REMZ / 01", 13, Palette.DIM, true)
	stamp.size_flags_horizontal = Control.SIZE_SHRINK_END
	stamp.autowrap_mode = TextServer.AUTOWRAP_OFF
	_feedback_t = 0

func _render_sidebar(parent: Node) -> void:
	var side := _vbox(parent, 10)
	side.custom_minimum_size.x = 250
	_eyebrow(side, "Class roster", Palette.MUTED)
	for id in Classes.ORDER:
		var card := _interactive(side, _inspect_class.bind(id), _accent(id), selected == id, false, 10)
		var row := _row(card.content, 10)
		var emblem := icon(row, id, 30, false)
		emblem.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		label(row, Classes.CLASSES[id].name, 21, Palette.PAPER, true)
		var rank := label(row, "%02d" % CharacterProfile.level(id), 24, _accent(id), true)
		rank.size_flags_horizontal = Control.SIZE_SHRINK_END
		rank.autowrap_mode = TextServer.AUTOWRAP_OFF
		card.button.tooltip_text = Classes.CLASSES[id].name
	_spacer(side, 4)
	var dossier := PanelContainer.new()
	dossier.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dossier.add_theme_stylebox_override("panel", Palette.box(Palette.INK, Palette.LINE, 0))
	side.add_child(dossier)
	_surface(dossier, _accent(), true)
	var details := _vbox(_pad(dossier, 18), 8)
	icon(details, selected, 64)
	xp(details, selected, true)
	label(details, Classes.CLASSES[selected].role, 15, Palette.MUTED)
	_spacer(details, 0, true)
	var choose := button(details, "Selected class" if selected == CharacterProfile.selected() else "Select class", func(): CharacterProfile.select_class(selected), true)
	choose.disabled = selected == CharacterProfile.selected()

func _inspect_class(id: String) -> void:
	selected = id
	_render_page(false)

func _render_gallery(parent: Node) -> void:
	var all := _vbox(parent, 22)
	all.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var row := _row(all, 14)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for id in Classes.ORDER:
		var card := _interactive(row, _select_gallery.bind(id), _accent(id), id == CharacterProfile.selected())
		card.button.set_meta("gallery_class", id)
		var column: VBoxContainer = card.content
		column.add_theme_constant_override("separation", 12)
		_eyebrow(column, Lang.t("Discipline %02d", [Classes.ORDER.find(id) + 1]), _accent(id))
		var art_panel := PanelContainer.new()
		art_panel.add_theme_stylebox_override("panel", Palette.box(Palette.INK, Color.TRANSPARENT, 0))
		art_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
		art_panel.custom_minimum_size.y = 130
		art_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		column.add_child(art_panel)
		_surface(art_panel, _accent(id), true)
		icon(art_panel, id, 110)
		var title := label(column, Classes.CLASSES[id].name, 32, Palette.PAPER, true)
		title.custom_minimum_size.y = 44
		var role := label(column, Classes.CLASSES[id].role, 16, Palette.MUTED)
		role.custom_minimum_size.y = 72
		_line(column)
		xp(column, id, true)
		label(column, "Selected class" if id == CharacterProfile.selected() else "Select class", 16, _accent(id))
		card.button.tooltip_text = Lang.t("Select %s", [Classes.CLASSES[id].name])
	var bottom := _row(all)
	label(bottom, "Six talent tiers. Two choices at each milestone. Your build, your approach.", 17, Palette.MUTED)
	button(bottom, "Edit selected build", func(): selected = CharacterProfile.selected(); _set_page("skills"), true)

func _select_gallery(id: String) -> void:
	selected = id
	if CharacterProfile.select_class(id): _feedback(Lang.t("Class selected: %s", [Classes.CLASSES[id].name]))

func _render_skills(parent: Node) -> void:
	if selected == "assassin": _render_teleport(parent)
	var level := CharacterProfile.level(selected)
	var title_row := _row(parent)
	label(title_row, Classes.CLASSES[selected].name, 31, _accent(), true)
	var count := 0
	for choice in CharacterProfile.data.classes[selected].choices:
		if int(choice) >= 0: count += 1
	var equipped := label(title_row, Lang.t("%d / 6 talents equipped", [count]), 14, Palette.MUTED)
	equipped.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	for tier in 6:
		var required: int = Classes.TIERS[tier]
		var locked := level < required
		var active_choice := int(CharacterProfile.data.classes[selected].choices[tier])
		var section := _vbox(parent, 7)
		var heading := _row(section)
		_eyebrow(heading, Lang.t("LEVEL %d", [required]), Palette.DIM if locked else _accent())
		var state := label(heading, "Locked" if locked else "Ready to choose" if active_choice < 0 else "Talent equipped", 13, Palette.MUTED)
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		var row := _row(section, 12)
		for choice in 2:
			var talent: Array = Classes.CLASSES[selected].talents[tier][choice]
			var active := active_choice == choice
			var card := _interactive(row, _pick_talent.bind(tier, choice), _accent(), active, locked)
			card.panel.custom_minimum_size.y = 110
			var pick: Button = card.button
			pick.set_meta("talent_tier", tier)
			pick.set_meta("talent_choice", choice)
			pick.set_meta("talent_locked", locked)
			pick.tooltip_text = _requirement(tier) if locked else Lang.t("Equip %s", [talent[1]])
			_talent_buttons["%d:%d" % [tier, choice]] = pick
			var top := _row(card.content, 10)
			var marker := Icon.new()
			marker.symbol = "lock" if locked else "check" if active else "diamond"
			marker.class_id = selected
			marker.decorated = false
			marker.modulate.a = 0.7 if locked else 1.0
			marker.custom_minimum_size = Vector2(24, 24)
			top.add_child(marker)
			label(top, Lang.t("%s", [talent[1]]), 23, Palette.MUTED if locked else Palette.PAPER, true)
			label(card.content, talent[2], 15, Palette.MUTED if locked else Color("c3cbbd"))

func _render_teleport(parent: Node) -> void:
	_eyebrow(parent, "TELEPORT / LEVEL 15", _accent())
	label(parent, "Choose one teleport mode for the round. Your passive talents remain available.", 15, Palette.MUTED)
	var locked := CharacterProfile.level("assassin") < Classes.TELEPORT_LEVEL
	var row := _row(parent, 12)
	for option in Classes.TELEPORTS:
		var mode: String = option[0]
		var active: bool = CharacterProfile.data.classes.assassin.get("teleport", "") == mode
		var card := _interactive(row, _pick_teleport.bind(mode), _accent(), active, locked)
		card.panel.custom_minimum_size.y = 120
		card.button.set_meta("teleport_mode", mode)
		card.button.tooltip_text = _requirement(2) if locked else Lang.t("Equip %s", [option[1]])
		label(card.content, option[1], 23, Palette.MUTED if locked else Palette.PAPER, true)
		label(card.content, option[2], 15, Palette.MUTED)
		label(card.content, "Locked" if locked else "Talent equipped" if active else "Select", 13, _accent())
	_line(parent)

func _pick_teleport(mode: String) -> void:
	if CharacterProfile.level("assassin") < Classes.TELEPORT_LEVEL:
		_feedback(_requirement(2))
	elif CharacterProfile.choose_teleport(mode):
		_feedback(Lang.t("Teleport mode equipped. Press V during the round."))

func _requirement(tier: int) -> String:
	var required: int = Classes.TIERS[tier]
	var missing := maxi(0, Classes.threshold(required) - int(CharacterProfile.data.classes[selected].total_xp))
	return Lang.t("Requires %s level %d. You are level %d.\nEarn %s more class XP to unlock this tier.", [Classes.CLASSES[selected].name, required, CharacterProfile.level(selected), Lang.raw(number(missing))])

func _pick_talent(tier: int, choice: int) -> void:
	if CharacterProfile.level(selected) < Classes.TIERS[tier]:
		_show_locked(tier, choice)
		return
	if CharacterProfile.choose_skill(selected, tier, choice):
		_feedback(Lang.t("Talent equipped: %s", [Classes.CLASSES[selected].talents[tier][choice][1]]))
		_focus_talent.call_deferred(tier, choice)

func _focus_talent(tier: int, choice: int) -> void:
	var pick: Button = _talent_buttons.get("%d:%d" % [tier, choice])
	if is_instance_valid(pick): pick.grab_focus()

func _feedback(text: String) -> void:
	if not is_instance_valid(feedback): return
	feedback.text = text
	feedback.add_theme_color_override("font_color", _accent())
	_feedback_t = 5.0

func _render_progress(parent: Node) -> void:
	var stats: Dictionary = CharacterProfile.data.classes[selected].stats
	label(parent, Classes.CLASSES[selected].name, 34, _accent(), true)
	_eyebrow(parent, "Lifetime class statistics", Palette.MUTED)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	parent.add_child(grid)
	for entry in [["Kills", number(int(stats.kills))], ["Headshots", number(int(stats.headshots))], ["Best kill streak", str(int(stats.best_streak))], ["Boss kills", number(int(stats.boss_kills))], ["Play time", Lang.t("%dh %dm", [int(stats.seconds) / 3600, int(stats.seconds) / 60 % 60])], ["Deaths", number(int(stats.deaths))], ["Completed missions", str(int(stats.missions))], ["Waves survived", str(int(stats.waves))]]:
		var tile := PanelContainer.new()
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.add_theme_stylebox_override("panel", Palette.box(Palette.PANEL, Palette.LINE, 18))
		grid.add_child(tile)
		var column := _vbox(tile, 4)
		label(column, entry[1], 34, Palette.PAPER, true)
		label(column, entry[0], 14, Palette.MUTED)
	label(parent, Lang.t("Multiplayer: %s kills · %s missions", [Lang.raw(number(int(stats.multiplayer_kills))), Lang.raw(number(int(stats.multiplayer_missions)))]), 15, Palette.MUTED)
	var next := _next_tier(selected)
	var milestone := PanelContainer.new()
	milestone.add_theme_stylebox_override("panel", Palette.box(Color("222c20"), Color(_accent(),0.5), 18))
	parent.add_child(milestone)
	var column := _vbox(milestone, 8)
	label(column, Lang.t("NEXT UNLOCK · LEVEL %d\nA new passive talent tier", [next]) if next else "All six talent tiers unlocked", 24, _accent(), true)
	_milestones(column, selected)
	_spacer(parent, 6)
	_eyebrow(parent, "Profile achievements")
	for achievement in Classes.ACHIEVEMENTS:
		var done: bool = CharacterProfile.data.achievements.get(achievement[0], false)
		var row := _row(parent, 16)
		var marker := Icon.new()
		marker.symbol = "check" if done else "diamond"
		marker.class_id = selected
		marker.decorated = false
		marker.custom_minimum_size = Vector2(30, 30)
		marker.modulate.a = 1.0 if done else 0.35
		row.add_child(marker)
		var words := _vbox(row, 3)
		words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label(words, Lang.t("%s", [achievement[1]]), 24, _accent() if done else Palette.PAPER, true)
		label(words, achievement[2], 14, Palette.MUTED)
		var reward := label(row, Lang.t("%s XP", [Lang.raw(number(achievement[3]))]), 21, Palette.MUTED, true)
		reward.size_flags_horizontal = Control.SIZE_SHRINK_END
		reward.autowrap_mode = TextServer.AUTOWRAP_OFF
		_line(parent)
	label(parent, Lang.t("Profile: %d total kills · %d quests completed · %d achievements\nFavourite class: %s", [int(CharacterProfile.data.total_kills), _quest_count(), CharacterProfile.data.achievements.size(), Classes.CLASSES[CharacterProfile.favourite()].name]), 15, Palette.MUTED)
	label(parent, Lang.t("%d cosmetic unlocks", [CharacterProfile.data.cosmetics.size()]), 14, Palette.MUTED)

func _quest_count() -> int:
	var count := 0
	for value in CharacterProfile.data.quests.values(): count += int(value)
	return count

func _build_notice() -> void:
	notice = Control.new()
	notice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(notice)
	var dim := ColorRect.new()
	dim.color = Color(0.01,0.02,0.015,0.86)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	notice.add_child(dim)
	var centre := CenterContainer.new()
	centre.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	notice.add_child(centre)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 560
	panel.add_theme_stylebox_override("panel", Palette.box(Palette.INK, Palette.GOLD, 28))
	centre.add_child(panel)
	_surface(panel, Palette.GOLD)
	notice_body = _vbox(panel, 16)
	notice.hide()

func _show_locked(tier: int, choice: int) -> void:
	clear(notice_body)
	_eyebrow(notice_body, "Talent locked")
	var top := _row(notice_body, 18)
	var lock := Icon.new()
	lock.symbol = "lock"
	lock.class_id = selected
	lock.decorated = false
	lock.custom_minimum_size = Vector2(48,48)
	top.add_child(lock)
	label(top, Lang.t("%s", [Classes.CLASSES[selected].talents[tier][choice][1]]), 36, Palette.PAPER, true)
	label(notice_body, _requirement(tier), 19)
	_bar(notice_body, CharacterProfile.data.classes[selected].total_xp, Classes.threshold(Classes.TIERS[tier]), _accent(), 7)
	label(notice_body, "Earn XP through combat, quests and completed waves. Choosing a talent does not spend XP.", 16, Palette.MUTED)
	var acknowledge := button(notice_body, "Understood", func(): notice.hide(); _focus_talent(tier, choice), true)
	notice.show()
	acknowledge.grab_focus()

func _open_profiles() -> void:
	clear(notice_body)
	_eyebrow(notice_body, "Survivor dossier")
	label(notice_body, "Local character profile", 34, Palette.PAPER, true)
	var profiles := CharacterProfile.profiles()
	_profile_ids = profiles.keys()
	var picker := OptionButton.new()
	picker.custom_minimum_size.y = 44
	for pid in _profile_ids: picker.add_item(Lang.t("%s", [Lang.raw(str(profiles[pid]))]))
	picker.select(_profile_ids.find(CharacterProfile.profile_id))
	picker.disabled = not CharacterProfile.can_edit()
	picker.item_selected.connect(func(index: int):
		if CharacterProfile.can_edit() and CharacterProfile.load_profile(str(_profile_ids[index])): notice.hide())
	notice_body.add_child(picker)
	_line(notice_body)
	var row := _row(notice_body)
	var name_field := LineEdit.new()
	name_field.placeholder_text = "New profile name"
	name_field.max_length = 24
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_field)
	var create := button(row, "Create profile", func():
		if CharacterProfile.create_profile(name_field.text): notice.hide(), true)
	create.disabled = not CharacterProfile.can_edit()
	button(notice_body, "Back", func(): notice.hide())
	notice.show()
	picker.grab_focus()

func _process(delta: float) -> void:
	if not hud: return
	var available: bool = hud.overlay.visible and hud.overlay_mode == "start" and not hud.game.started and not hud._loading and not hud.map_selection.visible
	if modal.visible and (not available or not CharacterProfile.can_edit()): close()
	if not available: notice.hide()
	summary.visible = available and not modal.visible and not hud._menu_detail.visible
	_refresh_t += delta
	if _refresh_t >= 0.5:
		_refresh_t = 0.0
		var signature := "%s:%s:%s" % [CharacterProfile.profile_id, CharacterProfile.selected(), CharacterProfile.context]
		if signature != _signature: _signature = signature; refresh()
	if _feedback_t > 0:
		_feedback_t -= delta
		if _feedback_t <= 0 and is_instance_valid(feedback):
			feedback.text = "One talent per tier. Change your choices freely in the main menu."
			feedback.add_theme_color_override("font_color", Palette.MUTED)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if notice.visible:
			notice.hide()
			get_viewport().set_input_as_handled()
		elif modal.visible:
			close()
			get_viewport().set_input_as_handled()
