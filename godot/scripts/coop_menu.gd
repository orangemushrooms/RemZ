extends VBoxContainer

# The Multiplayer tab: one name field, then two ways in - the online lobby (EOS, join code, no port
# forwarding) and the direct connection (ENet: IP + UDP port over LAN or Hamachi). Both end in the same
# player list, start and leave buttons of NetSession.
const MODES := ["online", "direct"]

var name_edit: LineEdit
var ip_edit: LineEdit
var port_edit: SpinBox
var code_edit: LineEdit
var mode_tabs: TabBar
var online_box: VBoxContainer
var direct_box: VBoxContainer
var online_note: Label
var code_panel: VBoxContainer
var code_value: Label
var copy_button: Button
var create_button: Button
var join_code_button: Button
var host_button: Button
var join_button: Button
var leave_button: Button
var start_button: Button
var state_label: Label
var players_label: Label
var hint_label: Label
var hud: Hud
var mode := "online"
var _refresh_t := 0.0
var _copied_t := 0.0

func setup(owner_hud: Hud) -> void:
	hud = owner_hud
	add_theme_constant_override("separation", 12)
	add_child(hud._heading("CO-OP · 1 TO 4 PLAYERS"))
	var config := ConfigFile.new()
	var loaded_config := config.load("user://network.cfg") == OK
	if loaded_config and str(config.get_value("network", "mode", mode)) in MODES: mode = str(config.get_value("network", "mode", mode))
	if not Online.available(): mode = "direct"
	var name_row := GridContainer.new()
	name_row.columns = 2
	name_row.add_theme_constant_override("h_separation", 14)
	add_child(name_row)
	name_row.add_child(hud._label("Your name", 14))
	name_edit = LineEdit.new()
	name_edit.text = NetSession.player_name
	name_edit.max_length = 24
	name_edit.custom_minimum_size.x = 350
	name_row.add_child(name_edit)
	mode_tabs = TabBar.new()
	mode_tabs.add_tab("Online lobby")
	mode_tabs.add_tab("Direct / LAN / Hamachi")
	mode_tabs.add_theme_font_size_override("font_size", 15)
	mode_tabs.current_tab = MODES.find(mode)
	mode_tabs.tab_changed.connect(func(index: int): _set_mode(MODES[clampi(index, 0, 1)]))
	add_child(mode_tabs)
	_build_online()
	_build_direct()
	if loaded_config:
		name_edit.text = config.get_value("network", "name", name_edit.text)
		# The default name used to be German ("Player" in the German catalogue): a saved default is the new default.
		if name_edit.text == Lang.resolve("Player", "de"): name_edit.text = "Player"
		ip_edit.text = config.get_value("network", "ip", ip_edit.text)
		port_edit.value = config.get_value("network", "port", port_edit.value)
	state_label = hud._label("", 14, Hud.GOLD)
	state_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(state_label)
	players_label = hud._label("", 15)
	add_child(players_label)
	start_button = hud._menu_button("Start co-op", true)
	start_button.pressed.connect(NetSession.start_game)
	add_child(start_button)
	leave_button = hud._menu_button("Leave session", false)
	leave_button.pressed.connect(func(): NetSession.leave())
	add_child(leave_button)
	var diagnostics := HBoxContainer.new()
	add_child(diagnostics)
	var version := hud._label("Version: Co-op 2026.09.25-O", 12)
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diagnostics.add_child(version)
	var logs := Button.new()
	logs.text = "Open logs"
	logs.pressed.connect(func():
		NetSession.trace_load("LOG_FOLDER_OPENED")
		if not NetSession.diagnostic_path.is_empty(): OS.shell_open(NetSession.diagnostic_path.get_base_dir())
	)
	diagnostics.add_child(logs)
	hint_label = hud._label("", 12, Hud.MUTED)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint_label)
	NetSession.changed.connect(refresh)
	Online.changed.connect(refresh)
	_set_mode(mode)
	refresh()

