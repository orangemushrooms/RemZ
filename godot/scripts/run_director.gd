class_name RunDirector
extends Node3D
## Shared, host-owned expedition state. UI never grants supplies, XP or damage itself.
const Rules = preload("res://scripts/run_rules.gd")
var game: Node3D
var enabled := true
var config: Dictionary = {}
var elapsed := 0.0
var profile := 0
var direction := "north"
var people: Dictionary = {}
var rewards: Dictionary = {}
var operation: Dictionary = {}
var finale: Dictionary = {}
var sites: Array = []
var puzzle_order: Array = []
var puzzle_step := 0
var puzzle_done := false
var cargo_peer := 0
var cargo_route := 0
var cargo_deliveries := 0
var range_game: Dictionary = {}
var weather_schedule: Array = []
var structures: Node3D
var book: CanvasLayer
var checkpoints: RefCounted
var _markers: Dictionary = {}
var _tick := 0.0
var _last_wave := 0
var _warning_wave := 0
var _spawn_t := 0.0
var _request_times: Dictionary = {}

func setup(scene: Node3D) -> void:
	game = scene
	name = "Expedition"
	enabled = not "--classic-run" in OS.get_cmdline_user_args() and game.get("exploration_only") != true
	var region := "planes" if game.get("survival_active") != null else "forest"
	var raw: Dictionary = get_tree().get_meta("expedition_config", {})
	if raw.is_empty() or raw.get("region") != region:
		raw = {"seed": maxi(1, int(Time.get_unix_time_from_system()) % 2147483647), "region": region, "difficulty": game.settings.difficulty}
	for flag in OS.get_cmdline_user_args():
		if flag.begins_with("--run-code="):
			var decoded := Rules.decode(flag.trim_prefix("--run-code="))
			if not decoded.is_empty() and decoded.region == region: raw = decoded
	config = Rules.clean(raw)
	weather_schedule = Rules.weather_plan(config)
	puzzle_order = Rules.shuffled([0, 1, 2], Rules.rng(config, "signals"))
	structures = preload("res://scripts/expedition_structures.gd").new()
	add_child(structures)
	structures.setup(self)
	checkpoints = preload("res://scripts/expedition_checkpoint.gd").new()
	checkpoints.director = self
	checkpoints.index_world()
	book = preload("res://scripts/expedition_book.gd").new()
	add_child(book)
	book.setup(self)
	if enabled: _build_sites()
	set_process(enabled)
	set_process_unhandled_input(enabled)

func reset() -> void:
	elapsed = 0.0
	profile = 0
	people.clear()
	rewards.clear()
	operation.clear()
	finale.clear()
	puzzle_step = 0
	puzzle_done = false
	cargo_peer = 0
	cargo_route = 0
	cargo_deliveries = 0
	range_game.clear()
	_last_wave = 0
	_warning_wave = 0
	structures.clear()
	_spawn_t = 0.0
	_tick = 0.0
	_build_sites()
	_sync_markers()

func actor(peer: int) -> Player:
	return NetSession.world.actor(peer) if NetSession.is_host() and NetSession.world else game.player if peer == game.player.peer_id else null

func gear(peer: int) -> Weapons:
	return NetSession.world.weapons.get(peer) if NetSession.is_host() and NetSession.world else game.weapons if peer == game.player.peer_id else null

func actors() -> Array:
	return NetSession.world.actors.values() if NetSession.is_host() and NetSession.world else [game.player]

func person(peer: int) -> Dictionary:
	if not people.has(peer):
		people[peer] = {"augments": [], "offers": [], "cooldown": 0.0, "swap_ready": 0.0, "bandages": 2,
			"revives": 0, "repairs": 0, "rescues": 0, "healing": 0.0, "contract": 0, "longshots": 0}
	return people[peer]

func round_limit() -> int:
	return Rules.rounds(config) if enabled else Campaign.ROUNDS

func has_augment(peer: int, id: String) -> bool:
	return enabled and id in person(peer).augments

func configure(raw: Dictionary) -> bool:
	if NetSession.is_client() or game.waves.wave != 0 or not operation.is_empty() or not finale.is_empty(): return false
	var clean := Rules.clean(raw)
	if clean.region != config.region: return false
	config = clean
	get_tree().set_meta("expedition_config", config.duplicate(true))
	game.settings.difficulty = config.difficulty
	game.difficulty = GameSettings.DIFFICULTIES[config.difficulty]
	game.player.regen_mul = float(game.difficulty.regen)
	game.hud._mark_difficulty(config.difficulty)
	weather_schedule = Rules.weather_plan(config)
	puzzle_order = Rules.shuffled([0, 1, 2], Rules.rng(config, "signals"))
	if config.region == "planes": game._spawn_rng = Rules.rng(config, "spawn", 0)
	_build_sites()
	return true

func wave_profile(number: int) -> Dictionary:
	var random := Rules.rng(config, "wave-profile", number)
	return {"profile": random.randi_range(0, 2) if config.region == "planes" else random.randi_range(0, 3),
		"direction": ["north", "south", "east", "west"][random.randi_range(0, 3)]}

