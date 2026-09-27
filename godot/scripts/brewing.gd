extends Node3D

const Recipes = preload("res://scripts/brew_recipes.gd")
const FX = preload("res://scripts/brew_fx.gd")
var game: Node3D
var stocks: Dictionary = {}
var jobs: Dictionary = {}
var kettles: Array[Dictionary] = []
var stations: Array[Vector3] = []
var pulse_times: Dictionary = {}
var menu: CanvasLayer

func setup(scene: Node3D) -> void:
	game = scene
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Rest the compact pot on the left of the cooking grate, clear of its suspension
	# wires and the stone surround. The right half stays available for venison.
	stations.append(game.grill_position + Vector3(-0.18, -0.06, 0.16))
	if not Map.SMALL_CAMPSITE.is_empty():
		var site: Vector2 = Map.SMALL_CAMPSITE.pos
		stations.append(Map.ground_pos(site.x + 0.7, site.y) + Vector3.UP * 0.15)
	for i in stations.size(): kettles.append(FX.kettle(self, stations[i], i == 0))
	preload("res://scripts/field_flowers.gd").build(game)
	menu = preload("res://scripts/brewing_menu.gd").new()
	add_child(menu)
	menu.setup(self)

func stock(peer: int) -> Dictionary:
	if not stocks.has(peer): stocks[peer] = {"flowers": {}, "drinks": {}}
	return stocks[peer]

func mushrooms(peer: int) -> Dictionary:
	if NetSession.is_host(): return NetSession.world.mushrooms.get(peer, {})
	return game.inventory.mushrooms

func station_for(p: Player) -> int:
	for i in stations.size():
		if game.hunting.reachable(p, stations[i] + Vector3.UP * 0.5, 3.8): return i
	return -1

func add_flower(peer: int, kind: String) -> void:
	if not Recipes.FLOWERS.has(kind): return
	var flowers: Dictionary = stock(peer).flowers
	flowers[kind] = int(flowers.get(kind, 0)) + 1

func ingredient_count(peer: int, kind: String) -> int:
	return int(stock(peer).flowers.get(kind, 0)) if Recipes.FLOWERS.has(kind) else int(mushrooms(peer).get(kind, 0))

func available(peer: int, kind: String) -> bool:
	if not Recipes.DRINKS.has(kind) or jobs.has(peer): return false
	if int(stock(peer).drinks.get(kind, 0)) >= Recipes.DRINK_LIMIT: return false
	for item in Recipes.DRINKS[kind].ingredients:
		if ingredient_count(peer, item) < int(Recipes.DRINKS[kind].ingredients[item]): return false
	return true

func request(action: String, kind: String) -> void:
	if NetSession.enabled: NetSession.command("brewing", [action, kind])
	else: game.hud.message(transact(game.player, action, kind), 3)
	if game.inventory.is_open: game.inventory._refresh()
	if menu.is_open: menu.refresh()

func transact(p: Player, action: String, kind: String) -> String:
	if NetSession.is_client() or not game.started or game.over or not p.alive or p.downed or p.controlling_drone or p.mounted_tower: return "You cannot brew or drink right now."
	if not Recipes.DRINKS.has(kind): return "Unknown recipe."
	var spec: Dictionary = Recipes.DRINKS[kind]
	var data := stock(p.peer_id)
	if action == "brew":
		var station := station_for(p)
		if station < 0: return "Go to a campfire to brew."
		if jobs.has(p.peer_id): return "Your drink is already brewing."
		if int(data.drinks.get(kind, 0)) >= Recipes.DRINK_LIMIT: return "You already carry eight of this drink."
		if not available(p.peer_id, kind): return "Ingredients missing. Gather flowers in the fields and mushrooms in the forest."
		# Validate the complete recipe before reserving any ingredients; one job per player.
		for item in spec.ingredients:
			var bag: Dictionary = data.flowers if Recipes.FLOWERS.has(item) else mushrooms(p.peer_id)
			bag[item] = int(bag[item]) - int(spec.ingredients[item])
		jobs[p.peer_id] = {"kind": kind, "left": Recipes.BREW_SECONDS, "station": station}
		Sfx.event(game, p.peer_id, "consume")
		return Lang.t("Brewing %s / 4 seconds", [spec.name])
	if action != "drink": return "Unknown action."
	if int(data.drinks.get(kind, 0)) <= 0: return "No such drink in your inventory."
	if not spec.has("duration") and p.hp >= p.max_hp: return "Health full - the drink stays in your inventory."
	data.drinks[kind] -= 1
	p.hp = minf(p.max_hp, p.hp + float(spec.get("heal", 0)))
	p.hud.set_health(p.hp)
	if spec.has("duration"): p.mushroom_effects[kind] = float(spec.duration)
	if spec.has("trip"):
		if p == game.player: game.hud.hallucinate(float(spec.trip))
		else: NetSession.feedback(p.peer_id, "hallucinate", [float(spec.trip)])
	Sfx.event(game, p.peer_id, "consume")
	show_burst(p.global_position, kind, 1.5)
	return Lang.t("%s: %s", [spec.name, spec.text])

