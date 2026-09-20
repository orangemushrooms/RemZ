extends Node

const Items = preload("res://scripts/rare_items.gd")
var game: Node
var npc: WorldNpc
var active := false
var stock: Dictionary = {}
var people: Dictionary = {}
var stock_wave := 0
var path := PackedVector3Array()
var path_index := 0
var retry := 0.0
var random := RandomNumberGenerator.new()
var moving := false
var target_position := Vector3.ZERO
var target_rotation := 0.0
var statuses: Dictionary = {}

func setup(main: Node, merchant: WorldNpc) -> void:
	game = main
	npc = merchant
	random.randomize()
	npc.hide()
	npc.body.collision_layer = 0
	npc.body.remove_from_group("navsource")

func data(peer: int) -> Dictionary:
	if not people.has(peer): people[peer] = {"owned": {}, "active": "", "ammo": {"fire": 0, "frost": 0}, "mode": "", "phoenix_wave": -1}
	return people[peer]

func restock(wave: int) -> void:
	if wave < 5 or wave == stock_wave: return
	stock_wave = wave
	stock = {"fire": 3}
	if wave >= 7: stock.frost = 2
	var choices: Array = []
	for id in Items.DEFS:
		if Items.DEFS[id].kind == "relic" and int(Items.DEFS[id].level) <= wave + 2: choices.append(id)
	for i in mini(2, choices.size()):
		var index := random.randi_range(0, choices.size() - 1)
		stock[choices[index]] = 1
		choices.remove_at(index)

func buy(p: Player, id: String) -> String:
	if not active or not stock.has(id) or not Items.DEFS.has(id): return "Diese Rarität ist gerade nicht im Sortiment."
	var spec: Dictionary = Items.DEFS[id]
	var d := data(p.peer_id)
	if spec.kind == "relic" and d.owned.get(id, false): return equip(p, id)
	if game.progression.mission_level() < int(spec.level): return "Einsatzlevel %d benötigt." % spec.level
	if int(stock[id]) <= 0: return "Ausverkauft. Neue Lieferung in der nächsten Welle."
	if p.score < int(spec.price): return "Zu wenig Punkte: %d P benötigt." % spec.price
	if spec.kind == "ammo" and int(d.ammo[id]) + int(spec.amount) > Items.AMMO_CAP: return "Spezialmunition voll (maximal 96 je Sorte). Erst verbrauchen."
	p.add_score(-int(spec.price))
	stock[id] -= 1
	if spec.kind == "relic":
		d.owned[id] = true
		d.active = id
		p.relic = id
	else:
		d.ammo[id] += int(spec.amount)
		d.mode = id
	Sfx.event(self, p.peer_id, "purchase")
	game.progression.weapon_for(p).update_hud()
	return "Gekauft und aktiviert: " + str(spec.name)

func equip(p: Player, id: String) -> String:
	var d := data(p.peer_id)
	if id == "normal": d.mode = ""
	elif id == "none":
		d.active = ""
		p.relic = ""
	elif id in ["fire", "frost"]:
		if int(d.ammo[id]) <= 0: return "Keine Patronen dieser Sorte."
		d.mode = id
	elif d.owned.get(id, false):
		d.active = id
		p.relic = id
	else: return "Diesen Talisman besitzt du nicht."
	game.progression.weapon_for(p).update_hud()
	return "Ausrüstung gewechselt."

func request_equip(id: String) -> void:
	if NetSession.enabled: NetSession.command("rare_equip", [id])
	else:
		game.hud.message(equip(game.player, id), 2)
		game.inventory._refresh()

func consume_round(p: Player) -> String:
	var d := data(p.peer_id)
	var mode: String = d.mode
	if mode.is_empty() or int(d.ammo.get(mode, 0)) <= 0: return ""
	d.ammo[mode] -= 1
	if d.ammo[mode] == 0: d.mode = ""
	return mode

func ammo_label(peer: int) -> String:
	var d := data(peer)
	return "" if str(d.mode).is_empty() else " · %s %d" % ["Feuer" if d.mode == "fire" else "Frost", d.ammo[d.mode]]

func prevent_death(p: Player) -> bool:
	var d := data(p.peer_id)
	if p.relic != "phoenix" or int(d.phoenix_wave) == game.waves.wave: return false
	d.phoenix_wave = game.waves.wave
	p.hp = p.max_hp * 0.4
	p.hud.set_health(p.hp)
	Sfx.event(self, p.peer_id, "pickup")
	return true

func on_kill(p: Player, weapon: String) -> void:
	if p.alive and p.relic == "blood" and weapon != "tower":
		p.hp = minf(p.max_hp, p.hp + 3)
		p.hud.set_health(p.hp)

func hit(z: Zombie, mode: String, peer: int, weapon: String) -> void:
	if mode.is_empty() or not z.alive: return
	if not statuses.has(z): statuses[z] = {"burn": 0.0, "tick": 0.0, "frost": 0.0, "peer": peer, "weapon": weapon}
	var s: Dictionary = statuses[z]
	if mode == "fire":
		if float(s.burn) <= 0: s.tick = 0.0
		s.burn = 3.0
		s.peer = peer
		s.weapon = weapon
	else: s.frost = 3.0
	update_status(z, s)

func update_status(z: Zombie, s: Dictionary) -> void:
	z.rare_status = "fire" if float(s.burn) > 0 else ("frost" if float(s.frost) > 0 else "")
	z.frost_mul = (0.8 if Zombie.is_titan_kind(z.net_kind) else 0.55) if float(s.frost) > 0 else 1.0

