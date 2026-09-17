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
	panel.custom_minimum_size = Vector2(760, 570)
	panel.position = Vector2(-380, -285)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.06, 0.94)
	style.border_color = Color(0.55, 0.45, 0.25)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var title := Label.new()
	title.text = "INVENTAR"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.28))
	v.add_child(title)
	grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)
	info = Label.new()
	info.text = ""
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(700, 40)
	info.add_theme_color_override("font_color", Color(0.85, 0.85, 0.8))
	v.add_child(info)
	ach_label = Label.new()
	ach_label.add_theme_font_size_override("font_size", 13)
	ach_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.4))
	ach_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ach_label.custom_minimum_size = Vector2(700, 60)
	v.add_child(ach_label)
	var hint := Label.new()
	hint.text = "B schliessen · Klick auf eine Waffe: ausrüsten · Klick auf Pilze: essen"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
	v.add_child(hint)

func add_mushroom(kind: String) -> void:
	mushrooms[kind] = mushrooms.get(kind, 0) + 1
	hud.message("%s gesammelt (%d)" % [MUSHROOMS[kind]["name"], mushrooms[kind]], 1.5)
	if main.achievements:
		main.achievements.event("mushrooms")

func _slot(title: String, sub: String, color: Color, detail: String, on_click: Callable) -> void:
	var b := Button.new()
	b.custom_minimum_size = Vector2(170, 92)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "%s\n%s" % [title, sub]
	b.add_theme_font_size_override("font_size", 14)
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.12, 0.12, 0.13)
	st.border_color = color
	st.set_border_width_all(2)
	st.set_corner_radius_all(4)
	st.set_content_margin_all(10)
	b.add_theme_stylebox_override("normal", st)
	var hv := st.duplicate()
	hv.bg_color = Color(0.2, 0.18, 0.14)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", hv)
	b.add_theme_stylebox_override("focus", hv)
	b.mouse_entered.connect(func(): info.text = detail)
	b.pressed.connect(on_click)
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
		ach_label.text = "★ %s: %s\nNächste Ziele: %s" % [main.achievements.progress_text(), ", ".join(names) if names.size() > 0 else "noch keine", ", ".join(next)]
	for id in weapons.DEFS:
		if not weapons.unlocked.get(id, false):
			continue
		var d: Dictionary = weapons.DEFS[id]
		var s: Dictionary = weapons.state[id]
		var eq: bool = id == weapons.current
		_slot(d["name"] + ("  ●" if eq else ""), "%d / %d" % [s["ammo"], s["reserve"]], Color(1.0, 0.7, 0.28) if eq else Color(0.5, 0.5, 0.45),
			"%s: %d im Magazin, %d Reserve. Schaden %d." % [d["name"], s["ammo"], s["reserve"], int(d["damage"])],
			func(): weapons.set_weapon(id); _refresh())
	_slot("Granaten", "%d Stück" % weapons.grenades, Color(0.4, 0.5, 0.35), "Handgranaten, werfen mit G.", func(): pass)
	for k in MUSHROOMS:
		var n: int = mushrooms.get(k, 0)
		var md: Dictionary = MUSHROOMS[k]
		_slot(md["name"], "%d Stück" % n, md["color"] if n > 0 else Color(0.3, 0.3, 0.3), md["text"], func(): _eat(k))

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
