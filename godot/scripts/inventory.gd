# Inventory (I): weapons with ammunition, grenades, collected mushrooms. Resident-Evil style grid, pauses the game.
class_name Inventory
extends CanvasLayer

const Mushrooms = preload("res://scripts/mushrooms.gd")
const MUSHROOMS = Mushrooms.DEFS

var player: Player
var weapons: Weapons
var hud: Hud
var main: Node
var is_open := false
var mushrooms := Mushrooms.empty_stock()
var panel: PanelContainer
var grid: GridContainer
var info: Label
var effects_label: Label
var active_label: Label
var _effects_ui_t := 0.0
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
	effects_label = Label.new()
	effects_label.position = Vector2(26, 320)
	effects_label.add_theme_font_size_override("font_size", 14)
	effects_label.add_theme_color_override("font_color", Color(0.8, 0.95, 0.65))
	effects_label.add_theme_constant_override("outline_size", 4)
	effects_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(effects_label)
	panel = PanelContainer.new()
	panel.visible = false
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(840, 600)
	panel.position = Vector2(-420, -300)
	panel.resized.connect(func(): panel.position = (get_viewport().get_visible_rect().size - panel.size) * 0.5)
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
	v.minimum_size_changed.connect(func(): panel.call_deferred("reset_size"))
	var head := HBoxContainer.new()
	v.add_child(head)
	var title := Label.new()
	title.text = "INVENTAR"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.28))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	stats_label = Label.new()
	stats_label.add_theme_font_size_override("font_size", 16)
	stats_label.add_theme_color_override("font_color", Color(0.62, 0.64, 0.6))
	stats_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stats_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	head.add_child(stats_label)
	var legend := Label.new()
	legend.text = "WAFFEN  ·  VORRÄTE  ·  SCHLÜSSEL"
	legend.add_theme_font_size_override("font_size", 12)
	legend.add_theme_color_override("font_color", Color(1.0, 0.7, 0.28))
	v.add_child(legend)
	active_label = Label.new()
	active_label.add_theme_font_size_override("font_size", 15)
	active_label.add_theme_constant_override("line_spacing", 3)
	active_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var effect_scroll := ScrollContainer.new()
	effect_scroll.custom_minimum_size = Vector2(760, 76)
	effect_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(effect_scroll)
	active_label.custom_minimum_size.x = 760
	active_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	effect_scroll.add_child(active_label)
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(795, 310)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	scroll.add_child(grid)
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
	info.add_theme_font_size_override("font_size", 17)
	info.add_theme_constant_override("line_spacing", 4)
	info.add_theme_color_override("font_color", Color(0.9, 0.9, 0.86))
	var detail_scroll := ScrollContainer.new()
	detail_scroll.custom_minimum_size = Vector2(760, 112)
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	info_panel.add_child(detail_scroll)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.custom_minimum_size.x = 740
	detail_scroll.add_child(info)
	ach_label = Label.new()
	ach_label.add_theme_font_size_override("font_size", 13)
	ach_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	ach_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ach_label.custom_minimum_size = Vector2(760, 40)
	v.add_child(ach_label)
	var hint := Label.new()
	hint.text = "I / Esc schliessen  ·  Klick auf eine Waffe: ausrüsten  ·  Klick auf Pilze: essen  ·  Waffen und Nachschub bei Vendor kaufen. Skins beim Händler für die ausgerüstete Waffe wählen."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)

func add_mushroom(kind: String) -> void:
	if not MUSHROOMS.has(kind): return
	mushrooms[kind] = mushrooms.get(kind, 0) + 1
	hud.message("%s gesammelt (%d)" % [MUSHROOMS[kind]["name"], mushrooms[kind]], 1.5)
	if main.achievements:
		main.achievements.event("mushrooms")

