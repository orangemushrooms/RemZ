extends RefCounted

var game: Node3D
var actors: Dictionary = {}
var weapons: Dictionary = {}
var avatars: Dictionary = {}
var levels: Dictionary = {}
var mushrooms: Dictionary = {}
var rage: Dictionary = {}
var pose_times: Dictionary = {}
var move_targets: Dictionary = {}
var loot_nodes: Dictionary = {}
var broken_nodes: Dictionary = {}
var zombies: Dictionary = {}
var grenades: Dictionary = {}
var drops: Dictionary = {}
var deer: Array = []
var revive: Dictionary = {}
var next_id := 1
var local_dead := false
var current_wave := 0
var state_loaded := false

func setup(node: Node3D) -> void:
	game = node
	var i := 0
	for loot in game.loots:
		if not is_instance_valid(loot): continue
		var id: String = "key:" + loot.key_id if loot is ForestKey else "loot:%d" % i
		loot.set_meta("coop_id", id)
		loot_nodes[id] = loot
		i += 1
	i = 0
	for pane in game.get_tree().get_nodes_in_group("breakable"):
		broken_nodes[i] = pane
		i += 1
	for child in game.get_children():
		if child is Deer: deer.append(child)

func actor(id: int) -> Player:
	return actors.get(id)

func add_player(id: int) -> void:
	if actors.has(id): return
	var p: Player
	var w: Weapons
	if id == NetSession.local_id():
		p = game.player
		w = game.weapons
		levels[id] = game.skills.levels
		mushrooms[id] = game.inventory.mushrooms
	else:
		p = Player.new()
		p.remote_actor = true
		p.peer_id = id
		p.name = "CoopPlayer_%d" % id
		var proxy: Hud = preload("res://scripts/coop_hud.gd").new()
		proxy.peer_id = id
		game.add_child(proxy)
		p.hud = proxy
		game.add_child(p)
		p.flashlight.visible = false
		p.flashlight.shadow_enabled = false
		p.global_position = spawn_position(actors.size())
		p.active = NetSession.phase == "running"
		p.regen_mul = float(game.difficulty.regen)
		p.died.connect(check_team)
		w = Weapons.new()
		p.add_child(w)
		w.setup_proxy(p, proxy, game.zombies_root)
		if NetSession.is_client(): w.set_process(false)
		levels[id] = {}
		for entry in Skills.UPGRADES: levels[id][entry.id] = 0
		mushrooms[id] = {"steinpilz": 0, "fliegenpilz": 0}
		var avatar = preload("res://scripts/coop_avatar.gd").new()
		p.add_child(avatar)
		avatar.setup(p, NetSession.roster.get(id, "Spieler"), actors.size())
		avatars[id] = avatar
	p.peer_id = id
	actors[id] = p
	weapons[id] = w
	pose_times[id] = NetSession._elapsed
	rage[id] = 0.0
	if NetSession.is_host() and game.waves.wave >= 3: w.unlock("shotgun")

func spawn_position(index: int) -> Vector3:
	var point: Vector3 = Map.ground_pos(Map.PLAYER_START.x + index * 1.3, Map.PLAYER_START.y + 1.0)
	if game.started:
		var near: Player = nearest_player(game.player.global_position)
		if near: point = near.global_position + Vector3(1.5, 0.3, 1.5)
	var nav: RID = game.nav_region.get_navigation_map()
	return NavigationServer3D.map_get_closest_point(nav, point) + Vector3.UP * 0.3

func remove_player(id: int) -> void:
	if actors.has(id) and is_instance_valid(actors[id]) and actors[id] != game.player:
		actors[id].hud.queue_free()
		actors[id].queue_free()
	for dict in [actors, weapons, avatars, levels, mushrooms, rage, pose_times, move_targets, revive]: dict.erase(id)

func sync_roster() -> void:
	for id in actors.keys():
		if not NetSession.roster.has(id): remove_player(id)
	for id in NetSession.roster: add_player(id)