func tick_statuses(delta: float) -> void:
	for z in statuses.keys():
		if not is_instance_valid(z) or not z.alive:
			statuses.erase(z)
			continue
		var s: Dictionary = statuses[z]
		s.tick += minf(delta, float(s.burn))
		s.burn = maxf(0, float(s.burn) - delta)
		s.frost = maxf(0, float(s.frost) - delta)
		while float(s.tick) + 0.00001 >= 1.0 and z.alive:
			s.tick = maxf(0.0, float(s.tick) - 1.0)
			z.hp -= 12.0
			if z.hp <= 0:
				z.killer_peer = int(s.peer)
				z.killer_weapon = s.weapon
				z.last_headshot = false
				z.die(Vector3.ZERO)
		update_status(z, s)
		if float(s.burn) <= 0 and float(s.frost) <= 0: statuses.erase(z)

func _physics_process(delta: float) -> void:
	if not game or not game.started or game.over or not game.navigation_ready: return
	if NetSession.is_client():
		if active:
			npc.global_position = npc.global_position.lerp(target_position, 1.0 - exp(-delta * 12))
			npc.figure.rotation.y = lerp_angle(npc.figure.rotation.y, target_rotation, minf(1, delta * 10))
		animate()
		return
	tick_statuses(delta)
	if game.waves.wave < 5: return
	if not active:
		var spawn := choose_destination()
		if spawn == Vector3.INF: return
		npc.global_position = spawn
		active = true
		npc.show()
		npc.body.collision_layer = 1
		game.hud.message("Der Nebelkrämer zieht durch den Wald. Halte nach seiner violetten Laterne Ausschau.", 5)
	restock(game.waves.wave)
	var customers: Array = NetSession.world.actors.values() if NetSession.is_host() else [game.player]
	moving = false
	for p: Player in customers:
		if p.alive and p.global_position.distance_to(npc.global_position) < 4.5:
			if Vector2(p.global_position.x - npc.global_position.x, p.global_position.z - npc.global_position.z).length() > 0.1:
				npc.figure.look_at(Vector3(p.global_position.x, npc.global_position.y, p.global_position.z), Vector3.UP, true)
			animate()
			return
	retry -= delta
	if path_index >= path.size():
		if retry > 0: return
		retry = 2.0
		var destination := choose_destination()
		if destination == Vector3.INF: return
		path = NavigationServer3D.map_get_path(game.nav_region.get_navigation_map(), npc.global_position, destination, true)
		path_index = 0
	if path_index >= path.size(): return
	var next := npc.global_position.move_toward(path[path_index], delta * 1.65)
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.7
	query.shape = capsule
	query.transform.origin = next + Vector3.UP
	query.collision_mask = 1 | 8
	query.exclude = [npc.body.get_rid()]
	if not game.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		path.clear()
		animate()
		return
	var direction := next - npc.global_position
	if direction.length() > 0.001:
		npc.figure.rotation.y = lerp_angle(npc.figure.rotation.y, atan2(direction.x, direction.z), minf(1, delta * 5))
		moving = true
	npc.global_position = next
	if next.distance_to(path[path_index]) < 0.2: path_index += 1
	animate()

func choose_destination() -> Vector3:
	var nav: RID = game.nav_region.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(nav) == 0: return Vector3.INF
	for attempt in 32:
		var road: Dictionary = Map.ROADS[random.randi_range(0, Map.ROADS.size() - 1)]
		var segment := random.randi_range(0, road.pts.size() - 2)
		var candidate: Vector2 = road.pts[segment].lerp(road.pts[segment + 1], random.randf())
		candidate += Vector2(random.randf_range(-5, 5), random.randf_range(-5, 5))
		if not Map.in_forest(candidate.x, candidate.y) or Map.in_building(candidate.x, candidate.y, 5): continue
		var ground := Map.ground_pos(candidate.x, candidate.y)
		var point := NavigationServer3D.map_get_closest_point(nav, ground)
		if point.distance_to(ground) > 1.5: continue
		if active and point.distance_to(npc.global_position) < 15: continue
		var origin: Vector3 = npc.global_position if active else Map.ground_pos(Map.FIRE.x, Map.FIRE.y)
		var route := NavigationServer3D.map_get_path(nav, origin, point, true)
		if route.is_empty() or route[route.size() - 1].distance_to(point) > 1: continue
		return point
	return Vector3.INF

func animate() -> void:
	if not npc.anim: return
	var desired := "walk" if moving else "idle"
	npc.anim.speed_scale = 0.75 if moving else 1.0
	for clip in npc.anim.get_animation_list():
		if desired in clip.to_lower() and npc.anim.current_animation != clip:
			npc.anim.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			npc.anim.play(clip, 0.2)
			break

func snapshot() -> Dictionary:
	return {"active": active, "pos": npc.global_position, "yaw": npc.figure.rotation.y, "moving": moving, "wave": stock_wave, "stock": stock.duplicate(), "people": people.duplicate(true)}

func apply_snapshot(s: Dictionary) -> void:
	var previous := data(game.player.peer_id).duplicate(true)
	var fresh := not active
	active = s.get("active", false)
	npc.visible = active
	npc.body.collision_layer = 1 if active else 0
	target_position = s.get("pos", npc.global_position)
	target_rotation = float(s.get("yaw", 0))
	moving = s.get("moving", false)
	if fresh: npc.global_position = target_position
	stock_wave = int(s.get("wave", 0))
	stock = s.get("stock", {}).duplicate()
	people = s.get("people", {}).duplicate(true)
	var current := data(NetSession.local_id() if NetSession.enabled else game.player.peer_id)
	game.player.relic = str(current.active)
	if previous != current and game.inventory.is_open: game.inventory._refresh()