func _slot(title: String, sub: String, color: Color, detail: String, on_click: Callable, fill: float = -1.0, icon_id := "item") -> void:
	var b := preload("res://scripts/item_slot_button.gd").new()
	b.custom_minimum_size = Vector2(186, 190)
	detail = detail.replace("  ·  ", "\n").replace(" · ", "\n")
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = title + "\n" + detail
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 10
	content.offset_right = -10
	content.offset_top = 6
	content.offset_bottom = -18
	content.add_child(ItemIcons.view(icon_id, Vector2(160, 74)))
	for line in [title, sub]:
		var label := Label.new()
		label.text = line
		label.add_theme_font_size_override("font_size", 16)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(160, 40 if line == title else 24)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(label)
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
	b.mouse_entered.connect(func(): info.text = title + "\n" + detail)
	b.focus_entered.connect(func(): info.text = title + "\n" + detail)
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
	active_label.text = Mushrooms.summary(player.mushroom_effects)
	active_label.visible = not active_label.text.is_empty()
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
	var market = main.progression.rare_market
	var rare: Dictionary = market.data(player.peer_id)
	for id in rare.owned:
		var spec: Dictionary = Player.RareItems.DEFS[id]
		_slot(spec.name, "Aktiv" if rare.active == id else "Talisman aktivieren", Color(0.8, 0.45, 1), spec.desc + " Ein Talisman gleichzeitig aktiv.", market.request_equip.bind(id), -1, "relic")
	if not rare.owned.is_empty():
		_slot("Talisman ablegen", "Kein Talisman", Color(0.55, 0.5, 0.6), "Alle Talismane bleiben im Besitz.", market.request_equip.bind("none"), -1, "relic")
	for id in ["fire", "frost"]:
		if int(rare.ammo[id]) <= 0: continue
		var spec: Dictionary = Player.RareItems.DEFS[id]
		_slot(spec.name, "%d Schüsse · %s" % [rare.ammo[id], "Aktiv" if rare.mode == id else "Aktivieren"], Color(1, 0.6, 0.2) if id == "fire" else Color(0.35, 0.8, 1), spec.desc + " Verbraucht zusätzlich zur normalen Munition eine Ladung pro Schuss, auch bei Fehlschüssen. Schrot: eine Ladung für alle Pellets.", market.request_equip.bind(id), -1, "ammo")
	if int(rare.ammo.fire) + int(rare.ammo.frost) > 0:
		_slot("Normale Patronen", "Spezialmunition sparen", Color(0.6, 0.6, 0.5), "Deaktiviert Spezialmunition, ohne Vorräte zu verlieren.", market.request_equip.bind("normal"), -1, "ammo")
	for id in weapons.ORDER:
		if not weapons.unlocked.get(id, false):
			continue
		var d: Dictionary = weapons.state[id].def
		var s: Dictionary = weapons.state[id]
		var eq: bool = id == weapons.current
		if Weapons.is_melee(id):
			var detail := "%s · %d Schaden pro Schlag · %.2f s Schlagabstand · %.2f m Reichweite. Keine Munition. Angriff: Linksklick oder Q." % [d.name, roundi(float(d.damage) * weapons.effective_damage_mul()), d.rate, d.range]
			detail += "\nRechtsklick: %d Schaden, %.2f s Erholung, %.2f m Reichweite." % [roundi(float(d.stab_damage) * weapons.effective_damage_mul()), d.stab_rate, d.stab_range]
			_slot(d.name + ("  ●" if eq else ""), "Nahkampf · " + ("Taste 0" if id == "knife" else "Mausrad / Inventar"), Color(1.0, 0.7, 0.28) if eq else Color(0.5, 0.5, 0.45), detail, func(): weapons.set_weapon(id); _refresh(), 1.0, id)
			continue
		var per_second := 1.0 / maxf(0.01, float(d["rate"]))
		var dps := float(d["damage"]) * float(d["pellets"]) * per_second * weapons.effective_damage_mul()
		var detail := "%s%s  ·  Magazin %d / %d, Reserve %d  ·  Schaden %d%s pro Schuss (×%.1f Skill), Kopfschuss ×2.2  ·  %.1f Schuss/s (%d Schaden/s)  ·  Reichweite %d m  ·  Nachladen %.1f s" % [
			d["name"], "  (ausgerüstet)" if eq else "", s["ammo"], int(d["mag"]), s["reserve"], int(d["damage"]), " × %d Schrot" % int(d["pellets"]) if int(d["pellets"]) > 1 else "", weapons.effective_damage_mul(), per_second, int(dps), int(d["range"]), float(d["reload"]) * weapons.effective_reload_mul()]
		var fill := float(s["ammo"] + s["reserve"]) / float(int(d["mag"]) + int(d["reserve"]))
		detail += "\n" + Weapons.Mods.summary(weapons.mod_loadout.get(id, {}))
		if d.has("pierce_targets"): detail += "\n" + Weapons.piercing_description(id, d)
		_slot(d["name"] + ("  ●" if eq else ""), "%d / %d  ·  Taste %d" % [s["ammo"], s["reserve"], weapons.ORDER.find(id) + 1], Color(1.0, 0.7, 0.28) if eq else Color(0.5, 0.5, 0.45),
			detail, func(): weapons.set_weapon(id); _refresh(), fill, id)
	_slot("Granaten", "%d Stück  ·  Taste G" % weapons.grenades, Color(0.4, 0.5, 0.35), "Handgranaten: 2,6 s Zünder, 7 m Radius, 260 Schaden im Zentrum. Werfen mit G. Taschenlimit: %d. Nachschub bei Vendor oder von gefallenen Zombies." % weapons.grenades_max, func(): pass, float(weapons.grenades) / maxf(1.0, weapons.grenades_max), "grenade")
	for k in MUSHROOMS:
		var n: int = mushrooms.get(k, 0)
		var md: Dictionary = MUSHROOMS[k]
		_slot(md["name"], "%d Stück  ·  Klick: essen" % n, md["color"] if n > 0 else Color(0.3, 0.3, 0.3), "WIRKUNG\n" + str(md["text"]).replace("; ", "\n") + "\n\nVERKAUF\n%d P pro Stück beim Vendor\n\nANWENDUNG\nKlick: essen · E: im Wald sammeln\nGleiche Effekte stapeln nicht. Erneutes Essen erneuert die Dauer." % md.sell, func(): _eat(k), -1, k)

	if main.forest_keys:
		for key_id: String in ForestKeys.KEYS:
			var found: bool = main.forest_keys.has_key(key_id)
			var detail := "Schlüssel für %s. %s" % [ForestKeys.KEYS[key_id], "Bleibt bei dir und öffnet alle Türen dieser Hütte." if found else "Ein seltener Fund im Wald – nicht in jedem Durchlauf vorhanden. In der Nähe helfen Hinweis und Richtungspfeil."]
			_slot("Schlüssel: %s" % ForestKeys.KEYS[key_id], "Gefunden" if found else "Noch nicht gefunden", Color(0.95, 0.73, 0.32) if found else Color(0.3, 0.3, 0.3), detail, func(): info.text = detail, -1, "key")

