extends Node3D

# All damage, drops and food transactions belong to the host. Animal IDs are stable
# across peers; the snapshot also restores deaths and uncollected meat for late joins.
const FOOD := {
	"raw_meat": {"name": "Rohes Wildfleisch", "sell": 12, "text": "Am Lagergrill mit E zubereiten (6 Sekunden). Oder beim Vendor verkaufen."},
	"cooked_meat": {"name": "Gegrilltes Wildfleisch", "sell": 20, "text": "Essen heilt 35 Leben. Bei voller Gesundheit wird nichts verbraucht."},
}
const COOK_TIME := 6.0
var game: Node3D
var animals: Array[Node3D] = []
var health: Array[float] = []
var stocks := {}
var drops := {}
var jobs := {}
var visuals := {}
var grill_food: Node3D

func setup(scene: Node3D) -> void:
	game = scene
	for node in game.get_children():
		if node is Deer: animals.append(node)
	for bird in game.cornfield.birds: animals.append(bird)
	for i in animals.size():
		var animal := animals[i]
		health.append(90.0 if animal is Deer and animal.kind == "stag" else 60.0 if animal is Deer else 20.0)
		if animal is Deer:
			animal.set_meta("hunt_id", i)
		else:
			var area := Area3D.new()
			area.collision_layer = Zombie.HITBOX_LAYER if animal.visible else 0
			area.collision_mask = 0
			area.monitoring = false
			area.monitorable = false
			area.set_meta("hunt_id", i)
			var shape := CollisionShape3D.new()
			var body := SphereShape3D.new()
			body.radius = 0.3
			shape.shape = body
			shape.position.y = 0.22
			area.add_child(shape)
			animal.add_child(area)
	_build_grate()
	grill_food = meat_model(true)
	add_child(grill_food)
	grill_food.global_position = game.grill_position
	grill_food.hide()

func _build_grate() -> void:
	var rack := Node3D.new()
	add_child(rack)
	rack.global_position = game.grill_position - Vector3.UP * 0.067
	var steel := DefenceTower.material(Color(0.12, 0.13, 0.14), 0.65)
	for i in 9:
		var bar := BoxMesh.new()
		bar.size = Vector3(0.8, 0.014, 0.012)
		DefenceTower.piece(rack, bar, Vector3(0, 0, (i - 4) * 0.095), steel)
	for side in [-1, 1]:
		var edge := BoxMesh.new()
		edge.size = Vector3(0.025, 0.025, 0.82)
		DefenceTower.piece(rack, edge, Vector3(side * 0.39, 0, 0), steel)
		var from := Vector3(side * 0.32, 0, 0)
		var to := Vector3(side * 0.32, 0.55, -0.4)
		var wire := CylinderMesh.new()
		wire.top_radius = 0.007
		wire.bottom_radius = 0.007
		wire.height = from.distance_to(to)
		var chain := DefenceTower.piece(rack, wire, (from + to) * 0.5, steel)
		chain.quaternion = Quaternion(Vector3.UP, (to - from).normalized())

func stock(peer: int) -> Dictionary:
	if not stocks.has(peer): stocks[peer] = {"raw_meat": 0, "cooked_meat": 0}
	return stocks[peer]

func hit(collider: Object, damage: float, peer: int) -> bool:
	if not is_instance_valid(collider) or not collider.has_meta("hunt_id"): return false
	var id := int(collider.get_meta("hunt_id"))
	if NetSession.is_client() or id < 0 or id >= animals.size() or health[id] <= 0: return false
	var animal := animals[id]
	if not animal.visible: return false
	health[id] = maxf(0, health[id] - damage)
	if health[id] > 0:
		if animal is Deer:
			animal.state = "flee"
			animal.flee_t = 9.0
			var shooter: Player = NetSession.world.actor(peer) if NetSession.is_host() else game.player
			animal.flee_dir = (animal.global_position - shooter.global_position).normalized()
		else: animal.scare(animal.global_position)
		return true
	_die(id)
	var pos := animal.global_position
	drops[id] = {"position": Map.ground_pos(pos.x, pos.z) + Vector3.UP * 0.12, "amount": 4 if animal is Deer and animal.kind == "stag" else 3 if animal is Deer else 1}
	_sync_visuals()
	game.achievements.event("hunted")
	return true

