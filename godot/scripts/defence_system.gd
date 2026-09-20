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

func setup(main: Node) -> void:
	game = main
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	hint = Label.new()
	hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	hint.position = Vector2(-400, -200)
	hint.size = Vector2(800, 100)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 21)
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
	ghost = Node3D.new()
	game.add_child(ghost)
	ghost_material = Barricade._marker_material(Color(0.2, 1, 0.55), 0.32)
	var preview := DefenceTower.new()
	preview.game = game
	preview.replica = true
	ghost.add_child(preview)
	preview.set_physics_process(false)
	preview.remove_from_group("defence_towers")
	preview.body.collision_layer = 0
	preview.label.hide()
	Barricade._override_preview(preview, ghost_material)
	var sector := ImmediateMesh.new()
	sector.surface_begin(Mesh.PRIMITIVE_LINES)
	var radius: float = DefenceTower.RANGE[0]
	for i in 40:
		for step in [i, i + 1]:
			var angle := lerpf(-DefenceTower.HALF_ARC, DefenceTower.HALF_ARC, step / 40.0)
			sector.surface_add_vertex(Vector3(sin(angle) * radius, 0.15, -cos(angle) * radius))
	for angle in [-DefenceTower.HALF_ARC, DefenceTower.HALF_ARC]:
		sector.surface_add_vertex(Vector3(0, 0.15, 0))
		sector.surface_add_vertex(Vector3(sin(angle) * radius, 0.15, -cos(angle) * radius))
	sector.surface_end()
	DefenceTower.piece(ghost, sector, Vector3.ZERO, ghost_material)
	DefenceTower.box(ghost, Vector3(0.16, 0.05, 4), Vector3(0, 0.15, -2.0), ghost_material)
	for sign in [-1, 1]:
		var tip := DefenceTower.box(ghost, Vector3(0.16, 0.05, 1.2), Vector3(sign * 0.38, 0.15, -3.6), ghost_material)
		tip.rotation.y = sign * -0.75
	ghost.hide()

func placement_error(p: Player, point: Vector3) -> String:
	if not p.alive or not point.is_finite(): return "Bauen momentan nicht möglich."
	if towers.size() >= DefenceTower.LIMIT: return "Maximal 6 Türme im Team."
	if p.score < DefenceTower.COST: return "Geschützturm: 120 Punkte benötigt."
	if p.global_position.distance_to(point) > 8.0: return "Bauplatz höchstens 8 m entfernt wählen."
	if not Map.BOUNDS.grow(-3).has_point(Vector2(point.x, point.z)): return "Ausserhalb des Baugebiets."
	var ground := Map.ground_pos(point.x, point.z)
	if absf(ground.y - point.y) > 0.25: return "Turm muss auf festem Boden stehen."
	if Map.in_building(point.x, point.z, 2.0): return "Abstand zum Gebäude halten."
	if not Map.POND.is_empty() and Vector2(point.x, point.z).distance_to(Map.POND.pos) < float(Map.POND.r) + 1.5:
		return "Am Teich kann kein Turm stehen."
	for offset in [Vector2(-1.2, -1.2), Vector2(1.2, -1.2), Vector2(-1.2, 1.2), Vector2(1.2, 1.2)]:
		if absf(Map.ground_height(point.x + offset.x, point.z + offset.y) - ground.y) > 0.45:
			return "Boden zu steil."
	for tower: DefenceTower in towers.values():
		if is_instance_valid(tower) and tower.global_position.distance_to(point) < 3.4: return "Zu nah an einem anderen Turm."
	for bar: Barricade in game.barricades:
		if bar.distance_to_line(point) < 2.0: return "Barrikadenlinie freihalten."
	if Vector2(p.global_position.x - point.x, p.global_position.z - point.z).length() < 1.8: return "Nicht auf deinem Standort bauen."
	var q := PhysicsShapeQueryParameters3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(2.6, 3.4, 2.6)
	q.shape = shape
	q.transform.origin = ground + Vector3.UP * 2.0
	q.collision_mask = 1 | 2 | 4 | 8 | 16
	if not game.get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty(): return "Bauplatz belegt."
	var ray := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 1.7, ground + Vector3.UP, 1 | 8, [p.get_rid()])
	if not game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return "Keine freie Sicht zum Bauplatz."
	return ""