func make_client() -> void:
	game.waves.set_process(false)
	game.day_night.set_process(false)
	game.achievements.set_process(false)
	for animal in deer: animal.set_physics_process(false)
	game.player.regen_timer = 99999.0

func nearest_player(position: Vector3) -> Player:
	var nearest: Player
	var distance := INF
	for p: Player in actors.values():
		if not is_instance_valid(p) or not p.alive: continue
		var d := p.global_position.distance_squared_to(position)
		if d < distance:
			distance = d
			nearest = p
	return nearest

func move_player(id: int, position: Vector3, yaw: float, pitch: float, light: bool, motion: Vector3, now: float) -> void:
	var p: Player = actor(id)
	if not p or not p.alive: return
	var dt := clampf(now - float(pose_times.get(id, now)), 0.01, 0.5)
	pose_times[id] = now
	var move := position - p.global_position
	var max_distance := Player.SPRINT_SPEED * p.speed_mul * dt + 0.7
	if Vector2(move.x, move.z).length() > max_distance or absf(move.y) > 16.0 * dt + 1.2: return
	if not Map.BOUNDS.has_point(Vector2(position.x, position.z)): return
	# Sweep the same capsule against terrain, buildings and barricades.
	p.move_and_collide(move)
	p.rotation.y = wrapf(yaw, -PI, PI)
	p.pitch = clampf(pitch, -1.45, 1.45)
	p.head.rotation.x = p.pitch
	p.flashlight.visible = light
	p.velocity = motion.limit_length(20.0)

func _aim(p: Player, args: Array, offset: int) -> bool:
	if args.size() < offset + 2 or not (args[offset] is float or args[offset] is int) or not (args[offset+1] is float or args[offset+1] is int): return false
	if not is_finite(float(args[offset])) or not is_finite(float(args[offset+1])): return false
	p.rotation.y = wrapf(float(args[offset]), -PI, PI)
	p.pitch = clampf(float(args[offset+1]), -1.45, 1.45)
	p.head.rotation.x = p.pitch
	return true

func action(id: int, operation: String, args: Array) -> void:
	var p: Player = actor(id)
	if not p or not p.alive: return
	var w: Weapons = weapons[id]
	match operation:
		"fire":
			if args.size() != 4 or not args[0] is String or not args[1] is float or not is_finite(args[1]) or not _aim(p, args, 2): return
			w.set_weapon(args[0])
			if w.current != args[0]: return
			w.ads = clampf(args[1], 0, 1)
			w.try_fire()
		"weapon":
			if args.size() == 1 and args[0] is String: w.set_weapon(args[0])
		"reload": w.reload()
		"melee":
			if _aim(p, args, 0): w.melee()
		"grenade":
			if _aim(p, args, 0): w.throw_grenade()
		"interact":
			if args.size() == 1 and args[0] is String: collect_loot(id, args[0])
		"build", "repair":
			if args.size() != 1 or not args[0] is int or args[0] < 0 or args[0] >= game.barricades.size(): return
			var b: Barricade = game.barricades[args[0]]
			var error := b.action_error(p, operation, true)
			if error.is_empty(): b.purchase(p, operation, true)
			else: NetSession.feedback(id, "message", [error, 2.0])
		"upgrade":
			if args.size() == 1 and args[0] is String: buy_upgrade(id, args[0])
		"eat":
			if args.size() == 1 and args[0] is String: eat(id, args[0])
		"revive":
			if args.size() == 1 and args[0] is int and actors.has(args[0]) and not actor(args[0]).alive:
				revive[id] = {"target": args[0], "time": 0.0}
		"next_wave":
			if id == 1 and game.waves.phase == "idle": game.waves.timer = minf(game.waves.timer, 1.0)

func _visible(p: Player, target: Vector3, object: Object = null) -> bool:
	var query := PhysicsRayQueryParameters3D.create(p.camera.global_position, target, 1 | 8, [p.get_rid()])
	var hit := game.get_world_3d().direct_space_state.intersect_ray(query)
	return hit.is_empty() or hit.collider == object

