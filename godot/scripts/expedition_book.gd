extends CanvasLayer
## An intentional, modal fieldbook. The world HUD only shows an active final objective.
const INK := Color("151e21")
const CARD := Color("1e2b2d")
const PAPER := Color("edf0e4")
const MUTED := Color("a6b8b2")
const ACCENT := Color("d8ba79")
var director: RunDirector
var panel: PanelContainer
var pages: TabContainer
var status: Label
var heading: Label
var message_label: Label
var launch: Button # Kept for integrations; opening the book belongs in the pause menu.
var is_open := false
var _was_active := false
var _was_paused := false
var _previous_focus: Control
var _refresh_t := 0.0
var _signature := ""
var _augment_signature := ""
var _team_signature := ""
var _journal_signature := ""
var _backdrop: ColorRect
var _subtitle: Label
var _close_button: Button
var _navigation: Array[Button] = []
var _navigation_group := ButtonGroup.new()
var _objective_title: Label
var _overview: Label
var _weather: Label
var _ability: Label
var _ability_button: Button
var _interact_button: Button
var _exploration: Label
var _quests: VBoxContainer
var _quest_signature := ""
var _orders: Label
var _camp_actions: VBoxContainer
var _contract_button: Button
var _cargo_button: Button
var _fire_button: Button
var _repair_button: Button
var _range_box: VBoxContainer
var _range_status: Label
var _range_buttons: Array[Button] = []
var _team: VBoxContainer
var _augments: VBoxContainer
var _journal: VBoxContainer
var _run: VBoxContainer
var _mode: OptionButton
var _code: LineEdit
var _apply_code: Button
var _apply_mode: Button
var _run_hint: Label
var _save_button: Button
var _load_button: Button
var _save_hint: Label
var _confirm_load: ConfirmationDialog
var _buy_bandage: Button
var _bandages: Label
var _team_buttons: Array[Dictionary] = []
var _message_t := 0.0
var _viewport_size := Vector2.ZERO

func setup(run: RunDirector) -> void:
	director = run
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 31
	status = _label("", 16)
	status.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	status.offset_top = 140
	status.offset_left = 200
	status.offset_right = -200
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_constant_override("outline_size", 4)
	status.hide()
	add_child(status)
	launch = Button.new()
	launch.hide()
	launch.pressed.connect(toggle)
	add_child(launch)
	_backdrop = ColorRect.new()
	_backdrop.color = Color(0.025, 0.04, 0.04, 0.76)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_backdrop.hide()
	add_child(_backdrop)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _style(INK, 24, 10))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)
	get_viewport().size_changed.connect(_fit)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	panel.add_child(layout)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 20)
	layout.add_child(header)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 3)
	header.add_child(titles)
	heading = _label("Fieldbook", 28, PAPER)
	titles.add_child(heading)
	_subtitle = _label("", 14, MUTED)
	titles.add_child(_subtitle)
	_close_button = _button(header, "Back to game", close)
	_close_button.custom_minimum_size.x = 160
	_close_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_close_button.tooltip_text = Lang.t("Close with Escape")
	header = HBoxContainer.new()
	header.size_flags_vertical = Control.SIZE_EXPAND_FILL
	header.add_theme_constant_override("separation", 22)
	layout.add_child(header)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 156
	sidebar.add_theme_constant_override("separation", 7)
	header.add_child(sidebar)
	pages = TabContainer.new()
	pages.tabs_visible = false
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	header.add_child(pages)
	var overview := _page("Overview", sidebar)
	_build_overview(overview)
	_augments = _page("Augments", sidebar)
	_team = _page("Team", sidebar)
	_journal = _page("Discoveries", sidebar)
	_run = _page("Expedition", sidebar)
	_build_run()
	pages.tab_changed.connect(_tab_changed)
	message_label = _label("", 14, ACCENT)
	message_label.custom_minimum_size.y = 20
	layout.add_child(message_label)
	_confirm_load = ConfirmationDialog.new()
	_confirm_load.title = Lang.t("Continue saved expedition")
	_confirm_load.dialog_text = Lang.t("Continue the saved checkpoint? Your current unsaved progress will be replaced.")
	_confirm_load.ok_button_text = Lang.t("Continue checkpoint")
	_confirm_load.cancel_button_text = Lang.t("Cancel")
	_confirm_load.confirmed.connect(func(): _request("load"))
	add_child(_confirm_load)
	panel.hide()
	_tab_changed(0)
	_fit()

