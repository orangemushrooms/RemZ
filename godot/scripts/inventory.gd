# Inventory (I): weapons with ammunition, grenades, collected mushrooms. Resident-Evil style grid, pauses the game.
class_name Inventory
extends CanvasLayer

const Mushrooms = preload("res://scripts/mushrooms.gd")
const MUSHROOMS = Mushrooms.DEFS
const SlotButton = preload("res://scripts/item_slot_button.gd")

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
const CATEGORIES := ["All", "Weapons", "Fireworks", "Supplies", "Keys"]
var category_filter := 0
var sort_order := 0
var category_buttons: Array[Button] = []
var sort_select: OptionButton
var item_scroll: ScrollContainer
var empty_label: Label
var _slot_category := 1

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
	title.text = "INVENTORY"
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
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	v.add_child(filters)
	var group := ButtonGroup.new()
	for i in CATEGORIES.size():
		var button := Button.new()
		button.text = CATEGORIES[i]
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = i == category_filter
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_color_override("font_pressed_color", Color(1.0, 0.7, 0.28))
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.pressed.connect(_select_category.bind(i))
		category_buttons.append(button)
		filters.add_child(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(spacer)
	sort_select = OptionButton.new()
	sort_select.add_theme_font_size_override("font_size", 14)
	for caption in ["Sort: category", "Name: A–Z", "Name: Z–A"]:
		sort_select.add_item(caption)
	sort_select.item_selected.connect(_select_sort)
	filters.add_child(sort_select)
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
	item_scroll = ScrollContainer.new()
	item_scroll.custom_minimum_size = Vector2(795, 310)
	item_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(item_scroll)
	var items := VBoxContainer.new()
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item_scroll.add_child(items)
	items.add_child(grid)
	empty_label = Label.new()
	empty_label.add_theme_font_size_override("font_size", 17)
	empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_label.custom_minimum_size.y = 100
	items.add_child(empty_label)
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
	info.text = "Hover over an item for details."
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
	hint.text = "Right click: assign a quick bar slot (1-9 / 0)  ·  I / Esc: close  ·  Click a weapon: equip  ·  Click mushrooms: eat  ·  Buy weapons and supplies from Vendor. Choose skins for the equipped weapon at the trader."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.55))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)

func add_mushroom(kind: String) -> void:
	if not MUSHROOMS.has(kind): return
	mushrooms[kind] = mushrooms.get(kind, 0) + 1
	hud.message(Lang.t("%s collected (%d)", [MUSHROOMS[kind]["name"], mushrooms[kind]]), 1.5)
	if main.achievements:
		main.achievements.event("mushrooms")