func collect_loot(id: int, key: String) -> void:
	var item = loot_nodes.get(key)
	if not is_instance_valid(item) or item.taken: return
	var p: Player = actor(id)
	var w: Weapons = weapons[id]
	if item is Door:
		item.take(w, p.hud)
		return
	var target: Vector3 = item.interaction_point() if item is ForestKey else item.global_position + Vector3.UP * 0.3
	if p.camera.global_position.distance_to(target) > 2.8 or not _visible(p, target): return
	if item is ForestKey:
		game.forest_keys.owned[item.key_id] = true
		if game.inventory.is_open: game.inventory._refresh()
		for peer in actors: NetSession.feedback(peer, "message", ["Teamschlüssel gefunden: " + ForestKeys.KEYS[item.key_id], 3.0])
	elif item.kind == "mushroom":
		mushrooms[id][item.id] += 1
		NetSession.feedback(id, "message", [item.label + " gesammelt", 1.5])
		game.achievements.event("mushrooms")
	elif item.kind == "weapon":
		if w.unlocked.get(item.id, false): w.add_ammo(item.id, int(Weapons.DEFS[item.id].reserve))
		else: w.unlock(item.id)
		NetSession.feedback(id, "message", [item.label + " aufgenommen", 2.0])
		game.achievements.event("weapons")
	else:
		for weapon_id in w.unlocked:
			if w.unlocked[weapon_id]: w.add_ammo(weapon_id, int(Weapons.DEFS[weapon_id].reserve))
		w.grenades += 2
	item.taken = true
	if item is ForestKey:
		item.pickup_visual.hide()
	else:
		item.hide()
		item.queue_free()
	w.update_hud()

func collect_drop(drop: Pickup, id: int) -> void:
	if not NetSession.is_host() or drop._taken or not actors.has(id): return
	var p: Player = actor(id)
	if not p.alive or p.global_position.distance_to(drop.global_position) > 2.3: return
	var w: Weapons = weapons[id]
	drop._taken = true
	match drop.kind:
		"ammo": w.add_ammo(w.current, int(Weapons.DEFS[w.current].mag))
		"grenade": w.grenades += 1
		_: p.hp = minf(p.max_hp, p.hp + 30.0)
	w.update_hud()
	p.hud.set_health(p.hp)
	NetSession.feedback(id, "message", ["Vorrat aufgenommen", 1.4])
	game.achievements.event("drops")
	drop.queue_free()

func buy_upgrade(id: int, key: String) -> void:
	if not levels[id].has(key): return
	var spec: Dictionary = {}
	for entry in Skills.UPGRADES:
		if entry.id == key: spec = entry
	var level: int = levels[id][key]
	var cost := int(spec.cost) + int(spec.cost) * level / 2
	var p: Player = actor(id)
	var w: Weapons = weapons[id]
	if level >= int(spec.max) or p.score < cost: return
	p.add_score(-cost)
	levels[id][key] += 1
	match key:
		"hp":
			p.max_hp += 25.0
			p.hp = minf(p.max_hp, p.hp + 25.0)
		"speed": p.speed_mul += 0.08
		"regen": p.regen_mul += 0.6
		"damage": w.damage_mul = (1.0 + 0.12 * levels[id][key]) * (2.0 if rage[id] > 0 else 1.0)
		"reload": w.reload_mul *= 0.85
		"steady": w.spread_mul *= 0.85
		"grenades":
			w.grenades_max += 1
			w.grenades += 1
		_: w.unlock(key.trim_prefix("w_"))
	if id == 1:
		game.hud.hp_bar.max_value = p.max_hp
		game.skills._refresh()
	p.hud.set_health(p.hp)
	w.update_hud()
	NetSession.feedback(id, "message", ["Verbesserung gekauft: " + spec.name, 1.5])

