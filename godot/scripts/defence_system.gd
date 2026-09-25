class_name DefenceSystem
extends CanvasLayer

var game: Node
var towers: Dictionary = {}
var next_id := 1
var placing := false
var input_grace := 0.0
var is_open := false
var ghost: Node3D
var ghost_material: StandardMaterial3D
var build_position := Vector3.ZERO
var build_error := ""
var build_yaw := 0.0
var rotating_id := 0
var hint: Label
var boss_panel: VBoxContainer
var boss_name: Label
var boss_bar: ProgressBar
var selected_kind := "standard"
var roof_slot := -1
var site_picker: OptionButton
var roof_repair: Button
var roof_align: Button
var build_menu: PanelContainer
var kind_buttons: Dictionary = {}
var _build_menu_state: Array = []
var _control_send := 0.0
var _was_mounted := false
var range_marker: Node3D
var range_label: Label
var _range_sample := 0.0
var _tower_ads := 0.0
const TOWER_AIM_FOV := 55.0

func setup(main: Node) -> void:
	game = main
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	hint = Label.new()
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-450, -285)
	hint.size = Vector2(900, 180)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 19)
	hint.add_theme_color_override("font_shadow_color", Color.BLACK)
	hint.add_theme_constant_override("shadow_offset_x", 2)
	hint.add_theme_constant_override("shadow_offset_y", 2)
	hint.hide()
	add_child(hint)
	var tower_icon := ItemIcons.view("tower", Vector2(96, 64))
	hint.add_child(tower_icon)
	tower_icon.position = Vector2(352, -70)
	boss_panel = VBoxContainer.new()
	add_child(boss_panel)
	boss_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	boss_panel.offset_left = -300
	boss_panel.offset_right = 300
	boss_panel.offset_top = 100
	boss_panel.offset_bottom = 164
	boss_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_name = Label.new()
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_name.add_theme_font_size_override("font_size", 22)
	boss_panel.add_child(boss_name)
	boss_bar = ProgressBar.new()
	boss_bar.custom_minimum_size = Vector2(600, 13)
	boss_bar.show_percentage = false
	var red := StyleBoxFlat.new()
	red.bg_color = Color(0.55, 0.07, 0.035)
	boss_bar.add_theme_stylebox_override("fill", red)
	boss_panel.add_child(boss_bar)
	boss_panel.hide()
	_build_menu()
	_build_preview()
	range_marker = preload("res://scripts/tower_range.gd").new()
	game.add_child(range_marker)
	range_label = Label.new()
	add_child(range_label)
	range_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	range_label.offset_left = -260
	range_label.offset_right = 260
	range_label.offset_top = 48
	range_label.offset_bottom = 110
	range_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	range_label.add_theme_font_size_override("font_size", 18)
	range_label.add_theme_constant_override("outline_size", 5)
	range_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	range_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	range_label.hide()

func _build_preview() -> void:
	if is_instance_valid(ghost):
		game.remove_child(ghost)
		ghost.queue_free()
	ghost = Node3D.new()
	game.add_child(ghost)
	ghost_material = Barricade._marker_material(Color(0.2, 1, 0.55), 0.32)
	var preview := DefenceTower.new()
	preview.game = game
	preview.kind = selected_kind
	preview.rooftop = roof_slot >= 0
	preview.replica = true
	ghost.add_child(preview)
	preview.set_physics_process(false)
	preview.remove_from_group("defence_towers")
	preview.body.collision_layer = 0
	preview.label.hide()
	Barricade._override_preview(preview, ghost_material)
	DefenceTower.box(ghost, Vector3(0.16, 0.05, 4), Vector3(0, 0.15, -2.0), ghost_material)
	for sign in [-1, 1]:
		var tip := DefenceTower.box(ghost, Vector3(0.16, 0.05, 1.2), Vector3(sign * 0.38, 0.15, -3.6), ghost_material)
		tip.rotation.y = sign * -0.75
	ghost.hide()