func prepare_wave(number: int) -> void:
	if not enabled or NetSession.is_client(): return
	var pattern := wave_profile(number)
	profile = pattern.profile
	direction = pattern.direction
	if config.region == "planes": game._spawn_rng = Rules.rng(config, "spawn", number)
	_last_wave = number
	for p: Player in actors():
		if not Rules.weapon_allowed(config, gear(p.peer_id).current):
			gear(p.peer_id).network_apply = true
			gear(p.peer_id).set_weapon("pistol")
			gear(p.peer_id).network_apply = false
	message(Lang.t("%s · Main approach: %s", [Lang.t(Rules.PROFILE_NAMES[profile]), Lang.t(direction.capitalize())]), 5)

func vary_plan(entries: Array, number: int) -> Array:
	if not enabled: return entries
	var random := Rules.rng(config, "wave-variation", number)
	var pattern := wave_profile(number)
	var result: Array = entries.duplicate(true)
	for entry: Dictionary in result:
		if Zombie.is_boss_kind(str(entry.type)): continue
		if random.randf() < 0.7: entry.lane = pattern.direction
		if config.region == "forest":
			entry.forest = pattern.profile == 1 or (pattern.profile != 0 and entry.get("forest", false))
			if pattern.profile == 2 and number >= 4 and entry.type == "runner": entry.corn = true
		else:
			entry.forest = pattern.profile == 1
			entry.corn = pattern.profile == 2
		if entry.type in ["shambler", "runner"] and random.randf() < 0.16:
			entry.type = "runner" if pattern.profile in [0, 2] else "soldier" if number >= 3 else "nurse" if number >= 2 else "shambler"
	if config.mode == "sprint":
		for i in maxi(3, number * 2): result.append({"type": "runner" if i % 3 else "brute" if number >= 3 else "shambler", "lane": pattern.direction, "forest": false})
	return result

func wave_cleared(number: int) -> void:
	if not enabled or NetSession.is_client(): return
	if number in [3, 7, 12, 17, 22]:
		for p: Player in actors():
			var state := person(p.peer_id)
			var choices: Array = Rules.AUGMENTS.keys().filter(func(id): return id not in state.augments)
			var identity: String = str(NetSession.roster.get(p.peer_id, CharacterProfile.data.name))
			state.offers = Rules.shuffled(choices, Rules.rng(config, "augments:"+identity, number)).slice(0, 3)
		message(Lang.t("Choose an augment in the fieldbook [K]."), 5)
	if operation.is_empty() and number % 3 == 2 and number < round_limit(): _new_operation(number)

func request(action: String, args: Array = []) -> String:
	if NetSession.enabled:
		NetSession.command("expedition", [action, args])
		return ""
	var result := transact(game.player.peer_id, action, args)
	if not result.is_empty(): game.hud.message(Lang.t(result), 3)
	return result

func transact(peer: int, action: String, args: Array) -> String:
	if NetSession.is_client() or not enabled or args.size() > 4: return "Invalid expedition request."
	var p := actor(peer)
	if not is_instance_valid(p) or not p.alive or p.downed or game.over: return "You must be alive to do this."
	var state := person(peer)
	match action:
		"ability":
			if not args.is_empty(): return "Invalid expedition request."
			return _ability(p)
		"augment":
			if args.size() != 1 or not args[0] is String or args[0] not in state.offers: return "Choose one of your offered augments."
			var id: String = args[0]
			state.augments.append(id)
			state.offers.clear()
			if id == "medic": state.bandages += 2
			if id == "reserve":
				gear(peer).refill_all()
				gear(peer).grenades = mini(gear(peer).grenades_max, gear(peer).grenades+1)
				gear(peer).update_hud()
			return "Augment selected."
		"interact":
			if args.size() != 1 or not args[0] is String: return "Invalid expedition request."
			return _interact(p, args[0])
		"heal", "bandage", "ammo", "drink": return _share(p, action, args)
		"buy_bandage":
			if not args.is_empty() or not _near(p, camp(), 5): return "Return to camp for supplies."
			if state.bandages >= 8 or p.score < 25: return "You need 25 Rem Dollars and a free bandage slot."
			p.add_score(-25)
			state.bandages += 1
			return "Bandage purchased."
		"contract":
			if config.region != "planes" or not args.is_empty() or not _near(p, camp(), 5): return "Accept the contract at camp."
			if state.contract != 0: return "Contract already accepted."
			state.contract = 1
			return "Eliminate five elite enemies from at least 60 metres."
		"cargo":
			if config.region != "planes" or not args.is_empty(): return "Invalid expedition request."
			if cargo_peer == peer:
				cargo_peer = 0
				return "Supply crate returned to camp."
			if cargo_peer or not _near(p, camp(), 5): return "Collect the supply crate at camp."
			cargo_route = cargo_deliveries % 3
			cargo_peer = peer
			return "Deliver the crate to the marked supply destination."
		"extinguish":
			if config.region != "planes" or not args.is_empty(): return "Invalid expedition request."
			if state.bandages <= 0: return "A bandage is needed for the wet fire blanket."
			var count: int = game.cornfield.fires.extinguish(p.global_position, 6.0)
			if count == 0: return "Move within six metres of a crop fire."
			state.bandages -= 1
			support(peer, "repairs", "fire:%d" % int(elapsed/10), count)
			return "Fire extinguished."
		"build":
			if args.size() != 1 or not args[0] is String: return "Invalid expedition request."
			return structures.build(p, args[0])
		"structure":
			if args.size() != 2 or not args[0] is int or not args[1] is String: return "Invalid expedition request."
			return structures.interact(p, args[0], args[1])
		"range":
			if args.size() != 1 or args[0] not in ["timed", "sequence", "competition"]: return "Invalid expedition request."
			return start_range(p, args[0])
		"save":
			if NetSession.enabled and peer != NetSession.local_id(): return "Only the host can save or continue an expedition."
			if not args.is_empty(): return "Invalid expedition request."
			return checkpoints.save_run()
		"load":
			if NetSession.enabled and peer != NetSession.local_id(): return "Only the host can save or continue an expedition."
			if not args.is_empty(): return "Invalid expedition request."
			return checkpoints.load_run()
	return "Invalid expedition request."

