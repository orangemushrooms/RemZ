extends CanvasLayer

const Recipes = preload("res://scripts/brew_recipes.gd")
var brewing: Node3D
var game: Node3D
var is_open := false
var panel: PanelContainer
var rows: Dictionary = {}
var status: Label
var progress: ProgressBar
var refresh_t := 0.0

func setup(system: Node3D) -> void:
	brewing = system
	game = system.game
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(850, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("121b1f")
	style.border_color = Color("bd9655")
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	style.set_content_margin_all(22)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	panel.resized.connect(_layout)
	get_viewport().size_changed.connect(_layout)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	# Wrapped labels can report a tall minimum before their first layout. Shrink
	# the panel again once the container assigns their actual width.
	box.minimum_size_changed.connect(func(): panel.call_deferred("reset_size"))
	var title := Label.new()
	title.text = "CAMPFIRE BREWING"
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color("f1cd8a"))
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Field flowers + forest mushrooms / one bottle per recipe / 4 seconds"
	hint.add_theme_font_size_override("font_size", 15)
	box.add_child(hint)
	status = Label.new()
	status.add_theme_color_override("font_color", Color("97e1bc"))
	box.add_child(status)
	progress = ProgressBar.new()
	progress.custom_minimum_size.y = 8
	progress.show_percentage = false
	box.add_child(progress)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(800, 390)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 9)
	scroll.add_child(list)
	for kind in Recipes.DRINKS:
		var spec: Dictionary = Recipes.DRINKS[kind]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		list.add_child(row)
		row.add_child(ItemIcons.view(kind, Vector2(60, 90)))
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(details)
		var name_label := Label.new()
		name_label.text = spec.name
		name_label.add_theme_font_size_override("font_size", 20)
		name_label.add_theme_color_override("font_color", spec.color)
		details.add_child(name_label)
		var effect := Label.new()
		effect.text = spec.text
		effect.custom_minimum_size.x = 520
		effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		effect.add_theme_font_size_override("font_size", 14)
		details.add_child(effect)
		var ingredients := Label.new()
		ingredients.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ingredients.add_theme_font_size_override("font_size", 14)
		details.add_child(ingredients)
		var button := Button.new()
		button.custom_minimum_size = Vector2(115, 60)
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		button.pressed.connect(brewing.request.bind("brew", kind))
		row.add_child(button)
		rows[kind] = {"ingredients": ingredients, "button": button}
	var note := Label.new()
	note.custom_minimum_size.x = 790
	note.text = "Bottles go into your inventory (I). Identical effects refresh; the strongest bonus applies."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", 14)
	box.add_child(note)
	var back := Button.new()
	back.text = "Back to the fire / C or Esc"
	back.pressed.connect(close)
	box.add_child(back)
	panel.hide()

func _layout() -> void:
	var viewport := get_viewport().get_visible_rect().size
	var factor := minf(1.0, minf((viewport.x - 30) / maxf(panel.size.x, 1), (viewport.y - 30) / maxf(panel.size.y, 1)))
	panel.scale = Vector2.ONE * factor
	panel.position = (viewport - panel.size * factor) * 0.5

func open() -> void:
	if is_open or not game.started or game.over or not game.player.active or game.player.downed or brewing.station_for(game.player) < 0: return
	is_open = true
	game.player.active = false
	game.weapons.viewmodel.hide()
	game.hud.set_prompt("")
	for part in game.hud.crosshair_parts: part.hide()
	get_tree().paused = not NetSession.enabled
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.show()
	panel.reset_size()
	refresh()
	_layout()

func close() -> void:
	if not is_open: return
	is_open = false
	panel.hide()
	if not game.over: get_tree().paused = false
	game.player.active = game.player.alive and not game.over
	game.weapons.viewmodel.visible = game.player.active
	for part in game.hud.crosshair_parts: part.visible = game.player.active
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if game.player.active else Input.MOUSE_MODE_VISIBLE

func refresh() -> void:
	var peer: int = game.player.peer_id
	for kind in rows:
		var recipe: Dictionary = Recipes.DRINKS[kind]
		var parts := PackedStringArray()
		for item in recipe.ingredients:
			var name_text: String = Recipes.FLOWERS[item].name if Recipes.FLOWERS.has(item) else Inventory.MUSHROOMS[item].name
			parts.append(Lang.t("%s %d/%d", [name_text, brewing.ingredient_count(peer, item), recipe.ingredients[item]]))
		rows[kind].ingredients.text = "  +  ".join(parts)
		var can_brew: bool = brewing.available(peer, kind)
		rows[kind].ingredients.modulate = Color("97e1bc") if can_brew else Color("c8bdb1")
		rows[kind].button.disabled = not can_brew
		rows[kind].button.text = Lang.t("Brew\n%d / 8 bottles", [int(brewing.stock(peer).drinks.get(kind, 0))])
	_update_progress()

func _update_progress() -> void:
	var job: Dictionary = brewing.jobs.get(game.player.peer_id, {})
	progress.value = (1.0 - float(job.left) / Recipes.BREW_SECONDS) * 100 if not job.is_empty() else 0
	status.text = Lang.t("%s / %d s remaining", [Recipes.DRINKS[job.kind].name, ceili(float(job.left))]) if not job.is_empty() else "Choose a recipe. Ingredients show owned / needed."

func _process(delta: float) -> void:
	if not is_open: return
	if not game.player.alive or game.player.downed or game.over or brewing.station_for(game.player) < 0:
		close()
		return
	_update_progress()
	refresh_t -= delta
	if refresh_t <= 0:
		refresh_t = 0.25
		refresh()

func _input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("pause") or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_C)):
		close()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_C:
		if game.player.active and not game.player.controlling_drone and not game.player.mounted_tower and not game.defences.placing:
			open()
			if is_open: get_viewport().set_input_as_handled()
