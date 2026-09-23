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
var trail := PackedVector3Array()
const ROAM_GRID := 3
var visited_cells: Dictionary = {}
var visit_clock := 0

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

const REGION_NAMES := {"N": "Nordwald", "E": "Ostwald", "S": "Südwald", "W": "Westwald"}
var stock_key := ""   # wave | phase | region the current assortment was rolled for
var here_region := ""  # forest quarter of the merchant's last stop

# Compass quarter of the merchant's position around the campsite (real north, not the plan's frame).
func region_at(pos: Vector3) -> String:
	var d := Vector2(pos.x - Map.FIRE.x, pos.z - Map.FIRE.y)
	if d.length() < 1: return "N"
	if absf(d.x) >= absf(d.y): return "E" if d.x > 0 else "W"
	return "S" if d.y > 0 else "N"

func phase() -> String:
	if not game or not game.day_night: return "night"
	return "day" if DayNightCycle.daylight_at(game.day_night.clock_seconds / 3600.0) >= 0.5 else "night"

func region_name() -> String:
	return REGION_NAMES.get(here_region, "Wald")

func offered(spec: Dictionary, wave: int, at_phase: String, in_region: String) -> bool:
	if spec.kind != "relic" or int(spec.level) > wave + 2: return false
	if spec.has("time") and at_phase not in spec.time: return false
	if spec.has("region") and in_region not in spec.region: return false
	return true

func restock(wave: int) -> void:
	if wave < 5: return
	if here_region.is_empty(): here_region = region_at(npc.global_position)
	var at_phase := phase()
	var key := "%d|%s|%s" % [wave, at_phase, here_region]
	if key == stock_key: return
	stock_key = key
	stock_wave = wave
	stock = {"fire": 3}
	if wave >= 7: stock.frost = 2
	# Weighted draw: goods bound to this time of day or this part of the forest turn up more often.
	var choices: Array = []
	var weights := PackedFloat32Array()
	for id in Items.DEFS:
		var spec: Dictionary = Items.DEFS[id]
		if not offered(spec, wave, at_phase, here_region): continue
		choices.append(id)
		weights.append(1.0 + (2.0 if spec.has("time") else 0.0) + (2.0 if spec.has("region") else 0.0))
	var count := mini(choices.size(), 3 + (1 if wave >= 8 else 0) + (1 if wave >= 12 else 0))
	for i in count:
		var index := random.rand_weighted(weights)
		stock[choices[index]] = 1
		choices.remove_at(index)
		weights.remove_at(index)

func buy(p: Player, id: String) -> String:
	if not active or not stock.has(id) or not Items.DEFS.has(id): return "Diese Rarität ist gerade nicht im Sortiment."
	var spec: Dictionary = Items.DEFS[id]
	var d := data(p.peer_id)
	if spec.kind == "relic" and d.owned.get(id, false): return equip(p, id)
	if game.progression.mission_level() < int(spec.level): return "Einsatzlevel %d benötigt." % spec.level
	if int(stock[id]) <= 0: return "Ausverkauft. Neue Lieferung in der nächsten Welle."
	if p.score < int(spec.price): return "Zu wenig Rem Dollars: %d R benötigt." % spec.price
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

func round_mode(p: Player) -> String:
	var d := data(p.peer_id)
	return str(d.mode) if int(d.ammo.get(d.mode, 0)) > 0 else ""

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
	z.rare_status = ("fire+frost" if float(s.frost) > 0 else "fire") if float(s.burn) > 0 else ("frost" if float(s.frost) > 0 else "")
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
			z.damage_peers[int(s.peer)] = true
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
		here_region = region_at(spawn)
		active = true
		mark_visited()
		npc.show()
		npc.body.collision_layer = 1
		game.hud.message("Der Nebelkrämer zieht durch die Gegend. Halte nach seiner violetten Laterne Ausschau.", 5)
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
		here_region = region_at(npc.global_position)
		var destination := choose_destination()
		if destination == Vector3.INF: return
		path = NavigationServer3D.map_get_path(game.nav_region.get_navigation_map(), npc.global_position, destination, true)
		path_index = 0
	if path_index >= path.size(): return
	var next := npc.global_position.move_toward(path[path_index], delta * 1.65)
	if not movement_clear(npc.global_position, next):
		# A newly built gate can invalidate an already accepted route. Back away
		# along the actual travelled route before selecting another destination.
		path = PackedVector3Array()
		for i in range(trail.size() - 1, -1, -1):
			if npc.global_position.distance_to(trail[i]) > 0.4 and movement_clear(npc.global_position, trail[i]):
				path.append(trail[i])
				break
		trail.clear()
		path_index = 0
		retry = 0.5
		animate()
		return
	var direction := next - npc.global_position
	if direction.length() > 0.001:
		npc.figure.rotation.y = lerp_angle(npc.figure.rotation.y, atan2(direction.x, direction.z), minf(1, delta * 5))
		moving = true
	if trail.is_empty() or trail[trail.size() - 1].distance_to(npc.global_position) > 0.5:
		trail.append(npc.global_position)
		if trail.size() > 20: trail.remove_at(0)
	npc.global_position = next
	if next.distance_to(path[path_index]) < 0.2:
		path_index += 1
		if path_index >= path.size(): mark_visited()
	animate()

