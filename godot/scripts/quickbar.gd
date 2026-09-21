extends CanvasLayer

const SLOT_COUNT := 10
var game: Node
var bindings: Array[String] = ["pistol", "", "", "", "", "", "", "", "", "knife"]
var bar: HBoxContainer
var picker: PopupMenu
var pending_item := ""
var buttons: Array[Button] = []
var icons: Array[TextureRect] = []
var counts: Array[Label] = []
var _refresh_time := 0.0

func setup(scene: Node) -> void:
	game = scene
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 21
	bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 4)
	add_child(bar)
	for index in SLOT_COUNT:
		var button := Button.new()
		button.custom_minimum_size = Vector2(54, 76)
		button.focus_mode = Control.FOCUS_NONE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.035, 0.05, 0.06, 0.94)
		style.border_color = Color(0.55, 0.43, 0.23)
		style.set_border_width_all(1)
		style.set_corner_radius_all(5)
		button.add_theme_stylebox_override("normal", style)
		bar.add_child(button)
		var content := VBoxContainer.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(content)
		content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 3
		content.offset_right = -3
		content.add_theme_constant_override("separation", 0)
		var key := Label.new()
		key.text = str(index + 1) if index < 9 else "10 [0]"
		key.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		key.add_theme_font_size_override("font_size", 12)
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(key)
		var icon := ItemIcons.view("item", Vector2(44, 32))
		content.add_child(icon)
		var count := Label.new()
		count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		count.add_theme_font_size_override("font_size", 11)
		count.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(count)
		button.pressed.connect(func():
			if game.inventory.is_open: show_picker(index))
		button.gui_input.connect(func(event: InputEvent):
			if game.inventory.is_open and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				bindings[index] = ""
				refresh()
				button.accept_event())
		buttons.append(button)
		icons.append(icon)
		counts.append(count)
	picker = PopupMenu.new()
	add_child(picker)
	picker.id_pressed.connect(_pick)
	refresh()

func item_data(id: String) -> Dictionary:
	if id.is_empty(): return {}
	if Weapons.DEFS.has(id):
		var state: Dictionary = game.weapons.state[id]
		return {"name": Weapons.DEFS[id].name, "icon": id, "owned": game.weapons.unlocked.get(id, false), "count": "" if Weapons.is_melee(id) else "%d/%d" % [state.ammo, state.reserve]}
	if Inventory.MUSHROOMS.has(id):
		var amount := int(game.inventory.mushrooms.get(id, 0))
		return {"name": Inventory.MUSHROOMS[id].name, "icon": id, "owned": amount > 0, "count": str(amount)}
	if Fireworks.DEFS.has(id):
		var amount := int(game.fireworks.stock(game.player.peer_id).get(id, 0))
		return {"name": Fireworks.DEFS[id].name, "icon": "firework_rocket" if Fireworks.DEFS[id].rocket else "firework_cracker", "owned": amount > 0, "count": str(amount)}
	if id == "grenade":
		return {"name": "Granaten", "icon": id, "owned": game.weapons.grenades > 0, "count": str(game.weapons.grenades)}
	if Player.RareItems.DEFS.has(id):
		var stock: Dictionary = game.progression.rare_market.data(game.player.peer_id)
		var ammo := id in ["fire", "frost"]
		return {"name": Player.RareItems.DEFS[id].name, "icon": "ammo" if ammo else "relic", "owned": int(stock.ammo.get(id, 0)) > 0 if ammo else stock.owned.get(id, false), "count": str(stock.ammo.get(id, 0)) if ammo else ""}
	return {}

func owned_items() -> Array[String]:
	var result: Array[String] = []
	var candidates: Array = Weapons.ORDER.duplicate()
	candidates.append_array(Inventory.MUSHROOMS.keys())
	candidates.append_array(Fireworks.DEFS.keys())
	candidates.append("grenade")
	candidates.append_array(Player.RareItems.DEFS.keys())
	for id in candidates:
		if item_data(id).get("owned", false): result.append(id)
	return result