func _die(id: int) -> void:
	var animal := animals[id]
	if animal.get_meta("hunted_dead", false): return
	animal.set_meta("hunted_dead", true)
	animal.set_physics_process(false)
	animal.set_process(false)
	if animal is Deer:
		animal.collision_layer = 0
		animal.state = "dead"
	else:
		animal.voice.stop()
		for child in animal.get_children():
			if child is Area3D: child.collision_layer = 0
	var tw := create_tween().set_parallel(true)
	tw.tween_property(animal, "rotation:z", PI * 0.48, 0.45)
	tw.tween_property(animal, "position:y", Map.ground_height(animal.global_position.x, animal.global_position.z) + 0.16, 0.65).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_interval(12.0)
	tw.chain().tween_callback(animal.hide)

func blast(origin: Vector3, radius: float, damage: float, peer: int) -> void:
	if NetSession.is_client(): return
	for i in animals.size():
		var animal := animals[i]
		if health[i] <= 0 or not animal.visible: continue
		var center := animal.global_position + Vector3.UP * (0.7 if animal is Deer else 0.22)
		var distance := origin.distance_to(center)
		if distance > radius: continue
		var q := PhysicsRayQueryParameters3D.create(origin + Vector3.UP * 0.15, center, 1 | 8)
		if animal is Deer: q.exclude = [animal.get_rid()]
		if not get_world_3d().direct_space_state.intersect_ray(q).is_empty(): continue
		var target: Object = animal
		if not animal is Deer:
			for child in animal.get_children():
				if child is Area3D: target = child
		hit(target, damage * lerpf(1.0, 0.25, distance / radius), peer)