func _build_menu() -> void:
	build_menu = PanelContainer.new()
	add_child(build_menu)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.025,0.035,0.04,0.96)
	panel.border_color = Color(0.55,0.43,0.23)
	panel.set_border_width_all(1)
	panel.set_corner_radius_all(8)
	panel.content_margin_left = 18
	panel.content_margin_right = 18
	panel.content_margin_top = 16
	panel.content_margin_bottom = 16
	build_menu.add_theme_stylebox_override("panel",panel)
	build_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	build_menu.offset_left = -320
	build_menu.offset_right = 320
	build_menu.offset_top = -335
	build_menu.offset_bottom = 335
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	build_menu.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",12)
	scroll.add_child(list)
	var title := Label.new()
	title.text = "TOWER BUILDING · up to 20 towers per team"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(title)
	site_picker = OptionButton.new()
	site_picker.add_item("Ground placement")
	for i in 6: site_picker.add_item(Lang.t("Forest hut roof · slot %d", [i + 1]))
	site_picker.item_selected.connect(func(index: int): roof_slot = index - 1)
	list.add_child(site_picker)
	roof_repair = Button.new()
	roof_repair.text = "Repair selected roof turret · 35 R"
	roof_repair.pressed.connect(_repair_roof)
	list.add_child(roof_repair)
	roof_align = Button.new()
	roof_align.text = "Align selected roof turret"
	roof_align.pressed.connect(_align_roof)
	list.add_child(roof_align)
	for kind in DefenceTower.TYPES:
		var spec: Dictionary = DefenceTower.SPECS[kind]
		var button := Button.new()
		button.text = Lang.t("%s · %d R\n%s · %d m", [spec.name,spec.cost,spec.info,spec.range])
		button.custom_minimum_size.y = 62
		button.pressed.connect(select_kind.bind(kind))
		list.add_child(button)
		kind_buttons[kind] = button
	var cancel := Button.new()
	cancel.text = "Close [T / Esc]"
	cancel.pressed.connect(close)
	list.add_child(cancel)
	build_menu.hide()

func begin_building() -> void:
	roof_slot = -1
	if roof_access(game.player):
		# Preselect the first free socket; with the roof full, the first turret for repair / alignment.
		roof_slot = 0
		for i in 6:
			if not roof_tower(i):
				roof_slot = i
				break
	site_picker.select(roof_slot + 1)
	_refresh_build_menu()
	is_open = true
	game.player.active = false
	build_menu.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.hud.set_prompt("")

func select_kind(kind: String) -> void:
	var reason := build_requirement(game.player, kind)
	if not reason.is_empty():
		game.hud.message(reason, 3)
		return
	selected_kind = kind
	close()
	_build_preview()
	placing = true
	rotating_id = 0
	build_yaw = float(Map.BUILDINGS.waldhuette.yaw) + (PI if roof_slot >= 3 else 0.0) if roof_slot >= 0 else game.player.rotation.y
	_focus_roof_preview()
	game.hud.set_prompt("")

func _focus_roof_preview() -> void:
	if roof_slot < 0: return
	var direction: Vector3 = roof_position(roof_slot) + Vector3.UP * 0.65 - game.player.camera.global_position
	game.player.rotation.y = atan2(-direction.x, -direction.z)
	game.player.pitch = clampf(atan2(direction.y, Vector2(direction.x, direction.z).length()), -1.45, 1.45)
	game.player.head.rotation.x = game.player.pitch

func unlock_waves(kind: String, level := 1) -> int:
	return int(DefenceTower.SPECS[kind].unlock_waves) + int(DefenceTower.UPGRADE_WAVE_OFFSETS[level - 1])

func unlock_reason(kind: String, level := 1) -> String:
	if not DefenceTower.SPECS.has(kind): return "Unknown tower type."
	if level < 1 or level > 3: return "Invalid upgrade tier."
	var required := unlock_waves(kind, level)
	if game.waves.completed >= required: return ""
	if level > 1: return Lang.t("%s · Tier %d: survive wave %d first (%d/%d).", [DefenceTower.SPECS[kind].name, level, required, game.waves.completed, required])
	return Lang.t("%s: survive wave %d first (%d/%d).", [DefenceTower.SPECS[kind].name, required, game.waves.completed, required])

func build_requirement(p: Player, kind: String) -> String:
	var reason := unlock_reason(kind)
	if not reason.is_empty(): return reason
	if towers.size() >= DefenceTower.LIMIT: return "No more than 20 towers per team."
	if p.score < int(DefenceTower.SPECS[kind].cost): return Lang.t("%s: %d Rem Dollars needed.", [DefenceTower.SPECS[kind].name, DefenceTower.SPECS[kind].cost])
	return ""

func upgrade_reason(p: Player, tower: DefenceTower) -> String:
	if tower.level >= 3: return "Maximum tier reached."
	if tower.operator_peer: return "The tower is being operated right now."
	var reason := unlock_reason(tower.kind, tower.level + 1)
	if not reason.is_empty(): return reason
	if p.score < tower.upgrade_cost(): return "Not enough Rem Dollars."
	return ""