func bind_item(index: int, id: String) -> void:
	if index < 0 or index >= SLOT_COUNT: return
	if not id.is_empty() and not item_data(id).get("owned", false): return
	bindings[index] = id
	refresh()

func offer_item(id: String) -> void:
	if not game.inventory.is_open or not item_data(id).get("owned", false): return
	pending_item = id
	picker.clear()
	picker.set_meta("slot", -1)
	for index in SLOT_COUNT:
		var current := item_data(bindings[index])
		picker.add_item("Platz %d%s: %s" % [index + 1, " (Taste 0)" if index == 9 else "", current.get("name", "Leer")], index)
	picker.position = Vector2i(bar.get_global_mouse_position())
	picker.popup()

func show_picker(index: int) -> void:
	picker.clear()
	picker.set_meta("slot", index)
	var items := owned_items()
	picker.set_meta("items", items)
	picker.add_item("Belegung entfernen", 0)
	for i in items.size():
		picker.add_item(item_data(items[i]).name, i + 1)
	picker.position = Vector2i(buttons[index].global_position - Vector2(0, 320))
	picker.popup()

func _pick(index: int) -> void:
	var slot: int = picker.get_meta("slot", -1)
	if slot < 0: bind_item(index, pending_item)
	else:
		var items: Array = picker.get_meta("items", [])
		bind_item(slot, "" if index == 0 else items[index - 1])

func activate(index: int) -> void:
	if index < 0 or index >= SLOT_COUNT: return
	if not game.started or game.over or not game.player.alive or not game.player.active or get_tree().paused: return
	if game.defences.placing: return
	var id := bindings[index]
	var data := item_data(id)
	if data.is_empty(): return
	if not data.owned:
		game.hud.message("%s: nicht im Inventar" % data.name, 1.5)
		return
	if Weapons.DEFS.has(id):
		game.fireworks.cancel()
		game.weapons.set_weapon(id)
	elif Inventory.MUSHROOMS.has(id): game.inventory._eat(id)
	elif Fireworks.DEFS.has(id): game.fireworks.select(id)
	elif id == "grenade": game.weapons.throw_grenade()
	else: game.progression.rare_market.request_equip(id)
	refresh()

func refresh() -> void:
	for index in SLOT_COUNT:
		var id := bindings[index]
		var data := item_data(id)
		icons[index].visible = not data.is_empty()
		if not data.is_empty(): icons[index].texture = ItemIcons.texture(data.icon)
		counts[index].text = str(data.get("count", ""))
		var active: bool = (game.fireworks.armed and game.fireworks.selected == id) or (not game.fireworks.armed and game.weapons.current == id)
		buttons[index].modulate = Color(1, 0.8, 0.4) if active else (Color.WHITE if data.get("owned", false) else Color(0.55, 0.55, 0.55))
		buttons[index].tooltip_text = "%s\nInventar: Klick zum Belegen, Rechtsklick zum Leeren" % data.get("name", "Leer")

func _process(delta: float) -> void:
	if not game: return
	bar.visible = game.started and not game.over and game.player.alive and not game.player.mounted_tower and (game.player.active or game.inventory.is_open)
	if not bar.visible:
		picker.hide()
		return
	var viewport_size := get_viewport().get_visible_rect().size
	var factor := minf(1.0, maxf(0.5, (viewport_size.x - 32.0) / 576.0))
	bar.scale = Vector2.ONE * factor
	bar.position = Vector2((viewport_size.x - bar.size.x * factor) * 0.5, viewport_size.y - bar.size.y * factor - 12)
	_refresh_time -= delta
	if _refresh_time <= 0:
		_refresh_time = 0.1
		refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	var key: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
	if key < KEY_0 or key > KEY_9: return
	if event.ctrl_pressed or event.alt_pressed or event.meta_pressed: return
	if not game.player.active or game.player.mounted_tower or get_tree().paused: return
	activate(9 if key == KEY_0 else key - KEY_1)
	get_viewport().set_input_as_handled()