func _style(colour: Color, margin: int = 14, radius: int = 7) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = colour
	style.set_content_margin_all(margin)
	style.set_corner_radius_all(radius)
	return style

func _fit() -> void:
	if not panel: return
	var viewport := get_viewport().get_visible_rect().size
	_viewport_size = viewport
	panel.custom_minimum_size = Vector2(minf(980, viewport.x-48), minf(660, viewport.y-48))
	panel.size = panel.custom_minimum_size
	panel.position = (viewport-panel.size)*0.5

func _label(value: String, size: int = 16, colour: Color = PAPER) -> Label:
	var label := Label.new()
	label.text = Lang.t(value)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _button(parent: Node, value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = Lang.t(value)
	button.custom_minimum_size.y = 38
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	button.add_theme_font_size_override("font_size", 15)
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_disabled_color", MUTED.darkened(0.3))
	button.add_theme_stylebox_override("normal", _style(Color("314244"), 10, 5))
	button.add_theme_stylebox_override("hover", _style(Color("405658"), 10, 5))
	button.add_theme_stylebox_override("pressed", _style(Color("526158"), 10, 5))
	button.add_theme_stylebox_override("disabled", _style(Color("253031"), 10, 5))
	var focus := _style(Color(0, 0, 0, 0), 0, 5)
	focus.set_border_width_all(2)
	focus.border_color = ACCENT
	button.add_theme_stylebox_override("focus", focus)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _page(title: String, sidebar: VBoxContainer) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	pages.add_child(scroll)
	var index := pages.get_tab_count()-1
	pages.set_tab_title(index, Lang.t(title))
	var nav := _button(sidebar, title, func(): pages.current_tab = index)
	nav.alignment = HORIZONTAL_ALIGNMENT_LEFT
	nav.toggle_mode = true
	nav.button_group = _navigation_group
	nav.custom_minimum_size.y = 46
	_navigation.append(nav)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 9)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	return box

func _tab_changed(index: int) -> void:
	for i in _navigation.size():
		_navigation[i].set_pressed_no_signal(i == index)
	if is_open:
		_navigation[index].grab_focus()
		refresh()

func _card(parent: Node, title: String = "") -> VBoxContainer:
	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", _style(CARD))
	parent.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	card.add_child(box)
	if not title.is_empty(): box.add_child(_label(title, 17, ACCENT))
	return box