func _refresh_build_menu() -> void:
	var state := [game.waves.completed, game.player.score, towers.size(), roof_slot, roof_access(game.player), Lang.current]
	if state == _build_menu_state: return
	_build_menu_state = state
	for i in 6: site_picker.set_item_text(i + 1, Lang.t("Forest hut roof · slot %d", [i + 1]))
	for kind in kind_buttons:
		var spec: Dictionary = DefenceTower.SPECS[kind]
		var button: Button = kind_buttons[kind]
		var reason := build_requirement(game.player, kind)
		if reason.is_empty() and roof_slot >= 0:
			if not roof_access(game.player): reason = "Move to the forest hut to build on its roof."
			elif roof_tower(roof_slot): reason = "Roof slot occupied."
		var available := "From the start" if unlock_waves(kind) == 0 else Lang.t("After wave %d", [unlock_waves(kind)])
		button.text = Lang.t("%s · %d R · %s\n%s · %d m", [spec.name, spec.cost, available, spec.info, spec.range])
		button.disabled = not reason.is_empty()
		# Lang.t wraps a plain literal reason, which would stay English next to a segment otherwise.
		if button.disabled: button.text += "\n" + Lang.t(reason)
		button.tooltip_text = Lang.t("Tier 2 after wave %d · Tier 3 after wave %d", [unlock_waves(kind, 2), unlock_waves(kind, 3)])

# Fixed, deterministic sockets: host and late joiners derive the same attachment
# from the existing hut transform. No building geometry or network format changes.
# 3.1 m from the ridge puts the gun just inside the wall line: from 2.45 m the wall hid every
# zombie closer than about 2 m, exactly the ones hitting the hut (tests/roof_defences.gd).
func roof_position(slot: int) -> Vector3:
	var b: Dictionary = Map.BUILDINGS["waldhuette"]
	var local := Vector3((slot % 3 - 1) * 2.1, 0, -3.1 if slot < 3 else 3.1)
	local.y = float(b.base_h) + float(b.wall_h) + 0.14 + float(b.roof_h) * (1.0 - (absf(local.z) - 0.7) / (float(b.size.y) * 0.5)) + 0.12
	return game.hut.center + local.rotated(Vector3.UP, float(b.yaw))

func roof_index(point: Vector3) -> int:
	if not point.is_finite() or not game.hut: return -1
	for i in 6:
		if point.distance_to(roof_position(i)) < 0.05: return i
	return -1

func roof_access(p: Player) -> bool:
	return p.alive and not p.mounted_tower and game.hut != null and not game.hut.destroyed and game.hut.distance(p.global_position) <= HutHealth.REPAIR_REACH and absf(p.global_position.y - game.hut.center.y) < 8.0

func roof_tower(slot: int) -> DefenceTower:
	if slot < 0: return null
	for tower: DefenceTower in towers.values():
		if is_instance_valid(tower) and tower.global_position.distance_to(roof_position(slot)) < 1.0: return tower
	return null

func _repair_roof() -> void:
	var tower := roof_tower(roof_slot)
	if not tower: return
	if NetSession.enabled: NetSession.command("tower_repair", [tower.tower_id])
	else: game.hud.message(maintain(game.player, tower.tower_id, "repair"), 2)

func _align_roof() -> void:
	var tower := roof_tower(roof_slot)
	if not tower or not roof_access(game.player): return
	close()
	begin_rotation(tower)

