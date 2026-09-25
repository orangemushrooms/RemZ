# Top-down tower planner (25 Sep 2026): T opens a bird's-eye view over the forest hut, the tower types on a
# card at the left, the six roof slots as markers, the mouse places a tower anywhere within PLANNER_REACH of
# the player, drags a standing ground tower to a new spot and the wheel / R turns the ghost. Everything goes
# through DefenceSystem (placement_error with planner = true, purchase, relocate, rotate_tower) so the host
# validates every move in co-op as before.
class_name TowerPlanner
extends CanvasLayer

const INK := Color(0.035, 0.048, 0.047, 0.97)
const MUTED := Color(0.61, 0.68, 0.65)
const PAPER := Color(0.93, 0.95, 0.9)
const GOLD := Color(0.94, 0.76, 0.43)
const GREEN := Color(0.35, 0.89, 0.66)
const RED := Color(1.0, 0.28, 0.22)
const VIEW_SIZE := 34.0            # the roof and its near surroundings (was 68: the hut was a stamp in the middle)
const VIEW_MIN := 18.0
const VIEW_MAX := 80.0
const PLANNER_REACH := 45.0
const ROOF_SNAP := 2.2              # a click this close to a roof slot goes onto the slot

var defences: Node
var game: Node
var player: Player
var is_open := false
var overview: Camera3D
var panel: Control
var kind_buttons: Dictionary = {}
var roof_buttons: Array[Button] = []
var wallet: Label
var status: Label
var hint: Label
var title: Label
var selected_roof := -1
var hover_point := Vector3.INF
var hover_valid := false
var hover_tower: DefenceTower = null
var dragging: DefenceTower = null
var drag_moved := false
var ghost_yaw := 0.0
var roof_markers: Array[MeshInstance3D] = []
var _saved_mouse := Input.MOUSE_MODE_CAPTURED
var _saved_hud := true
var _saved_viewmodel := true
var _was_paused := false
var _refresh_t := 0.0
var _state: Array = []

func setup(system: Node) -> void:
	defences = system
	game = system.game
	player = game.player
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 25
	overview = Camera3D.new()
	overview.name = "TowerPlannerOverview"
	overview.projection = Camera3D.PROJECTION_ORTHOGONAL
	overview.size = VIEW_SIZE
	overview.near = 0.5
	overview.far = 400.0
	overview.cull_mask = player.camera.cull_mask
	game.add_child(overview)
	_build_ui()

static func _style(bg: Color, border := Color(0.2, 0.27, 0.25), pad := 14.0) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = pad
	box.content_margin_bottom = pad
	return box

static func _label(text: String, size: int, color := PAPER) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

static func _button(text: String, accent := false) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_stylebox_override("normal", _style(Color(0.19, 0.25, 0.22) if accent else Color(0.08, 0.11, 0.10), GOLD if accent else Color(0.23, 0.3, 0.27), 10))
	button.add_theme_stylebox_override("hover", _style(Color(0.22, 0.28, 0.24), GOLD, 10))
	button.add_theme_stylebox_override("pressed", _style(Color(0.1, 0.22, 0.17), GREEN, 10))
	button.add_theme_stylebox_override("disabled", _style(Color(0.065, 0.08, 0.075), Color(0.15, 0.19, 0.17), 10))
	button.add_theme_color_override("font_color", PAPER)
	button.add_theme_color_override("font_disabled_color", MUTED)
	return button

