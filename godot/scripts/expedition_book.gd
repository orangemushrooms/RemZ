extends CanvasLayer
## One accessible fieldbook for both maps. Solo pauses; cooperative play keeps running.
var director: RunDirector
var panel: PanelContainer
var pages: TabContainer
var status: Label
var heading: Label
var message_label: Label
var is_open := false
var _was_active := false
var _was_paused := false
var _refresh_t := 0.0
var _signature := ""
var _overview: Label
var _team: VBoxContainer
var _augments: VBoxContainer
var _journal: VBoxContainer
var _run: VBoxContainer
var _mode: OptionButton
var _code: LineEdit
var launch: Button

func setup(run: RunDirector) -> void:
	director = run
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 31
	status = Label.new()
	status.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	status.offset_top = 140
	status.offset_left = 200
	status.offset_right = -200
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 15)
	status.add_theme_constant_override("outline_size", 4)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(status)
	launch = Button.new()
	launch.text = Lang.t("Fieldbook [K]")
	launch.position = Vector2(20, 70)
	launch.pressed.connect(toggle)
	add_child(launch)
	launch.visible = director.enabled
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(890, 590)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.075, 1)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	panel.resized.connect(_fit)
	get_viewport().size_changed.connect(_fit)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	var row := HBoxContainer.new()
	root.add_child(row)
	heading = _label("EXPEDITION FIELDBOOK", 24)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(heading)
	_button(row, "Close [K / Esc]", close)
	message_label = _label("", 15)
	message_label.modulate = Color(1, 0.76, 0.35)
	root.add_child(message_label)
	pages = TabContainer.new()
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(pages)
	var overview := _page("Operations")
	_overview = _label("", 15)
	overview.add_child(_overview)
	_button(overview, "Use class action [Z]", func(): _request("ability"))
	_button(overview, "Interact with nearby objective [E]", func(): _request("interact", [director.nearest(director.game.player)]))
	if director.config.region == "planes":
		_button(overview, "Accept long-range elite contract at camp", func(): _request("contract"))
		_button(overview, "Collect / return supply crate at camp", func(): _request("cargo"))
		_button(overview, "Extinguish nearby crop fire · 1 bandage", func(): _request("extinguish"))
		var build := HBoxContainer.new()
		overview.add_child(build)
		for id in ["gate", "embrasure", "observation"]:
			var name: String = director.structures.NAMES[id]
			_button(build, Lang.t("%s · %d R", [Lang.t(name), director.structures.COSTS[id]]), func(): _request("build", [id]))
		_button(overview, "Repair nearest expedition fortification · 30 R", func():
			var id: String = director.structures.nearest(director.game.player)
			if not id.is_empty(): _request("structure", [int(id.trim_prefix("structure_")), "repair"]))
		var range_buttons := HBoxContainer.new()
		overview.add_child(range_buttons)
		for mode in ["timed", "sequence", "competition"]:
			_button(range_buttons, "Timed series" if mode == "timed" else "Target sequence" if mode == "sequence" else "Team competition", func(): _request("range", [mode]))
	_augments = _page("Augments")
	_team = _page("Team support")
	_journal = _page("Journal & bestiary")
	_run = _page("Run & checkpoint")
	_build_run()
	panel.hide()
	_fit()

func _fit() -> void:
	if not panel: return
	var viewport := get_viewport().get_visible_rect().size
	panel.custom_minimum_size = Vector2(minf(890, viewport.x-32), minf(590, viewport.y-40))
	panel.size = panel.custom_minimum_size
	panel.position = (viewport-panel.size)*0.5

func _label(value: String, size: int = 15) -> Label:
	var label := Label.new()
	label.text = Lang.t(value)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	return label

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = Lang.t(text)
	button.custom_minimum_size.y = 34
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _page(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	pages.add_child(scroll)
	pages.set_tab_title(pages.get_tab_count()-1, Lang.t(title))
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)
	return box

func _build_run() -> void:
	_run.add_child(_label("Run settings can be changed before wave one. Use the same map and run code to reproduce wave profiles, missions, augments and weather."))
	_code = LineEdit.new()
	_code.placeholder_text = Lang.t("Paste a run code")
	_code.text = RunRules.encode(director.config)
	_code.max_length = 48
	_run.add_child(_code)
	var row := HBoxContainer.new()
	_run.add_child(row)
	_button(row, "Copy run code", func(): DisplayServer.clipboard_set(RunRules.encode(director.config)))
	_button(row, "Apply run code", func():
		var config := RunRules.decode(_code.text)
		message_label.text = Lang.t("Invalid run code or wrong map.") if config.is_empty() or config.get("region") != director.config.region else Lang.t("Run configured.") if director.configure(config) else Lang.t("Only the host can configure a run before wave one.")
		_signature = "")
	_mode = OptionButton.new()
	for name in RunRules.MODE_NAMES: _mode.add_item(Lang.t(name))
	_mode.select(RunRules.MODES.find(director.config.mode))
	_run.add_child(_mode)
	_button(_run, "Apply challenge", func():
		var config := director.config.duplicate()
		config.mode = RunRules.MODES[_mode.selected]
		message_label.text = Lang.t("Run configured.") if director.configure(config) else Lang.t("Only the host can configure a run before wave one.")
		_code.text = RunRules.encode(director.config))
	_run.add_child(_label("Save in a quiet wave intermission. For a cooperative checkpoint the same player slots must join before the host loads it. Completed rewards are not issued again."))
	_button(_run, "Save checkpoint", func(): _request("save"))
	_button(_run, "Continue saved expedition", func(): _request("load"))