func reachable(p: Player, point: Vector3, distance := 3.0) -> bool:
	if p.global_position.distance_to(point) > distance: return false
	var q := PhysicsRayQueryParameters3D.create(p.camera.global_position, point + Vector3.UP * 0.3, 1 | 8, [p.get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func nearby_drop(p: Player) -> int:
	var nearest := -1
	var distance := 3.0
	for id in drops:
		var at: Vector3 = drops[id].position
		if p.global_position.distance_to(at) < distance and reachable(p, at):
			nearest = id
			distance = p.global_position.distance_to(at)
	return nearest

func at_grill(p: Player) -> bool:
	return reachable(p, game.grill_position, 3.4)

func prompt(p: Player, drop: int) -> String:
	if drop >= 0: return "[E] Wildfleisch aufnehmen · %d Stück" % drops[drop].amount
	if jobs.has(p.peer_id): return "Grill · noch %d s" % ceili(float(jobs[p.peer_id]))
	return "[E] Wildfleisch grillen · 6 s · %d roh" % int(stock(p.peer_id).raw_meat)

func request(action: String, id := -1) -> void:
	if NetSession.enabled: NetSession.command("hunting", [action, id])
	else: game.hud.message(transact(game.player, action, id), 2.5)

func transact(p: Player, action: String, id := -1) -> String:
	if NetSession.is_client() or not p.alive or game.over: return "Gerade nicht möglich."
	var food := stock(p.peer_id)
	match action:
		"collect":
			if not drops.has(id) or not reachable(p, drops[id].position): return "Gehe zur Beute."
			var amount: int = drops[id].amount
			food.raw_meat += amount
			drops.erase(id)
			_sync_visuals()
			Sfx.event(game, p.peer_id, "pickup")
			return "%d Stück Wildfleisch gesammelt" % amount
		"cook":
			if not at_grill(p): return "Gehe zum Lagergrill."
			if jobs.has(p.peer_id): return "Dein Fleisch liegt bereits auf dem Grill."
			if int(food.raw_meat) <= 0: return "Kein rohes Fleisch im Inventar."
			food.raw_meat -= 1
			jobs[p.peer_id] = COOK_TIME
			return "Wildfleisch wird gegrillt · 6 Sekunden"
		"eat":
			if int(food.cooked_meat) <= 0: return "Kein gegrilltes Fleisch im Inventar."
			if p.hp >= p.max_hp: return "Deine Gesundheit ist bereits voll."
			food.cooked_meat -= 1
			p.hp = minf(p.max_hp, p.hp + 35.0)
			p.hud.set_health(p.hp)
			Sfx.event(game, p.peer_id, "consume")
			if p == game.player and game.inventory.is_open: game.inventory._refresh()
			return "Wildfleisch gegessen · +35 Leben"
	return "Unbekannte Aktion."

func _process(delta: float) -> void:
	if not game or not game.started or game.over: return
	for i in animals.size():
		if animals[i] is Deer: continue
		for child in animals[i].get_children():
			if child is Area3D: child.collision_layer = Zombie.HITBOX_LAYER if health[i] > 0 and animals[i].visible else 0
	grill_food.visible = not jobs.is_empty()
	if NetSession.is_client(): return
	for peer in jobs.keys():
		jobs[peer] = maxf(0, float(jobs[peer]) - delta)
		if float(jobs[peer]) > 0: continue
		jobs.erase(peer)
		stock(peer).cooked_meat += 1
		if peer == game.player.peer_id and game.inventory.is_open: game.inventory._refresh()
		if NetSession.enabled: NetSession.feedback(peer, "message", ["Wildfleisch fertig · im Inventar essen oder verkaufen", 3.0])
		else: game.hud.message("Wildfleisch fertig · im Inventar essen oder verkaufen", 3.0)

func _sync_visuals() -> void:
	for id in visuals.keys():
		if not drops.has(id):
			visuals[id].queue_free()
			visuals.erase(id)
	for id in drops:
		if visuals.has(id): continue
		var node := meat_model(false)
		var caption := Label3D.new()
		caption.text = "Wildfleisch ×%d" % drops[id].amount
		caption.position.y = 0.8
		caption.font_size = 26
		caption.pixel_size = 0.004
		caption.modulate = Color(1, 0.82, 0.6)
		caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		caption.visibility_range_end = 16.0
		node.add_child(caption)
		add_child(node)
		node.global_position = drops[id].position
		visuals[id] = node

static func meat_model(cooked: bool) -> Node3D:
	var root := Node3D.new()
	var meat := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.23
	mesh.height = 0.46
	meat.mesh = mesh
	meat.scale = Vector3(1, 0.28, 1.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.09, 0.035) if cooked else Color(0.48, 0.075, 0.065)
	mat.roughness = 0.65 if cooked else 0.36
	meat.material_override = mat
	root.add_child(meat)
	for i in 4:
		var line := MeshInstance3D.new()
		var strip := BoxMesh.new()
		strip.size = Vector3(0.31, 0.008, 0.014)
		line.mesh = strip
		line.position = Vector3(0, 0.055, (i - 1.5) * 0.105)
		line.rotation.y = 0.25
		var fat := StandardMaterial3D.new()
		fat.albedo_color = Color(0.075, 0.035, 0.016) if cooked else Color(0.86, 0.66, 0.54)
		line.material_override = fat
		root.add_child(line)
	return root

func snapshot() -> Dictionary:
	var poses := []
	for i in animals.size():
		var a := animals[i]
		poses.append([a.global_position, a.rotation, a.visible, health[i], 0.0 if a is Deer else a.flying])
	return {"animals": poses, "stocks": stocks.duplicate(true), "drops": drops.duplicate(true), "jobs": jobs.duplicate()}

func apply_snapshot(data: Dictionary) -> void:
	# stocks is nested per peer, and Godot compares the inner dictionaries by reference: against a
	# fresh duplicate() the whole dictionary always looked different, so an open inventory was
	# rebuilt ten times a second and no slot stayed clickable. Compare our own flat entry instead.
	var previous: Dictionary = stock(game.player.peer_id).duplicate()
	stocks = data.get("stocks", {}).duplicate(true)
	var changed: bool = previous != stock(game.player.peer_id)
	drops = data.get("drops", {}).duplicate(true)
	jobs = data.get("jobs", {}).duplicate()
	var poses: Array = data.get("animals", [])
	for i in mini(animals.size(), poses.size()):
		var a := animals[i]
		health[i] = float(poses[i][3])
		if health[i] <= 0:
			if not a.get_meta("hunted_dead", false): a.global_position = poses[i][0]
			_die(i)
			a.visible = poses[i][2]
		else:
			a.visible = poses[i][2]
			if a is Deer:
				a.global_position = poses[i][0]
				a.rotation = poses[i][1]
			else:
				if not a.remote_position.is_finite():
					a.global_position = poses[i][0]
					a.rotation = poses[i][1]
				a.remote_position = poses[i][0]
				a.remote_yaw = float(poses[i][1].y)
				a.flying = float(poses[i][4])
	_sync_visuals()
	if changed and game.inventory.is_open: game.inventory._refresh()