func _details(parent: Node, title: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	var button := _button(parent, title, func(): box.visible = not box.visible)
	button.toggle_mode = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.hide()
	parent.add_child(box)
	return box

func _build_overview(overview: VBoxContainer) -> void:
	var objective := _card(overview)
	_objective_title = _label("Your next step", 18, ACCENT)
	objective.add_child(_objective_title)
	_overview = _label("")
	objective.add_child(_overview)
	_interact_button = _button(objective, "Interact with objective", func(): _request("interact", [director.nearest(director.game.player)]))
	var conditions := HBoxContainer.new()
	conditions.add_theme_constant_override("separation", 12)
	overview.add_child(conditions)
	var weather := _card(conditions, "Field conditions")
	_weather = _label("", 15, MUTED)
	weather.add_child(_weather)
	var ability := _card(conditions, "Class action")
	_ability = _label("", 15, MUTED)
	ability.add_child(_ability)
	_ability_button = _button(ability, "Use class action", func(): _request("ability"))
	_quests = _details(overview, "Your quests")
	var exploration := _details(overview, "Places to explore")
	_exploration = _label("", 15, MUTED)
	exploration.add_child(_exploration)
	if director.config.region != "planes": return
	var orders := _details(overview, "Field assignments")
	_orders = _label("", 15, MUTED)
	orders.add_child(_orders)
	_camp_actions = VBoxContainer.new()
	_camp_actions.add_theme_constant_override("separation", 8)
	orders.add_child(_camp_actions)
	_contract_button = _button(_camp_actions, "Accept long-range elite contract at camp", func(): _request("contract"))
	_cargo_button = _button(_camp_actions, "Collect / return supply crate at camp", func(): _request("cargo"))
	var build := _details(overview, "Field fortifications")
	build.add_child(_label("Face the intended building site before opening the fieldbook. Keep paths and objectives clear.", 15, MUTED))
	for id in ["gate", "embrasure", "observation"]:
		var title: String = director.structures.NAMES[id]
		_button(build, Lang.t("%s · %d R", [Lang.t(title), director.structures.COSTS[id]]), func(): _request("build", [id]))
	_repair_button = _button(build, "Repair nearest expedition fortification · 30 R", func():
		var id: String = director.structures.nearest(director.game.player)
		if not id.is_empty(): _request("structure", [int(id.trim_prefix("structure_")), "repair"]))
	_fire_button = _button(overview, "Extinguish nearby crop fire · 1 bandage", func(): _request("extinguish"))
	_range_box = _details(overview, "Shooting range")
	_range_status = _label("", 15, MUTED)
	_range_box.add_child(_range_status)
	for mode in ["timed", "sequence", "competition"]:
		_range_buttons.append(_button(_range_box, "Timed series" if mode == "timed" else "Target sequence" if mode == "sequence" else "Team competition", func(): _request("range", [mode])))

func _build_run() -> void:
	var checkpoint := _card(_run, "Checkpoint")
	_save_hint = _label("", 15, MUTED)
	checkpoint.add_child(_save_hint)
	_save_button = _button(checkpoint, "Save checkpoint", func(): _request("save"))
	_load_button = _button(checkpoint, "Continue saved expedition", func(): _confirm_load.popup_centered(Vector2i(460, 150)))
	var challenge := _card(_run, "Challenge")
	_run_hint = _label("", 15, MUTED)
	challenge.add_child(_run_hint)
	_mode = OptionButton.new()
	_mode.custom_minimum_size.y = 38
	for title in RunRules.MODE_NAMES: _mode.add_item(Lang.t(title))
	_mode.select(RunRules.MODES.find(director.config.mode))
	challenge.add_child(_mode)
	_apply_mode = _button(challenge, "Apply challenge", func():
		var config := director.config.duplicate()
		config.mode = RunRules.MODES[_mode.selected]
		_feedback("Run configured." if director.configure(config) else "Only the host can configure a run before wave one.")
		_code.text = RunRules.encode(director.config)
		refresh())
	var code := _details(_run, "Share or enter a run code")
	code.add_child(_label("Use the same map and code to replay the same expedition conditions.", 15, MUTED))
	_code = LineEdit.new()
	_code.placeholder_text = Lang.t("Paste a run code")
	_code.text = RunRules.encode(director.config)
	_code.max_length = 48
	_code.custom_minimum_size.y = 38
	code.add_child(_code)
	_button(code, "Copy run code", func():
		DisplayServer.clipboard_set(RunRules.encode(director.config))
		_feedback("Run code copied."))
	_apply_code = _button(code, "Apply run code", func():
		var config := RunRules.decode(_code.text.strip_edges())
		_feedback("Invalid run code or wrong map." if config.is_empty() or config.get("region") != director.config.region else "Run configured." if director.configure(config) else "Only the host can configure a run before wave one.")
		_mode.select(RunRules.MODES.find(director.config.mode))
		refresh())

func toggle() -> void:
	if is_open: close()
	else: open()

func open() -> void:
	if not director.enabled or is_open: return
	var game := director.game
	if not game.started or game.over or not game.player.alive or game.player.downed: return
	if game.get("intro") and game.intro.active: return
	if game.player.controlling_drone or game.player.mounted_tower: return
	if game.hud.overlay.visible and game.hud.overlay_mode != "pause": return
	if not game.player.active and not game.hud.overlay.visible: return
	_was_active = game.player.active
	_was_paused = get_tree().paused
	_previous_focus = get_viewport().gui_get_focus_owner()
	_close_button.text = Lang.t("Back to menu" if game.hud.overlay.visible else "Back to game")
	if game.inventory.is_open: game.inventory.close()
	if game.progression.is_open: game.progression.close()
	if game.defences.is_open: game.defences.close()
	if game.brewing.menu.is_open: game.brewing.menu.close()
	for id in ["skills", "barricade_menu", "drones", "cheat_menu"]:
		var menu: Variant = game.get(id)
		if menu and menu.is_open: menu.close()
	game.defences.cancel_placement()
	if game.get("field_building") and (game.field_building.placing or game.field_building.kit_menu.visible): game.field_building.cancel()
	is_open = true
	game.player.active = false
	if not NetSession.enabled: get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_backdrop.show()
	panel.show()
	status.hide()
	_signature = ""
	message_label.text = ""
	refresh()
	_fit()
	_navigation[pages.current_tab].grab_focus()

func close() -> void:
	if not is_open: return
	is_open = false
	_confirm_load.hide()
	panel.hide()
	_backdrop.hide()
	var focused := get_viewport().gui_get_focus_owner()
	if focused: focused.release_focus()
	if is_instance_valid(_previous_focus) and _previous_focus.is_visible_in_tree(): _previous_focus.grab_focus()
	get_tree().paused = _was_paused if not NetSession.enabled else false
	var player: Player = director.game.player
	player.active = _was_active and not director.game.over and player.alive and not player.downed
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if player.active else Input.MOUSE_MODE_VISIBLE

func _feedback(value: String) -> void:
	message_label.text = Lang.t(value)
	_message_t = 6.0

func _request(action: String, args: Array = []) -> void:
	var result := director.request(action, args)
	if not result.is_empty(): _feedback(result)
	if action == "ability" and (result == "Class action activated." or (NetSession.enabled and result.is_empty())):
		close() # A short combat buff should begin with the player back in control.
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
	var focused := get_viewport().gui_get_focus_owner()
	if is_open and focused and box.is_ancestor_of(focused): _navigation[pages.current_tab].grab_focus()
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()

func refresh() -> void:
	var peer: int = director.game.player.peer_id
	var state := director.person(peer)
	_subtitle.text = Lang.t("%s · %s", [Lang.t("Forest" if director.config.region == "forest" else "The Planes"), Lang.t("World paused" if not NetSession.enabled else "Co-op continues while you read")])
	_refresh_overview(state)
	_refresh_quests()
	_refresh_run()
	var force := _signature.is_empty()
	_signature = "ready"
	var signature := str([state.augments, state.offers, director.game.waves.completed])
	if force or signature != _augment_signature:
		_augment_signature = signature
		_build_augments(state)
	signature = str([director.people.keys(), NetSession.roster, director.game.brewing.stock(peer).drinks])
	if force or signature != _team_signature:
		_team_signature = signature
		_build_team(peer)
	signature = str([CharacterProfile.data.get("journal", {}), CharacterProfile.data.get("mastery", {}), CharacterProfile.data.get("title", "")])
	if force or (pages.current_tab == 3 and signature != _journal_signature):
		_journal_signature = signature
		_build_journal()
	_refresh_team(state)

func _refresh_overview(state: Dictionary) -> void:
	var player: Player = director.game.player
	_objective_title.text = Lang.t("Your next step")
	_overview.text = Lang.t("Visit the Vendor at camp, prepare your equipment and follow your current quest. Explore at your own pace between waves.")
	if not director.finale.is_empty():
		_objective_title.text = Lang.t("Final defence")
		_overview.text = Lang.t("Final defence: %s · %d s · Health %d", [Lang.t(str(director.finale.stage).capitalize()), ceili(director.finale.timer), ceili(director.finale.health)])
	elif not director.operation.is_empty() and not director.operation.done:
		_objective_title.text = Lang.t("Optional operation")
		var op := director.operation
		_overview.text = Lang.t("Operation: %s · %s · %d m · Health %d", [Lang.t(str(op.kind).capitalize()), Lang.t(str(op.stage).capitalize()), roundi(Vector3(op.at).distance_to(player.global_position)), ceili(op.health)])
	elif director.game.waves.wave > 0:
		_overview.text = Lang.t("Wave %d of %d. Keep your defences supplied and use quiet moments to explore or save your expedition.", [director.game.waves.wave, director.round_limit()])
	_interact_button.visible = not director.nearest(player).is_empty()
	var weather := director.forecast()
	_weather.text = Lang.t("Forecast: %s → %s in %d s", [Lang.t(str(weather.state).capitalize()), Lang.t(str(weather.next).capitalize()), weather.seconds])
	var cooldown := ceili(maxf(0, state.cooldown-director.elapsed))
	var assassin: bool = player.class_combat.build.id == "assassin"
	var descriptions := {"gunslinger": "Focus · Steadier aim and less recoil for 6 seconds.", "assault": "Suppression · Faster fire and slowing hits for 8 seconds.", "breacher": "Shockwave · Damage and slow visible enemies within 9 metres.", "marksman": "Target mark · Aim at an enemy to increase damage against it for 10 seconds."}
	_ability.text = Lang.t("Use your chosen teleport with [V].") if assassin else Lang.t(descriptions.get(player.class_combat.build.id, "Class action"))+"\n\n"+(Lang.t("Ready to use") if cooldown == 0 else Lang.t("Ready in %d s", [cooldown]))
	_ability_button.visible = not assassin
	_ability_button.disabled = cooldown > 0
	var lines := PackedStringArray()
	var nearby: Array = director.sites.duplicate()
	nearby.sort_custom(func(a, b): return Vector3(a.at).distance_squared_to(player.global_position) < Vector3(b.at).distance_squared_to(player.global_position))
	for site in nearby:
		if site.done: continue
		var offset: Vector3 = site.at-player.global_position
		var bearing := posmod(roundi(rad_to_deg(atan2(offset.x, -offset.z))/45.0), 8)
		var compass: String = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][bearing]
		var title: String = Lang.t("Transmitter %d", [int(site.id.trim_prefix("site_"))-4]) if site.kind == "signal" else Lang.t("Outpost" if site.kind == "outpost" else "Cache")
		lines.append(Lang.t("%s · %d m · %s", [title, roundi(offset.length()), compass]))
	_exploration.text = "\n\n".join(lines) if not lines.is_empty() else Lang.t("All expedition locations discovered.")
	if director.config.region != "planes": return
	lines = PackedStringArray([Lang.t("Long-range elites: %d / 5 · Supply deliveries: %d", [state.longshots, director.cargo_deliveries]), Lang.t("Transmitter order: %d → %d → %d · Progress %d / 3", [int(director.puzzle_order[0])+1, int(director.puzzle_order[1])+1, int(director.puzzle_order[2])+1, director.puzzle_step])])
	if director.cargo_peer: lines.append(Lang.t("Supply destination: %d m", [roundi(director.cargo_destination().distance_to(player.global_position))]))
	var at_camp := director._near(player, director.camp(), 5)
	if not at_camp: lines.append(Lang.t("Return to camp to accept contracts or collect supplies."))
	_orders.text = "\n\n".join(lines)
	_camp_actions.visible = at_camp or director.cargo_peer == player.peer_id
	_contract_button.visible = at_camp and state.contract == 0
	_cargo_button.disabled = director.cargo_peer != 0 and director.cargo_peer != player.peer_id
	_fire_button.visible = _near_fire()
	_fire_button.disabled = state.bandages < 1
	_repair_button.visible = not director.structures.nearest(player).is_empty()
	var range_active: bool = not director.range_game.is_empty() and director.range_game.timer > 0
	var at_range: bool = director.game.shooting_range.opened and director.game.shooting_range.inside(player)
	_range_status.text = Lang.t("Visit the shooting range to begin a series.")
	if at_range: _range_status.text = Lang.t("Choose a 30-second series. Your best results are kept in Discoveries.")
	for button in _range_buttons: button.disabled = not at_range or range_active
	if not director.range_game.is_empty():
		var session := director.range_game
		_range_status.text = Lang.t("Range: %d s · Score %d", [ceili(session.timer), int(session.scores.get(player.peer_id, 0))])
		if session.mode == "sequence" and session.timer > 0: _range_status.text += "\n"+Lang.t("Next target: %d", [int(session.sequence[int(session.progress.get(player.peer_id, 0)) % 6])+1])