func toggle() -> void:
	if is_open: close()
	else: open()

func open() -> void:
	if not director.enabled or is_open: return
	var game := director.game
	if game.over: return
	if game.inventory.is_open: game.inventory.close()
	if game.progression.is_open: game.progression.close()
	if game.defences.is_open: game.defences.close()
	if game.brewing.menu.is_open: game.brewing.menu.close()
	for id in ["skills", "barricade_menu", "drones", "cheat_menu"]:
		var menu: Variant = game.get(id)
		if menu and menu.is_open: menu.close()
	game.defences.cancel_placement()
	if game.get("field_building"): game.field_building.cancel()
	_was_active = game.player.active
	_was_paused = get_tree().paused
	is_open = true
	game.player.active = false
	if not NetSession.enabled: get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.show()
	_signature = ""
	refresh()
	_fit()

func close() -> void:
	if not is_open: return
	is_open = false
	panel.hide()
	get_tree().paused = _was_paused if not NetSession.enabled else false
	director.game.player.active = _was_active and not director.game.over
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if director.game.player.active else Input.MOUSE_MODE_VISIBLE

func _request(action: String, args: Array = []) -> void:
	var result := director.request(action, args)
	message_label.text = Lang.t(result)
	if action == "load" and result == "Expedition continued.":
		_was_paused = false
		_was_active = true
		close()
		director.game.hud.hide_overlay()
		director.game.player.active = true
		get_tree().paused = false
	_signature = ""
	refresh()

func _clear(box: Node) -> void:
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