func _build_ui() -> void:
	panel = Control.new()
	panel.name = "TowerPlanner"
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	panel.hide()
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _style(INK))
	card.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	card.offset_left = 24
	card.offset_top = 24
	card.offset_bottom = -24
	card.custom_minimum_size.x = 360
	panel.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	card.add_child(column)
	column.add_child(_label("REMETSCHWIL SENNHOF   /   DEFENSE", 12, GOLD))
	title = _label("TOWER PLANNER", 26)
	column.add_child(title)
	wallet = _label("", 18, GOLD)
	column.add_child(wallet)
	column.add_child(_label("TOWER TYPES", 12, GOLD))
	for kind in DefenceTower.TYPES:
		var button := _button("")
		button.pressed.connect(select_kind.bind(kind))
		column.add_child(button)
		kind_buttons[kind] = button
	column.add_child(_label("FOREST HUT ROOF", 12, GOLD))
	var roof_row := GridContainer.new()
	roof_row.columns = 3
	roof_row.add_theme_constant_override("h_separation", 6)
	roof_row.add_theme_constant_override("v_separation", 6)
	column.add_child(roof_row)
	for i in 6:
		var button := _button("")
		button.custom_minimum_size.y = 40
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.pressed.connect(place_roof.bind(i))
		roof_row.add_child(button)
		roof_buttons.append(button)
	status = _label("", 14, MUTED)
	column.add_child(status)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	var back := _button("Back to the game  [T / Esc]")
	back.pressed.connect(close)
	column.add_child(back)
	hint = _label("", 14)
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("shadow_offset_y", 2)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_left = 410
	hint.offset_right = -24
	hint.offset_top = -70
	hint.offset_bottom = -20
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(hint)

func _build_roof_markers() -> void:
	for i in 6:
		var marker := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 0.55
		ring.outer_radius = 0.8
		marker.mesh = ring
		marker.material_override = Barricade._marker_material(GOLD, 0.85)
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.position = defences.roof_position(i) + Vector3.UP * 0.1
		marker.hide()
		game.add_child(marker)
		roof_markers.append(marker)

func open() -> void:
	if is_open or not game.started or game.over or not player.alive or not player.active or player.mounted_tower: return
	_was_paused = get_tree().paused
	_saved_mouse = Input.mouse_mode
	_saved_hud = game.hud.visible
	_saved_viewmodel = game.weapons.viewmodel.visible
	is_open = true
	defences.is_open = true
	selected_roof = -1
	dragging = null
	hover_tower = null
	ghost_yaw = player.rotation.y
	player.active = false
	get_tree().paused = not NetSession.enabled
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.hud.hide()
	game.weapons.viewmodel.hide()
	var centre: Vector3 = game.hut.center
	overview.size = VIEW_SIZE
	overview.global_position = centre + Vector3.UP * 60.0
	overview.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	overview.make_current()
	if roof_markers.is_empty(): _build_roof_markers()
	for marker in roof_markers: marker.show()
	for crowns in get_tree().get_nodes_in_group("tree_crowns"): crowns.visible = false   # see the ground, not the canopy
	defences._build_preview()
	panel.show()
	_state = []
	_refresh()

func close() -> void:
	if not is_open: return
	is_open = false
	defences.is_open = false
	dragging = null
	panel.hide()
	for marker in roof_markers: marker.hide()
	for crowns in get_tree().get_nodes_in_group("tree_crowns"): crowns.visible = true
	if defences.ghost: defences.ghost.hide()
	if defences.range_marker: defences.range_marker.hide()
	player.camera.make_current()
	game.hud.visible = _saved_hud
	game.weapons.viewmodel.visible = _saved_viewmodel
	get_tree().paused = not NetSession.enabled and (_was_paused or game.over)
	player.active = player.alive and not game.over and not get_tree().paused
	Input.mouse_mode = _saved_mouse if player.active else Input.MOUSE_MODE_VISIBLE
	game.hud.set_prompt("")
	defences.input_grace = 0.2

func select_kind(kind: String) -> void:
	var reason: String = defences.build_requirement(player, kind)
	if not reason.is_empty():
		status.text = Lang.t(reason)
		status.add_theme_color_override("font_color", RED)
		return
	defences.selected_kind = kind
	defences._build_preview()
	status.text = Lang.t("%s selected. Click the map to place it, drag a standing tower to move it.", [DefenceTower.SPECS[kind].name])
	status.add_theme_color_override("font_color", GREEN)
	_state = []

# the roof slot a point snaps to (-1 = none): the six rings are the targets, not the roof tiles between them
func roof_slot_near(point: Vector3) -> int:
	if not point.is_finite(): return -1
	var best := -1
	var best_d := ROOF_SNAP
	for i in 6:
		var slot: Vector3 = defences.roof_position(i)
		var d := Vector2(slot.x - point.x, slot.z - point.z).length()
		if d < best_d and absf(slot.y - point.y) < 4.0:
			best_d = d
			best = i
	return best