func create_tower(point: Vector3, owner: int, id := 0, remote := false) -> DefenceTower:
	var tower := DefenceTower.new()
	if id == 0:
		id = next_id
		next_id += 1
	tower.tower_id = id
	tower.owner_peer = owner
	tower.game = game
	tower.replica = remote
	tower.position = point
	game.add_child(tower)
	towers[id] = tower
	tower.tree_exiting.connect(func(): towers.erase(id))
	return tower

func purchase(p: Player, point: Vector3, yaw := 0.0) -> String:
	if NetSession.is_client(): return "Nur der Host bestätigt Bauten."
	if not is_finite(yaw): return "Ungültige Ausrichtung."
	var error := placement_error(p, point)
	if not error.is_empty(): return error
	p.add_score(-DefenceTower.COST)
	var tower := create_tower(Map.ground_pos(point.x, point.z), p.peer_id)
	tower.rotation.y = wrapf(yaw, -PI, PI)
	game.progression.event("built")
	Sfx.play_at(game, "build", point, -8)
	return ""

func maintain(p: Player, id: int, action: String, at_merchant := false) -> String:
	if NetSession.is_client(): return "Nur der Host bestätigt Bauten."
	if not towers.has(id) or not is_instance_valid(towers[id]): return "Turm nicht mehr vorhanden."
	var tower: DefenceTower = towers[id]
	if action in ["upgrade", "sell"]:
		if not at_merchant or not game.progression.close_enough(p, "mechanic"): return "Ausbau und Abbau nur bei Mechanic."
	else:
		if not p.alive or p.global_position.distance_to(tower.global_position) > 6: return "Zu weit vom Turm entfernt."
		if not reachable(p, tower): return "Keine freie Sicht zum Turm."
	var cost := 0
	match action:
		"upgrade":
			if tower.level >= 3: return "Maximale Stufe erreicht."
			cost = DefenceTower.UPGRADES[tower.level - 1]
		"repair":
			if tower.hp >= tower.max_hp(): return "Keine Reparatur nötig."
			cost = DefenceTower.REPAIR_COST
		"sell":
			if p.peer_id != tower.owner_peer: return "Nur der Erbauer kann den Turm abbauen."
			p.add_score(40)
			towers.erase(id)
			tower.queue_free()
			Sfx.event(self, p.peer_id, "purchase")
			return ""
		_: return "Unbekannte Aktion."
	if p.score < cost: return "Zu wenig Punkte."
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
		if not is_instance_valid(tower): continue
		var d := p.global_position.distance_to(tower.global_position)
		if d < distance and reachable(p, tower):
			distance = d
			found = tower
	return found

func reachable(p: Player, tower: DefenceTower) -> bool:
	var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP * 1.7, tower.global_position + Vector3.UP * 1.7, 1 | 8, [p.get_rid()])
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.collider == tower.body

func open(tower: DefenceTower) -> void:
	begin_rotation(tower)

func begin_rotation(tower: DefenceTower) -> void:
	if not game.player.active or not is_instance_valid(tower): return
	rotating_id = tower.tower_id
	build_yaw = tower.rotation.y
	build_position = tower.global_position
	placing = true
	game.hud.set_prompt("")

func rotate_tower(p: Player, id: int, yaw: float) -> String:
	if NetSession.is_client() or not is_finite(yaw): return "Ungültige Ausrichtung."
	var tower: DefenceTower = towers.get(id)
	if not is_instance_valid(tower) or not p.alive: return "Turm nicht vorhanden."
	if p.global_position.distance_to(tower.global_position) > 6 or not reachable(p, tower): return "Gehe näher an den Turm."
	if absf(angle_difference(tower.rotation.y, yaw)) < 0.05: return "Drehe den Turm mit R oder dem Mausrad."
	tower.rotation.y = wrapf(yaw, -PI, PI)
	tower.target = null
	tower.aim_yaw = 0
	game.progression.event("turned")
	return ""

func close() -> void:
	cancel_placement()
	is_open = false

func cancel_placement() -> void:
	placing = false
	rotating_id = 0
	input_grace = 0.2
	ghost.hide()
	hint.hide()