func _build_online() -> void:
	online_box = VBoxContainer.new()
	online_box.add_theme_constant_override("separation", 10)
	add_child(online_box)
	var help := hud._label("Plays over the internet without Hamachi or router setup: the host creates a lobby and shares the six-letter join code, up to three teammates enter it and join. Traffic goes through Epic Online Services (peer to peer, relayed when needed); no Epic account is required.", 14)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	online_box.add_child(help)
	online_note = hud._label("", 13, Hud.MUTED)
	online_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	online_box.add_child(online_note)
	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 14)
	form.add_theme_constant_override("v_separation", 10)
	online_box.add_child(form)
	form.add_child(hud._label("Join code", 14))
	code_edit = LineEdit.new()
	code_edit.placeholder_text = "The host's code, e.g. K7PZ4M"
	code_edit.max_length = 12
	code_edit.custom_minimum_size.x = 350
	code_edit.text_submitted.connect(func(_text: String): if not join_code_button.disabled: join_code_button.pressed.emit())
	form.add_child(code_edit)
	var actions := HBoxContainer.new()
	online_box.add_child(actions)
	create_button = hud._menu_button("Create lobby", true)
	join_code_button = hud._menu_button("Join with code", false)
	create_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_code_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(create_button)
	actions.add_child(join_code_button)
	create_button.pressed.connect(func():
		_save()
		NetSession.host_online(name_edit.text)
		refresh())
	join_code_button.pressed.connect(func():
		_save()
		NetSession.join_online(code_edit.text, name_edit.text)
		refresh())
	code_panel = VBoxContainer.new()
	code_panel.add_theme_constant_override("separation", 4)
	online_box.add_child(code_panel)
	code_panel.add_child(hud._label("JOIN CODE - give it to your teammates", 12, Hud.MUTED))
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 18)
	code_panel.add_child(code_row)
	code_value = hud._label("", 40, Hud.GOLD)
	code_row.add_child(code_value)
	copy_button = Button.new()
	copy_button.text = "Copy code"
	copy_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	copy_button.pressed.connect(func():
		DisplayServer.clipboard_set(NetSession.join_code)
		_copied_t = 2.0
		refresh())
	code_row.add_child(copy_button)

func _build_direct() -> void:
	direct_box = VBoxContainer.new()
	direct_box.add_theme_constant_override("separation", 10)
	add_child(direct_box)
	var help := hud._label("All players join the same Hamachi network. One of you hosts the game; the others enter the host's Hamachi IP. On a LAN the local IP works too.", 14)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	direct_box.add_child(help)
	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 14)
	form.add_theme_constant_override("v_separation", 10)
	direct_box.add_child(form)
	form.add_child(hud._label("Host IP", 14))
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "The host's Hamachi IP, e.g. 25.12.34.56"
	ip_edit.text = NetSession.address
	ip_edit.custom_minimum_size.x = 350
	form.add_child(ip_edit)
	form.add_child(hud._label("UDP port", 14))
	port_edit = SpinBox.new()
	port_edit.min_value = 1024
	port_edit.max_value = 65535
	port_edit.value = NetSession.port
	form.add_child(port_edit)
	var actions := HBoxContainer.new()
	direct_box.add_child(actions)
	host_button = hud._menu_button("Host game", true)
	join_button = hud._menu_button("Join", false)
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(host_button)
	actions.add_child(join_button)
	host_button.pressed.connect(func():
		_save()
		NetSession.host(name_edit.text, int(port_edit.value))
		refresh())
	join_button.pressed.connect(func():
		_save()
		NetSession.join(ip_edit.text, name_edit.text, int(port_edit.value))
		refresh())

func _set_mode(value: String) -> void:
	mode = value
	if mode_tabs.current_tab != MODES.find(mode): mode_tabs.current_tab = MODES.find(mode)
	online_box.visible = mode == "online"
	direct_box.visible = mode == "direct"
	var ips: Array[String] = []
	for ip in IP.get_local_addresses():
		if ":" not in ip and not ip.begins_with("127.") and not ip.begins_with("169.254."): ips.append(ip)
	if mode == "online":
		hint_label.text = "Windows Firewall: allow RemZ on your network. Host and teammates need the same game version.\nCo-op: no friendly fire. Revive with E (3 s close by). Menus do not pause the shared world."
	else:
		hint_label.text = Lang.t("Your IPv4 addresses: %s\nWindows Firewall: allow RemZ on the Hamachi / private network. Host and teammates must use the same port and the same game version.\nCo-op: no friendly fire. Revive with E (3 s close by). Menus do not pause the shared world.", [Lang.raw(", ".join(ips))])
	if is_instance_valid(state_label): refresh()

