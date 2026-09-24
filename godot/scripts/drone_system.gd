class_name DroneSystem
extends Node3D

var game: Node
var station: Node3D
var drones: Dictionary = {}
var refit: Dictionary = {}
var next_id := 1
var is_open := false
var selected := "scout"
var ui: CanvasLayer
var panel: PanelContainer
var buttons: Dictionary = {}
var launch_button: Button
var status: Label
var flight_hud: Label
var reticle: Label
var ended: Dictionary = {}
var _view_id := 0
var _look_yaw := 0.0
var _look_pitch := 0.0
var _send_time := 0.0
var _return_pending := false
var input_grace := 0.0

func setup(main: Node) -> void:
	game = main
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_station()
	_build_ui()

func _build_station() -> void:
	station = Node3D.new()
	station.name = "DroneControlStation"
	add_child(station)
	station.add_to_group("render_dynamic")
	var b: Dictionary = Map.BUILDINGS.waldhuette
	station.rotation.y = float(b.yaw)
	station.position = game.hut.center + Vector3(-1.1,float(b.base_h)+0.25,-float(b.size.y)*0.5+0.7).rotated(Vector3.UP,float(b.yaw))
	var steel := DefenceTower.material(Color(0.12,0.18,0.2),0.65)
	var trim := DefenceTower.material(Color(0.42,0.51,0.5),0.7)
	DefenceTower.box(station,Vector3(1.9,0.12,0.8),Vector3(0,0.8,0),steel)
	for x in [-0.78,0.78]: DefenceTower.box(station,Vector3(0.12,0.8,0.65),Vector3(x,0.4,0),trim)
	for i in 3:
		var x := (i-1)*0.58
		DefenceTower.box(station,Vector3(0.55,0.42,0.08),Vector3(x,1.2,-0.22),steel)
		var screen := ShaderMaterial.new()
		screen.shader = preload("res://shaders/drone_console.gdshader")
		screen.set_shader_parameter("ink",Color(0.08,0.7,0.65) if i == 0 else Color(0.2,0.5,0.9) if i == 1 else Color(0.9,0.5,0.1))
		DefenceTower.box(station,Vector3(0.49,0.35,0.012),Vector3(x,1.2,-0.171),screen)
		for row in 3:
			DefenceTower.box(station,Vector3(0.33-row*0.05,0.013,0.008),Vector3(x,1.27-row*0.07,-0.161),trim)
	DefenceTower.box(station,Vector3(0.72,0.04,0.24),Vector3(0,0.89,0.16),trim)
	for row in 4:
		for col in 12:
			DefenceTower.box(station,Vector3(0.043,0.012,0.036),Vector3(-0.29+col*0.052,0.918,0.085+row*0.043),steel)
	DefenceTower.box(station,Vector3(0.34,0.55,0.55),Vector3(0.53,0.39,-0.05),steel)
	for i in 6: DefenceTower.box(station,Vector3(0.26,0.014,0.02),Vector3(0.53,0.26+i*0.055,0.235),trim)
	for x in [-0.59,0.59]:
		DefenceTower.cylinder(station,0.035,0.18,Vector3(x,0.95,0.15),steel)
	var label := Label3D.new()
	label.text = "DRONE CONTROL"
	label.font_size = 30
	label.pixel_size = 0.0045
	label.position = Vector3(0,1.65,-0.1)
	station.add_child(label)
	var light := OmniLight3D.new()
	light.light_color = Color(0.2,0.7,0.85)
	light.light_energy = 0.45
	light.omni_range = 2.5
	light.position = Vector3(0,1.3,0.1)
	station.add_child(light)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.9,0.8,0.8)
	shape.shape = box
	shape.position.y = 0.4
	body.add_child(shape)
	station.add_child(body)
	body.add_to_group("navsource")

