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
	add_child(hud._heading("KOOP · 1 BIS 4 SPIELER"))
	var help := hud._label("Alle Spieler verbinden sich mit demselben Hamachi-Netzwerk. Einer erstellt das Spiel; die anderen geben seine Hamachi-IP ein. Im LAN funktioniert auch die lokale IP.", 14)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	var form := GridContainer.new()
	form.columns = 2
	form.add_theme_constant_override("h_separation", 14)
	form.add_theme_constant_override("v_separation", 10)
	add_child(form)
	form.add_child(hud._label("Dein Name", 14))
	name_edit = LineEdit.new()
	name_edit.text = NetSession.player_name
	name_edit.max_length = 24
	name_edit.custom_minimum_size.x = 350
	form.add_child(name_edit)
	form.add_child(hud._label("Host-IP", 14))
	ip_edit = LineEdit.new()
	ip_edit.placeholder_text = "Hamachi-IP des Hosts, z. B. 25.12.34.56"
	ip_edit.text = NetSession.address
	form.add_child(ip_edit)
	form.add_child(hud._label("UDP-Port", 14))
	port_edit = SpinBox.new()
	port_edit.min_value = 1024
	port_edit.max_value = 65535
	port_edit.value = NetSession.port
	form.add_child(port_edit)
	var config := ConfigFile.new()
	if config.load("user://network.cfg") == OK:
		name_edit.text = config.get_value("network", "name", name_edit.text)
		ip_edit.text = config.get_value("network", "ip", ip_edit.text)
		port_edit.value = config.get_value("network", "port", port_edit.value)
	var actions := HBoxContainer.new()
	add_child(actions)
	host_button = hud._menu_button("Spiel erstellen", true)
	join_button = hud._menu_button("Beitreten", false)
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
	start_button = hud._menu_button("Koop starten", true)
	start_button.pressed.connect(NetSession.start_game)
	add_child(start_button)
	leave_button = hud._menu_button("Sitzung verlassen", false)
	leave_button.pressed.connect(func(): NetSession.leave())
	add_child(leave_button)
	var ips: Array[String] = []
	for ip in IP.get_local_addresses():
		if ":" not in ip and not ip.begins_with("127.") and not ip.begins_with("169.254."): ips.append(ip)
	var hint := hud._label("Deine IPv4-Adressen: %s\nWindows-Firewall: RemZ für das Hamachi-/private Netzwerk zulassen. Host und Mitspieler müssen denselben Port und dieselbe Spielversion nutzen.\nKoop: kein Beschuss unter Freunden. Mit E wiederbeleben (3 s in der Nähe). Menüs halten die gemeinsame Welt nicht an." % ", ".join(ips), 12, Hud.MUTED)
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
	host_button.disabled = NetSession.enabled or not loaded or playing
	join_button.disabled = host_button.disabled
	name_edit.editable = not NetSession.enabled
	ip_edit.editable = not NetSession.enabled
	port_edit.editable = not NetSession.enabled
	if NetSession.enabled:
		name_edit.text = NetSession.player_name
		port_edit.value = NetSession.port
		if NetSession.is_client(): ip_edit.text = NetSession.address
	state_label.text = NetSession.status if loaded else "Die Karte wird vorbereitet …"
	if loaded and playing and not NetSession.enabled: state_label.text = "Zum Erstellen oder Beitreten zuerst ins Hauptmenü zurückkehren."
	var lines: Array[String] = []
	for id in NetSession.roster:
		lines.append("● %s%s  ·  %s" % [NetSession.roster[id], " (Host)" if id == 1 else "", "bereit" if NetSession.ready_peers.get(id, false) else "lädt …"])
	players_label.text = "Spieler: %d / 4\n%s" % [lines.size(), "\n".join(lines)] if NetSession.enabled else ""
	start_button.visible = NetSession.is_host() and NetSession.phase == "lobby"
	start_button.disabled = not loaded or false in NetSession.ready_peers.values()
	leave_button.visible = NetSession.enabled
	if NetSession.enabled and loaded and not playing:
		hud.overlay_button.text = "Koop starten" if NetSession.is_host() else "Warte auf Host"
		hud.overlay_button.disabled = not NetSession.is_host() or start_button.disabled
		hud.set_difficulty_locked(NetSession.is_client())

func _process(delta: float) -> void:
	_refresh_t += delta
	if _refresh_t >= 0.5:
		_refresh_t = 0.0
		refresh()