func _save() -> void:
	if "--smoke-test" in OS.get_cmdline_user_args(): return
	var config := ConfigFile.new()
	config.set_value("network", "name", name_edit.text)
	config.set_value("network", "ip", ip_edit.text)
	config.set_value("network", "port", int(port_edit.value))
	config.set_value("network", "mode", mode)
	config.save("user://network.cfg")

func refresh() -> void:
	var loaded: bool = hud.game and hud.game.navigation_ready
	var playing: bool = hud.game and hud.game.started
	var busy: bool = NetSession._closing or NetSession.enabled or NetSession.online_pending or not loaded or playing
	host_button.disabled = busy
	join_button.disabled = busy
	create_button.disabled = busy or not Online.available()
	join_code_button.disabled = busy or not Online.available()
	mode_tabs.set_tab_disabled(0, NetSession.enabled or NetSession.online_pending)
	mode_tabs.set_tab_disabled(1, NetSession.enabled or NetSession.online_pending)
	name_edit.editable = not NetSession.enabled and not NetSession.online_pending
	ip_edit.editable = not NetSession.enabled
	port_edit.editable = not NetSession.enabled
	code_edit.editable = not NetSession.enabled and not NetSession.online_pending
	online_note.text = Online.unavailable_reason()
	online_note.visible = not Online.available()
	if NetSession.enabled:
		name_edit.text = NetSession.player_name
		port_edit.value = NetSession.port
		if NetSession.is_client() and NetSession.transport == "enet": ip_edit.text = NetSession.address
	if NetSession.enabled and NetSession.transport == "eos" and mode != "online": _set_mode("online")
	if NetSession.enabled and NetSession.transport == "enet" and mode != "direct": _set_mode("direct")
	code_panel.visible = NetSession.is_host() and NetSession.transport == "eos" and not NetSession.join_code.is_empty()
	code_value.text = NetSession.join_code
	copy_button.text = "Copied!" if _copied_t > 0.0 else "Copy code"
	if NetSession.enabled and NetSession.transport == "eos" and not NetSession.join_code.is_empty(): code_edit.text = NetSession.join_code
	state_label.text = NetSession.status if loaded else "Preparing the map …"
	if loaded and playing and not NetSession.enabled: state_label.text = "Return to the main menu first to host or join a game."
	var lines: Array[String] = []
	for id in NetSession.roster:
		lines.append(Lang.t("● %s%s  ·  %s", [Lang.raw(NetSession.roster[id]), Lang.raw(" (Host)" if id == 1 else ""), "ready" if NetSession.ready_peers.get(id, false) else "loading …"]))
	players_label.text = Lang.t("Players: %d / 4\n%s", [lines.size(), "\n".join(lines)]) if NetSession.enabled else ""
	start_button.visible = NetSession.is_host() and NetSession.phase == "lobby"
	start_button.disabled = not loaded or false in NetSession.ready_peers.values()
	leave_button.visible = NetSession.enabled or NetSession.online_pending
	leave_button.text = "Cancel" if NetSession.online_pending and not NetSession.enabled else "Leave session"
	if NetSession.enabled and loaded and not playing:
		hud.overlay_button.text = "Start co-op" if NetSession.is_host() else "Waiting for host"
		hud.overlay_button.disabled = not NetSession.is_host() or start_button.disabled
		hud.set_difficulty_locked(NetSession.is_client())

func _process(delta: float) -> void:
	_refresh_t += delta
	if _copied_t > 0.0:
		_copied_t -= delta
		if _copied_t <= 0.0: refresh()
	if _refresh_t >= 0.5:
		_refresh_t = 0.0
		refresh()