func eat(id: int, kind: String) -> void:
	if not Inventory.MUSHROOMS.has(kind) or mushrooms[id].get(kind, 0) <= 0: return
	mushrooms[id][kind] -= 1
	var p: Player = actor(id)
	p.hp = clampf(p.hp + float(Inventory.MUSHROOMS[kind].heal), 1.0, p.max_hp)
	if kind == "fliegenpilz":
		rage[id] = 20.0
		weapons[id].damage_mul = (1.0 + 0.12 * levels[id].get("damage", 0)) * 2.0
		game.achievements.event("rausch")
	game.stats.mushrooms_eaten += 1
	p.hud.set_health(p.hp)
	NetSession.feedback(id, "message", [Inventory.MUSHROOMS[kind].name + " gegessen", 2.0])
	if id == 1: game.inventory._refresh()

func check_team() -> void:
	if not NetSession.is_host() or NetSession.phase != "running": return
	if nearest_player(Vector3.ZERO) == null:
		NetSession.phase = "over"
		game.over = true
		NetSession._send_lobby()
		for id in NetSession.ready_peers:
			if id != 1 and NetSession.ready_peers[id]: NetSession._world_state.rpc_id(id, NetSession.epoch, NetSession._sequence, snapshot(), false)
		_show_game_over()

func _show_game_over() -> void:
	_close_local_menus()
	game.over = true
	game.player.active = false
	game.hud.show_overlay("TEAM AUSGESCHIEDEN", "Alle Spieler sind ausgeschieden. Der Host kann eine neue Runde starten.", "Neue Runde" if NetSession.is_host() else "Warte auf Host", "", "over")
	game.hud.overlay_button.disabled = NetSession.is_client()
	game.stats.finish(game.player.score, game.waves.completed, "Koop · " + str(game.difficulty.name))

func _close_local_menus() -> void:
	for menu in [game.skills, game.inventory, game.barricade_menu]:
		if menu.is_open: menu.close()
	game.get_tree().paused = false

func tick(delta: float) -> void:
	if NetSession.is_host():
		for id in avatars: avatars[id].set_weapon(weapons[id].current)
		for id in rage:
			if rage[id] > 0:
				rage[id] = maxf(0, rage[id] - delta)
				if rage[id] == 0: weapons[id].damage_mul = 1.0 + 0.12 * levels[id].get("damage", 0)
		for id in revive.keys():
			var target: Player = actor(revive[id].target)
			var p: Player = actor(id)
			if not p or not p.alive or not target or target.alive or p.global_position.distance_to(target.global_position) > 2.5 or not _visible(p, target.global_position + Vector3.UP):
				revive.erase(id)
				continue
			revive[id].time += delta
			if revive[id].time >= 3.0:
				target.hp = minf(target.max_hp, 50.0)
				target.alive = true
				target.active = true
				target.regen_timer = 5.0
				revive.erase(id)
		if not game.player.active and game.player.alive: game.player._regenerate(delta)
	else:
		for id in move_targets:
			if not actors.has(id): continue
			var p: Player = actors[id]
			var target: Array = move_targets[id]
			p.global_position = p.global_position.lerp(target[0], 1.0-exp(-delta*16.0))
			p.rotation.y = lerp_angle(p.rotation.y, target[1], 1.0-exp(-delta*16.0))
			p.head.rotation.x = p.pitch
		game.day_night.advance(delta)
	_update_local_life()

func nearby_downed_player() -> int:
	for id in actors:
		if id == NetSession.local_id() or actor(id).alive: continue
		if actor(id).global_position.distance_to(game.player.global_position) < 2.5 and _visible(game.player, actor(id).global_position + Vector3.UP):
			return id
	return 0

func _update_local_life() -> void:
	if not game.player.alive and not local_dead:
		local_dead = true
		_close_local_menus()
		game.player.active = false
		game.weapons.viewmodel.hide()
		game.hud.message("Du bist ausgeschieden. Ein Mitspieler kann dich mit E wiederbeleben.", 60.0)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif game.player.alive and local_dead:
		local_dead = false
		game.player.active = true
		game.weapons.viewmodel.show()
		game.hud.set_health(game.player.hp)
		game.hud.message("Wiederbelebt!", 2.0)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func show_shot(id: int, weapon: String) -> void:
	if avatars.has(id): avatars[id].shot(weapon)

func track_grenade(grenade: Node3D) -> void:
	grenade.set_meta("coop_id", next_id)
	grenades[next_id] = grenade
	next_id += 1

