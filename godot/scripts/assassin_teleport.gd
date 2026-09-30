class_name AssassinTeleport
extends CanvasLayer
## Host-authoritative relocation. The selected mode is frozen with the class loadout.
const FORWARD_RANGE := 8.0
const MAP_RANGE := 40.0
const FORWARD_COOLDOWN := 12.0
const MAP_COOLDOWN := 30.0
const TargetMap = preload("res://scripts/teleport_map.gd")
var game: Node
var is_open := false
var panel: Control
var map_view: Control
var status: Label
var flash: ColorRect
var _pending := false
var _point := Vector2.ZERO
var _hover_time := 0.0
var _saved_mouse := Input.MOUSE_MODE_CAPTURED

func setup(main: Node) -> void:
	game = main
	layer = 24
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = Control.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(panel)
	var shade := ColorRect.new()
	shade.color = Color(0.01, 0.015, 0.025, 0.85)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_child(center)
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", TowerPlanner._style(Color("101719"), Color("b6a0d8"), 20))
	center.add_child(card)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	card.add_child(column)
	column.add_child(TowerPlanner._label("TELEPORT / MAP", 24, Color("b6a0d8")))
	column.add_child(TowerPlanner._label("Choose a safe point within 40 metres. The round keeps running.", 15))
	map_view = TargetMap.new()
	map_view.controller = self
	column.add_child(map_view)
	status = TowerPlanner._label("", 15)
	column.add_child(status)
	var cancel := TowerPlanner._button("Cancel (Esc / right click)")
	cancel.button_down.connect(close)
	column.add_child(cancel)
	panel.hide()
	flash = ColorRect.new()
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	flash.color = Color(0.58, 0.38, 0.85, 0.0)
	add_child(flash)

static func mode_for(actor: Player) -> String:
	var build: Dictionary = actor.class_combat.build
	return str(build.get("teleport", "")) if build.id == "assassin" and int(build.level) >= 15 else ""

func unavailable(actor: Player) -> String:
	if mode_for(actor).is_empty(): return "Choose a Teleport mode in Class skills at Assassin level 15."
	if not game.started or game.over or not actor.alive or actor.downed or actor.spectating or actor.mounted_tower or actor.controlling_drone:
		return "Teleport is unavailable right now."
	if not actor.active and not (actor == game.player and is_open): return "Teleport is unavailable right now."
	if game.intro and game.intro.active: return "Teleport is unavailable during the intro."
	if actor.teleport_cooldown > 0.0: return "Teleport is recharging."
	return ""

func _input(event: InputEvent) -> void:
	if not game: return
	if is_open:
		if event is InputEventMouseMotion: return
		if event.is_action_pressed("pause") or event.is_action_pressed("class_ability") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT):
			close()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			var local: Vector2 = map_view.get_global_transform_with_canvas().affine_inverse() * event.position
			if Rect2(Vector2.ZERO, map_view.size).has_point(local):
				if event.pressed:
					_point = map_view.world_point(local)
					_pending = true
			else:
				return # Let the cancel button receive its GUI event.
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("class_ability") and not event.is_echo() and game.player.active and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		get_viewport().set_input_as_handled()
		var error := unavailable(game.player)
		if not error.is_empty(): game.hud.message(error, 2.5); return
		if mode_for(game.player) == "map": open()
		else: _point = Vector2.ZERO; _pending = true

func open() -> void:
	if is_open or mode_for(game.player) != "map" or not unavailable(game.player).is_empty(): return
	is_open = true
	_saved_mouse = Input.mouse_mode
	game.player.active = false
	game.player.velocity = Vector3.ZERO
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var edge := clampf(get_viewport().get_visible_rect().size.y - 230.0, 260.0, 520.0)
	map_view.custom_minimum_size = Vector2.ONE * edge
	map_view.origin = Vector2(game.player.global_position.x, game.player.global_position.z)
	map_view.valid = false
	status.text = Lang.t("Left click: teleport / Esc: cancel")
	panel.show()
	map_view.queue_redraw()

func close() -> void:
	if not is_open: return
	is_open = false
	_pending = false
	panel.hide()
	if game.started and not game.over and game.player.alive and not game.hud.overlay.visible and not get_tree().paused:
		game.player.active = true
		Input.mouse_mode = _saved_mouse

func _physics_process(delta: float) -> void:
	if not game: return
	if is_open and (game.over or not game.player.alive or game.player.downed or game.hud.overlay.visible or get_tree().paused): close()
	if get_tree().paused or not game.started or game.over: return
	var actors: Array = NetSession.world.actors.values() if NetSession.is_host() and NetSession.world else [game.player]
	for actor: Player in actors: actor.teleport_cooldown = maxf(0.0, actor.teleport_cooldown - delta)
	if is_open:
		_hover_time -= delta
		if _hover_time <= 0.0:
			_hover_time = 0.05
			var local := map_view.get_local_mouse_position()
			map_view.hover = map_view.world_point(local)
			var result := destination(game.player, map_view.hover)
			map_view.valid = result.has("point") and Rect2(Vector2.ZERO, map_view.size).has_point(local)
			status.text = Lang.t("Left click: teleport / Esc: cancel") if map_view.valid else Lang.t(str(result.get("error", "Choose a point on the map.")))
			map_view.queue_redraw()
	if _pending:
		_pending = false
		if is_open:
			var result := destination(game.player, _point)
			if not result.has("point"):
				status.text = Lang.t(str(result.error))
				return
			close()
			Input.action_release("fire")
		if NetSession.enabled:
			NetSession.command("teleport", [_point, game.player.rotation.y, game.player.pitch])
		else:
			var error := perform(game.player, _point)
			if not error.is_empty(): game.hud.message(error, 2.5)