func placement_error(p: Player, point: Vector3, kind := "standard") -> String:
	if not DefenceTower.SPECS.has(kind): return "Unknown tower type."
	if p.mounted_tower: return "Dismount before building."
	if not p.alive or not point.is_finite(): return "Building not possible right now."
	var requirement := build_requirement(p, kind)
	if not requirement.is_empty(): return requirement
	var socket := roof_index(point)
	if socket >= 0:
		if not roof_access(p): return "Move to the forest hut to build on its roof."
		if roof_tower(socket): return "Roof slot occupied."
		return ""
	if p.global_position.distance_to(point) > 8.0: return "Choose a building site no more than 8 m away."
	if not Map.BOUNDS.grow(-3).has_point(Vector2(point.x, point.z)): return "Outside the building area."
	var ground := Map.ground_pos(point.x, point.z)
	if absf(ground.y - point.y) > 0.25: return "The tower must stand on solid ground."
	if Map.in_building(point.x, point.z, 2.0): return "Keep your distance from the building."
	if not Map.POND.is_empty() and Vector2(point.x, point.z).distance_to(Map.POND.pos) < float(Map.POND.r) + 1.5:
		return "No tower can stand at the pond."
	for offset in [Vector2(-1.2, -1.2), Vector2(1.2, -1.2), Vector2(-1.2, 1.2), Vector2(1.2, 1.2)]:
		if absf(Map.ground_height(point.x + offset.x, point.z + offset.y) - ground.y) > 0.45:
			return "Ground too steep."
	for tower: DefenceTower in towers.values():
		if is_instance_valid(tower) and tower.global_position.distance_to(point) < 3.4: return "Too close to another tower."
	for bar: Barricade in game.barricades:
		if bar.distance_to_line(point) < 2.0: return "Keep the barricade line clear."
	if Vector2(p.global_position.x - point.x, p.global_position.z - point.z).length() < 1.8: return "Don't build where you are standing."
	var q := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.6, 3.4, 2.6)
	q.shape = shape
	q.transform.origin = ground + Vector3.UP * 2.0
	q.collision_mask = 1 | 2 | 4 | 8 | 16
	if not game.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty(): return "Building site occupied."
	var ray := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 1.7, ground + Vector3.UP, 1 | 8, [p.get_rid()])
	if not game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return "No clear view of the building site."
	return ""

func create_tower(point: Vector3, owner: int, id := 0, remote := false, kind := "standard") -> DefenceTower:
	var tower := DefenceTower.new()
	tower.kind = kind if DefenceTower.SPECS.has(kind) else "standard"
	tower.hp = tower.max_hp()
	if id == 0:
		id = next_id
		next_id += 1
	tower.tower_id = id
	tower.owner_peer = owner
	tower.game = game
	tower.replica = remote
	tower.rooftop = roof_index(point) >= 0
	tower.position = point
	game.add_child(tower)
	towers[id] = tower
	tower.tree_exiting.connect(func(): towers.erase(id))
	return tower

func purchase(p: Player, point: Vector3, yaw := 0.0, kind := "standard") -> String:
	if NetSession.is_client(): return "Only the host confirms construction."
	if not is_finite(yaw): return "Invalid orientation."
	var error := placement_error(p, point, kind)
	if not error.is_empty(): return error
	p.add_score(-int(DefenceTower.SPECS[kind].cost))
	var tower := create_tower(roof_position(roof_index(point)) if roof_index(point) >= 0 else Map.ground_pos(point.x, point.z), p.peer_id,0,false,kind)
	tower.rotation.y = wrapf(yaw, -PI, PI)
	game.progression.event("built")
	Sfx.play_at(game, "build", point, -8)
	return ""

func maintain(p: Player, id: int, action: String, at_merchant := false) -> String:
	if NetSession.is_client(): return "Only the host confirms construction."
	if not towers.has(id) or not is_instance_valid(towers[id]): return "The tower no longer exists."
	var tower: DefenceTower = towers[id]
	if tower.operator_peer: return "The tower is being operated right now."
	if action in ["upgrade", "sell"]:
		if not at_merchant or not game.progression.close_enough(p, "mechanic"): return "Upgrading and dismantling only at Mechanic."
	else:
		if not p.alive or (not tower.rooftop and p.global_position.distance_to(tower.global_position) > 6): return "Too far from the tower."
		if not reachable(p, tower): return "No clear view of the tower."
	var cost := 0
	match action:
		"upgrade":
			var reason := upgrade_reason(p, tower)
			if not reason.is_empty(): return reason
			cost = tower.upgrade_cost()
		"repair":
			if tower.hp >= tower.max_hp(): return "No repair needed."
			cost = DefenceTower.REPAIR_COST
		"sell":
			if p.peer_id != tower.owner_peer: return "Only the builder can dismantle the tower."
			p.add_score(tower.refund())
			towers.erase(id)
			tower.queue_free()
			Sfx.event(self, p.peer_id, "purchase")
			return ""
		_: return "Unknown action."
	if p.score < cost: return "Not enough Rem Dollars."
	p.add_score(-cost)
	if action == "upgrade": tower.level += 1
	tower.hp = tower.max_hp()
	tower.refresh()
	Sfx.event(self, p.peer_id, "purchase")
	return ""