func show_explosion(position: Vector3) -> void:
	var grenade := Grenade.new()
	grenade.replica = true
	grenade.setup(null, game.zombies_root, game.player)
	game.add_child(grenade)
	grenade.global_position = position
	grenade._explode()

func _entity_id(node: Node) -> int:
	if not node.has_meta("coop_id"):
		node.set_meta("coop_id", next_id)
		next_id += 1
	return int(node.get_meta("coop_id"))

func snapshot() -> Dictionary:
	var players := {}
	for id in actors:
		var p: Player = actor(id)
		var w: Weapons = weapons[id]
		var ammo := {}
		for wid in w.state:
			var s: Dictionary = w.state[wid]
			ammo[wid] = [s.ammo, s.reserve, s.reloading]
		players[id] = {"p": p.global_position, "yaw": p.rotation.y, "pitch": p.pitch, "v": p.velocity,
			"hp": p.hp, "max_hp": p.max_hp, "alive": p.alive, "score": p.score, "speed": p.speed_mul, "regen": p.regen_mul,
			"light": p.flashlight.visible, "weapon": w.current, "ammo": ammo, "unlocked": w.unlocked.duplicate(),
			"grenades": w.grenades, "grenades_max": w.grenades_max, "mods": [w.damage_mul, w.reload_mul, w.spread_mul],
			"levels": levels[id].duplicate(), "mushrooms": mushrooms[id].duplicate(), "ack": NetSession._commands.get(id, 0)}
	var zs := {}
	for z in game.zombies_root.get_children():
		if not z is Zombie: continue
		zs[_entity_id(z)] = [z.net_kind, z.global_position, z.rotation.y, z.hp, z.alive, z.state, z.speed_mul]
	var gs := {}
	for id in grenades.keys():
		var g = grenades[id]
		if not is_instance_valid(g):
			grenades.erase(id)
			continue
		gs[id] = [g.global_position, g.rotation]
	var ds := {}
	for child in game.get_children():
		if child is Pickup and not child._taken:
			ds[_entity_id(child)] = [child.kind, child.global_position, child._t]
	var available: Array = []
	var door_states := {}
	var key_positions := {}
	for key in loot_nodes:
		var node = loot_nodes[key]
		if not is_instance_valid(node): continue
		if node is Door:
			door_states[key] = [node.is_open, node._open_side]
		elif not node.taken:
			available.append(key)
			if node is ForestKey: key_positions[key] = node.global_position
	var bars: Array = []
	for b in game.barricades: bars.append([b.level, b.hp])
	var intact: Array = []
	for id in broken_nodes:
		if is_instance_valid(broken_nodes[id]): intact.append(id)
	var animals: Array = []
	for d in deer: animals.append([d.global_position, d.rotation, d.state])
	return {"players": players, "zombies": zs, "grenades": gs, "drops": ds, "loots": available, "doors": door_states,
		"keys": game.forest_keys.owned.duplicate(), "key_positions": key_positions, "bars": bars, "intact": intact, "deer": animals,
		"time": game.day_night.clock_seconds, "phase": NetSession.phase,
		"difficulty": game.settings.difficulty,
		"wave": [game.waves.wave, game.waves.completed, game.waves.phase, game.waves.timer, game.waves.total, game.alive_zombies()+game.waves.queue.size()],
		"stats": [game.stats.kills, game.stats.headshots, game.stats.shots, game.stats.hits, game.stats.seconds, game.stats.best_streak, game.stats.grenades_thrown, game.stats.melee_hits, game.stats.barricades_built, game.stats.mushrooms_eaten, game.stats.damage_taken, game.stats.points_earned],
		"achievements": [game.achievements.counters.duplicate(), game.achievements.session_unlocked.duplicate()]}