func _near_fire() -> bool:
	var fires: Node3D = director.game.cornfield.fires
	for cell in fires.active:
		var at: Vector3 = fires.wheat[cell]
		if at.distance_to(director.game.player.global_position) <= 6: return true
	return false

func _refresh_quests() -> void:
	if not director.game.progression.has_method("fieldbook_quests"): return
	var quests: Array = director.game.progression.fieldbook_quests()
	var signature := str(quests)
	if signature == _quest_signature: return
	_quest_signature = signature
	_clear(_quests)
	if quests.is_empty():
		_quests.add_child(_label("Speak to the traders to discover new quests.", 15, MUTED))
	for quest in quests:
		var card := _card(_quests, str(quest.name))
		card.add_child(_label(Lang.t("%s · Reward %d R", [quest.npc, quest.reward]), 14, ACCENT))
		if quest.ready: card.add_child(_label("Ready to turn in", 15, ACCENT))
		var text := RichTextLabel.new()
		text.bbcode_enabled = true
		text.fit_content = true
		text.scroll_active = false
		text.add_theme_font_size_override("normal_font_size", 15)
		text.add_theme_color_override("default_color", MUTED)
		text.text = str(quest.details)
		card.add_child(text)

func _refresh_run() -> void:
	var configurable: bool = not NetSession.is_client() and director.game.waves.wave == 0 and director.operation.is_empty() and director.finale.is_empty()
	_mode.disabled = not configurable
	_apply_mode.disabled = not configurable
	_apply_code.disabled = not configurable
	_code.editable = configurable
	_run_hint.text = Lang.t("Choose your challenge before the first wave.") if configurable else Lang.t("Run settings are fixed once the first wave begins.") if not NetSession.is_client() else Lang.t("Only the host can configure a run before wave one.")
	var reason: String = director.checkpoints.eligibility()
	_save_button.disabled = not reason.is_empty()
	_save_hint.text = Lang.t(reason) if not reason.is_empty() else Lang.t("A quiet moment. Your equipment, discoveries and progress can be saved now.")
	_load_button.disabled = NetSession.is_client() or not FileAccess.file_exists(director.checkpoints.path())
	_load_button.tooltip_text = Lang.t("Only the host can save or continue an expedition.") if NetSession.is_client() else Lang.t("No checkpoint saved for this character and map.") if _load_button.disabled else Lang.t("Continue with the same teammates for a cooperative checkpoint.")