func _ability(p: Player) -> String:
	var state := person(p.peer_id)
	if state.cooldown > elapsed: return "Class action is cooling down."
	var combat: RefCounted = p.class_combat
	match str(combat.build.id):
		"gunslinger": combat.buff("exp_focus", 6)
		"assault": combat.buff("exp_suppression", 8)
		"breacher":
			for enemy: Zombie in _enemies():
				if enemy.global_position.distance_to(p.global_position) <= 9 and _visible(p.global_position+Vector3.UP, enemy.global_position+Vector3.UP):
					enemy.class_slow_time = maxf(enemy.class_slow_time, 4)
					enemy.killer_peer = p.peer_id
					enemy.killer_weapon = "shockwave"
					enemy.damage(65 if not Zombie.is_boss_kind(enemy.net_kind) else 35, (enemy.global_position-p.global_position).normalized())
		"marksman":
			var target: Zombie
			var alignment := 0.97
			for enemy: Zombie in _enemies():
				var offset := enemy.global_position+Vector3.UP-p.camera.global_position
				var dot := (-p.camera.global_basis.z).dot(offset.normalized())
				if offset.length() <= 180 and dot > alignment and _visible(p.camera.global_position, enemy.global_position+Vector3.UP):
					target = enemy
					alignment = dot
			if not target: return "Aim at a visible enemy to mark it."
			target.set_meta("exp_mark_until", elapsed+10)
			target.rare_status = "marked"
			combat.buff("exp_mark", 10)
		"assassin": return "Use your chosen teleport with [V]."
		_: return "Invalid expedition request."
	state.cooldown = elapsed+30
	return "Class action activated."

func incoming_damage(enemy: Zombie, amount: float) -> float:
	if not enabled: return amount
	if float(enemy.get_meta("exp_mark_until", 0)) > elapsed: amount *= 1.25
	var p := actor(enemy.killer_peer)
	if p and p.class_combat.active("exp_suppression") and enemy.killer_weapon not in ["tower", "grenade", "fire"]:
		enemy.class_slow_time = maxf(enemy.class_slow_time, 2)
	return amount

func switched(peer: int) -> void:
	if NetSession.is_client() or not has_augment(peer, "swap"): return
	var state := person(peer)
	if state.swap_ready > elapsed: return
	state.swap_ready = elapsed+8
	var p := actor(peer)
	if p: p.class_combat.buff("exp_swap", 3)

func grenade_effect(at: Vector3, peer: int) -> bool:
	if not has_augment(peer, "frost"): return false
	for enemy: Zombie in _enemies():
		if enemy.global_position.distance_to(at) < Grenade.RADIUS and _visible(at, enemy.global_position+Vector3.UP):
			gear(peer).specials.chill(enemy, 1.0, peer, "cryo_smg", 6.0 if not Zombie.is_boss_kind(enemy.net_kind) else 2.0)
	return true

func _share(p: Player, action: String, args: Array) -> String:
	if args.size() < 1 or args.size() > 2 or not args[0] is int: return "Choose a nearby teammate."
	var target := actor(args[0])
	if not target or target == p or not target.alive or target.downed or not _near(p, target.global_position, 3) or not _visible(p.global_position+Vector3.UP, target.global_position+Vector3.UP): return "Move within three metres of a living teammate."
	var stock := person(p.peer_id)
	if action in ["bandage", "heal"]:
		if args.size() != 1 or stock.bandages < 1: return "No bandage available."
		if action == "bandage":
			if person(target.peer_id).bandages >= 8: return "Your teammate has enough bandages."
			person(target.peer_id).bandages += 1
		else:
			var health := minf(45 if has_augment(p.peer_id, "medic") else 30, target.max_hp-target.hp)
			if health <= 0: return "Your teammate is already healthy."
			target.hp += health
			target.hud.set_health(target.hp)
			support(p.peer_id, "healing", "heal:%d:%d" % [target.peer_id, int(elapsed/15)], health)
		stock.bandages -= 1
	elif action == "ammo":
		if args.size() != 1: return "Invalid expedition request."
		var source := gear(p.peer_id)
		var destination := gear(target.peer_id)
		var id: String = destination.current
		if not source.state.has(id) or Weapons.is_melee(id) or not destination.has_ammo_space(id): return "No compatible spare ammunition."
		var count := mini(30, int(source.state[id].reserve))
		count = mini(count, destination.reserve_limit(id)-int(destination.state[id].reserve))
		if count <= 0: return "No compatible spare ammunition."
		source.state[id].reserve -= count
		destination.add_ammo(id, count)
		source.update_hud()
	else:
		if args.size() != 2 or not args[1] is String or not preload("res://scripts/brew_recipes.gd").DRINKS.has(args[1]): return "Invalid expedition request."
		var from: Dictionary = game.brewing.stock(p.peer_id).drinks
		var to: Dictionary = game.brewing.stock(target.peer_id).drinks
		var id: String = args[1]
		if int(from.get(id, 0)) < 1 or int(to.get(id, 0)) >= preload("res://scripts/brew_recipes.gd").DRINK_LIMIT: return "No drink available or teammate inventory full."
		from[id] -= 1
		to[id] = int(to.get(id, 0))+1
	return "Supplies transferred."

