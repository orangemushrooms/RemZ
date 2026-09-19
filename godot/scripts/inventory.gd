# Inventory (B): weapons with ammunition, grenades, collected mushrooms. Resident-Evil style grid, pauses the game.
class_name Inventory
extends CanvasLayer

const MUSHROOMS := {
	"steinpilz": { "name": "Steinpilz", "text": "Essen: +25 Leben", "heal": 25.0, "color": Color(0.55, 0.38, 0.22) },
	"fliegenpilz": { "name": "Fliegenpilz", "text": "Giftig! Essen: -15 Leben, aber 20 s doppelter Schaden", "heal": -15.0, "color": Color(0.8, 0.12, 0.1) },
}

var player: Player
var weapons: Weapons
var hud: Hud
var main: Node
var is_open := false
var mushrooms := { "steinpilz": 0, "fliegenpilz": 0 }
var panel: PanelContainer
var grid: GridContainer
var info: Label
var _rage_t := 0.0
var ach_label: Label
var stats_label: Label

func setup(p: Player, w: Weapons, h: Hud, m: Node) -> void:
	player = p
	weapons = w
	hud = h
	main = m

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	panel = PanelContainer.new()
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(840, 600)
	panel.position = Vector2(-420, -300)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.043, 0.06, 0.08, 0.96)
	style.border_color = Color(1, 1, 1, 0.15)
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = "INVENTAR"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.28))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	stats_label = Label.new()
	stats_label.add_theme_font_size_override("font_size", 13)
	stats_label.add_theme_color_override("font_color", Color(0.62, 0.64, 0.6))
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	head.add_child(stats_label)
	var legend := Label.new()
	legend.text = "WAFFEN  ·  VORRÄTE  ·  SCHLÜSSEL"
	legend.add_theme_font_size_override("font_size", 12)
	legend.add_theme_color_override("font_color", Color(1.0, 0.7, 0.28))
	v.add_child(legend)
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	var info_panel := PanelContainer.new()
	var ist := StyleBoxFlat.new()
	ist.bg_color = Color(0.03, 0.042, 0.055)
	ist.border_color = Color(1, 1, 1, 0.08)
	ist.set_border_width_all(1)
	ist.set_corner_radius_all(6)
	ist.set_content_margin_all(12)
	info_panel.add_theme_stylebox_override("panel", ist)
	v.add_child(info_panel)
	info = Label.new()
	info.text = "Fahre über einen Gegenstand für Details."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(760, 58)
	info.add_theme_font_size_override("font_size", 14)
	info.add_theme_color_override("font_color", Color(0.9, 0.9, 0.86))
	info_panel.add_child(info)
	ach_label = Label.new()
	ach_label.add_theme_font_size_override("font_size", 13)
	ach_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	ach_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ach_label.custom_minimum_size = Vector2(760, 40)
	v.add_child(ach_label)
	var hint := Label.new()
	hint.text = "B / Esc schliessen  ·  Klick auf eine Waffe: ausrüsten  ·  Klick auf Pilze: essen  ·  Munition und Granaten gibt es von gefallenen Zombies und nach jeder Welle"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)

func add_mushroom(kind: String) -> void:
	mushrooms[kind] = mushrooms.get(kind, 0) + 1
	hud.message("%s gesammelt (%d)" % [MUSHROOMS[kind]["name"], mushrooms[kind]], 1.5)
	if main.achievements:
		main.achievements.event("mushrooms")

func _slot(title: String, sub: String, color: Color, detail: String, on_click: Callable, fill: float = -1.0) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(186, 96)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "%s\n%s" % [title, sub]
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_color_override("font_color", Color(0.93, 0.92, 0.88))
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.075, 0.095, 0.115)
	st.border_color = color
	st.set_border_width_all(2)
	st.set_corner_radius_all(6)
	st.content_margin_left = 12; st.content_margin_right = 12; st.content_margin_top = 10; st.content_margin_bottom = 18
	b.add_theme_stylebox_override("normal", st)
	var hv := st.duplicate()
	hv.bg_color = Color(0.16, 0.15, 0.11)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("focus", hv)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.mouse_entered.connect(func(): info.text = detail)
	b.pressed.connect(on_click)
	if fill >= 0.0:
		# thin ammunition / stock bar along the bottom edge
		var bar := ProgressBar.new()
		bar.max_value = 1.0
		bar.value = clampf(fill, 0.0, 1.0)
		bar.show_percentage = false
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		bar.offset_left = 12
		bar.offset_right = -12
		bar.offset_top = -12
		bar.offset_bottom = -8
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.1)
		bg.set_corner_radius_all(2)
		var fg := StyleBoxFlat.new()
		fg.bg_color = color.lerp(Color.WHITE, 0.2)
		fg.set_corner_radius_all(2)
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fg)
		b.add_child(bar)
	grid.add_child(b)