func _build_augments(state: Dictionary) -> void:
	_clear(_augments)
	_augments.add_child(_label("One choice, lasting for this expedition", 20, ACCENT))
	if state.offers.is_empty():
		var next_wave := 0
		for number in [3, 7, 12, 17, 22]:
			if number > director.game.waves.completed:
				next_wave = number
				break
		_augments.add_child(_label(Lang.t("Your next augment choice unlocks after wave %d.", [next_wave]) if next_wave else Lang.t("All augment milestones reached."), 16, MUTED))
	else:
		for id in state.offers:
			var card := _card(_augments, RunRules.AUGMENTS[id][0])
			card.add_child(_label(RunRules.AUGMENTS[id][1], 15, MUTED))
			_button(card, "Choose this augment", func(): _request("augment", [id]))
	if not state.augments.is_empty():
		_augments.add_child(_label("Active augments", 18, ACCENT))
		for id in state.augments:
			var card := _card(_augments, RunRules.AUGMENTS[id][0])
			card.add_child(_label(RunRules.AUGMENTS[id][1], 15, MUTED))
	_navigation[1].text = Lang.t("Augments")+"  •" if not state.offers.is_empty() else Lang.t("Augments")

func _build_team(peer: int) -> void:
	_clear(_team)
	_team_buttons.clear()
	var supplies := _card(_team, "Your supplies")
	_bandages = _label("", 16, MUTED)
	supplies.add_child(_bandages)
	_buy_bandage = _button(supplies, "Buy bandage at camp · 25 R", func(): _request("buy_bandage"))
	var teammates := 0
	for id in director.people:
		if id == peer: continue
		teammates += 1
		var card := _card(_team, str(NetSession.roster.get(id, Lang.t("Teammate %d", [id]))))
		card.add_child(_label("Transfers and healing require a living teammate within three metres and a clear line of sight.", 14, MUTED))
		for kind in ["heal", "bandage", "ammo"]:
			var button := _button(card, "Heal teammate" if kind == "heal" else "Give bandage" if kind == "bandage" else "Give ammunition", func(): _request(kind, [id]))
			_team_buttons.append({"button": button, "kind": kind, "peer": id})
		var drinks: Dictionary = director.game.brewing.stock(peer).drinks
		for drink in drinks:
			if int(drinks[drink]) > 0:
				var button := _button(card, Lang.t("Give %s", [Lang.t(preload("res://scripts/brew_recipes.gd").DRINKS[drink].name)]), func(): _request("drink", [id, drink]))
				_team_buttons.append({"button": button, "kind": "drink", "peer": id})
	if teammates == 0: _team.add_child(_label("Travelling alone. Teammates and supply sharing appear here when someone joins your expedition.", 16, MUTED))