func _slot(title: String, sub: String, color: Color, detail: String, on_click: Callable, fill: float = -1.0, icon_id := "item", quick_id := "") -> void:
	if category_filter != 0 and category_filter != _slot_category:
		return
	var b := SlotButton.new()
	b.set_meta("category", _slot_category)
	b.set_meta("item_title", title)
	b.set_meta("item_order", grid.get_child_count())
	b.custom_minimum_size = Vector2(186, 190)
	# Title and detail stay portable text; the card and the detail panel resolve it when shown and put
	# every " · " part of the detail on its own line (SlotButton.card_text).
	var card := Lang.t("%s\n%s", [title, detail])
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.tooltip_text = card
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
	b.mouse_entered.connect(func(): info.text = SlotButton.card_text(card))
	b.focus_entered.connect(func(): info.text = SlotButton.card_text(card))
	b.pressed.connect(on_click)
	if not quick_id.is_empty():
		b.tooltip_text += "\n" + Lang.t("Right click: assign to the quick bar (1-9 / 0)")
		b.gui_input.connect(func(event: InputEvent):
			if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
				main.quickbar.offer_item(quick_id)
				b.accept_event())
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
		grid.remove_child(c)
		c.queue_free()
	if main.achievements:
		var names: Array = []
		var next: Array = []
		for d in Achievements.DEFS:
			if main.achievements.unlocked.has(d["id"]):
				names.append(d["title"])
			elif next.size() < 3:
				next.append(Lang.t("%s (%d/%d)", [d["text"], main.achievements.counters.get(d["counter"], 0), d["target"]]))
		ach_label.text = Lang.t("★ %s · latest: %s\nNext goals: %s", [main.achievements.progress_text(), names.back() if names.size() > 0 else "none yet", ", ".join(next)])
	if "stats" in main and main.stats:
		var st = main.stats
		stats_label.text = Lang.t("This round: %d kills · %d headshots · accuracy %d%% · streak %d", [st.kills, st.headshots, int(round(st.accuracy() * 100.0)), st.best_streak])
	_slot_category = 2
	for id in Fireworks.DEFS:
		var spec: Dictionary = Fireworks.DEFS[id]
		var amount: int = main.fireworks.stock(player.peer_id)[id]
		if amount <= 0: continue
		var usage := Lang.t("%s\n\nUSAGE\nSelecting closes the inventory. Left click: set up and light. Rockets and batteries need open sky.\nRight click: back to your weapon. No combat damage.", [spec.desc]) if spec.rocket else Lang.t("%s\n\nUSAGE\nSelecting closes the inventory. Left click: light and throw. Bang after 2.4 seconds.\nRight click: back to your weapon. No combat damage.", [spec.desc])
		_slot(spec.name, Lang.t("%d owned · Select", [amount]), spec.color, usage, main.fireworks.select.bind(id), float(amount) / spec.limit, Fireworks.icon_id(id), id)
	_slot_category = 3
	var market = main.progression.rare_market
	var rare: Dictionary = market.data(player.peer_id)
	for id in rare.owned:
		var spec: Dictionary = Player.RareItems.DEFS[id]
		_slot(spec.name, "Active" if rare.active == id else "Activate talisman", Color(0.8, 0.45, 1), Lang.t("%s One talisman active at a time.", [spec.desc]), market.request_equip.bind(id), -1, "relic", id)
	if not rare.owned.is_empty():
		_slot("Unequip talisman", "No talisman", Color(0.55, 0.5, 0.6), "You keep all your talismans.", market.request_equip.bind("none"), -1, "relic")
	for id in ["fire", "frost"]:
		if int(rare.ammo[id]) <= 0: continue
		var spec: Dictionary = Player.RareItems.DEFS[id]
		_slot(spec.name, Lang.t("%d rounds · %s", [rare.ammo[id], "Active" if rare.mode == id else "Activate"]), Color(1, 0.6, 0.2) if id == "fire" else Color(0.35, 0.8, 1), Lang.t("%s Uses one charge per shot on top of normal ammo, misses included. Shotgun: one charge for all pellets.", [spec.desc]), market.request_equip.bind(id), -1, "ammo", id)
	if int(rare.ammo.fire) + int(rare.ammo.frost) > 0:
		_slot("Normal rounds", "Save special ammo", Color(0.6, 0.6, 0.5), "Turns special ammo off without losing any of it.", market.request_equip.bind("normal"), -1, "ammo")
	_slot_category = 1
	for id in weapons.ORDER:
		if not weapons.unlocked.get(id, false):
			continue
		var d: Dictionary = weapons.state[id].def
		var s: Dictionary = weapons.state[id]
		var eq: bool = id == weapons.current
		if Weapons.is_melee(id):
			var detail := Lang.t("%s · %d damage per hit · %.2f s between hits · %.2f m range. No ammo. Attack: left click or H.", [d.name, roundi(float(d.damage) * weapons.effective_damage_mul()), d.rate, d.range])
			detail += "\n" + Lang.t("Right click: %d damage, %.2f s recovery, %.2f m range.", [roundi(float(d.stab_damage) * weapons.effective_damage_mul()), d.stab_rate, d.stab_range])
			_slot(Lang.t("%s  ●", [d.name]) if eq else d.name, "Melee · Equip", Color(1.0, 0.7, 0.28) if eq else Color(0.5, 0.5, 0.45), detail, func(): main.fireworks.cancel(); weapons.set_weapon(id); _refresh(), 1.0, id, id)
			continue
		var per_second := 1.0 / maxf(0.01, float(d["rate"]))
		var dps := float(d["damage"]) * float(d["pellets"]) * per_second * weapons.effective_damage_mul()
		var detail := Lang.t("%s%s  ·  Magazine %d / %d, reserve %d  ·  Damage %d%s per shot (×%.1f skill), headshot ×2.2  ·  %.1f rounds/s (%d damage/s)  ·  Range %d m  ·  Reload %.1f s", [
			d["name"], "  (equipped)" if eq else "", s["ammo"], int(d["mag"]), s["reserve"], int(d["damage"]), Lang.t(" × %d pellets", [int(d["pellets"])]) if int(d["pellets"]) > 1 else "", weapons.effective_damage_mul(), per_second, int(dps), int(d["range"]), float(d["reload"]) * weapons.effective_reload_mul()])
		var fill := float(s["ammo"] + s["reserve"]) / float(int(d["mag"]) + int(d["reserve"]))
		detail += "\n" + Weapons.Mods.summary(weapons.mod_loadout.get(id, {}))
		if d.has("pierce_targets"): detail += "\n" + Weapons.piercing_description(id, d)
		_slot(Lang.t("%s  ●", [d["name"]]) if eq else d["name"], Lang.t("%d / %d  ·  Equip", [s["ammo"], s["reserve"]]), Color(1.0, 0.7, 0.28) if eq else Color(0.5, 0.5, 0.45),
			detail, func(): main.fireworks.cancel(); weapons.set_weapon(id); _refresh(), fill, id, id)
	if weapons.grenades > 0:
		_slot("Grenades", Lang.t("%d owned  ·  Key G", [weapons.grenades]), Color(0.4, 0.5, 0.35), Lang.t("Hand grenades: 2.6 s fuse, 7 m radius, 260 damage at the center. Throw with G. Pouch limit: %d. Restock at Vendor or from fallen zombies.", [weapons.grenades_max]), func(): pass, float(weapons.grenades) / maxf(1.0, weapons.grenades_max), "grenade", "grenade")
	_slot_category = 3
	for kind in main.hunting.FOOD:
		var count := int(main.hunting.stock(player.peer_id).get(kind, 0))
		if count <= 0: continue
		var spec: Dictionary = main.hunting.FOOD[kind]
		_slot(spec.name, Lang.t("%d owned · %s", [count, "Eat" if kind == "cooked_meat" else "Grill at the camp"]), Color(0.72, 0.34, 0.2), Lang.t("%s\nSale: %d R each at Vendor.", [spec.text, spec.sell]), func():
			if kind == "cooked_meat": main.hunting.request("eat")
			else: info.text = spec.text, -1, kind, kind if kind == "cooked_meat" else "")
	for k in MUSHROOMS:
		var n: int = mushrooms.get(k, 0)
		if n <= 0: continue
		var md: Dictionary = MUSHROOMS[k]
		if md.get("collectible", false):
			_slot(md.name, Lang.t("%d owned · sells for 1000 R", [n]), md.color, md.text, func(): info.text = md.text, -1, k)
			continue
		# One effect per line: the split has to run on the translated text, so it is resolved here (the
		# inventory is rebuilt on every opening, in the language of the moment).
		var effect := Lang.raw(Lang.text(str(md["text"])).replace("; ", "\n"))
		_slot(md["name"], Lang.t("%d owned  ·  Click: eat", [n]), md["color"] if n > 0 else Color(0.3, 0.3, 0.3), Lang.t("EFFECT\n%s\n\nSALE\n%d R each at Vendor\n\nUSAGE\nClick: eat · E: gather in the forest\nIdentical effects do not stack. Eating again renews the duration.", [effect, md.sell]), func(): _eat(k), -1, k, k)

	_slot_category = 4
	if main.forest_keys:
		for key_id: String in ForestKeys.KEYS:
			var found: bool = main.forest_keys.has_key(key_id)
			if not found: continue
			var detail := Lang.t("Key for the %s. Stays with you and opens every door of this hut.", [ForestKeys.KEYS[key_id]]) if found else Lang.t("Key for the %s. A rare find in the forest – not there in every run. Nearby, a hint and a direction arrow help.", [ForestKeys.KEYS[key_id]])
			_slot(Lang.t("Key: %s", [ForestKeys.KEYS[key_id]]), "Found" if found else "Not found yet", Color(0.95, 0.73, 0.32) if found else Color(0.3, 0.3, 0.3), detail, func(): info.text = detail, -1, "key")

	_sort_slots()
	empty_label.visible = grid.get_child_count() == 0
	empty_label.text = "No items." if category_filter == 0 else Lang.t("No items in the %s category.", [CATEGORIES[category_filter]])