func refresh() -> void:
	var peer: int = director.game.player.peer_id
	var p := director.person(peer)
	var weather := director.forecast()
	var lines := PackedStringArray([RunRules.encode(director.config), Lang.t("Forecast: %s → %s in %d s", [Lang.t(str(weather.state).capitalize()), Lang.t(str(weather.next).capitalize()), weather.seconds]),
		Lang.t("Bandages: %d · Action ready in %d s", [p.bandages, ceili(maxf(0, p.cooldown-director.elapsed))])])
	if not director.operation.is_empty():
		var op := director.operation
		lines.append(Lang.t("Operation: %s · %s · %d m · Health %d", [Lang.t(str(op.kind).capitalize()), Lang.t(str(op.stage).capitalize()), roundi(Vector3(op.at).distance_to(director.game.player.global_position)), ceili(op.health)]))
	if not director.finale.is_empty():
		var final := director.finale
		lines.append(Lang.t("Final defence: %s · %d s · Health %d", [Lang.t(str(final.stage).capitalize()), ceili(final.timer), ceili(final.health)]))
	if director.config.region == "planes":
		lines.append(Lang.t("Long-range elites: %d / 5 · Supply deliveries: %d", [p.longshots, director.cargo_deliveries]))
		lines.append(Lang.t("Transmitter order: %d → %d → %d · Progress %d / 3", [int(director.puzzle_order[0])+1, int(director.puzzle_order[1])+1, int(director.puzzle_order[2])+1, director.puzzle_step]))
		if director.cargo_peer:
			lines.append(Lang.t("Supply destination: %d m", [roundi(director.cargo_destination().distance_to(director.game.player.global_position))]))
		if not director.range_game.is_empty():
			var r := director.range_game
			lines.append(Lang.t("Range: %d s · Score %d", [ceili(r.timer), int(r.scores.get(peer, 0))]))
			if r.mode == "sequence" and r.timer > 0: lines.append(Lang.t("Next target: %d", [int(r.sequence[int(r.progress.get(peer, 0)) % 6])+1]))
	for site in director.sites:
		if not site.done:
			var offset: Vector3 = site.at-director.game.player.global_position
			var bearing := posmod(roundi(rad_to_deg(atan2(offset.x, -offset.z))/45.0), 8)
			var compass: String = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][bearing]
			var title: String = Lang.t("Transmitter %d", [int(site.id.trim_prefix("site_"))-4]) if site.kind == "signal" else Lang.t("Outpost" if site.kind == "outpost" else "Cache")
			lines.append(Lang.t("%s · %d m · %s", [title, roundi(offset.length()), compass]))
	_overview.text = "\n".join(lines)
	var signature := str([p.augments, p.offers, director.people.keys(), CharacterProfile.data.get("journal", {}), CharacterProfile.data.get("mastery", {}), CharacterProfile.data.get("title", ""), director.game.brewing.stock(peer).drinks])
	if signature == _signature: return
	_signature = signature
	_clear(_augments)
	_augments.add_child(_label("Choose one of three offers after waves 3, 7, 12, 17 and 22. The choice lasts for this expedition."))
	for id in p.offers:
		_augments.add_child(_label(RunRules.AUGMENTS[id][1]))
		_button(_augments, RunRules.AUGMENTS[id][0], func(): _request("augment", [id]))
	for id in p.augments: _augments.add_child(_label(Lang.t("Selected: %s", [Lang.t(RunRules.AUGMENTS[id][0])]), 17))
	_clear(_team)
	_team.add_child(_label("Transfers and healing require a living teammate within three metres and a clear line of sight."))
	_button(_team, "Buy bandage at camp · 25 R", func(): _request("buy_bandage"))
	for id in director.people:
		if id == peer: continue
		_team.add_child(_label(str(NetSession.roster.get(id, Lang.t("Teammate %d", [id]))), 18))
		var row := HBoxContainer.new()
		_team.add_child(row)
		for kind in ["heal", "bandage", "ammo"]: _button(row, "Heal teammate" if kind == "heal" else "Give bandage" if kind == "bandage" else "Give ammunition", func(): _request(kind, [id]))
		var drinks: Dictionary = director.game.brewing.stock(peer).drinks
		for drink in drinks:
			if int(drinks[drink]) > 0: _button(_team, Lang.t("Give %s", [Lang.t(preload("res://scripts/brew_recipes.gd").DRINKS[drink].name)]), func(): _request("drink", [id, drink]))
	_clear(_journal)
	_journal.add_child(_label("Class and weapon mastery unlock cosmetic badges and titles. Mastery grants no combat bonus."))
	_journal.add_child(_label(Lang.t("Equipped title: %s", [CharacterProfile.mastery_title(CharacterProfile.data.get("title", ""))])))
	for id in CharacterProfile.data.cosmetics:
		var title: String = CharacterProfile.mastery_title(id)
		if not title.is_empty(): _button(_journal, Lang.t("Equip title: %s", [title]), func(): CharacterProfile.choose_title(id); _signature = ""; refresh())
	_journal.add_child(_label(Lang.t("Class mastery: %d · Weapon mastery: %s", [int(CharacterProfile.data.get("mastery", {}).get("classes", {}).get(CharacterProfile.active_class(), 0))/5000, str(CharacterProfile.data.get("mastery", {}).get("weapons", {}))])))
	var journal: Dictionary = CharacterProfile.data.get("journal", {})
	for i in RunRules.LORE.size():
		if journal.get("record_%d" % i, false):
			_journal.add_child(_label(RunRules.LORE[i][0], 18))
			_journal.add_child(_label(RunRules.LORE[i][1]))
	for id in RunRules.BESTIARY:
		if journal.get(id, false):
			_journal.add_child(_label(RunRules.BESTIARY[id][0], 18))
			_journal.add_child(_label(RunRules.BESTIARY[id][1]))

func _process(delta: float) -> void:
	if not director or not director.enabled: return
	if is_open and (director.game.over or not director.game.player.alive or director.game.player.downed): close()
	launch.visible = not director.game.over
	if director.game.over:
		status.hide()
		return
	_refresh_t -= delta
	if _refresh_t > 0: return
	_refresh_t = 0.25
	if is_open: refresh()
	status.visible = director.game.started and not director.game.over and not is_open and not director.game.hud.overlay.visible
	if not status.visible: return
	var p := director.person(director.game.player.peer_id)
	var text := Lang.t("[K] Fieldbook · [Z] Class action · Bandages %d", [p.bandages])
	if not director.finale.is_empty(): text = Lang.t("Final defence · %d s · Health %d · [E] at the objective", [ceili(director.finale.timer), ceili(director.finale.health)])
	elif not director.operation.is_empty() and not director.operation.done: text += Lang.t(" · Operation %d m", [roundi(Vector3(director.operation.at).distance_to(director.game.player.global_position))])
	status.text = text

func _input(event: InputEvent) -> void:
	if is_open and event is InputEventKey and event.pressed and event.physical_keycode not in [KEY_ESCAPE, KEY_K, KEY_TAB, KEY_ENTER, KEY_SPACE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT] and not get_viewport().gui_get_focus_owner() is LineEdit:
		get_viewport().set_input_as_handled()
	if not is_open and director and director.enabled and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_K:
		open()
		get_viewport().set_input_as_handled()
		return
	if is_open and event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_ESCAPE, KEY_K]:
		close()
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if is_open: get_tree().paused = false