func advance_jobs(delta: float) -> void:
	if NetSession.is_client(): return
	for peer in jobs.keys():
		jobs[peer].left = maxf(0, float(jobs[peer].left) - delta)
		if float(jobs[peer].left) > 0: continue
		var job: Dictionary = jobs[peer]
		var bag: Dictionary = stock(peer).drinks
		bag[job.kind] = int(bag.get(job.kind, 0)) + 1
		jobs.erase(peer)
		show_burst(stations[job.station] + Vector3.UP * 0.5, job.kind, 1.2)
		var message := Lang.t("%s is ready! Drink it from inventory or the quick bar.", [Recipes.DRINKS[job.kind].name])
		if NetSession.enabled: NetSession.feedback(peer, "message", [message, 3.5])
		else: game.hud.message(message, 3.5)
		if peer == game.player.peer_id and game.inventory.is_open: game.inventory._refresh()

func show_burst(at: Vector3, kind: String, radius: float) -> void:
	if NetSession.is_host():
		for peer in NetSession.world.actors: NetSession.feedback(peer, "brew_fx", [at, kind, radius])
	else: receive_burst(at, kind, radius)

func receive_burst(at: Vector3, kind: String, radius: float) -> void:
	if Recipes.DRINKS.has(kind): FX.burst(self, at, Recipes.DRINKS[kind].color, radius)

func tick_auras(delta: float) -> void:
	if NetSession.is_client(): return
	var actors: Array = NetSession.world.actors.values() if NetSession.is_host() else [game.player]
	var live := {}
	for p: Player in actors:
		if not p.alive or p.downed: continue
		for kind in p.mushroom_effects:
			var spec: Dictionary = Recipes.DRINKS.get(kind, {})
			if not spec.has("pulse") or float(p.mushroom_effects[kind]) <= 0: continue
			var key := str(p.peer_id) + ":" + str(kind)
			live[key] = true
			pulse_times[key] = float(pulse_times.get(key, 0)) - delta
			if float(pulse_times[key]) > 0: continue
			pulse_times[key] = float(spec.interval)
			show_burst(p.global_position, kind, float(spec.radius))
			for zombie in game.zombies_root.get_children():
				if not zombie is Zombie or not zombie.alive: continue
				if zombie.global_position.distance_to(p.global_position) > float(spec.radius): continue
				var q := PhysicsRayQueryParameters3D.create(p.global_position + Vector3.UP, zombie.global_position + Vector3.UP, 1 | 8, [p.get_rid(), zombie.get_rid()])
				if not get_world_3d().direct_space_state.intersect_ray(q).is_empty(): continue
				game.progression.rare_market.hit(zombie, spec.pulse, p.peer_id, "brew")
	for key in pulse_times.keys():
		if not live.has(key): pulse_times.erase(key)

func _process(delta: float) -> void:
	if not game or not game.started or game.over: return
	# Solo menu pauses combat, while its reserved brew finishes. Other pause menus freeze jobs.
	if not get_tree().paused or menu.is_open: advance_jobs(delta)
	if not get_tree().paused: tick_auras(delta)
	for i in kettles.size():
		var active := ""
		for job in jobs.values():
			if int(job.station) == i: active = job.kind; break
		kettles[i].steam.emitting = not active.is_empty()
		if not active.is_empty():
			var color: Color = Recipes.DRINKS[active].color
			kettles[i].liquid.material_override.albedo_color = color
			kettles[i].liquid.material_override.emission = color
			kettles[i].steam.color = color

func snapshot() -> Dictionary:
	return {"stocks": stocks.duplicate(true), "jobs": jobs.duplicate(true)}

func apply_snapshot(data: Dictionary) -> void:
	var before: Dictionary = stock(game.player.peer_id).duplicate(true)
	stocks = data.get("stocks", {}).duplicate(true)
	jobs = data.get("jobs", {}).duplicate(true)
	if before != stock(game.player.peer_id) and game.inventory.is_open: game.inventory._refresh()