func _eat(kind: String) -> void:
	if NetSession.enabled:
		NetSession.command("eat", [kind])
		return
	var error := Mushrooms.consume(player, mushrooms, kind)
	if not error.is_empty():
		info.text = error
		return
	if kind == "fliegenpilz" and main.achievements: main.achievements.event("rausch")
	main.stats.mushrooms_eaten += 1
	hud.message("%s: %s" % [MUSHROOMS[kind].name, MUSHROOMS[kind].text], 3.0)
	Sfx.play(self, "consume", -8.0)
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
	get_tree().paused = not NetSession.enabled
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func close() -> void:
	is_open = false
	panel.visible = false
	get_tree().paused = false
	player.active = player.alive and not main.over
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if player.active else Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	if not player or not main: return
	_effects_ui_t -= delta
	if _effects_ui_t > 0.0: return
	_effects_ui_t = 0.1
	var text := Mushrooms.summary(player.mushroom_effects)
	effects_label.text = text
	var quests: RichTextLabel = main.progression.tracker
	effects_label.position.y = maxf(320.0, quests.position.y + quests.get_minimum_size().y + 16.0) if quests.visible else 320.0
	effects_label.visible = main.started and not main.over and player.alive and player.active and not text.is_empty()
	active_label.text = text
	active_label.get_parent().visible = not text.is_empty()
	active_label.visible = not text.is_empty()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_I and main.started and not main.over:
		if main.skills and main.skills.is_open:
			return
		toggle()