func destination(actor: Player, requested: Vector2) -> Dictionary:
	if not requested.is_finite(): return {"error": "Choose a safe point on the map."}
	var mode := mode_for(actor)
	if mode.is_empty(): return {"error": "Choose a Teleport mode in Class skills at Assassin level 15."}
	var origin := Vector2(actor.global_position.x, actor.global_position.z)
	if mode == "map":
		if origin.distance_to(requested) > MAP_RANGE: return {"error": "That point is beyond the 40 metre range."}
		return safe_point(actor, requested, MAP_RANGE)
	var forward := -actor.global_basis.z
	var direction := Vector2(forward.x, forward.z).normalized()
	# Stop in front of walls and locked doors, then find the furthest free landing.
	var ray := PhysicsRayQueryParameters3D.create(actor.global_position + Vector3.UP, actor.global_position + Vector3.UP + Vector3(direction.x, 0, direction.y) * FORWARD_RANGE, 1 | 8)
	ray.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(ray)
	var reach := FORWARD_RANGE
	if not hit.is_empty(): reach = minf(reach, actor.global_position.distance_to(hit.position - Vector3.UP) - 0.65)
	while reach >= 2.0:
		var result := safe_point(actor, origin + direction * reach, FORWARD_RANGE)
		if result.has("point"): return result
		reach -= 0.5
	return {"error": "There is no safe landing ahead."}

func safe_point(actor: Player, requested: Vector2, reach: float) -> Dictionary:
	var failed := {"error": "That landing is blocked or unsafe."}
	if not requested.is_finite() or not Map.BOUNDS.grow(-0.6).has_point(requested): return failed
	if game.get("field_building") and not preload("res://scripts/planes_boundary.gd").contains(requested): return failed
	if not game.navigation_ready or not game.nav_region: return failed
	var nav: RID = game.nav_region.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(nav) == 0: return failed
	var ground := Map.ground_pos(requested.x, requested.y)
	var nearest := NavigationServer3D.map_get_closest_point(nav, ground)
	if Vector2(nearest.x, nearest.z).distance_to(requested) > 1.0 or absf(nearest.y - ground.y) > 2.0: return failed
	var ray := PhysicsRayQueryParameters3D.create(nearest + Vector3.UP * 1.5, nearest - Vector3.UP * 2.0, 1 | 8)
	ray.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(ray)
	if hit.is_empty() or hit.normal.dot(Vector3.UP) < 0.72: return failed
	var target: Vector3 = hit.position + Vector3.UP * 0.08
	if Vector2(target.x, target.z).distance_to(Vector2(actor.global_position.x, actor.global_position.z)) > reach + 0.05: return failed
	if target.distance_to(actor.global_position) < 1.5: return {"error": "Choose a point a little further away."}
	if game.field_trials and not game.field_trials.permits(target): return failed
	# A navigation path prevents crossing sealed buildings or disconnected map islands.
	var path := NavigationServer3D.map_get_path(nav, actor.global_position, nearest, true)
	if path.is_empty() or path[-1].distance_to(nearest) > 1.0: return failed
	var cap := CapsuleShape3D.new()
	cap.radius = 0.43
	cap.height = Player.STAND_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = cap
	query.transform = Transform3D(Basis.IDENTITY, target + Vector3.UP * (Player.STAND_HEIGHT * 0.5))
	query.collision_mask = 1 | 2 | 4 | 8
	query.exclude = [actor.get_rid()]
	if not actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): return failed
	return {"point": target}

func perform(actor: Player, requested: Vector2) -> String:
	if NetSession.is_client(): return "Teleport is unavailable right now."
	var error := unavailable(actor)
	if not error.is_empty(): return error
	var result := destination(actor, requested)
	if not result.has("point"): return str(result.error)
	actor.global_position = result.point
	actor.velocity = Vector3.ZERO
	actor._shove = Vector3.ZERO
	actor.reset_physics_interpolation()
	actor.teleport_cooldown = MAP_COOLDOWN if mode_for(actor) == "map" else FORWARD_COOLDOWN
	if actor.class_combat.has("master_assassin"): actor.teleport_cooldown *= 0.5
	actor.teleport_serial += 1
	if actor == game.player: local_effect()
	return ""

func local_effect() -> void:
	if not game: return
	Sfx.play(game.player, "flashlight", -8.0)
	game.hud.message("Teleport", 1.1)
	if flash:
		flash.color.a = 0.18
		create_tween().tween_property(flash, "color:a", 0.0, 0.24)