func nearest(p: Player) -> DefenceTower:
	var found: DefenceTower
	var distance := 4.0
	for tower: DefenceTower in towers.values():
		if not is_instance_valid(tower) or tower.rooftop: continue
		var d := p.global_position.distance_to(tower.global_position)
		if d < distance and reachable(p, tower):
			distance = d
			found = tower
	return found

func reachable(p: Player, tower: DefenceTower) -> bool:
	if tower.rooftop: return roof_access(p)
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 1.7, tower.global_position + Vector3.UP * 1.7, 1 | 8, [p.get_rid()])
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.collider == tower.body

func open(tower: DefenceTower) -> void:
	begin_rotation(tower)

func begin_rotation(tower: DefenceTower) -> void:
	if not game.player.active or not is_instance_valid(tower): return
	if tower.operator_peer: return
	selected_kind = tower.kind
	roof_slot = roof_index(tower.global_position)
	_build_preview()
	rotating_id = tower.tower_id
	build_yaw = tower.rotation.y
	build_position = tower.global_position
	_focus_roof_preview()
	placing = true
	game.hud.set_prompt("")

func rotate_tower(p: Player, id: int, yaw: float) -> String:
	if NetSession.is_client() or not is_finite(yaw): return "Invalid orientation."
	var tower: DefenceTower = towers.get(id)
	if not is_instance_valid(tower) or not p.alive: return "Tower not found."
	if tower.operator_peer: return "The tower is being operated right now."
	if (not tower.rooftop and p.global_position.distance_to(tower.global_position) > 6) or not reachable(p, tower): return "Move closer to the tower."
	if absf(angle_difference(tower.rotation.y, yaw)) < 0.05: return "Rotate the tower with R or the mouse wheel."
	tower.rotation.y = wrapf(yaw, -PI, PI)
	tower.target = null
	tower.aim_yaw = 0
	game.progression.event("turned")
	return ""

func close() -> void:
	cancel_placement()
	is_open = false
	if build_menu: build_menu.hide()
	game.player.active = game.started and game.player.alive and not game.over and not game.hud.overlay.visible
	if game.player.active: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func mount(p: Player, id: int) -> String:
	if NetSession.is_client(): return "Only the host confirms mounting."
	var tower: DefenceTower = towers.get(id)
	if not is_instance_valid(tower) or tower.hp<=0: return "Tower not found."
	if tower.rooftop: return "Roof turrets operate automatically."
	if not p.alive or p.mounted_tower or p.global_position.distance_to(tower.global_position)>4 or not reachable(p,tower): return "Move closer to the tower."
	if tower.operator_peer: return "This tower is already occupied."
	tower.operator_peer = p.peer_id
	tower.exit_position = p.global_position
	tower.target = null
	tower.trigger = false
	tower.aiming = false
	tower.control_timeout = 0.0
	tower.aim_yaw = 0
	tower.aim_pitch = 0
	tower.gun.rotation.y = 0
	p.mounted_tower = id
	p.set_crouching(true,false)
	p.head.position.y = Player.CROUCH_EYE
	p.velocity = Vector3.ZERO
	p.global_position = tower.seat_position()
	p.rotation.y = tower.rotation.y
	p.pitch = 0
	p.recoil_offset = Vector2.ZERO
	p.head.rotation.x = 0
	tower.refresh()
	return ""

func release_tower(tower: DefenceTower) -> void:
	if not tower.operator_peer: return
	var p: Player = NetSession.world.actor(tower.operator_peer) if NetSession.enabled and NetSession.world else game.player
	if is_instance_valid(p):
		p.mounted_tower = 0
		p.camera.fov = 75.0
		if p == game.player: _tower_ads = 0.0
		p.set_crouching(false,false)
		p.head.position.y = Player.EYE
		p.velocity = Vector3.ZERO
		p.global_position = _safe_exit(p,tower)
	tower.operator_peer = 0
	tower.trigger = false
	tower.aiming = false
	tower.control_timeout = 0.0
	tower.target = null
	tower.refresh()
	input_grace = 0.25

func _safe_exit(p: Player, tower: DefenceTower) -> Vector3:
	var candidates: Array[Vector3] = [tower.exit_position]
	for radius in [2.4,3.4,4.5]:
		for i in 12:
			var at: Vector3 = tower.global_position+Vector3(sin(i*TAU/12),0,cos(i*TAU/12))*radius
			candidates.append(Map.ground_pos(at.x,at.z)+Vector3.UP*0.1)
	for at in candidates:
		if not Map.BOUNDS.has_point(Vector2(at.x,at.z)): continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = p.body_shape.shape
		query.transform.origin = at+Vector3.UP*0.95
		query.collision_mask = 1|4|8
		query.exclude = [p.get_rid()]
		if game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return at
	return tower.seat_position()+Vector3.UP*0.2