func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 12
	add_child(ui)
	panel = PanelContainer.new()
	ui.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -300
	panel.offset_right = 300
	panel.offset_top = -270
	panel.offset_bottom = 270
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.018,0.04,0.055,0.97)
	style.border_color = Color(0.1,0.68,0.73)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel",style)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation",14)
	panel.add_child(list)
	var title := Label.new()
	title.text = "DRONE CONTROL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size",26)
	list.add_child(title)
	for kind in AttackDrone.SPECS:
		var button := Button.new()
		button.custom_minimum_size.y = 72
		button.pressed.connect(func(): selected = kind; _refresh_menu())
		list.add_child(button)
		buttons[kind] = button
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(550,60)
	list.add_child(status)
	launch_button = Button.new()
	launch_button.text = "Ready to fly"
	launch_button.custom_minimum_size.y = 50
	launch_button.pressed.connect(request_launch)
	list.add_child(launch_button)
	var cancel := Button.new()
	cancel.text = "Close [Esc]"
	cancel.pressed.connect(close)
	list.add_child(cancel)
	panel.hide()
	flight_hud = Label.new()
	ui.add_child(flight_hud)
	flight_hud.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	flight_hud.offset_left = -420
	flight_hud.offset_right = 420
	flight_hud.offset_top = 115
	flight_hud.offset_bottom = 270
	flight_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	flight_hud.add_theme_font_size_override("font_size",20)
	flight_hud.add_theme_constant_override("outline_size",5)
	flight_hud.add_theme_color_override("font_color",Color(0.45,0.95,1))
	flight_hud.hide()
	reticle = Label.new()
	ui.add_child(reticle)
	reticle.text = "+"
	reticle.add_theme_font_size_override("font_size",26)
	reticle.add_theme_color_override("font_color",Color(0.4,1,0.9))
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.offset_left = -16
	reticle.offset_right = 16
	reticle.offset_top = -20
	reticle.offset_bottom = 20
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	reticle.hide()

func actor(peer: int) -> Player:
	return NetSession.world.actor(peer) if NetSession.enabled and NetSession.world else (game.player if peer == game.player.peer_id else null)