func _select_category(index: int) -> void:
	category_filter = index
	category_buttons[index].set_pressed_no_signal(true)
	_refresh()
	_reset_item_view()

func _select_sort(index: int) -> void:
	sort_order = index
	_sort_slots()
	_reset_item_view()

func _reset_item_view() -> void:
	item_scroll.scroll_vertical = 0
	info.text = "Hover over an item for details."

func _notification(what: int) -> void:
	# The detail panel may still hold the resolved card of the last hovered item.
	if what == NOTIFICATION_TRANSLATION_CHANGED and info:
		info.text = "Hover over an item for details."

func _sort_slots() -> void:
	var slots := grid.get_children()
	slots.sort_custom(func(a: Node, b: Node) -> bool:
		if sort_order == 0:
			var ac := int(a.get_meta("category"))
			var bc := int(b.get_meta("category"))
			return ac < bc if ac != bc else int(a.get_meta("item_order")) < int(b.get_meta("item_order"))
		# Titles are portable text: sort by the names the player reads.
		var comparison := Lang.text(str(a.get_meta("item_title"))).naturalnocasecmp_to(Lang.text(str(b.get_meta("item_title"))))
		return comparison < 0 if sort_order == 1 else comparison > 0)
	for i in slots.size():
		grid.move_child(slots[i], i)

func _eat(kind: String) -> void:
	if NetSession.enabled:
		NetSession.command("eat", [kind])
		return
	var error := Mushrooms.consume(player, mushrooms, kind)
	if not error.is_empty():
		# The quick bar triggers this with the inventory closed, where the detail panel cannot be
		# seen at all: say it on the HUD as well, like the coop host already does.
		info.text = error
		hud.message(error, 2.0)
		return
	if kind == "fliegenpilz" and main.achievements: main.achievements.event("rausch")
	main.stats.mushrooms_eaten += 1
	hud.message(Lang.t("%s: %s", [MUSHROOMS[kind].name, MUSHROOMS[kind].text]), 3.0)
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
	weapons.viewmodel.visible = player.active
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
