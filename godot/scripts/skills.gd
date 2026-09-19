# Skill menu (Tab): spend points on upgrades and weapon unlocks.
class_name Skills
extends CanvasLayer

var player: Player
var weapons: Weapons
var hud: Hud
var main: Node
var panel: Control
var points_label: Label
var rows := {}
var levels := {}
var is_open := false

const UPGRADES := [
	{ "id": "hp", "name": "Zähigkeit", "desc": "+25 maximale Lebenspunkte", "cost": 100, "max": 4 },
	{ "id": "speed", "name": "Beine", "desc": "+8 % Laufgeschwindigkeit", "cost": 80, "max": 4 },
	{ "id": "regen", "name": "Erholung", "desc": "Schnellere Regeneration", "cost": 80, "max": 3 },
	{ "id": "damage", "name": "Schusskraft", "desc": "+12 % Schaden", "cost": 120, "max": 5 },
	{ "id": "reload", "name": "Schnelle Hände", "desc": "-15 % Nachladezeit", "cost": 80, "max": 3 },
	{ "id": "steady", "name": "Ruhige Hand", "desc": "-15 % Streuung", "cost": 90, "max": 3 },
	{ "id": "grenades", "name": "Granatentasche", "desc": "+1 Granate pro Welle", "cost": 70, "max": 4 },
	{ "id": "w_revolver", "name": "Revolver", "desc": "Waffe freischalten (Taste 2)", "cost": 150, "max": 1 },
	{ "id": "w_smg", "name": "MP5", "desc": "Waffe freischalten (Taste 3)", "cost": 200, "max": 1 },
	{ "id": "w_ak47", "name": "AK-47", "desc": "Waffe freischalten (Taste 4)", "cost": 300, "max": 1 },
	{ "id": "w_shotgun", "name": "Schrotflinte", "desc": "Waffe freischalten (Taste 5)", "cost": 180, "max": 1 },
]

func setup(p: Player, w: Weapons, h: Hud, m: Node) -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	player = p
	weapons = w
	hud = h
	main = m
	layer = 20
	panel = Control.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.visible = false
	add_child(panel)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.01, 0.02, 0.03, 0.82)
	panel.add_child(dim)
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	card.grow_vertical = Control.GROW_DIRECTION_BOTH
	var cs := StyleBoxFlat.new()
	cs.bg_color = Color(0.043, 0.06, 0.08)
	cs.border_color = Color(1, 1, 1, 0.15)
	cs.set_border_width_all(1)
	cs.set_corner_radius_all(10)
	cs.content_margin_left = 30; cs.content_margin_right = 30; cs.content_margin_top = 22; cs.content_margin_bottom = 22
	card.add_theme_stylebox_override("panel", cs)
	panel.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.custom_minimum_size = Vector2(640, 0)
	card.add_child(v)
	var title := Label.new()
	title.text = "SKILLS"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.28))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	points_label = Label.new()
	points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	points_label.add_theme_font_size_override("font_size", 16)
	v.add_child(points_label)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 6)
	v.add_child(grid)
	for u in UPGRADES:
		levels[u["id"]] = 0
		var name := Label.new()
		name.text = u["name"]
		name.add_theme_font_size_override("font_size", 16)
		grid.add_child(name)
		var desc := Label.new()
		desc.text = u["desc"]
		desc.modulate.a = 0.75
		desc.add_theme_font_size_override("font_size", 13)
		desc.custom_minimum_size = Vector2(240, 0)
		grid.add_child(desc)
		var lvl := Label.new()
		lvl.add_theme_font_size_override("font_size", 14)
		grid.add_child(lvl)
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(120, 30)
		btn.pressed.connect(_buy.bind(u["id"]))
		grid.add_child(btn)
		rows[u["id"]] = { "lvl": lvl, "btn": btn, "def": u }
	var hint := Label.new()
	hint.text = "Tab schliesst das Menü. Punkte kommen von Abschüssen und überstandenen Wellen."
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate.a = 0.6
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	_refresh()

func _cost(u: Dictionary) -> int:
	return int(u["cost"]) + int(u["cost"]) * levels[u["id"]] / 2

func _refresh() -> void:
	points_label.text = "Punkte: %d" % player.score
	for id in rows:
		var r: Dictionary = rows[id]
		var u: Dictionary = r["def"]
		var l: int = levels[id]
		r["lvl"].text = ("%d / %d" % [l, u["max"]]) if u["max"] > 1 else ("frei" if l > 0 else "gesperrt")
		if l >= int(u["max"]):
			r["btn"].text = "Max"
			r["btn"].disabled = true
		else:
			r["btn"].text = "Kaufen (%d)" % _cost(u)
			r["btn"].disabled = player.score < _cost(u)

func _buy(id: String) -> void:
	if NetSession.enabled:
		NetSession.command("upgrade", [id])
		return
	var u: Dictionary = rows[id]["def"]
	if levels[id] >= int(u["max"]) or player.score < _cost(u):
		return
	player.add_score(-_cost(u))
	levels[id] += 1
	match id:
		"hp":
			player.max_hp += 25.0
			player.hp = minf(player.max_hp, player.hp + 25.0)
			hud.hp_bar.max_value = player.max_hp
			hud.set_health(player.hp)
		"speed":
			player.speed_mul += 0.08
		"regen":
			player.regen_mul += 0.6
		"damage":
			weapons.damage_mul += 0.12
		"reload":
			weapons.reload_mul *= 0.85
		"steady":
			weapons.spread_mul *= 0.85
		"grenades":
			weapons.grenades_max += 1
			weapons.grenades += 1
			weapons.update_hud()
		_:
			if id.begins_with("w_"):
				weapons.unlock(id.substr(2))
				weapons.add_ammo(id.substr(2), 0)
	Sfx.play(self, "confirm", -8.0)
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
	player.active = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("skills") and main.started and not main.over:
		toggle()