# the ground (or roof) point under a screen position, INF when the ray misses
func point_at(screen: Vector2) -> Vector3:
	var origin := overview.project_ray_origin(screen)
	var normal := overview.project_ray_normal(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + normal * 200.0, 1)
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return Vector3.INF
	return hit.position

func tower_near(point: Vector3, radius := 2.2) -> DefenceTower:
	var best: DefenceTower = null
	var best_d := radius
	for tower: DefenceTower in defences.towers.values():
		if not is_instance_valid(tower): continue
		var d: float = Vector2(tower.global_position.x - point.x, tower.global_position.z - point.z).length()
		if d < best_d:
			best_d = d
			best = tower
	return best

# ---- actions (the mouse handlers and the tests call these)
func place_at(point: Vector3) -> String:
	if not point.is_finite(): return "Point the map at a building site."
	var kind: String = defences.selected_kind
	var target := point
	var slot: int = defences.roof_index(point)
	if slot < 0: slot = roof_slot_near(point)
	if slot >= 0: target = defences.roof_position(slot)
	else: target = Map.ground_pos(point.x, point.z)
	if NetSession.enabled:
		NetSession.command("tower_place", [target, ghost_yaw, kind, true])
		return ""
	var error: String = defences.purchase(player, target, ghost_yaw, kind, true)
	_state = []
	return error

func place_roof(slot: int) -> void:
	selected_roof = slot
	var tower: DefenceTower = defences.roof_tower(slot)
	if tower:
		status.text = Lang.t("Roof slot %d: %s · Tier %d · %d / %d HP", [slot + 1, tower.spec().name, tower.level, ceili(tower.hp), int(tower.max_hp())])
		status.add_theme_color_override("font_color", GOLD)
		return
	_report(place_at(defences.roof_position(slot)))

func move_tower(tower: DefenceTower, point: Vector3) -> String:
	if not is_instance_valid(tower) or not point.is_finite(): return "Tower not found."
	if NetSession.enabled:
		NetSession.command("tower_move", [tower.tower_id, Map.ground_pos(point.x, point.z)])
		return ""
	var error: String = defences.relocate(player, tower.tower_id, Map.ground_pos(point.x, point.z))
	_state = []
	return error

func rotate_hovered(steps: int) -> void:
	if hover_tower and not dragging:
		var yaw := wrapf(hover_tower.rotation.y + deg_to_rad(15.0) * steps, -PI, PI)
		if NetSession.enabled: NetSession.command("tower_rotate", [hover_tower.tower_id, yaw, true])
		else: _report(defences.rotate_tower(player, hover_tower.tower_id, yaw, true))
	else:
		ghost_yaw = wrapf(ghost_yaw + deg_to_rad(15.0) * steps, -PI, PI)

func _report(error: String) -> void:
	if error.is_empty():
		status.text = "Done."
		status.add_theme_color_override("font_color", GREEN)
		Sfx.play(self, "confirm", -8.0)
	else:
		status.text = Lang.t(error)
		status.add_theme_color_override("font_color", RED)