func _refresh() -> void:
	for c in grid.get_children():
		c.queue_free()
	if main.achievements:
		var names: Array = []
		var next: Array = []
		for d in Achievements.DEFS:
			if main.achievements.unlocked.has(d["id"]):
				names.append(d["title"])
			elif next.size() < 3:
				next.append("%s (%d/%d)" % [d["text"], main.achievements.counters.get(d["counter"], 0), d["target"]])
		ach_label.text = "★ %s · zuletzt: %s\nNächste Ziele: %s" % [main.achievements.progress_text(), names.back() if names.size() > 0 else "noch keiner", ", ".join(next)]
	if "stats" in main and main.stats:
		var st = main.stats
		stats_label.text = "Diese Runde: %d Abschüsse · %d Kopfschüsse · Treffer %d %% · Serie %d" % [st.kills, st.headshots, int(round(st.accuracy() * 100.0)), st.best_streak]
	for id in weapons.ORDER:
		if not weapons.unlocked.get(id, false):
			continue
		var d: Dictionary = weapons.DEFS[id]
		var s: Dictionary = weapons.state[id]
		var eq: bool = id == weapons.current
		var per_second := 1.0 / maxf(0.01, float(d["rate"]))
		var dps := float(d["damage"]) * float(d["pellets"]) * per_second * weapons.damage_mul
		var detail := "%s%s  ·  Magazin %d / %d, Reserve %d  ·  Schaden %d%s pro Schuss (×%.1f Skill), Kopfschuss ×2.2  ·  %.1f Schuss/s (%d Schaden/s)  ·  Reichweite %d m  ·  Nachladen %.1f s" % [
			d["name"], "  (ausgerüstet)" if eq else "", s["ammo"], int(d["mag"]), s["reserve"], int(d["damage"]), " × %d Schrot" % int(d["pellets"]) if int(d["pellets"]) > 1 else "", weapons.damage_mul, per_second, int(dps), int(d["range"]), float(d["reload"]) * weapons.reload_mul]
		var fill := float(s["ammo"] + s["reserve"]) / float(int(d["mag"]) + int(d["reserve"]))
		_slot(d["name"] + ("  ●" if eq else ""), "%d / %d  ·  Taste %d" % [s["ammo"], s["reserve"], weapons.ORDER.find(id) + 1], Color(1.0, 0.7, 0.28) if eq else Color(0.5, 0.5, 0.45),
			detail, func(): weapons.set_weapon(id); _refresh(), fill)
	_slot("Granaten", "%d Stück  ·  Taste G" % weapons.grenades, Color(0.4, 0.5, 0.35), "Handgranaten: 2,6 s Zünder, 7 m Radius, 260 Schaden im Zentrum. Werfen mit G. Nach jeder Welle wieder voll (%d), Zombies lassen weitere fallen." % weapons.grenades_max, func(): pass, float(weapons.grenades) / maxf(1.0, weapons.grenades_max))
	for k in MUSHROOMS:
		var n: int = mushrooms.get(k, 0)
		var md: Dictionary = MUSHROOMS[k]
		_slot(md["name"], "%d Stück  ·  Klick: essen" % n, md["color"] if n > 0 else Color(0.3, 0.3, 0.3), md["text"] + "  ·  Wächst im Laub rund um den Grillplatz, mit E sammeln.", func(): _eat(k))

	if main.forest_keys:
		for key_id: String in ForestKeys.KEYS:
			var found: bool = main.forest_keys.has_key(key_id)
			var detail := "Schlüssel für %s. %s" % [ForestKeys.KEYS[key_id], "Bleibt bei dir und öffnet alle Türen dieser Hütte." if found else "Im Wald versteckt. In der Nähe helfen Hinweis und Richtungspfeil."]
			_slot("Schlüssel: %s" % ForestKeys.KEYS[key_id], "Gefunden" if found else "Noch nicht gefunden", Color(0.95, 0.73, 0.32) if found else Color(0.3, 0.3, 0.3), detail, func(): info.text = detail)

func _eat(kind: String) -> void:
	if mushrooms.get(kind, 0) <= 0:
		info.text = "Keine %s im Inventar." % MUSHROOMS[kind]["name"]
		return
	mushrooms[kind] -= 1
	var heal: float = MUSHROOMS[kind]["heal"]
	player.hp = clampf(player.hp + heal, 1.0, player.max_hp)
	if kind == "fliegenpilz":
		_rage_t = 20.0
		weapons.damage_mul = 2.0
		hud.message("Fliegenpilz: Rausch! 20 s doppelter Schaden", 3.0)
		main.achievements.event("rausch")
	else:
		hud.message("Steinpilz gegessen: +%d Leben" % int(heal), 2.0)
	Sfx.play(self, "pickup", -8.0)
	_refresh()

func toggle() -> void:
	if is_open:
		close()
	else:
		open()

func open() -> void:
	if not player.alive or not player.active:
		return
	is_open = true
	_refresh()
	panel.visible = true
	player.active = false
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	is_open = false
	panel.visible = false
	get_tree().paused = false
	player.active = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	if _rage_t > 0.0 and not get_tree().paused:
		_rage_t -= delta
		if _rage_t <= 0.0:
			weapons.damage_mul = 1.0
			hud.message("Der Rausch lässt nach.", 1.5)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_B and main.started and not main.over:
		if main.skills and main.skills.is_open:
			return
		toggle()
