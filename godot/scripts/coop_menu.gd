extends VBoxContainer

var name_edit: LineEdit
var ip_edit: LineEdit
var port_edit: SpinBox
var host_button: Button
var join_button: Button
var leave_button: Button
var start_button: Button
var state_label: Label
var players_label: Label
var hud: Hud
var _refresh_t := 0.0

func setup(owner_hud: Hud) -> void:
	hud = owner_hud
	add_theme_constant_override("separation", 12)
	add_child(hud._heading("CO-OP · 1 TO 4 PLAYERS"))
	var help := hud._label("All players join the same Hamachi network. One of you hosts the game; the others enter the host's Hamachi IP. On a LAN the local IP works too.", 14)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 14)
	form.add_theme_constant_override("v_separation", 10)
	add_child(form)
	form.add_child(hud._label("Your name", 14))
	name_edit = LineEdit.new()
	name_edit.text = NetSession.player_name
	name_edit.max_length = 24
	name_edit.custom_minimum_size.x = 350
	form.add_child(name_edit)
	form.add_child(hud._label("Host IP", 14))
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "The host's Hamachi IP, e.g. 25.12.34.56"
	ip_edit.text = NetSession.address
	form.add_child(ip_edit)
	form.add_child(hud._label("UDP port", 14))
	port_edit = SpinBox.new()
	port_edit.min_value = 1024
	port_edit.max_value = 65535
	port_edit.value = NetSession.port
	form.add_child(port_edit)
	var config := ConfigFile.new()
	if config.load("user://network.cfg") == OK:
		name_edit.text = config.get_value("network", "name", name_edit.text)
		# The default name used to be German ("Player" in the German catalogue): a saved default is the new default.
		if name_edit.text == Lang.resolve("Player", "de"): name_edit.text = "Player"
		ip_edit.text = config.get_value("network", "ip", ip_edit.text)
		port_edit.value = config.get_value("network", "port", port_edit.value)
	var actions := HBoxContainer.new()
	add_child(actions)
	host_button = hud._menu_button("Host game", true)
	join_button = hud._menu_button("Join", false)
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(host_button)
	actions.add_child(join_button)
	host_button.pressed.connect(func(): _save(); NetSession.host(name_edit.text, int(port_edit.value)); refresh())
	join_button.pressed.connect(func(): _save(); NetSession.join(ip_edit.text, name_edit.text, int(port_edit.value)); refresh())
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
	var version := hud._label("Version: Co-op 2026.09.20-C", 12)
	version.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diagnostics.add_child(version)
	var logs := Button.new()
	logs.text = "Open logs"
	logs.pressed.connect(func():
		NetSession.trace_load("LOG_FOLDER_OPENED")
		if not NetSession.diagnostic_path.is_empty(): OS.shell_open(NetSession.diagnostic_path.get_base_dir())
	)
	diagnostics.add_child(logs)
	var ips: Array[String] = []
	for ip in IP.get_local_addresses():
		if ":" not in ip and not ip.begins_with("127.") and not ip.begins_with("169.254."): ips.append(ip)
	var hint := hud._label(Lang.t("Your IPv4 addresses: %s\nWindows Firewall: allow RemZ on the Hamachi / private network. Host and teammates must use the same port and the same game version.\nCo-op: no friendly fire. Revive with E (3 s close by). Menus do not pause the shared world.", [Lang.raw(", ".join(ips))]), 12, Hud.MUTED)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	NetSession.changed.connect(refresh)
	refresh()

func _save() -> void:
	if "--smoke-test" in OS.get_cmdline_user_args(): return
	var config := ConfigFile.new()
	config.set_value("network", "name", name_edit.text)
	config.set_value("network", "ip", ip_edit.text)
	config.set_value("network", "port", int(port_edit.value))
	config.save("user://network.cfg")

func refresh() -> void:
	var loaded: bool = hud.game and hud.game.navigation_ready
	var playing: bool = hud.game and hud.game.started
	host_button.disabled = NetSession._closing or NetSession.enabled or not loaded or playing
	join_button.disabled = host_button.disabled
	name_edit.editable = not NetSession.enabled
	ip_edit.editable = not NetSession.enabled
	port_edit.editable = not NetSession.enabled
	if NetSession.enabled:
		name_edit.text = NetSession.player_name
		port_edit.value = NetSession.port
		if NetSession.is_client(): ip_edit.text = NetSession.address
	state_label.text = NetSession.status if loaded else "Preparing the map …"
	if loaded and playing and not NetSession.enabled: state_label.text = "Return to the main menu first to host or join a game."
	var lines: Array[String] = []
	for id in NetSession.roster:
		lines.append(Lang.t("● %s%s  ·  %s", [Lang.raw(NetSession.roster[id]), Lang.raw(" (Host)" if id == 1 else ""), "ready" if NetSession.ready_peers.get(id, false) else "loading …"]))
	players_label.text = Lang.t("Players: %d / 4\n%s", [lines.size(), "\n".join(lines)]) if NetSession.enabled else ""
	start_button.visible = NetSession.is_host() and NetSession.phase == "lobby"
	start_button.disabled = not loaded or false in NetSession.ready_peers.values()
	leave_button.visible = NetSession.enabled
	if NetSession.enabled and loaded and not playing:
		hud.overlay_button.text = "Start co-op" if NetSession.is_host() else "Waiting for host"
		hud.overlay_button.disabled = not NetSession.is_host() or start_button.disabled
		hud.set_difficulty_locked(NetSession.is_client())

func _process(delta: float) -> void:
	_refresh_t += delta
	if _refresh_t >= 0.5:
		_refresh_t = 0.0
		refresh()