# ---- input
func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseMotion:
		hover_point = point_at(event.position)
		if dragging and hover_point.is_finite(): drag_moved = true
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				hover_point = point_at(event.position)
				var tower := tower_near(hover_point) if hover_point.is_finite() else null
				if tower and not tower.rooftop:
					dragging = tower
					drag_moved = false
				elif hover_point.is_finite():
					_report(place_at(hover_point))
			elif dragging:
				var target := point_at(event.position)
				if drag_moved and target.is_finite(): _report(move_tower(dragging, target))
				dragging = null
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			rotate_hovered(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_R:
			rotate_hovered(-1 if event.shift_pressed else 1)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_ESCAPE or event.physical_keycode == KEY_T:
			close()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
			overview.size = clampf(overview.size * 0.8, VIEW_MIN, VIEW_MAX)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			overview.size = clampf(overview.size * 1.25, VIEW_MIN, VIEW_MAX)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode >= KEY_1 and event.physical_keycode <= KEY_5:
			var index: int = event.physical_keycode - KEY_1
			if index < DefenceTower.TYPES.size(): select_kind(DefenceTower.TYPES[index])
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not is_open: return
	if not player.alive or game.over:
		close()
		return
	_refresh_t += delta
	if _refresh_t >= 0.25:
		_refresh_t = 0.0
		_refresh()
	var ghost: Node3D = defences.ghost
	if not hover_point.is_finite():
		if ghost: ghost.hide()
		if defences.range_marker: defences.range_marker.hide()
		return
	hover_tower = dragging if dragging else tower_near(hover_point)
	var kind: String = defences.selected_kind
	var spec: Dictionary = DefenceTower.SPECS[kind]
	if dragging:
		var target := Map.ground_pos(hover_point.x, hover_point.z)
		var error: String = defences.placement_error(player, target, dragging.kind, true, dragging.tower_id)
		hover_valid = error.is_empty()
		if ghost:
			ghost.global_position = target
			ghost.rotation.y = dragging.rotation.y
			ghost.show()
			defences.ghost_material.albedo_color = Color(0.2, 0.95, 0.5, 0.28) if hover_valid else Color(1, 0.16, 0.08, 0.3)
		if defences.range_marker: defences.range_marker.display(target, dragging.attack_range(), dragging.rotation.y, false, not hover_valid)
		hint.text = Lang.t("Moving %s · release to drop it here", [dragging.spec().name]) if hover_valid else Lang.t("Moving %s · %s", [dragging.spec().name, Lang.t(error)])
		return
	if hover_tower:
		if ghost: ghost.hide()
		if defences.range_marker: defences.range_marker.display(hover_tower.global_position, hover_tower.attack_range(), hover_tower.rotation.y, false)
		hint.text = Lang.t("%s · Tier %d · %d / %d HP · drag to move · R / wheel to turn", [hover_tower.spec().name, hover_tower.level, ceili(hover_tower.hp), int(hover_tower.max_hp())])
		return
	var slot: int = defences.roof_index(hover_point)
	if slot < 0: slot = roof_slot_near(hover_point)
	var target: Vector3 = defences.roof_position(slot) if slot >= 0 else Map.ground_pos(hover_point.x, hover_point.z)
	var error: String = defences.placement_error(player, target, kind, true)
	hover_valid = error.is_empty()
	if ghost:
		ghost.global_position = target
		ghost.rotation.y = ghost_yaw
		ghost.show()
		defences.ghost_material.albedo_color = Color(0.2, 0.95, 0.5, 0.28) if hover_valid else Color(1, 0.16, 0.08, 0.3)
	if defences.range_marker: defences.range_marker.display(target, defences.preview_range(), ghost_yaw, false, not hover_valid)
	if slot >= 0 and hover_valid:
		hint.text = Lang.t("Roof slot %d · %s · %d R · click to build", [slot + 1, spec.name, spec.cost])
	else:
		hint.text = Lang.t("%s · %d R · click to build · R / wheel to turn · +/- zoom", [spec.name, spec.cost]) if hover_valid else Lang.t("%s · %s", [spec.name, Lang.t(error)])

func _refresh() -> void:
	var state := [game.waves.completed, player.score, defences.towers.size(), defences.selected_kind, Lang.current]
	if state == _state: return
	_state = state
	wallet.text = Lang.t("%d  REM DOLLARS  ·  %d / %d towers", [player.score, defences.towers.size(), DefenceTower.LIMIT])
	for kind in kind_buttons:
		var spec: Dictionary = DefenceTower.SPECS[kind]
		var button: Button = kind_buttons[kind]
		var reason: String = defences.build_requirement(player, kind)
		var available := "From the start" if defences.unlock_waves(kind) == 0 else Lang.t("After wave %d", [defences.unlock_waves(kind)])
		button.text = Lang.t("%d  %s · %d R · %d m\n%s", [DefenceTower.TYPES.find(kind) + 1, spec.name, spec.cost, spec.range, available if reason.is_empty() else Lang.t(reason)])
		button.disabled = not reason.is_empty()
		button.add_theme_color_override("font_color", GOLD if kind == defences.selected_kind else PAPER)
	for i in roof_buttons.size():
		var tower: DefenceTower = defences.roof_tower(i)
		roof_buttons[i].text = Lang.t("%d · %s", [i + 1, tower.spec().name if tower else "free"])
		roof_buttons[i].add_theme_color_override("font_color", GREEN if tower else PAPER)
