# Hold Tab for the current round's standings. This overlay never pauses gameplay or captures the mouse.
extends CanvasLayer

var game: Node
var panel: PanelContainer
var rows_box: VBoxContainer
var scroll: ScrollContainer
var subtitle: Label
var _signature := ""

func setup(node: Node) -> void:
	game = node
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel = PanelContainer.new()
	root.add_child(panel)
	panel.anchor_left = 0.10
	panel.anchor_right = 0.90
	panel.anchor_top = 0.23
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.04, 0.055, 0.97)
	style.border_color = Color(0.66, 0.48, 0.22)
	style.set_border_width_all(1)
	style.border_width_top = 3
	style.set_corner_radius_all(10)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 22
	style.content_margin_bottom = 22
	panel.add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	box.add_child(_label("LEADERBOARD", 28, Hud.PAPER))
	subtitle = _label("", 16, Hud.GOLD)
	box.add_child(subtitle)
	box.add_child(_row(["#", "SPIELER", "KILLS", "HEADSHOTS", "DEATHS", "TITAN KILLS", "ASSISTS", "PUNKTE", "PING"], true))
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.focus_mode = Control.FOCUS_NONE
	box.add_child(scroll)
	rows_box = VBoxContainer.new()
	rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows_box.add_theme_constant_override("separation", 4)
	scroll.add_child(rows_box)
	var help := _label("TAB halten · Q Aufträge · Punkte = Guthaben · Ping zum Host\nHeadshots = Kills durch Kopfschuss. Assists = Schaden beigetragen, Mitspieler erzielt den Kill.", 14, Hud.MUTED)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(help)
	panel.hide()

func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _row(values: Array, heading := false, local := false) -> PanelContainer:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.34, 0.25, 0.12, 0.65) if local else Color(0.10, 0.13, 0.16, 0.65)
	style.set_content_margin_all(10)
	style.set_corner_radius_all(4)
	row.add_theme_stylebox_override("panel", style)
	var line := HBoxContainer.new()
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_theme_constant_override("separation", 8)
	row.add_child(line)
	for i in values.size():
		var label := _label(str(values[i]), 14 if heading else 19, Hud.GOLD if local else Hud.MUTED if heading else Hud.PAPER)
		label.custom_minimum_size.x = 32 if i == 0 else 220 if i == 1 else 100 if i == 7 else 90 if i == 8 else 116
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i < 2 else HORIZONTAL_ALIGNMENT_CENTER
		if i == 1:
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		line.add_child(label)
	return row

func _allowed() -> bool:
	if not game or not game.started: return false
	var focus := get_viewport().gui_get_focus_owner()
	if focus is LineEdit or focus is TextEdit: return false
	return game.player.active or game.over or not game.player.alive or game.hud.overlay.visible

func _input(event: InputEvent) -> void:
	if event.is_action_released("leaderboard"):
		panel.hide()
	elif event.is_action_pressed("leaderboard") and not event.is_echo() and _allowed():
		refresh()
		panel.show()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and panel: panel.hide()

func _process(_delta: float) -> void:
	if not panel or not panel.visible: return
	if not _allowed():
		panel.hide()
		return
	refresh()

func refresh() -> void:
	if not NetSession.enabled: game.stats.update_live(game.player.peer_id, game.player.score, 0)
	elif NetSession.is_host() and NetSession.world: NetSession.world.refresh_leaderboard()
	var entries: Array = game.stats.leaderboard_rows()
	var signature := str([entries, game.waves.wave, game.over])
	if signature == _signature: return
	_signature = signature
	scroll.custom_minimum_size.y = minf(260, entries.size() * 51)
	subtitle.text = "%s · WELLE %d · %s" % ["KOOP" if NetSession.enabled else "SOLO", maxi(1, game.waves.wave), "RUNDENENDE" if game.over else "LAUFENDE RUNDE"]
	for child in rows_box.get_children():
		rows_box.remove_child(child)
		child.queue_free()
	var rank := 0
	for entry: Dictionary in entries:
		rank += 1
		var local: bool = int(entry.id) == NetSession.local_id()
		var display_name := str(entry.name) + (" · DU" if local else "") + (" · OFFLINE" if not entry.connected else "")
		var ping: int = entry.get("ping_ms", -1)
		var ping_text := "%d ms" % ping if entry.connected and ping >= 0 else "—"
		rows_box.add_child(_row([rank, display_name, entry.kills, entry.headshots, entry.deaths, entry.titan_kills, entry.assists, entry.get("score", 0), ping_text], false, local))