func support(peer: int, kind: String, token: String, amount: float = 1) -> void:
	if not enabled or NetSession.is_client() or kind not in ["revives", "repairs", "rescues", "healing"]: return
	var key := "support:%d:%d:%s" % [peer, game.waves.wave, token]
	if rewards.has(key): return
	var budget := "support-budget:%d:%d" % [peer, game.waves.wave]
	if int(rewards.get(budget, 0)) >= 20: return
	rewards[key] = true
	rewards[budget] = int(rewards.get(budget, 0))+1
	person(peer)[kind] += amount if kind == "healing" else int(amount)
	game.stats.record_support(peer, kind, amount)
	game.classes._deliver(peer, "support", [kind, 75 if kind != "healing" else 35, amount])

func killed(enemy: Zombie) -> void:
	if not enabled or NetSession.is_client(): return
	game.classes._deliver(enemy.killer_peer, "discovery", [enemy.net_kind, enemy.killer_weapon])
	var p := actor(enemy.killer_peer)
	if config.region == "planes" and p:
		var state := person(p.peer_id)
		if state.contract == 1 and enemy.net_kind not in ["shambler", "runner"] and p.global_position.distance_to(enemy.global_position) >= 60 and enemy.killer_weapon in ["marksman", "titanbreaker", "plasma_sniper"]:
			state.longshots += 1
			if state.longshots >= 5:
				state.contract = 2
				_reward("sniper:%d" % p.peer_id, [p.peer_id], 350, 800)

func camp() -> Vector3:
	return Map.ground_pos(22, 3) if config.region == "planes" else Map.ground_pos(Map.FIRE.x, Map.FIRE.y)

func _near(p: Player, at: Vector3, distance: float) -> bool:
	return p.global_position.distance_to(at) <= distance

func _visible(from: Vector3, to: Vector3) -> bool:
	return game.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1|8)).is_empty()

func _enemies() -> Array:
	return game.zombies_root.get_children().filter(func(z): return z is Zombie and z.alive and not z.is_queued_for_deletion())

func message(value: String, duration: float = 4) -> void:
	game.hud.message(value, duration)
	if NetSession.is_host():
		for peer in NetSession.world.actors:
			if peer != NetSession.local_id(): NetSession.feedback(peer, "message", [value, duration])

func _reward(token: String, peers: Array, dollars: int, xp: int) -> void:
	if rewards.has(token) or NetSession.is_client(): return
	rewards[token] = true
	for peer in peers:
		var p := actor(peer)
		if not p: continue
		p.add_score(dollars)
		game.classes.quest(peer, "expedition:"+token, dollars)
	game.classes.objective("expedition:"+token, xp)

func _safe_point(point: Vector2) -> Vector3:
	var at := Map.ground_pos(point.x, point.y)
	if game.get("nav_region"):
		var nav: RID = game.nav_region.get_navigation_map()
		if NavigationServer3D.map_get_iteration_id(nav) > 0:
			var candidate := NavigationServer3D.map_get_closest_point(nav, at)
			if candidate.distance_to(at) < 12: at = candidate
	return at

func _build_sites() -> void:
	for marker in _markers.values():
		if is_instance_valid(marker): marker.queue_free()
	_markers.clear()
	sites.clear()
	if not enabled: return
	var anchors := [Vector2(-82, 112), Vector2(105, 125), Vector2(45, -120), Vector2(-70, -98), Vector2(85, -190)]
	if config.region == "planes": anchors = [Vector2(102, 48), Vector2(-80, 230), Vector2(-112, 307), Vector2(151, -7), Vector2(78, 205), Vector2(166, 118), Vector2(48, 92), Vector2(112, 112)]
	for i in anchors.size():
		var random := Rules.rng(config, "site", i)
		var point: Vector2 = anchors[i] + Vector2(random.randf_range(-3, 3), random.randf_range(-3, 3))
		if config.region == "planes" and not preload("res://scripts/planes_boundary.gd").contains(point): point = anchors[i]
		var kind := "record" if i < 5 else "signal"
		if config.region == "planes" and i < 2: kind = "outpost"
		var site := {"id": "site_%d" % i, "kind": kind, "at": _safe_point(point), "done": false, "health": 160.0, "timer": 0.0}
		sites.append(site)
		if kind == "signal": site.at = _corn_signal_point(point, i-5)
		_marker(site.id, site.at, "Abandoned outpost" if kind == "outpost" else "Cornfield transmitter" if kind == "signal" else "Expedition cache", Color(0.7, 0.85, 1))