func _refresh_team(state: Dictionary) -> void:
	_bandages.text = Lang.t("Bandages: %d", [state.bandages])
	_buy_bandage.visible = director._near(director.game.player, director.camp(), 5)
	_buy_bandage.disabled = state.bandages >= 8 or director.game.player.score < 25
	for entry in _team_buttons:
		var target := director.actor(entry.peer)
		var nearby := true # Clients leave remote position validation to the host.
		if target: nearby = target.alive and not target.downed and director._near(director.game.player, target.global_position, 3)
		entry.button.disabled = not nearby or (entry.kind in ["heal", "bandage"] and state.bandages == 0)

func _build_journal() -> void:
	var expanded := {}
	var previous_button: Button
	for child in _journal.get_children():
		if child is Button: previous_button = child
		elif child is VBoxContainer and previous_button:
			expanded[previous_button.text] = child.visible
			previous_button = null
	_clear(_journal)
	var journal: Dictionary = CharacterProfile.data.get("journal", {})
	var entries := 0
	for i in RunRules.LORE.size():
		if not journal.get("record_%d" % i, false): continue
		entries += 1
		var record := _details(_journal, RunRules.LORE[i][0])
		record.add_child(_label(RunRules.LORE[i][1], 16, MUTED))
	for id in RunRules.BESTIARY:
		if not journal.get(id, false): continue
		entries += 1
		var entry := _details(_journal, RunRules.BESTIARY[id][0])
		entry.add_child(_label(RunRules.BESTIARY[id][1], 16, MUTED))
	if entries == 0:
		var empty := _card(_journal, "Your story starts here")
		empty.add_child(_label("Find records in the world and face new enemies to fill these pages.", 16, MUTED))
	var mastery := _details(_journal, "Mastery & titles")
	mastery.add_child(_label("Class and weapon mastery unlock cosmetic badges and titles. Mastery grants no combat bonus.", 15, MUTED))
	var progress: Dictionary = CharacterProfile.data.get("mastery", {})
	mastery.add_child(_label(Lang.t("Class mastery: %d", [int(progress.get("classes", {}).get(CharacterProfile.active_class(), 0))/5000])))
	for weapon in progress.get("weapons", {}):
		var title: String = Weapons.DEFS.get(weapon, {}).get("name", weapon)
		mastery.add_child(_label(Lang.t("%s · %d mastery kills", [Lang.t(title), progress.weapons[weapon]]), 15, MUTED))
	var title := CharacterProfile.mastery_title(CharacterProfile.data.get("title", ""))
	if not title.is_empty(): mastery.add_child(_label(Lang.t("Equipped title: %s", [title])))
	for id in CharacterProfile.data.cosmetics:
		var cosmetic: String = CharacterProfile.mastery_title(id)
		if not cosmetic.is_empty(): _button(mastery, Lang.t("Equip title: %s", [cosmetic]), func(): CharacterProfile.choose_title(id); _signature = ""; refresh())
	var records: Dictionary = progress.get("range", {})
	if not records.is_empty():
		var scores := _card(_journal, "Shooting range records")
		for mode in records:
			var name := "Timed series" if mode == "timed" else "Target sequence" if mode == "sequence" else "Team competition"
			scores.add_child(_label(Lang.t("%s · %d points", [Lang.t(name), records[mode]]), 15, MUTED))
	previous_button = null
	for child in _journal.get_children():
		if child is Button: previous_button = child
		elif child is VBoxContainer and previous_button:
			child.visible = expanded.get(previous_button.text, false)
			previous_button.set_pressed_no_signal(child.visible)
			previous_button = null