func apply_snapshot(data: Dictionary, initial: bool) -> void:
	if not NetSession.is_client(): return
	game.difficulty = GameSettings.DIFFICULTIES[int(data.difficulty)]
	if initial: game.hud._mark_difficulty(int(data.difficulty))
	for id in data.players:
		add_player(id)
		var p: Player = actor(id)
		var s: Dictionary = data.players[id]
		p.hp = s.hp
		p.max_hp = s.max_hp
		p.alive = s.alive
		p.score = s.score
		p.speed_mul = s.speed
		p.regen_mul = s.regen
		if id != NetSession.local_id():
			p.velocity = s.v
			p.pitch = s.pitch
			p.flashlight.visible = s.light
			if initial: p.global_position = s.p
			move_targets[id] = [s.p, s.yaw]
			avatars[id].set_weapon(s.weapon)
		else:
			if initial or p.global_position.distance_to(s.p) > 1.8:
				p.global_position = s.p
				p.velocity = Vector3.ZERO
			if initial:
				p.rotation.y = s.yaw
				p.pitch = s.pitch
			game.hud.hp_bar.max_value = p.max_hp
			game.hud.set_health(p.hp)
			game.hud.set_score(p.score)
			if initial or int(s.ack) >= NetSession._command_seq:
				var w: Weapons = game.weapons
				var inventory_changed: bool = w.unlocked != s.unlocked or game.inventory.mushrooms != s.mushrooms or w.grenades != s.grenades
				w.unlocked = s.unlocked.duplicate()
				w.network_apply = true
				w.set_weapon(s.weapon)
				w.network_apply = false
				for wid in s.ammo:
					if w.state[wid].ammo != s.ammo[wid][0] or w.state[wid].reserve != s.ammo[wid][1]: inventory_changed = true
					w.state[wid].ammo = s.ammo[wid][0]
					w.state[wid].reserve = s.ammo[wid][1]
					w.state[wid].reloading = s.ammo[wid][2]
				w.grenades = s.grenades
				w.grenades_max = s.grenades_max
				w.damage_mul = s.mods[0]
				w.reload_mul = s.mods[1]
				w.spread_mul = s.mods[2]
				w.update_hud()
				game.skills.levels = s.levels.duplicate()
				game.inventory.mushrooms = s.mushrooms.duplicate()
				if game.skills.is_open: game.skills._refresh()
				if game.inventory.is_open and inventory_changed: game.inventory._refresh()
	for id in zombies.keys():
		if not data.zombies.has(id):
			if is_instance_valid(zombies[id]):
				if is_instance_valid(zombies[id]._pool): zombies[id]._pool.queue_free()
				zombies[id].queue_free()
			zombies.erase(id)
	game._alive_count = 0
	for id in data.zombies:
		var s: Array = data.zombies[id]
		if not zombies.has(id):
			var z := Zombie.new()
			z.replica = true
			z.setup(s[0], game.player, game.barricades, s[6], Callable())
			game.zombies_root.add_child(z)
			z.global_position = s[1]
			zombies[id] = z
		var z: Zombie = zombies[id]
		z.net_position = s[1]
		z.net_yaw = s[2]
		if z.hp > float(s[3]): z._flash()
		z.hp = s[3]
		if not s[4] and z.alive: z.die(Vector3.ZERO)
		if z.alive:
			game._alive_count += 1
			if z.state != s[5]: z.play(s[5])
	for id in grenades.keys():
		if not data.grenades.has(id):
			if is_instance_valid(grenades[id]): grenades[id].queue_free()
			grenades.erase(id)
	for id in data.grenades:
		if not grenades.has(id):
			var g := Grenade.new()
			g.replica = true
			g.setup(load("res://assets/models/grenade.glb"), game.zombies_root, game.player)
			game.add_child(g)
			grenades[id] = g
		grenades[id].global_position = data.grenades[id][0]
		grenades[id].rotation = data.grenades[id][1]
	for id in drops.keys():
		if not data.drops.has(id):
			if is_instance_valid(drops[id]): drops[id].queue_free()
			drops.erase(id)
	for id in data.drops:
		if not drops.has(id) or not is_instance_valid(drops[id]):
			var drop := Pickup.new()
			drop.setup(data.drops[id][0])
			game.add_child(drop)
			drops[id] = drop
		drops[id].global_position = data.drops[id][1]
		drops[id]._t = data.drops[id][2]
	var keys_changed: bool = game.forest_keys.owned != data["keys"]
	game.forest_keys.owned = data["keys"].duplicate()
	if keys_changed and game.inventory.is_open: game.inventory._refresh()
	for key in loot_nodes:
		var node = loot_nodes[key]
		if not is_instance_valid(node): continue
		if node is Door:
			if data.doors.has(key) and node.is_open != data.doors[key][0]:
				node._open_side = data.doors[key][1]
				node._set_open(data.doors[key][0])
		elif not key in data.loots:
			node.taken = true
			if node is ForestKey: node.pickup_visual.hide()
			else:
				node.hide()
				node.queue_free()
		elif node is ForestKey and data.key_positions.has(key): node.global_position = data.key_positions[key]
	for i in game.barricades.size():
		var b: Barricade = game.barricades[i]
		var changed: bool = b.level != data.bars[i][0] or b.hp != data.bars[i][1]
		var rebuild: bool = b.level != data.bars[i][0]
		if b.level > 0 and data.bars[i][0] == 0:
			Sfx.play_at(game, "barricade_break", b.center, 0.0)
			game.hud.message("Barrikade %s durchbrochen!" % b.slot.name, 2.0)
		b.level = data.bars[i][0]
		b.hp = data.bars[i][1]
		if changed:
			if rebuild: b.rebuild()
			b.changed.emit()
	for id in broken_nodes:
		if not id in data.intact and is_instance_valid(broken_nodes[id]): broken_nodes[id].shatter()
	for i in mini(deer.size(), data.deer.size()):
		deer[i].global_position = data.deer[i][0]
		deer[i].rotation = data.deer[i][1]
		deer[i].state = data.deer[i][2]
	game.day_night.clock_seconds = data.time
	game.waves.wave = data.wave[0]
	game.waves.completed = data.wave[1]
	game.waves.phase = data.wave[2]
	game.waves.timer = data.wave[3]
	game.waves.total = data.wave[4]
	game.hud.set_wave(data.wave[0] if data.wave[2] != "idle" else data.wave[0]+1, "%d übrig" % data.wave[5] if data.wave[2] != "idle" else "Start in %d s · Host startet die nächste Welle" % ceili(data.wave[3]))
	game.hud.set_wave_progress(data.wave[5], data.wave[4])
	if current_wave != data.wave[0]:
		current_wave = data.wave[0]
		game.hud.message("Welle %d" % current_wave, 2.0)
		if game.music: game.music.play("combat")
	game.stats.kills = data.stats[0]
	game.stats.headshots = data.stats[1]
	game.stats.shots = data.stats[2]
	game.stats.hits = data.stats[3]
	game.stats.seconds = data.stats[4]
	game.stats.best_streak = data.stats[5]
	game.stats.grenades_thrown = data.stats[6]
	game.stats.melee_hits = data.stats[7]
	game.stats.barricades_built = data.stats[8]
	game.stats.mushrooms_eaten = data.stats[9]
	game.stats.damage_taken = data.stats[10]
	game.stats.points_earned = data.stats[11]
	game.achievements.counters = data.achievements[0].duplicate()
	var previous_achievements: int = game.achievements.unlocked.size()
	game.achievements.unlocked.merge(data.achievements[1], true)
	if game.achievements.unlocked.size() != previous_achievements: game.achievements._save()
	state_loaded = true
	_update_local_life()
	if data.phase == "over" and not game.over:
		NetSession.phase = "over"
		_show_game_over()

func wave_started(number: int) -> void:
	if number == 3:
		for w: Weapons in weapons.values(): w.unlock("shotgun")

func wave_cleared(bonus: int) -> void:
	for id in actors:
		var p: Player = actor(id)
		if id != 1:
			p.add_score(bonus)
			weapons[id].refill_all()
		if not p.alive:
			p.alive = true
			p.hp = p.max_hp
			p.active = true
		NetSession.feedback(id, "message", ["Welle überstanden · Munition aufgefüllt · +%d Punkte" % bonus, 3.0])