func _corn_signal_point(preferred: Vector2, index: int) -> Vector3:
	var choices: Array[Vector2] = []
	for x in range(-150, 350, 12):
		for z in range(-140, 265, 12):
			var point := Vector2(x, z)
			if game.cornfield.in_corn(point) and preload("res://scripts/planes_boundary.gd").contains(point): choices.append(point)
	choices.sort_custom(func(a: Vector2, b: Vector2): return a.distance_squared_to(preferred) < b.distance_squared_to(preferred))
	for point in choices:
		var at := _safe_point(point)
		if not game.cornfield.in_corn(Vector2(at.x, at.z)): continue
		if sites.any(func(site): return site.kind == "signal" and site.at.distance_to(at) < 25): continue
		return at
	return _safe_point(preferred+Vector2(index*25, 0))

func _marker(id: String, at: Vector3, label: String, color: Color) -> void:
	if _markers.has(id):
		_markers[id].position = at
		_markers[id].get_node("Caption").text = Lang.t(label)
		return
	var root := Node3D.new()
	add_child(root)
	root.position = at
	root.add_to_group("render_dynamic")
	if id == "operation" and not operation.is_empty():
		WorldModels.attach(root, "npc_secret_trader" if operation.kind == "escort" else "drone_scout" if operation.kind == "drone" else "ammo_crate", Vector3.ZERO, 1.8 if operation.kind == "escort" else 1.0)
	elif id == "finale":
		WorldModels.attach(root, "ammo_crate", Vector3(1.1, 0, 0), 1.0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.9, 0.6, 0.7)
	DefenceTower.piece(root, mesh, Vector3.UP*0.3, DefenceTower.material(color.darkened(0.5)))
	var pole := CylinderMesh.new()
	pole.top_radius = 0.045
	pole.bottom_radius = 0.045
	pole.height = 2.3
	DefenceTower.piece(root, pole, Vector3.UP*1.15, DefenceTower.material(color))
	var caption := Label3D.new()
	caption.name = "Caption"
	caption.text = Lang.t(label)
	caption.position.y = 2.65
	caption.font_size = 32
	caption.pixel_size = 0.014
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.modulate = color
	root.add_child(caption)
	_markers[id] = root

func _sync_markers() -> void:
	for site in sites:
		if _markers.has(site.id): _markers[site.id].visible = not site.done or site.kind == "outpost"
	for id in ["operation", "finale"]:
		var state: Dictionary = operation if id == "operation" else finale
		if state.is_empty() and _markers.has(id):
			_markers[id].queue_free()
			_markers.erase(id)

func nearest(p: Player) -> String:
	if not enabled or not p.alive or p.downed: return ""
	if not finale.is_empty() and _near(p, finale.at, 4): return "finale"
	if not operation.is_empty() and not operation.get("done", false) and _near(p, operation.at, 4): return "operation"
	if cargo_peer == p.peer_id and _near(p, cargo_destination(), 5): return "delivery"
	for site in sites:
		if (not site.done or site.kind == "outpost") and _near(p, site.at, 3.2): return site.id
	return structures.nearest(p)

func cargo_destination() -> Vector3:
	if sites.size() < 4: return camp()
	return sites[[2, 3, 0][cargo_route]].at

func _interact(p: Player, id: String) -> String:
	if nearest(p) != id: return "Move closer to the expedition objective."
	if id.begins_with("structure_"): return structures.interact(p, int(id.trim_prefix("structure_")), "use")
	if id == "delivery":
		cargo_peer = 0
		cargo_deliveries += 1
		gear(p.peer_id).refill_all()
		_reward("delivery:%d" % cargo_deliveries, [p.peer_id], 100, 200)
		support(p.peer_id, "rescues", "cargo:%d" % cargo_deliveries)
		return "Supplies delivered. Ammunition restocked."
	if id == "finale":
		if finale.stage == "prepare":
			finale.stage = "defend"
			finale.remaining = 18+round_limit()
			finale.hold = 0.0
			finale.timer = 90.0
			message(Lang.t("Final assault · Defend the signal and remain near the objective."), 6)
		return "Final defence is active."
	if id == "operation":
		if operation.stage == "offered":
			operation.stage = "active"
			operation.peer = p.peer_id
			operation.timer = 45.0 if operation.kind == "radio" else 0.0
			operation.pending = 6 if operation.kind == "drone" else 8
			operation.spawn_t = 0.0
		elif operation.kind == "drone" and operation.stage == "active" and operation.pending == 0 and not _enemies().any(func(z): return z.global_position.distance_to(operation.at) < 30): _finish_operation(p.peer_id)
		return "Operation started."
	for site in sites:
		if site.id != id: continue
		if site.kind == "outpost":
			if site.done:
				var token := "outpost-restock:%s:%d:%d" % [id, p.peer_id, game.waves.wave]
				if rewards.has(token): return "Outpost supplies are replenished next wave."
				rewards[token] = true
				gear(p.peer_id).add_ammo(gear(p.peer_id).current, 30)
				person(p.peer_id).bandages = mini(8, person(p.peer_id).bandages+1)
				return "Outpost supplies received."
			if site.timer <= 0:
				site.timer = 35.0
				site.pending = 6
				site.spawn_t = 0.0
			return "Hold the outpost for 35 seconds."
		if site.done: return "Already collected."
		if site.kind == "signal":
			var signal_number := int(id.trim_prefix("site_"))-5
			if signal_number != int(puzzle_order[puzzle_step]):
				puzzle_step = 0
				return "Signal order incorrect. Sequence reset."
			puzzle_step += 1
			if puzzle_step == 3:
				puzzle_done = true
				for other in sites:
					if other.kind == "signal": other.done = true
				_reward("signal-puzzle", game.classes.peers(), 500, 1000)
				for peer in game.classes.peers(): game.classes._deliver(peer, "lore", [2])
				for peer in game.classes.peers(): person(peer).bandages = mini(8, person(peer).bandages+2)
				return "Receiver unlocked. The station log and medical equipment are yours."
			return "Signal accepted. Find the next transmitter."
		site.done = true
		_reward("cache:"+id, [p.peer_id], 60, 100)
		gear(p.peer_id).add_ammo(gear(p.peer_id).current, 30)
		game.classes._deliver(p.peer_id, "lore", [int(id.trim_prefix("site_")) % Rules.LORE.size()])
		return "Cache and journal record collected."
	return "Invalid expedition request."