func nearby(p: Player) -> bool:
	if not p.alive or p.controlling_drone or p.mounted_tower or game.over: return false
	if absf(p.global_position.y-station.global_position.y) > 0.8: return false
	var target := station.to_global(Vector3(0,1.3,0.15))
	if p.camera.global_position.distance_to(target) > 2.4: return false
	var ray := PhysicsRayQueryParameters3D.create(p.camera.global_position,target,1|8,[p.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

func available_wave() -> int:
	return maxi(game.waves.wave,game.waves.completed)

func requirement(p: Player, kind: String) -> String:
	if not AttackDrone.SPECS.has(kind): return "Unknown drone."
	if not game.started or game.over or not nearby(p): return "Use the drone station upstairs in the forest hut."
	if not game.forest_keys.has_key("waldhuette"): return "The forest hut key is required."
	if available_wave() < int(AttackDrone.SPECS[kind].wave): return Lang.t("Available from wave %d.",[AttackDrone.SPECS[kind].wave])
	for drone: AttackDrone in drones.values():
		if drone.kind == kind: return "This drone is already in flight."
	if float(refit.get(kind,0)) > 0: return Lang.t("Refitting drone: %d s",[ceili(refit[kind])])
	return ""

func open() -> void:
	if not nearby(game.player): return
	is_open = true
	game.player.active = false
	game.hud.set_prompt("")
	panel.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh_menu()

func close() -> void:
	is_open = false
	panel.hide()
	game.player.active = game.started and game.player.alive and not game.over and not game.hud.overlay.visible
	if game.player.active: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	input_grace = 0.25

func _refresh_menu() -> void:
	for kind in buttons:
		var spec: Dictionary = AttackDrone.SPECS[kind]
		var error := requirement(game.player,kind)
		buttons[kind].text = Lang.t("%s · Wave %d · %d HP\n%d damage · %.1f shots/s",[spec.name,spec.wave,spec.hp,spec.damage,1.0/float(spec.rate)])
		buttons[kind].modulate = Color(0.35,0.95,1) if selected == kind else Color.WHITE
		buttons[kind].disabled = not error.is_empty()
		buttons[kind].tooltip_text = error
	var reason := requirement(game.player,selected)
	status.text = reason if not reason.is_empty() else "WASD: fly · Mouse: aim · Space / Ctrl: climb / descend\nLeft click: fire · R / Esc: return · Your body stays at the station."
	launch_button.disabled = not reason.is_empty()

func request_launch() -> void:
	if NetSession.enabled:
		NetSession.command("drone_launch",[selected])
	else:
		var error := launch(game.player,selected)
		if not error.is_empty(): game.hud.message(error,3)

func spawn_position(kind: String) -> Vector3:
	var b: Dictionary = Map.BUILDINGS.waldhuette
	var shape := SphereShape3D.new()
	shape.radius = float(AttackDrone.SPECS[kind].size)*0.45
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collision_mask = 1|2|4|8
	for offset in [Vector3(0,8,-5.8),Vector3(0,10,5.8),Vector3(5.5,10,0),Vector3(-5.5,12,0)]:
		var at: Vector3 = game.hut.center + offset.rotated(Vector3.UP,float(b.yaw))
		q.transform.origin = at
		if get_world_3d().direct_space_state.intersect_shape(q,1).is_empty(): return at
	return Vector3(INF,INF,INF)

func create_drone(id: int, kind: String, peer: int, at: Vector3, remote := false, motor_elapsed := 0.0) -> AttackDrone:
	var drone := AttackDrone.new()
	drone.drone_id = id
	drone.kind = kind
	drone.owner_peer = peer
	drone.hp = float(AttackDrone.SPECS[kind].hp)
	drone.replica = remote
	drone.motor_elapsed = motor_elapsed
	drone.game = game
	drone.system = self
	drone.position = at
	drone.target_position = at
	add_child(drone)
	drones[id] = drone
	return drone

func launch(p: Player, kind: String) -> String:
	if NetSession.is_client(): return "Only the host launches drones."
	var reason := requirement(p,kind)
	if not reason.is_empty(): return reason
	var at := spawn_position(kind)
	if not at.is_finite(): return "Drone launch area blocked."
	var drone := create_drone(next_id,kind,p.peer_id,at)
	next_id += 1
	drone.yaw = float(Map.BUILDINGS.waldhuette.yaw)
	drone.update_view()
	p.controlling_drone = drone.drone_id
	p.velocity = Vector3.ZERO
	if p == game.player:
		close()
		_sync_view()
	return ""

func control(p: Player, id: int, move: Vector3, yaw: float, pitch: float, fire: bool) -> void:
	if NetSession.is_client() or not p.alive or game.over: return
	if not move.is_finite() or not is_finite(yaw) or not is_finite(pitch): return
	var drone: AttackDrone = drones.get(id)
	if not drone or p.controlling_drone != id or drone.owner_peer != p.peer_id: return
	drone.input_move = move.limit_length(1)
	drone.yaw = wrapf(yaw,-PI,PI)
	drone.pitch = clampf(pitch,-1.3,1.0)
	drone.firing = fire
	drone.input_timeout = 0.35

func recall(p: Player) -> void:
	if NetSession.is_client(): return
	var drone: AttackDrone = drones.get(p.controlling_drone)
	if drone and drone.owner_peer == p.peer_id: finish(drone.drone_id,false)

func finish(id: int, destroyed: bool) -> void:
	var drone: AttackDrone = drones.get(id)
	if not drone: return
	var p := actor(drone.owner_peer)
	if p and p.controlling_drone == id: p.controlling_drone = 0
	refit[drone.kind] = 30.0 if destroyed else 10.0
	ended[id] = [drone.global_position,destroyed]
	while ended.size() > 16: ended.erase(ended.keys()[0])
	drones.erase(id)
	drone.queue_free()
	if p == game.player:
		_sync_view()
		game.hud.message("Drone destroyed. Refitting for 30 seconds." if destroyed else "Drone recalled. Refitting for 10 seconds.",3)

func shutdown() -> void:
	if is_open: close()
	for id in drones.keys(): finish(id,false)
	_sync_view()

func _sync_view() -> void:
	var id: int = game.player.controlling_drone
	var drone: AttackDrone = drones.get(id)
	if id and not drone: return # The player and entity may arrive in adjacent snapshots.
	if _view_id == id: return
	_view_id = id
	_return_pending = false
	if drone:
		if is_open: close()
		game.fireworks.cancel()
		_look_yaw = drone.yaw
		_look_pitch = drone.pitch
		drone.camera.make_current()
		game.weapons.viewmodel.hide()
		game.hud.set_prompt("")
		Sfx.stop_fire_loop(game.weapons)
	else:
		game.player.camera.make_current()
		game.weapons.viewmodel.visible = game.player.alive and not game.over
		flight_hud.hide()
		reticle.hide()
		game.hud.ammo_label.get_parent().show()
		input_grace = 0.3
		game.defences.input_grace = 0.3

func _input(event: InputEvent) -> void:
	if not game or not game.started or game.over: return
	if game.hud.overlay.visible or get_tree().paused: return
	if is_open:
		if event.is_action_pressed("pause"):
			close()
			get_viewport().set_input_as_handled()
		return
	if not game.player.controlling_drone: return
	if event is InputEventKey and event.physical_keycode in [KEY_M,KEY_F11,KEY_TAB]: return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_yaw = wrapf(_look_yaw-event.screen_relative.x*Player.SENS*game.player.mouse_sensitivity,-PI,PI)
		_look_pitch = clampf(_look_pitch-event.screen_relative.y*Player.SENS*game.player.mouse_sensitivity,-1.3,1.0)
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode in [KEY_R,KEY_ESCAPE]:
		_return_pending = true
		if NetSession.enabled: NetSession.command("drone_recall")
		else: recall(game.player)
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not game: return
	input_grace = maxf(0,input_grace-delta)
	if not NetSession.is_client() and not get_tree().paused:
		for kind in refit: refit[kind] = maxf(0,refit[kind]-delta)
		for id in drones.keys():
			var p := actor(drones[id].owner_peer)
			if not p or not p.alive or game.over: finish(id,false)
	if is_open:
		if not nearby(game.player): close()
		else: _refresh_menu()
	_sync_view()
	var drone: AttackDrone = drones.get(game.player.controlling_drone)
	if not drone: return
	var enabled: bool = game.player.alive and game.player.active and not game.over and not get_tree().paused and not game.hud.overlay.visible and not _return_pending
	var axis := Input.get_vector("move_left","move_right","move_forward","move_back") if enabled else Vector2.ZERO
	var up := float(Input.is_physical_key_pressed(KEY_SPACE))-float(Input.is_physical_key_pressed(KEY_CTRL)) if enabled else 0.0
	var move := Vector3(axis.x,up,axis.y).limit_length(1)
	var fire := enabled and Input.is_action_pressed("fire") and input_grace <= 0
	_send_time -= delta
	if _send_time <= 0:
		_send_time = 0.05
		if NetSession.enabled: NetSession.command("drone_control",[drone.drone_id,move,_look_yaw,_look_pitch,fire])
		else: control(game.player,drone.drone_id,move,_look_yaw,_look_pitch,fire)
	flight_hud.visible = enabled
	reticle.visible = enabled
	game.hud.ammo_label.get_parent().hide()
	flight_hud.text = Lang.t("%s · HULL %d / %d · HEAT %d%%\nAltitude %.1f m · %s\nWASD fly · Mouse aim · Space / Ctrl up / down · LMB fire · R / Esc return",[drone.spec().name,ceili(drone.hp),int(drone.spec().hp),roundi(drone.heat*100),drone.global_position.y-Map.ground_height(drone.global_position.x,drone.global_position.z),"COOLING" if drone.overheated else "LIVE FEED"])
	game.weapons.viewmodel.hide()

func snapshot() -> Dictionary:
	var live := {}
	for id in drones:
		var d: AttackDrone = drones[id]
		live[id] = [d.kind,d.owner_peer,d.global_position,d.yaw,d.pitch,d.hp,d.heat,d.overheated,d.shots,d.shot_origin,d.impact,d.velocity,d.motor_elapsed]
	return {"live": live,"refit":refit.duplicate(),"ended":ended.duplicate(true)}

func apply_snapshot(data: Dictionary, initial: bool) -> void:
	var live: Dictionary = data.get("live",{})
	refit = data.get("refit",{}).duplicate()
	ended = data.get("ended",{}).duplicate(true)
	for id in drones.keys():
		if not live.has(id):
			if not initial and ended.has(id) and ended[id][1]:
				AttackDrone.Effects.explosion(game,ended[id][0])
				Sfx.play_at(game,"barricade_break",ended[id][0],-8)
			drones[id].queue_free()
			drones.erase(id)
	for id in live:
		var s: Array = live[id]
		var fresh := not drones.has(id)
		if fresh:
			var elapsed := float(s[12]) if s.size() > 12 else AttackDrone.MOTOR_LOOP_START
			if initial: elapsed = maxf(AttackDrone.MOTOR_LOOP_START,elapsed)
			create_drone(id,s[0],s[1],s[2],true,elapsed)
		var d: AttackDrone = drones[id]
		d.target_position = s[2]
		d.target_yaw = s[3]
		d.target_pitch = s[4]
		d.hp = s[5]
		d.heat = s[6]
		d.overheated = s[7]
		d.shot_origin = s[9]
		d.impact = s[10]
		d.velocity = s[11]
		if fresh or initial:
			d.yaw = s[3]
			d.pitch = s[4]
			d.global_position = s[2]
			d.update_view()
		elif s[8] > d.shots: d.show_shot()
		d.shots = s[8]