func control(p: Player, id: int, yaw: float, pitch: float, firing: bool, aiming := false) -> void:
	if not is_finite(yaw) or not is_finite(pitch) or not p.alive: return
	var tower: DefenceTower = towers.get(id)
	if not is_instance_valid(tower) or tower.operator_peer!=p.peer_id or p.mounted_tower!=id: return
	p.rotation.y = wrapf(yaw,-PI,PI)
	p.pitch = clampf(pitch,-1.1,0.85)
	p.head.rotation.x = p.pitch
	tower.aim_yaw = wrapf(p.rotation.y-tower.rotation.y,-PI,PI)
	tower.aim_pitch = p.pitch
	tower.trigger = firing
	tower.aiming = aiming
	tower.control_timeout = 0.35

func request_mount(tower: DefenceTower) -> void:
	if NetSession.enabled: NetSession.command("tower_mount",[tower.tower_id])
	else: game.hud.message(mount(game.player,tower.tower_id),2)
	input_grace = 0.25

func cancel_placement() -> void:
	placing = false
	rotating_id = 0
	input_grace = 0.2
	ghost.hide()
	hint.hide()
	if range_marker: range_marker.hide()

func preview_range() -> float:
	var tower: DefenceTower = towers.get(rotating_id)
	return tower.attack_range() if is_instance_valid(tower) else float(DefenceTower.SPECS[selected_kind].range)

func aim_readout(tower: DefenceTower) -> Dictionary:
	var camera: Camera3D = game.player.camera
	var origin := camera.global_position
	var query := PhysicsRayQueryParameters3D.create(origin, origin - camera.global_basis.z * 250, Zombie.SHOT_MASK, [game.player.get_rid(), tower.body.get_rid()])
	query.collide_with_areas = true
	var hit: Dictionary = Zombie.cast_ray(game, query)
	if hit.is_empty(): return {"distance": -1.0, "within": false, "blocked": false}
	var distance: float = tower.muzzle.global_position.distance_to(hit.position)
	var within := distance <= tower.attack_range()
	var blocked := false
	if within and tower.kind != "mortar":
		query.from = tower.muzzle.global_position
		query.to = hit.position
		var bore_hit: Dictionary = Zombie.cast_ray(game, query)
		var enemy := Zombie.from_hit(hit)
		var same_enemy := enemy != null and Zombie.from_hit(bore_hit) == enemy
		blocked = not bore_hit.is_empty() and bore_hit.position.distance_to(hit.position) > 0.7 and not same_enemy
	return {"distance": distance, "within": within, "blocked": blocked}