func _input(event: InputEvent) -> void:
	if not game or not game.started or game.over: return
	if placing and event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		build_yaw = wrapf(build_yaw + deg_to_rad(15) * (-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1), -PI, PI)
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_T and game.player.active:
			if placing: cancel_placement()
			else:
				placing = true
				rotating_id = 0
				build_yaw = game.player.rotation.y
				game.hud.set_prompt("")
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
		elif event.physical_keycode == KEY_ESCAPE and (placing or is_open):
			if placing: cancel_placement()
			else: close()
			get_viewport().set_input_as_handled()
		elif placing and event.is_action_pressed("interact"):
			if build_error.is_empty():
				if rotating_id:
					if NetSession.enabled: NetSession.command("tower_rotate", [rotating_id, build_yaw])
					else: game.hud.message(rotate_tower(game.player, rotating_id, build_yaw), 2)
				elif NetSession.enabled: NetSession.command("tower_place", [build_position, build_yaw])
				else: game.hud.message(purchase(game.player, build_position, build_yaw), 2)
				cancel_placement()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not game: return
	input_grace = maxf(0, input_grace - delta)
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
				build_error = "" if game.player.global_position.distance_to(build_position) <= 6 and reachable(game.player, tower) else "Gehe näher an den Turm."
			else:
				build_position = Map.ground_pos(point.x, point.z)
				build_error = placement_error(game.player, build_position)
			ghost.rotation.y = build_yaw
			ghost.global_position = build_position
			ghost.show()
			ghost_material.albedo_color = Color(0.2, 0.95, 0.5, 0.28) if build_error.is_empty() else Color(1, 0.16, 0.08, 0.3)
			hint.text = ("WÄCHTER AUSRICHTEN · kostenlos" if rotating_id else "WÄCHTER · 120 P") + " · %d / 6 Türme\n%s\n[R / Mausrad] Drehen · Shift+R zurück\n[E] Bestätigen    [T / Esc] Abbrechen" % [towers.size(), "160° Feuersektor · 26 m Reichweite" if build_error.is_empty() else build_error]
			hint.show()
	var titan: Zombie
	for z in game.zombies_root.get_children():
		if z is Zombie and Zombie.is_titan_kind(z.net_kind) and z.alive:
			if titan == null or z.global_position.distance_squared_to(game.player.global_position) < titan.global_position.distance_squared_to(game.player.global_position): titan = z
	boss_panel.visible = titan != null and game.started and not game.over and game.player.active and not game.hud.overlay.visible
	if titan:
		boss_bar.max_value = titan.max_hp
		boss_bar.value = titan.hp
		boss_name.text = str(titan.type.get("name", "DER FELDTITAN")) + " · %d m%s" % [roundi(titan.global_position.distance_to(game.player.global_position)), " · RASEREI" if titan.hp < titan.max_hp * Titan.RAGE_THRESHOLD else ""]

func snapshot() -> Dictionary:
	var data := {}
	for id in towers:
		var tower: DefenceTower = towers[id]
		if not is_instance_valid(tower) or tower.is_queued_for_deletion(): continue
		data[id] = [tower.global_position, tower.owner_peer, tower.level, tower.hp, tower.aim_yaw, tower.aim_pitch, tower.shots, tower.last_impact, tower.heat, tower.rotation.y]
	return data

func apply_snapshot(data: Dictionary, initial: bool) -> void:
	for id in towers.keys():
		if not data.has(id):
			towers[id].queue_free()
			towers.erase(id)
	for id in data:
		var state: Array = data[id]
		var fresh := not towers.has(id)
		if fresh: create_tower(state[0], state[1], id, true)
		var tower: DefenceTower = towers[id]
		tower.owner_peer = state[1]
		tower.level = state[2]
		tower.hp = state[3]
		tower.aim_yaw = state[4]
		tower.aim_pitch = state[5]
		tower.last_impact = state[7]
		tower.heat = state[8]
		tower.rotation.y = state[9] if state.size() > 9 else 0.0
		if state[6] > tower.shots and not initial and not fresh: tower.show_shot()
		tower.shots = state[6]
		tower.refresh()
