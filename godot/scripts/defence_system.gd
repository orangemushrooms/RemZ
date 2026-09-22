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
var build_menu: PanelContainer
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
	build_menu.offset_top = -250
	build_menu.offset_bottom = 250
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation",12)
	build_menu.add_child(list)
	var title := Label.new()
	title.text = "TURMBAU · maximal 6 Türme im Team"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	list.add_child(title)
	for kind in DefenceTower.TYPES:
		var spec: Dictionary = DefenceTower.SPECS[kind]
		var button := Button.new()
		button.text = "%s · %d P\n%s · %d m" % [spec.name,spec.cost,spec.info,spec.range]
		button.custom_minimum_size.y = 70
		button.pressed.connect(select_kind.bind(kind))
		list.add_child(button)
	var cancel := Button.new()
	cancel.text = "Schließen [T / Esc]"
	cancel.pressed.connect(close)
	list.add_child(cancel)
	build_menu.hide()

func begin_building() -> void:
	is_open = true
	game.player.active = false
	build_menu.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.hud.set_prompt("")

func select_kind(kind: String) -> void:
	selected_kind = kind
	close()
	_build_preview()
	placing = true
	rotating_id = 0
	build_yaw = game.player.rotation.y
	game.hud.set_prompt("")

func placement_error(p: Player, point: Vector3, kind := "standard") -> String:
	if not DefenceTower.SPECS.has(kind): return "Unbekannter Turmtyp."
	if p.mounted_tower: return "Zum Bauen zuerst absteigen."
	if not p.alive or not point.is_finite(): return "Bauen momentan nicht möglich."
	if towers.size() >= DefenceTower.LIMIT: return "Maximal 6 Türme im Team."
	if p.score < int(DefenceTower.SPECS[kind].cost): return "%s: %d Punkte benötigt." % [DefenceTower.SPECS[kind].name,DefenceTower.SPECS[kind].cost]
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
	tower.position = point
	game.add_child(tower)
	towers[id] = tower
	tower.tree_exiting.connect(func(): towers.erase(id))
	return tower

func purchase(p: Player, point: Vector3, yaw := 0.0, kind := "standard") -> String:
	if NetSession.is_client(): return "Nur der Host bestätigt Bauten."
	if not is_finite(yaw): return "Ungültige Ausrichtung."
	var error := placement_error(p, point, kind)
	if not error.is_empty(): return error
	p.add_score(-int(DefenceTower.SPECS[kind].cost))
	var tower := create_tower(Map.ground_pos(point.x, point.z), p.peer_id,0,false,kind)
	tower.rotation.y = wrapf(yaw, -PI, PI)
	game.progression.event("built")
	Sfx.play_at(game, "build", point, -8)
	return ""

func maintain(p: Player, id: int, action: String, at_merchant := false) -> String:
	if NetSession.is_client(): return "Nur der Host bestätigt Bauten."
	if not towers.has(id) or not is_instance_valid(towers[id]): return "Turm nicht mehr vorhanden."
	var tower: DefenceTower = towers[id]
	if tower.operator_peer: return "Der Turm wird gerade bedient."
	if action in ["upgrade", "sell"]:
		if not at_merchant or not game.progression.close_enough(p, "mechanic"): return "Ausbau und Abbau nur bei Mechanic."
	else:
		if not p.alive or p.global_position.distance_to(tower.global_position) > 6: return "Zu weit vom Turm entfernt."
		if not reachable(p, tower): return "Keine freie Sicht zum Turm."
	var cost := 0
	match action:
		"upgrade":
			if tower.level >= 3: return "Maximale Stufe erreicht."
			cost = tower.upgrade_cost()
		"repair":
			if tower.hp >= tower.max_hp(): return "Keine Reparatur nötig."
			cost = DefenceTower.REPAIR_COST
		"sell":
			if p.peer_id != tower.owner_peer: return "Nur der Erbauer kann den Turm abbauen."
			p.add_score(tower.refund())
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
	if tower.operator_peer: return
	selected_kind = tower.kind
	_build_preview()
	rotating_id = tower.tower_id
	build_yaw = tower.rotation.y
	build_position = tower.global_position
	placing = true
	game.hud.set_prompt("")

func rotate_tower(p: Player, id: int, yaw: float) -> String:
	if NetSession.is_client() or not is_finite(yaw): return "Ungültige Ausrichtung."
	var tower: DefenceTower = towers.get(id)
	if not is_instance_valid(tower) or not p.alive: return "Turm nicht vorhanden."
	if tower.operator_peer: return "Der Turm wird gerade bedient."
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
	if build_menu: build_menu.hide()
	game.player.active = game.started and game.player.alive and not game.over and not game.hud.overlay.visible
	if game.player.active: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func mount(p: Player, id: int) -> String:
	if NetSession.is_client(): return "Nur der Host bestätigt den Einstieg."
	var tower: DefenceTower = towers.get(id)
	if not is_instance_valid(tower) or tower.hp<=0: return "Turm nicht vorhanden."
	if not p.alive or p.mounted_tower or p.global_position.distance_to(tower.global_position)>4 or not reachable(p,tower): return "Gehe näher an den Turm."
	if tower.operator_peer: return "Dieser Turm ist bereits besetzt."
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
	if not game or not game.started or game.over: return
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
		var state := "SICHT BLOCKIERT" if aim.blocked else "IN REICHWEITE" if aim.within else "AUSSER REICHWEITE" if aim.distance >= 0 else "KEIN ZIEL"
		range_label.text = "%s · Reichweite %d m\n%s" % ["Ziel %.1f m" % aim.distance if aim.distance >= 0 else "Freies Schussfeld", roundi(mounted.attack_range()), state]
		range_label.modulate = Color(0.65, 1, 0.7) if aim.within and not aim.blocked else Color(1, 0.4, 0.25) if aim.distance >= 0 else Hud.GOLD
	if game.weapons and game.weapons.viewmodel: game.weapons.viewmodel.visible = mounted == null
	if mounted:
		game.player.head.position.y = Player.CROUCH_EYE
		game.hud.ammo_label.text = "MANUELL · %d %%" % roundi(mounted.heat*100)
		game.hud.weapon_label.text = "%s · Stufe %d" % [mounted.spec().name,mounted.level]
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
			game.hud.set_prompt("%s · [Linksklick] Feuern · [Rechtsklick halten] Zielen · [E] Absteigen\n%s · Hitze %d %%" % [mounted.spec().name,"ÜBERHITZT – abkühlen lassen" if mounted.overheated or mounted.heat>=0.99 else "Präzisionsmodus" if aiming else "Manuelle Steuerung",roundi(mounted.heat*100)])
	if is_open and (not game.player.alive or game.over): close()
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
				build_error = placement_error(game.player, build_position, selected_kind)
			ghost.rotation.y = build_yaw
			ghost.global_position = build_position
			ghost.show()
			ghost_material.albedo_color = Color(0.2, 0.95, 0.5, 0.28) if build_error.is_empty() else Color(1, 0.16, 0.08, 0.3)
			var spec: Dictionary = DefenceTower.SPECS[selected_kind]
			hint.text = ("%s AUSRICHTEN · kostenlos" % spec.name if rotating_id else "%s · %d P" % [spec.name,spec.cost]) + " · %d / 6 Türme\n%s\n[R / Mausrad] Drehen · Shift+R zurück\n[E] Bestätigen    [T / Esc] Abbrechen" % [towers.size(), "Max. %d m · heller Sektor: Automatik (160°)\nManuell: ganzer Kreis · Hindernisse blockieren" % roundi(preview_range()) if build_error.is_empty() else build_error]
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
