extends CanvasLayer
## Purchased kits are consumed only after a valid placement. No navigation rebakes.
var game: Node
var placing := false
var kind := "palisade"
var yaw := 0.0
var point := Vector3.ZERO
var error := ""
var ghost: MeshInstance3D
var material: StandardMaterial3D
var kit_menu: PanelContainer
var kit_rows: VBoxContainer

static func prewarm(parent: Node3D, main: Node3D) -> void:
	preload("res://scripts/tower_audio.gd").prewarm()
	for i in DefenceTower.TYPES.size():
		var tower := DefenceTower.new()
		tower.kind = DefenceTower.TYPES[i]
		tower.game = main
		tower.replica = true
		parent.add_child(tower)
		tower.set_physics_process(false)
		tower.remove_from_group("defence_towers")
		tower.scale = Vector3.ONE * 0.3
		tower.position = Vector3(-3 + i * 1.5, 1.5, -1)
		tower.fx.fire(4.0)
		tower.flash.show()
		if tower._lightning: tower._lightning.fire(PackedVector3Array([tower.muzzle.global_position, tower.muzzle.global_position + Vector3.UP]))
	var wall := Barricade.new()
	for tier in range(1, 4):
		var segment := wall._make_segment(tier)
		parent.add_child(segment)
		segment.position = Vector3(tier - 2, 0, 0)
		segment.scale = Vector3.ONE * 0.3
	wall.free()
	var bags := SandbagLine.new()
	parent.add_child(bags._make_segment())
	bags.free()

func setup(main: Node) -> void:
	game = main
	layer = 9
	ghost = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(3.2,1.55,0.5)
	ghost.mesh = mesh
	material = Barricade._marker_material(Color(0.2,1,0.55),0.35)
	ghost.material_override = material
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	game.add_child(ghost)
	ghost.hide()
	kit_menu = PanelContainer.new()
	add_child(kit_menu)
	kit_menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	kit_menu.offset_left = -230; kit_menu.offset_right = 230
	kit_menu.offset_top = -110; kit_menu.offset_bottom = 110
	kit_rows = VBoxContainer.new()
	kit_menu.add_child(kit_rows)
	kit_menu.hide()

func reset_run() -> void:
	cancel()
	for bar in game.barricades: bar.queue_free()
	game.barricades.clear()

func open_kits() -> void:
	if not game.survival_active or game.over: return
	for child in kit_rows.get_children():
		kit_rows.remove_child(child); child.queue_free()
	for id in ["palisade","sandbags"]:
		var button := Button.new()
		button.text = "%s · carried %d" % [id,game.progression.kit_stock[id]]
		button.disabled = game.progression.kit_stock[id]<=0
		button.pressed.connect(begin.bind(id))
		kit_rows.add_child(button)
	var close_button := Button.new()
	close_button.text = "Close [B / Esc] · Buy kits at Mechanic"
	close_button.pressed.connect(cancel)
	kit_rows.add_child(close_button)
	kit_menu.show()
	game.player.active = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func begin(id: String) -> void:
	if not game.progression.kit_stock.has(id) or game.progression.kit_stock[id]<=0: return
	kind = id
	error = "Choose solid ground."
	kit_menu.hide()
	game.player.active = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	yaw = game.player.rotation.y
	placing = true
	ghost.show()

func cancel() -> void:
	placing = false
	if ghost: ghost.hide()
	if kit_menu: kit_menu.hide()
	if game and not game.over and not get_tree().paused:
		game.player.active = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func placement_error(at: Vector3, angle: float, builder: Player = null) -> String:
	if not builder: builder = game.player
	if not at.is_finite() or not is_finite(angle) or not game.survival_active: return "Building unavailable."
	if game.barricades.size()>=40: return "Fortification limit reached."
	var distance: float = builder.position.distance_to(at)
	if distance<2 or distance>8: return "Choose ground 2–8 m away."
	if absf(Map.ground_height(at.x,at.z)-at.y)>0.2: return "Choose solid ground."
	for offset in [Vector3(-1.8,0,-0.6),Vector3(1.8,0,-0.6),Vector3(-1.8,0,0.6),Vector3(1.8,0,0.6)]:
		var p: Vector3 = at+offset.rotated(Vector3.UP,angle)
		if not preload("res://scripts/planes_boundary.gd").contains(Vector2(p.x,p.z)): return "Outside the playable area."
		if absf(Map.ground_height(p.x,p.z)-at.y)>0.65: return "Ground too steep."
	for npc in game.progression.npcs.values():
		if npc.position.distance_to(at)<5: return "Keep the traders accessible."
	if at.distance_to(Map.ground_pos(18,11))<3: return "Keep the campfire clear."
	for bar in game.barricades:
		if bar.distance_to_line(at)<1.8: return "Too close to another fortification."
	for tower in game.defences.towers.values():
		if tower.position.distance_to(at)<3: return "Keep tower access clear."
	var shape := BoxShape3D.new()
	shape.size = Vector3(3.4,1.2,0.7)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP,angle),at+Vector3.UP*0.9)
	query.collision_mask = 1|2|8
	if not game.get_world_3d().direct_space_state.intersect_shape(query,1).is_empty(): return "Building site occupied."
	var ray := PhysicsRayQueryParameters3D.create(builder.position+Vector3.UP*1.7,at+Vector3.UP,1|8,[builder.get_rid()])
	if not game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(): return "No clear view of the site."
	return ""