func movement_clear(origin: Vector3, destination: Vector3, mask := 9) -> bool:
	var query := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.45
	capsule.height = 1.7
	query.shape = capsule
	query.collision_mask = mask
	query.exclude = [npc.body.get_rid()]
	query.transform.origin = destination + Vector3.UP
	var space: PhysicsDirectSpaceState3D = game.get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty(): return false
	query.transform.origin = origin + Vector3.UP
	query.motion = destination - origin
	var sweep: PackedFloat32Array = space.cast_motion(query)
	return sweep.is_empty() or sweep[0] >= 0.999

func route_clear(route: PackedVector3Array) -> bool:
	# Validate the same capsule and collision layers used during walking.
	# Checking gates alone accepted routes through other scenery, causing the
	# trader to repeatedly backtrack and pick the same blocked passage.
	for i in range(1, route.size()):
		if not movement_clear(route[i - 1], route[i]): return false
	return true

func roam_cell(point: Vector3) -> int:
	var area := Map.extent()
	var relative := (Vector2(point.x, point.z) - area.position) / area.size
	return clampi(int(relative.y * ROAM_GRID), 0, ROAM_GRID - 1) * ROAM_GRID + clampi(int(relative.x * ROAM_GRID), 0, ROAM_GRID - 1)

func mark_visited() -> void:
	visit_clock += 1
	visited_cells[roam_cell(npc.global_position)] = visit_clock

func choose_destination() -> Vector3:
	# Tour the entire playable map, prioritising sectors not visited recently.
	# Terrain type does not restrict the trader: paths, fields and clearings count.
	var nav: RID = game.nav_region.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(nav) == 0: return Vector3.INF
	var area := Map.extent()
	var cell_size := area.size / float(ROAM_GRID)
	var cells: Array = []
	for id in ROAM_GRID * ROAM_GRID:
		cells.append({"id": id, "visit": int(visited_cells.get(id, 0)), "tie": random.randf()})
	cells.sort_custom(func(a: Dictionary, b: Dictionary): return a.visit < b.visit if a.visit != b.visit else a.tie < b.tie)
	for cell in cells:
		var start := area.position + Vector2(int(cell.id) % ROAM_GRID, int(cell.id) / ROAM_GRID) * cell_size
		for attempt in 24:
			var candidate := start + Vector2(random.randf(), random.randf()) * cell_size
			var ground := Map.ground_pos(candidate.x, candidate.y)
			var point := NavigationServer3D.map_get_closest_point(nav, ground)
			if point.distance_to(ground) > 1.5 or roam_cell(point) != int(cell.id): continue
			if active and point.distance_to(npc.global_position) < 20: continue
			var origin: Vector3 = npc.global_position if active else Map.ground_pos(Map.FIRE.x, Map.FIRE.y)
			var route := NavigationServer3D.map_get_path(nav, origin, point, true)
			if route.is_empty() or route[route.size() - 1].distance_to(point) > 1: continue
			if active and not route_clear(route): continue
			if not movement_clear(point, point): continue
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
	return {"active": active, "pos": npc.global_position, "yaw": npc.figure.rotation.y, "moving": moving, "wave": stock_wave, "key": stock_key, "region": here_region, "stock": stock.duplicate(), "people": people.duplicate(true)}

func apply_snapshot(s: Dictionary) -> void:
	# Both ends of the comparison below have to describe the same player: on a client
	# game.player.peer_id and NetSession.local_id() can differ, which would compare our own
	# equipment against somebody else's.
	var peer: int = NetSession.local_id() if NetSession.enabled else game.player.peer_id
	var previous := data(peer).duplicate(true)
	var fresh := not active
	active = s.get("active", false)
	npc.visible = active
	npc.body.collision_layer = 1 if active else 0
	target_position = s.get("pos", npc.global_position)
	target_rotation = float(s.get("yaw", 0))
	moving = s.get("moving", false)
	if fresh: npc.global_position = target_position
	stock_wave = int(s.get("wave", 0))
	stock_key = str(s.get("key", ""))
	here_region = str(s.get("region", ""))
	stock = s.get("stock", {}).duplicate()
	people = s.get("people", {}).duplicate(true)
	var current := data(peer)
	game.player.relic = str(current.active)
	if previous != current and game.inventory.is_open: game.inventory._refresh()