func _new_operation(number: int) -> void:
	if _markers.has("operation"):
		_markers.operation.queue_free()
		_markers.erase("operation")
	var random := Rules.rng(config, "operation", number)
	var kind: String = ["drone", "escort", "radio"][random.randi_range(0, 2)]
	var at: Vector3 = sites[random.randi_range(0, sites.size()-1)].at if not sites.is_empty() else camp()+Vector3(25, 0, 15)
	operation = {"kind": kind, "at": at, "stage": "offered", "done": false, "health": 120.0, "timer": 0.0,
		"wave": number, "peer": 0, "expires": elapsed+600}
	_marker("operation", at, "Crashed supply drone" if kind == "drone" else "Stranded survivor" if kind == "escort" else "Radio defence", Color(1, 0.7, 0.2))
	message(Lang.t("Optional operation available · Open the fieldbook [K]."), 5)

func _finish_operation(peer: int) -> void:
	if operation.done: return
	operation.done = true
	operation.stage = "complete"
	operation.expires = elapsed+30
	_reward("operation:%d" % int(operation.wave), game.classes.peers(), 125, 400)
	if operation.kind == "escort": support(peer, "rescues", "escort:%d" % int(operation.wave))
	for id in game.classes.peers():
		game.classes._deliver(id, "lore", [1 if operation.kind == "drone" else 3])
		person(id).bandages = mini(8, person(id).bandages+1)
		gear(id).add_ammo(gear(id).current, 30)
	message(Lang.t("Operation complete. Team supplies and XP awarded."), 5)

func begin_finale() -> bool:
	if not enabled: return false
	if NetSession.is_client(): return true
	if not finale.is_empty(): return true
	var at := camp() + Vector3(6, 0, 8) if config.region == "planes" else camp()+Vector3(2, 0, 4)
	at = _safe_point(Vector2(at.x, at.z))
	finale = {"stage": "prepare", "at": at, "health": 240.0, "remaining": 0, "timer": 90.0, "hold": 0.0}
	game.waves.phase = "finale"
	game.waves.queue.clear()
	_marker("finale", at, "Extraction transport" if config.region == "planes" else "Emergency transmitter", Color(0.2, 1, 0.6))
	message(Lang.t("Prepare the extraction transport [E].") if config.region == "planes" else Lang.t("Send the final radio signal [E]. Hold until dawn."), 8)
	return true

func _tick_finale(delta: float) -> void:
	if finale.is_empty() or finale.stage != "defend": return
	var present := actors().any(func(p): return p.alive and not p.downed and _near(p, finale.at, 18))
	if present:
		finale.timer = maxf(0, finale.timer-delta)
		finale.hold += delta
	for enemy: Zombie in _enemies():
		if enemy.global_position.distance_to(finale.at) < 5: finale.health -= delta*3
	if config.region == "forest" and game.hut.destroyed: finale.health = 0
	if finale.health <= 0:
		finale.stage = "failed"
		if NetSession.is_host():
			NetSession.phase = "over"
			game.over = true
			NetSession._send_lobby()
			NetSession._sequence += 1
			for peer in NetSession.ready_peers:
				if peer != NetSession.local_id() and NetSession.ready_peers[peer]: NetSession.send_reliable_state(peer, false)
			NetSession.world._show_game_over()
		elif config.region == "planes": game.finish_survival(false)
		else: game._end_round("SIGNAL LOST", "The final transmitter was destroyed. Defend it until dawn.")
		return
	_spawn_t -= delta
	if finale.remaining > 0 and _spawn_t <= 0 and game.alive_zombies() < (16 if config.region == "planes" else 30):
		var kind := "brute" if int(finale.remaining) % 7 == 0 else "runner"
		var spawned: bool = game.spawn_enemy(kind, game.waves.wave) != null if config.region == "planes" else game.waves._try_spawn({"type": kind, "lane": direction})
		if spawned:
			finale.remaining -= 1
		_spawn_t = 0.7
	if finale.timer <= 0 and finale.remaining == 0 and game.alive_zombies() == 0:
		finale.stage = "complete"
		game.classes.mission_complete()
		game.day_night.set_time_hours(6.7)
		game.classes.objective("expedition:finale", 1000)
		game.waves.phase = "complete"
		if config.region == "planes":
			if NetSession.is_host():
				game.victory = true
				NetSession.world.campaign_victory()
			else: game.finish_survival(true)
		else: game._campaign_victory()