func _input(event: InputEvent) -> void:
	if not game or not game.started or game.over or game.player.controlling_drone: return
	if game.player.mounted_tower:
		if event.is_action_pressed("interact") and input_grace<=0:
			if NetSession.enabled: NetSession.command("tower_exit")
			else: release_tower(towers[game.player.mounted_tower])
			get_viewport().set_input_as_handled()
		return
	if placing and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		build_yaw = wrapf(build_yaw + deg_to_rad(15) * (-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1), -PI, PI)
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_T and (game.player.active or is_open):
			if placing: cancel_placement()
			elif is_open: close()
			else:
				begin_building()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_R and placing:
			build_yaw = wrapf(build_yaw + deg_to_rad(15) * (-1 if event.shift_pressed else 1), -PI, PI)
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_F and game.player.active and not placing:
			var tower := nearest(game.player)
			if tower:
				if NetSession.enabled: NetSession.command("tower_repair", [tower.tower_id])
				else: game.hud.message(maintain(game.player, tower.tower_id, "repair"), 2)
				get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_R and game.player.active and not placing:
			var tower := nearest(game.player)
			if tower:
				begin_rotation(tower)
				get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_ESCAPE and (placing or is_open):
			if placing: cancel_placement()
			else: close()
			get_viewport().set_input_as_handled()
		elif placing and event.is_action_pressed("interact"):
			if build_error.is_empty():
				if rotating_id:
					if NetSession.enabled: NetSession.command("tower_rotate", [rotating_id, build_yaw])
					else: game.hud.message(rotate_tower(game.player, rotating_id, build_yaw), 2)
				elif NetSession.enabled: NetSession.command("tower_place", [build_position, build_yaw, selected_kind])
				else: game.hud.message(purchase(game.player, build_position, build_yaw, selected_kind), 2)
				cancel_placement()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not game: return
	input_grace = maxf(0, input_grace - delta)
	var mounted: DefenceTower = towers.get(game.player.mounted_tower)
	var can_control: bool = mounted != null and game.player.active and game.player.alive and not game.over and not get_tree().paused and not game.hud.overlay.visible and input_grace <= 0
	var aiming := can_control and Input.is_action_pressed("aim")
	if mounted:
		_tower_ads = lerpf(_tower_ads, 1.0 if aiming else 0.0, 1.0 - exp(-delta * 12.0)) if can_control else 0.0
		game.player.camera.fov = lerpf(75.0, TOWER_AIM_FOV, _tower_ads)
	elif _was_mounted:
		_tower_ads = 0.0
		game.player.camera.fov = 75.0
	var showing: bool = game.started and not game.over and game.player.active and not game.hud.overlay.visible
	if range_marker:
		if not showing: range_marker.hide()
		elif placing: range_marker.display(build_position, preview_range(), build_yaw, false, not build_error.is_empty())
		elif mounted: range_marker.display(mounted.global_position, mounted.attack_range(), game.player.rotation.y, true)
		else:
			var nearby := nearest(game.player)
			if nearby: range_marker.display(nearby.global_position, nearby.attack_range(), nearby.rotation.y, false)
			else: range_marker.hide()
	if range_label: range_label.visible = showing and mounted != null
	_range_sample -= delta
	if showing and mounted and _range_sample <= 0:
		_range_sample = 0.1
		var aim := aim_readout(mounted)
		var state := "VIEW BLOCKED" if aim.blocked else "IN RANGE" if aim.within else "OUT OF RANGE" if aim.distance >= 0 else "NO TARGET"
		range_label.text = Lang.t("%s · Range %d m\n%s", [Lang.t("Target %.1f m", [aim.distance]) if aim.distance >= 0 else "Clear field of fire", roundi(mounted.attack_range()), state])
		range_label.modulate = Color(0.65, 1, 0.7) if aim.within and not aim.blocked else Color(1, 0.4, 0.25) if aim.distance >= 0 else Hud.GOLD
	if game.weapons and game.weapons.viewmodel: game.weapons.viewmodel.visible = mounted == null and not game.player.controlling_drone
	if mounted:
		game.player.head.position.y = Player.CROUCH_EYE
		game.hud.ammo_label.text = Lang.t("MANUAL · %d%%", [roundi(mounted.heat*100)])
		game.hud.weapon_label.text = Lang.t("%s · Tier %d", [mounted.spec().name,mounted.level])
	elif _was_mounted:
		game.player.head.position.y = Player.EYE
		game.weapons.update_hud()
	_was_mounted = mounted != null
	if mounted:
		if not game.player.alive or game.over:
			if not NetSession.is_client(): release_tower(mounted)
		else:
			game.player.global_position = mounted.seat_position()
			var firing := can_control and Input.is_action_pressed("fire")
			_control_send -= delta
			if _control_send<=0:
				_control_send = 0.05
				if NetSession.enabled: NetSession.command("tower_control",[mounted.tower_id,game.player.rotation.y,game.player.pitch,firing,aiming])
				else: control(game.player,mounted.tower_id,game.player.rotation.y,game.player.pitch,firing,aiming)
			game.hud.set_prompt(Lang.t("%s · [Left click] Fire · [Hold right click] Aim · [E] Dismount\n%s · Heat %d%%", [mounted.spec().name,"OVERHEATED – let it cool down" if mounted.overheated or mounted.heat>=0.99 else "Precision mode" if aiming else "Manual control",roundi(mounted.heat*100)]))
	if is_open and (not game.player.alive or game.over): close()
	if is_open:
		_refresh_build_menu()
		var selected := roof_tower(roof_slot)
		roof_repair.visible = roof_slot >= 0
		roof_align.visible = roof_slot >= 0
		roof_repair.disabled = not selected or not roof_access(game.player) or selected.hp >= selected.max_hp() or game.player.score < DefenceTower.REPAIR_COST
		roof_align.disabled = not selected or not roof_access(game.player)
	if placing:
		if not game.player.active or not game.player.alive:
			cancel_placement()
		else:
			var camera: Camera3D = game.player.camera
			var from := camera.global_position
			var ray := PhysicsRayQueryParameters3D.create(from, from - camera.global_basis.z * 10, 1)
			var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(ray)
			var point: Vector3 = hit.position if not hit.is_empty() else from - camera.global_basis.z * 6
			if rotating_id:
				var tower: DefenceTower = towers.get(rotating_id)
				if not is_instance_valid(tower):
					cancel_placement()
					return
				build_position = tower.global_position
				build_error = "" if (tower.rooftop or game.player.global_position.distance_to(build_position) <= 6) and reachable(game.player, tower) else "Move closer to the tower."
			else:
				build_position = roof_position(roof_slot) if roof_slot >= 0 else Map.ground_pos(point.x, point.z)
				build_error = placement_error(game.player, build_position, selected_kind)
			ghost.rotation.y = build_yaw
			ghost.global_position = build_position
			ghost.show()
			ghost_material.albedo_color = Color(0.2, 0.95, 0.5, 0.28) if build_error.is_empty() else Color(1, 0.16, 0.08, 0.3)
			var spec: Dictionary = DefenceTower.SPECS[selected_kind]
			var head := Lang.t("ALIGN %s · free", [spec.name]) if rotating_id else Lang.t("%s · %d R", [spec.name,spec.cost])
			var detail := Lang.t("Max. %d m · bright sector: automatic (160°)\nManual: full circle · obstacles block", [roundi(preview_range())]) if build_error.is_empty() else build_error
			if roof_slot >= 0 and build_error.is_empty():
				detail = Lang.t("Roof slot %d · automatic (160°) · max. %d m\nObstacles block the line of fire", [roof_slot + 1, roundi(preview_range())])
			hint.text = Lang.t("%s · %d / 20 towers\n%s\n[R / Mouse wheel] Rotate · Shift+R back\n[E] Confirm    [T / Esc] Cancel", [head, towers.size(), detail])
			hint.show()
	var titan: Zombie
	for z in game.zombies_root.get_children():
		if z is Zombie and Zombie.is_boss_kind(z.net_kind) and z.alive:
			if titan == null or z.global_position.distance_squared_to(game.player.global_position) < titan.global_position.distance_squared_to(game.player.global_position): titan = z
	boss_panel.visible = titan != null and game.started and not game.over and game.player.active and not game.hud.overlay.visible
	if titan:
		boss_bar.max_value = titan.max_hp
		boss_bar.value = titan.hp
		var status: String = titan.status_label() if titan is Earthworm else ("RAGE" if titan.hp < titan.max_hp * Titan.RAGE_THRESHOLD else "")
		var boss: String = str(titan.type.get("name", "THE FIELD TITAN"))
		var metres := roundi(titan.global_position.distance_to(game.player.global_position))
		boss_name.text = Lang.t("%s · %d m · %s", [boss, metres, status]) if not status.is_empty() else Lang.t("%s · %d m", [boss, metres])