func place(id: String, at: Vector3, angle: float, builder: Player = null) -> String:
	if not builder: builder = game.player
	if not game.progression.kit_stock.has(id) or game.progression.kit_stock[id]<=0: return "Buy a kit at Mechanic first."
	if NetSession.is_client():
		NetSession.command("planes",["place",[id,at,angle]])
		return ""
	var reason := placement_error(at,angle,builder)
	if not reason.is_empty(): return reason
	var bar: Barricade = SandbagLine.new() if id=="sandbags" else Barricade.new()
	bar.setup({"id":"field_%d" % Time.get_ticks_usec(),"name":id,"pos":Vector2(at.x,at.z),"yaw":angle,"segments":1},game.hud)
	game.add_child(bar)
	bar.build()
	game.barricades.append(bar)
	game.progression.kit_stock[id] -= 1
	game.progression.event("built_wall")
	bar.breached.connect(func():
		game.barricades.erase(bar)
		bar.queue_free())
	Sfx.play_at(game,"build",at,-8)
	return ""

func nearest_bar(builder: Player = null) -> Barricade:
	if not builder: builder = game.player
	var result: Barricade
	var distance := 3.0
	for bar: Barricade in game.barricades:
		var d := bar.distance_to_line(builder.position)
		if d<distance:
			distance = d; result = bar
	return result

func repair_nearest(builder: Player = null) -> void:
	if not builder: builder = game.player
	if NetSession.is_client():
		NetSession.command("planes",["repair",[]])
		return
	var bar := nearest_bar(builder)
	if not bar or bar.hp>=bar.max_hp(): return
	var cost: int = SandbagLine.REPAIRS[bar.level] if bar is SandbagLine else Barricade.repair_cost(bar.level)
	if builder.score<cost:
		game.hud.message("Not enough Rem Dollars.",2); return
	if bar.repair():
		builder.add_score(-cost)
		game.progression.event("repairs")

func upgrade_bar(index: int, builder: Player = null) -> String:
	if not builder: builder = game.player
	if not game.progression.close_enough(builder,"mechanic") or index<0 or index>=game.barricades.size(): return "Go to Mechanic."
	var bar: Barricade = game.barricades[index]
	if NetSession.is_client():
		NetSession.command("planes",["upgrade_bar",[str(bar.slot.id)]])
		return "Request sent to host."
	if bar.level>=3: return "Maximum tier reached."
	if game.waves.completed<(3 if bar.level==1 else 8): return "Survive wave 3 / 8 for stronger fortifications."
	var cost: int = SandbagLine.UPGRADE_COST[bar.level] if bar is SandbagLine else Barricade.build_cost(bar.level+1)
	if builder.score<cost: return "Not enough Rem Dollars."
	if bar.build(): builder.add_score(-cost)
	return "Fortification upgraded."

func _unhandled_input(event: InputEvent) -> void:
	if not game or not game.survival_active or game.over or game.player.downed or game.player.mounted_tower: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode==KEY_B and not game.progression.is_open and not game.defences.is_open and not game.defences.placing:
			if placing or kit_menu.visible: cancel()
			else: open_kits()
			get_viewport().set_input_as_handled()
		elif event.physical_keycode==KEY_ESCAPE and (placing or kit_menu.visible):
			cancel(); get_viewport().set_input_as_handled()
		elif placing and event.physical_keycode==KEY_R:
			yaw += deg_to_rad(15); get_viewport().set_input_as_handled()
		elif placing and event.is_action_pressed("interact"):
			var reason := place(kind,point,yaw) if error.is_empty() else error
			if reason.is_empty(): cancel()
			else: game.hud.message(reason,2)
			get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not placing: return
	if game.over or not game.player.alive: cancel(); return
	var camera: Camera3D = game.player.camera
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,camera.global_position-camera.global_basis.z*12,1,[game.player.get_rid()])
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		error = "Look at nearby ground."
		ghost.hide()
	else:
		point = hit.position
		error = placement_error(point,yaw)
		ghost.position = point+Vector3.UP*0.7
		ghost.rotation.y = yaw
		ghost.show()
		material.albedo_color = Color(0.2,1,0.55,0.35) if error.is_empty() else Color(1,0.2,0.15,0.35)
	game.hud.set_prompt("[E] Place · [R] Rotate · [Esc] Cancel" if error.is_empty() else error)

func upgrade_id(id: String, builder: Player) -> String:
	for index in game.barricades.size():
		if str(game.barricades[index].slot.id)==id: return upgrade_bar(index,builder)
	return "Fortification not found."

func snapshot() -> Array:
	var result: Array = []
	for bar: Barricade in game.barricades:
		result.append({"slot":bar.slot.duplicate(true),"sandbags":bar is SandbagLine,"level":bar.level,"hp":bar.hp})
	return result

func apply_snapshot(states: Array) -> void:
	var existing := {}
	for bar: Barricade in game.barricades: existing[str(bar.slot.id)] = bar
	var ordered: Array = []
	for entry: Dictionary in states:
		var id := str(entry.slot.id)
		var bar: Barricade = existing.get(id)
		if not bar:
			bar = SandbagLine.new() if entry.sandbags else Barricade.new()
			bar.setup(entry.slot,game.hud)
			game.add_child(bar)
			bar.level = int(entry.level)
			bar.hp = float(entry.hp)
			bar.rebuild()
		ordered.append(bar)
		existing.erase(id)
	for bar: Barricade in existing.values(): bar.queue_free()
	game.barricades.assign(ordered)