func structure_grade() -> String:
	var health := 0.0
	var maximum := 0.0
	if config.region == "forest":
		health += game.hut.hp
		maximum += HutHealth.MAX_HP
	for b in game.barricades:
		if b.level > 0:
			health += b.hp
			maximum += b.max_hp()
	for line in game.sandbags:
		if line.level > 0:
			health += line.hp
			maximum += line.max_hp()
	for tower in game.defences.towers.values():
		if is_instance_valid(tower):
			health += tower.hp
			maximum += tower.max_hp()
	var ratio := health/maximum if maximum > 0 else 0.0
	return "A" if ratio >= 0.85 else "B" if ratio >= 0.6 else "C" if ratio >= 0.3 else "D"

func start_range(p: Player, mode: String) -> String:
	if config.region != "planes" or not game.shooting_range.opened or not game.shooting_range.inside(p): return "Enter the unlocked shooting range."
	if not range_game.is_empty() and range_game.timer > 0: return "A range session is already active."
	range_game = {"mode": mode, "timer": 30.0, "scores": {}, "sequence": Rules.shuffled([0, 1, 2, 3, 4, 5], Rules.rng(config, "range", int(elapsed))), "progress": {}, "owner": p.peer_id}
	return "Thirty second range session started."

func map_points() -> Array:
	var result: Array = []
	if not enabled: return result
	for site in sites:
		if site.done and site.kind != "outpost": continue
		result.append({"at": site.at, "label": str(int(site.id.trim_prefix("site_"))-4) if site.kind == "signal" else "", "color": Color(0.3, 0.9, 1) if site.kind == "signal" else Color(0.7, 0.85, 1)})
	for objective in [operation, finale]:
		if not objective.is_empty() and not objective.get("done", false) and objective.get("stage", "") not in ["complete", "failed"]: result.append({"at": objective.at, "label": "", "color": Color(1, 0.7, 0.2) if objective == operation else Color(0.2, 1, 0.6)})
	if cargo_peer: result.append({"at": cargo_destination(), "label": "", "color": Color(0.2, 1, 0.6)})
	for item in structures.items.values(): result.append({"at": item.at, "label": "", "color": Color(0.4, 0.75, 0.55)})
	return result

func range_hit(peer: int, lane: int, points: int) -> void:
	if range_game.is_empty() or range_game.timer <= 0 or NetSession.is_client(): return
	if range_game.mode != "competition" and peer != range_game.owner: return
	var position := int(range_game.progress.get(peer, 0))
	if range_game.mode == "sequence":
		if lane != int(range_game.sequence[position % 6]): return
		position += 1
		range_game.progress[peer] = position
	range_game.scores[peer] = int(range_game.scores.get(peer, 0))+points

func forecast() -> Dictionary:
	var time := elapsed
	for i in weather_schedule.size():
		var entry: Dictionary = weather_schedule[i]
		if time < float(entry.seconds):
			return {"state": entry.state, "next": weather_schedule[(i+1)%weather_schedule.size()].state, "seconds": ceili(entry.seconds-time)}
		time -= float(entry.seconds)
	var duration := 0.0
	for entry in weather_schedule: duration += float(entry.seconds)
	var old := elapsed
	elapsed = fmod(old, duration)
	var result := forecast()
	elapsed = old
	return result

func _process(delta: float) -> void:
	if not enabled or not game or not game.started or game.over or not game.get("waves"): return
	if not NetSession.enabled and not game.player.active: return
	if NetSession.is_client(): return
	elapsed += delta
	_tick -= delta
	if _tick > 0: return
	var step := 0.25+maxf(0, -_tick)
	_tick = 0.25
	if cargo_peer and (not actor(cargo_peer) or not actor(cargo_peer).alive or actor(cargo_peer).downed): cargo_peer = 0
	if game.waves.phase == "idle" and game.waves.timer <= 12 and _warning_wave != game.waves.wave+1:
		_warning_wave = game.waves.wave+1
		var pattern := wave_profile(_warning_wave)
		message(Lang.t("Radio forecast · %s · Approach from %s", [Lang.t(Rules.PROFILE_NAMES[pattern.profile]), Lang.t(str(pattern.direction).capitalize())]), 6)
	if not operation.is_empty() and not operation.done:
		if elapsed > operation.expires or operation.health <= 0:
			operation.done = true
			operation.stage = "failed"
		elif operation.stage == "active":
			_tick_reinforcements(operation, step)
			for enemy: Zombie in _enemies():
				if enemy.global_position.distance_to(operation.at) < 4: operation.health -= step*3
			if operation.kind == "radio":
				if actors().any(func(p): return p.alive and not p.downed and _near(p, operation.at, 12)): operation.timer = maxf(0, operation.timer-step)
				if operation.timer <= 0 and operation.get("pending", 0) == 0 and not _enemies().any(func(z): return z.global_position.distance_to(operation.at) < 25): _finish_operation(operation.peer)
			elif operation.kind == "escort": _escort(step)
	if not operation.is_empty() and operation.done and elapsed > float(operation.expires):
		operation.clear()
		_sync_markers()
	for site in sites:
		if site.kind != "outpost" or site.done or site.timer <= 0: continue
		_tick_reinforcements(site, step)
		if actors().any(func(p): return p.alive and not p.downed and _near(p, site.at, 14)): site.timer -= step
		for enemy: Zombie in _enemies():
			if enemy.global_position.distance_to(site.at) < 4: site.health -= step*2
		if site.health <= 0:
			site.timer = 0
			site.health = 160.0
		elif site.timer <= 0 and site.get("pending", 0) == 0 and not _enemies().any(func(z): return z.global_position.distance_to(site.at) < 25):
			site.done = true
			_reward("outpost:"+site.id, game.classes.peers(), 150, 350)
			for peer in game.classes.peers(): game.classes._deliver(peer, "lore", [int(site.id.trim_prefix("site_"))])
		elif site.timer <= 0: site.timer = 0.1
	if not range_game.is_empty() and range_game.timer > 0:
		range_game.timer = maxf(0, range_game.timer-step)
		if range_game.timer <= 0:
			for peer in range_game.scores: game.classes._deliver(peer, "range_record", [range_game.mode, int(range_game.scores[peer])])
			message(Lang.t("Range session complete. Results and records are in the fieldbook."), 5)
	_tick_finale(step)
	for enemy: Zombie in _enemies():
		if enemy.rare_status == "marked" and float(enemy.get_meta("exp_mark_until", 0)) <= elapsed: enemy.rare_status = ""
	_sync_markers()