func snapshot() -> Dictionary:
	var data := {}
	for id in towers:
		var tower: DefenceTower = towers[id]
		if not is_instance_valid(tower) or tower.is_queued_for_deletion(): continue
		data[id] = [tower.global_position, tower.owner_peer, tower.level, tower.hp, tower.aim_yaw, tower.aim_pitch, tower.shots, tower.last_impact, tower.heat, tower.rotation.y,tower.kind,tower.operator_peer,tower.overheated,tower.chain_points,tower.aiming]
	return data

func apply_snapshot(data: Dictionary, initial: bool) -> void:
	for id in towers.keys():
		if not data.has(id):
			towers[id].queue_free()
			towers.erase(id)
	for id in data:
		var state: Array = data[id]
		var fresh := not towers.has(id)
		if fresh: create_tower(state[0], state[1], id, true, str(state[10]) if state.size()>10 else "standard")
		var tower: DefenceTower = towers[id]
		tower.owner_peer = state[1]
		tower.level = state[2]
		tower.hp = state[3]
		tower.aim_yaw = state[4]
		tower.aim_pitch = state[5]
		tower.last_impact = state[7]
		tower.heat = state[8]
		tower.rotation.y = state[9] if state.size() > 9 else 0.0
		tower.operator_peer = int(state[11]) if state.size()>11 else 0
		tower.overheated = bool(state[12]) if state.size()>12 else false
		tower.chain_points = state[13] if state.size()>13 else PackedVector3Array()
		tower.aiming = bool(state[14]) if state.size()>14 else false
		if state[6] > tower.shots and not initial and not fresh: tower.show_shot()
		tower.shots = state[6]
		tower.refresh()