func _process(delta: float) -> void:
	if not director or not director.enabled: return
	var viewport := get_viewport().get_visible_rect().size
	var desired := Vector2(minf(980, viewport.x-48), minf(660, viewport.y-48))
	if _viewport_size != viewport or (is_open and panel.size != desired): _fit()
	if is_open and (director.game.over or not director.game.player.alive or director.game.player.downed): close()
	if _message_t > 0:
		_message_t -= delta
		if _message_t <= 0: message_label.text = ""
	_refresh_t -= delta
	if _refresh_t > 0: return
	_refresh_t = 0.25
	if is_open: refresh()
	status.visible = director.game.started and director.game.player.active and not director.game.over and not is_open and not director.game.hud.overlay.visible and not director.finale.is_empty() and director.finale.get("stage") == "defend"
	if status.visible: status.text = Lang.t("Final defence · %d s · Health %d", [ceili(director.finale.timer), ceili(director.finale.health)])

func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key: Key = event.keycode if event.keycode != 0 else event.physical_keycode
	if _confirm_load.visible: return # Escape first cancels the confirmation dialog.
	var editing := get_viewport().gui_get_focus_owner() is LineEdit
	var book_key: bool = event.is_action_pressed("expedition_book") and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed
	if is_open and (event.is_action_pressed("pause") or (book_key and not editing)):
		close()
		get_viewport().set_input_as_handled()
	elif not is_open and director and director.enabled and book_key and not editing and director.can_use_world_action():
		open()
		get_viewport().set_input_as_handled()
	elif is_open and not editing and key not in [KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_HOME, KEY_END, KEY_PAGEUP, KEY_PAGEDOWN]:
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if is_open: get_tree().paused = false