func _escort(delta: float) -> void:
	var p := actor(operation.peer)
	if not p or not p.alive or p.downed or not _near(p, operation.at, 14): return
	var nav: RID = game.nav_region.get_navigation_map()
	var target := NavigationServer3D.map_get_closest_point(nav, camp())
	if Vector3(operation.at).distance_to(target) < 5:
		if int(operation.get("pending", 0)) == 0 and not _enemies().any(func(z): return z.global_position.distance_to(operation.at) < 25): _finish_operation(operation.peer)
		return
	var path := NavigationServer3D.map_get_path(nav, operation.at, target, true)
	if path.size() < 2: return
	var destination: Vector3 = path[1]
	operation.at = Vector3(operation.at).move_toward(destination, delta*2.8)
	_marker("operation", operation.at, "Stranded survivor", Color(1, 0.7, 0.2))

func _tick_reinforcements(objective: Dictionary, delta: float) -> void:
	objective.spawn_t = float(objective.get("spawn_t", 0.0))-delta
	if int(objective.get("pending", 0)) <= 0 or objective.spawn_t > 0 or game.alive_zombies() >= (16 if config.region == "planes" else 30): return
	var number := maxi(1, game.waves.wave)
	var spawned: bool = game.spawn_enemy("runner", number) != null if config.region == "planes" else game.waves._try_spawn({"type": "runner", "lane": direction})
	if spawned: objective.pending -= 1
	objective.spawn_t = 1.5

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.physical_keycode == KEY_K:
		book.toggle()
		get_viewport().set_input_as_handled()
	elif game.started and game.player.active and not game.over:
		if event.physical_keycode == KEY_Z:
			request("ability")
			get_viewport().set_input_as_handled()
		elif event.physical_keycode == KEY_E:
			var id := nearest(game.player)
			if not id.is_empty():
				request("interact", [id])
				get_viewport().set_input_as_handled()

func snapshot() -> Dictionary:
	return {"config": config.duplicate(true), "elapsed": elapsed, "profile": profile, "direction": direction,
		"people": people.duplicate(true), "rewards": rewards.duplicate(true), "operation": operation.duplicate(true),
		"finale": finale.duplicate(true), "sites": sites.duplicate(true), "puzzle_order": puzzle_order.duplicate(),
		"puzzle_step": puzzle_step, "puzzle_done": puzzle_done, "cargo_peer": cargo_peer, "cargo_route": cargo_route,
		"cargo_deliveries": cargo_deliveries, "range": range_game.duplicate(true), "structures": structures.snapshot(), "last_wave": _last_wave}

func apply_snapshot(state: Dictionary) -> void:
	if state.is_empty(): return
	config = Rules.clean(state.get("config", config))
	weather_schedule = Rules.weather_plan(config)
	elapsed = float(state.get("elapsed", 0))
	profile = int(state.get("profile", 0))
	direction = str(state.get("direction", "north"))
	people = state.get("people", {}).duplicate(true)
	rewards = state.get("rewards", {}).duplicate(true)
	operation = state.get("operation", {}).duplicate(true)
	finale = state.get("finale", {}).duplicate(true)
	sites = state.get("sites", []).duplicate(true)
	puzzle_order = state.get("puzzle_order", [0, 1, 2]).duplicate()
	puzzle_step = int(state.get("puzzle_step", 0))
	puzzle_done = bool(state.get("puzzle_done", false))
	cargo_peer = int(state.get("cargo_peer", 0))
	cargo_route = int(state.get("cargo_route", 0))
	cargo_deliveries = int(state.get("cargo_deliveries", 0))
	range_game = state.get("range", {}).duplicate(true)
	_last_wave = int(state.get("last_wave", 0))
	structures.apply_snapshot(state.get("structures", []))
	for site in sites: _marker(site.id, site.at, "Abandoned outpost" if site.kind == "outpost" else "Cornfield transmitter" if site.kind == "signal" else "Expedition cache", Color(0.7, 0.85, 1))
	if not operation.is_empty(): _marker("operation", operation.at, "Optional operation", Color(1, 0.7, 0.2))
	if not finale.is_empty(): _marker("finale", finale.at, "Final defence", Color(0.2, 1, 0.6))
	_sync_markers()
