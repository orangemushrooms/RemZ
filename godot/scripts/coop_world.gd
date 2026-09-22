extends RefCounted

var game: Node3D
var actors: Dictionary = {}
var weapons: Dictionary = {}
var avatars: Dictionary = {}
var levels: Dictionary = {}
var mushrooms: Dictionary = {}
var pose_times: Dictionary = {}
var pose_acks: Dictionary = {}
var movement_sync = preload("res://scripts/movement_sync.gd").new()
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
var intro_lock := 0.0

func prepare_intro() -> void:
	game.waves.phase = "intro"
	intro_lock = Intro.LOGO_IN + Intro.LOGO_HOLD + Intro.LOGO_OUT
	var ids: Array = actors.keys()
	ids.sort()
	for index in ids.size():
		var p: Player = actor(ids[index])
		p.global_position = Intro.start_position(index)
		p.velocity = Vector3.ZERO
		p.rotation.y = Intro.START_YAW
		p.pitch = 0.0
		p.head.rotation.x = 0.0
		pose_times[ids[index]] = NetSession._elapsed

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
		mushrooms[id] = Inventory.Mushrooms.empty_stock()
		var avatar = preload("res://scripts/coop_avatar.gd").new()
		p.add_child(avatar)
		avatar.setup(p, NetSession.roster.get(id, "Spieler"), actors.size())
		avatars[id] = avatar
	p.peer_id = id
	actors[id] = p
	weapons[id] = w
	pose_times[id] = NetSession._elapsed
	game.progression.data(id)
	if NetSession.is_host(): game.stats.register_player(id, NetSession.roster.get(id, "Spieler"))

func spawn_position(index: int) -> Vector3:
	var point: Vector3 = Map.ground_pos(Map.PLAYER_START.x + index * 1.3, Map.PLAYER_START.y + 1.0)
	if game.started:
		var near: Player = nearest_player(game.player.global_position)
		if near: point = near.global_position + Vector3(1.5, 0.3, 1.5)
	var nav: RID = game.nav_region.get_navigation_map()
	return NavigationServer3D.map_get_closest_point(nav, point) + Vector3.UP * 0.3

func remove_player(id: int) -> void:
	if NetSession.is_host() and game.stats.players.has(id):
		if is_instance_valid(actor(id)): game.stats.update_live(id, actor(id).score, -1)
		game.stats.players[id].connected = false
		game.stats.players[id].ping_ms = -1
	if NetSession.is_host():
		for tower: DefenceTower in game.defences.towers.values():
			if tower.operator_peer == id: game.defences.release_tower(tower)
			if tower.owner_peer == id: tower.owner_peer = 1
	if actors.has(id) and is_instance_valid(actors[id]) and actors[id] != game.player:
		actors[id].hud.queue_free()
		actors[id].queue_free()
	for dict in [actors, weapons, avatars, levels, mushrooms, pose_times, pose_acks, move_targets, revive]: dict.erase(id)

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

func move_player(id: int, position: Vector3, yaw: float, pitch: float, light: bool, motion: Vector3, now: float, sequence: int = 0, crouching: bool = false) -> void:
	if sequence > 0:
		if sequence <= int(pose_acks.get(id, 0)): return
		pose_acks[id] = sequence
	if intro_lock > 0.0: return
	var p: Player = actor(id)
	if not p or not p.alive: return
	if p.mounted_tower: return
	var dt := clampf(now - float(pose_times.get(id, now)), 0.01, 0.5)
	pose_times[id] = now
	p.set_crouching(crouching)
	var move := position - p.global_position
	var max_distance := (Player.CROUCH_SPEED if p.crouching else Player.SPRINT_SPEED) * p.effective_speed_mul() * dt + 0.7
	if Vector2(move.x, move.z).length() > max_distance or absf(move.y) > 16.0 * dt + 1.2: return
	if not Map.BOUNDS.has_point(Vector2(position.x, position.z)): return
	# Sweep the same capsule against terrain, buildings and barricades.
	# A floor contact must not discard the horizontal remainder of a step.
	# In particular, down-slope movement often touches terrain before its end.
	for slide in 4:
		if move.length_squared() < 0.000001: break
		var collision := p.move_and_collide(move)
		if not collision: break
		move = collision.get_remainder().slide(collision.get_normal())
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
	if intro_lock > 0.0: return
	var p: Player = actor(id)
	if not p or not p.alive: return
	var w: Weapons = weapons[id]
	match operation:
		"hunting":
			if args.size() != 2 or not args[0] is String or not args[1] is int: return
			NetSession.feedback(id, "message", [game.hunting.transact(p, args[0], args[1]), 2.5])
		"firework":
			if args.size() != 3 or not args[0] is String or not _aim(p, args, 1): return
			var error: String = game.fireworks.ignite(p, args[0])
			if not error.is_empty(): NetSession.feedback(id, "message", [error, 2.0])
		"drop_cash":
			if not args.is_empty(): return
			var message := Pickup.throw_cash(p)
			if not message.is_empty(): NetSession.feedback(id, "message", [message, 1.4])
		"rare_equip":
			if args.size() != 1 or not args[0] is String or args[0].length() > 40: return
			NetSession.feedback(id, "message", [game.progression.rare_market.equip(p, args[0]), 2.0])
		"shop":
			if args.size() != 4: return
			for argument in args:
				if not argument is String or argument.length() > 80: return
			var before: int = p.score
			var result: String = game.progression.transact(p, args[0], args[1], args[2], args[3])
			NetSession.feedback(id, "trade", [result, p.score - before])
		"tower_rotate":
			if args.size() != 2 or not args[0] is int or not args[1] is float or not is_finite(args[1]): return
			var error: String = game.defences.rotate_tower(p, args[0], args[1])
			if not error.is_empty(): NetSession.feedback(id, "message", [error, 2.0])
		"tower_place":
			if args.size() not in [1, 2, 3] or not args[0] is Vector3 or not args[0].is_finite(): return
			if args.size() >= 2 and (not args[1] is float or not is_finite(args[1])): return
			if args.size() == 3 and not args[2] is String: return
			var error: String = game.defences.purchase(p, args[0], float(args[1]) if args.size() >= 2 else 0.0, str(args[2]) if args.size()==3 else "standard")
			if not error.is_empty(): NetSession.feedback(id, "message", [error, 2.0])
		"tower_mount":
			if args.size()!=1 or not args[0] is int: return
			var error: String = game.defences.mount(p,args[0])
			if not error.is_empty(): NetSession.feedback(id,"message",[error,2.0])
		"tower_exit":
			if args.is_empty() and game.defences.towers.has(p.mounted_tower): game.defences.release_tower(game.defences.towers[p.mounted_tower])
		"tower_control":
			if args.size()!=5 or not args[0] is int or not args[1] is float or not args[2] is float or not args[3] is bool or not args[4] is bool: return
			game.defences.control(p,args[0],args[1],args[2],args[3],args[4])
		"tower_upgrade", "tower_repair", "tower_sell":
			if args.size() != 1 or not args[0] is int: return
			var error: String = game.defences.maintain(p, args[0], operation.trim_prefix("tower_"))
			if not error.is_empty(): NetSession.feedback(id, "message", [error, 2.0])
		"hut_repair":
			if not game.hut: return
			var error: String = game.hut.repair(p)
			if not error.is_empty(): NetSession.feedback(id, "message", [error, 2.0])
		"fire":
			if args.size() != 4 or not args[0] is String or not args[1] is float or not is_finite(args[1]) or not _aim(p, args, 2): return
			if w.current != args[0]: w.set_weapon(args[0])
			if w.current != args[0]: return
			w.ads = clampf(args[1], 0, 1)
			w.try_fire()
		"weapon":
			if args.size() == 1 and args[0] is String: w.set_weapon(args[0])
		"reload": w.reload()
		"melee":
			if _aim(p, args, 0): w.melee(args.size() == 3 and args[2] is bool and args[2])
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
	elif item.kind == "maze_cache":
		if not item.grant_cache(p,w): return
	elif item.kind == "mushroom":
		mushrooms[id][item.id] = int(mushrooms[id].get(item.id, 0)) + 1
		if item.id == "steinpilz": game.progression.event("edible_mushrooms")
		NetSession.feedback(id, "message", [item.label + " gesammelt", 1.5])
		game.achievements.event("mushrooms")
	else:
		if not item.grant_supplies(w, p.hud): return
	item.taken = true
	Sfx.event(game, id, "key_pickup" if item is ForestKey else "mushroom_pickup" if item.kind == "mushroom" else "pickup")
	if item is ForestKey:
		item.pickup_visual.hide()
	else:
		item.hide()
		if not (item is Loot and item.renewable): item.queue_free()
	w.update_hud()

func collect_drop(drop: Pickup, id: int) -> void:
	if not NetSession.is_host() or drop._taken or not actors.has(id): return
	var p: Player = actor(id)
	if not p.alive or p.global_position.distance_to(drop.global_position) > 2.3: return
	var w: Weapons = weapons[id]
	if not drop.can_collect(p, w): return
	drop._taken = true
	match drop.kind:
		"cash": p.add_score(drop.amount)
		"ammo": w.add_ammo(w.ammo_weapon(), int(Weapons.DEFS[w.ammo_weapon()].mag))
		"grenade": w.grenades = mini(w.grenades_max, w.grenades + 1)
		_: p.hp = minf(p.max_hp, p.hp + 30.0)
	w.update_hud()
	p.hud.set_health(p.hp)
	NetSession.feedback(id, "message", ["+%d R aufgenommen" % drop.amount if drop.kind == "cash" else "Vorrat aufgenommen", 1.4])
	Sfx.event(game, id, "pickup")
	if drop.kind != "cash": game.achievements.event("drops")
	drop.queue_free()

func buy_upgrade(id: int, key: String) -> void:
	# Legacy command still validates merchant proximity and never unlocks a weapon.
	var trainee: Player = actor(id)
	var before: int = trainee.score
	var result: String = game.progression.transact(trainee, "mechanic", "training", key)
	NetSession.feedback(id, "trade", [result, trainee.score - before])

func eat(id: int, kind: String) -> void:
	if not NetSession.is_host() or not actors.has(id) or not mushrooms.has(id): return
	var p: Player = actor(id)
	var error := Inventory.Mushrooms.consume(p, mushrooms[id], kind)
	if not error.is_empty():
		NetSession.feedback(id, "message", [error, 2.0])
		return
	if kind == "fliegenpilz": game.achievements.event("rausch")
	game.stats.mushrooms_eaten += 1
	p.hud.set_health(p.hp)
	Sfx.event(game, id, "consume")
	NetSession.feedback(id, "message", ["%s: %s" % [Inventory.MUSHROOMS[kind].name, Inventory.MUSHROOMS[kind].text], 3.0])
	if id == 1: game.inventory._refresh()

func check_team() -> void:
	if not NetSession.is_host() or NetSession.phase != "running": return
	if nearest_player(Vector3.ZERO) == null:
		NetSession.phase = "over"
		game.over = true
		NetSession._send_lobby()
		NetSession._sequence += 1
		for id in NetSession.ready_peers:
			if id != 1 and NetSession.ready_peers[id]: NetSession.send_reliable_state(id, false)
		_show_game_over()

# the Waldhütte fell (host only): the whole team loses the round
func hut_lost() -> void:
	if not NetSession.is_host() or NetSession.phase != "running": return
	NetSession.phase = "over"
	game.over = true
	NetSession._send_lobby()
	NetSession._sequence += 1
	for id in NetSession.ready_peers:
		if id != 1 and NetSession.ready_peers[id]: NetSession.send_reliable_state(id, false)
	_show_game_over()

func _show_game_over() -> void:
	_close_local_menus()
	game.over = true
	game.player.active = false
	var hut_fell: bool = game.hut != null and game.hut.destroyed
	game.hud.show_overlay("HÜTTE VERLOREN" if hut_fell else "TEAM AUSGESCHIEDEN", ("Die Waldhütte ist zerstört." if hut_fell else "Alle Spieler sind ausgeschieden.") + " Der Host kann eine neue Runde starten.", "Neue Runde" if NetSession.is_host() else "Warte auf Host", "", "over")
	game.hud.overlay_button.disabled = NetSession.is_client()
	game.stats.finish(game.player.score, game.waves.completed, "Koop · " + str(game.difficulty.name))

func _close_local_menus() -> void:
	game.defences.cancel_placement()
	for menu in [game.skills, game.inventory, game.barricade_menu, game.defences, game.progression, game.cheat_menu]:
		if menu.is_open: menu.close()
	game.get_tree().paused = false

func tick(delta: float) -> void:
	if NetSession.is_host():
		intro_lock = maxf(0.0, intro_lock - delta)
		# Any teammate can reach the junction; only the host releases wave one.
		if intro_lock == 0.0 and game.waves.phase == "intro" and game.waves.wave == 0:
			for p: Player in actors.values():
				if p.alive and game.intro.distance_to_road(p.global_position) < 5.0:
					game.waves.start(1)
					break
		for id in avatars:
			avatars[id].set_weapon(weapons[id].current)
			avatars[id].set_mods(weapons[id].mod_loadout.get(weapons[id].current, {}))
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

func show_shot(id: int, weapon: String, mod_effects: Array = []) -> void:
	if avatars.has(id): avatars[id].shot(weapon, mod_effects)

func track_grenade(grenade: Node3D) -> void:
	grenade.set_meta("coop_id", next_id)
	grenades[next_id] = grenade
	next_id += 1

func show_flare(position: Vector3) -> void:
	if game.weapons.specials: game.weapons.specials.plant_flare(position)

# The graviton cannon, drawn the same way for everyone who can see it.
func show_blast(position: Vector3) -> void:
	WeaponSpecials.blast_visuals(game, position)

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

func refresh_leaderboard() -> void:
	if not NetSession.is_host(): return
	for id in actors:
		game.stats.update_live(id, actor(id).score, NetSession.peer_ping(id))

func snapshot() -> Dictionary:
	refresh_leaderboard()
	var players := {}
	for id in actors:
		var p: Player = actor(id)
		var w: Weapons = weapons[id]
		var ammo := {}
		var specials := {}
		for wid in w.state:
			var s: Dictionary = w.state[wid]
			ammo[wid] = [s.ammo, s.reserve, s.reloading]
			var extra := WeaponSpecials.net_state(w, wid)
			if not extra.is_empty(): specials[wid] = extra
		players[id] = {"p": p.global_position, "yaw": p.rotation.y, "pitch": p.pitch, "v": p.velocity, "crouch": p.crouching, "tower": p.mounted_tower,
			"hp": p.hp, "max_hp": p.max_hp, "alive": p.alive, "score": p.score, "speed": p.speed_mul, "regen": p.regen_mul, "effects": p.mushroom_effects.duplicate(),
			"relic": p.relic, "light": p.flashlight.visible, "weapon": w.current, "ammo": ammo, "unlocked": w.unlocked.duplicate(), "skins": w.skins.duplicate(), "mod_owned": w.mod_owned.duplicate(true), "mod_loadout": w.mod_loadout.duplicate(true),
			"grenades": w.grenades, "grenades_max": w.grenades_max, "mods": [w.damage_mul, w.reload_mul, w.spread_mul],
			"levels": levels[id].duplicate(), "mushrooms": mushrooms[id].duplicate(), "ack": NetSession._commands.get(id, 0), "pose_ack": pose_acks.get(id, 0),
			"specials": specials}
	var zs := {}
	for z in game.zombies_root.get_children():
		if not z is Zombie: continue
		zs[_entity_id(z)] = [z.net_kind, z.global_position, z.rotation.y, z.hp, z.alive, z.state, z.speed_mul, z.max_hp, z.boss_state() if z is Titan else [], z.model_path, z.appearance_seed, z.height, z.rare_status]
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
			ds[_entity_id(child)] = [child.kind, child.global_position, child._t, child.amount, child.owner_peer]
	var available: Array = []
	var door_states := {}
	var key_positions := {}
	var mushroom_positions := {}
	var maze_caches := {}
	for key in loot_nodes:
		var node = loot_nodes[key]
		if not is_instance_valid(node): continue
		if node is Loot and node.kind == "maze_cache":
			maze_caches[key] = [node.stocked_wave, node.cache_respawn_wave]
		if node is Door:
			door_states[key] = [node.is_open, node._open_side]
		elif not node.taken:
			available.append(key)
			if node is ForestKey: key_positions[key] = node.global_position
			if node is Loot and node.id == "goldroehrling": mushroom_positions[key] = node.global_position
	var bars: Array = []
	for b in game.barricades: bars.append([b.level, b.hp, b.attack_alert_remaining])
	var intact: Array = []
	for id in broken_nodes:
		if is_instance_valid(broken_nodes[id]): intact.append(id)
	var animals: Array = []
	for d in deer: animals.append([d.global_position, d.rotation, d.state])
	var pumpkin_states: Array = []
	for pumpkin in game.pumpkins: pumpkin_states.append(pumpkin.broken)
	return {"maze_caches": maze_caches, "hunting": game.hunting.snapshot(), "leaderboard": game.stats.players.duplicate(true), "fireworks": game.fireworks.snapshot(), "pumpkins": pumpkin_states, "progression": game.progression.snapshot(), "players": players, "zombies": zs, "towers": game.defences.snapshot(), "grenades": gs, "drops": ds, "loots": available, "doors": door_states,
		"hut": [game.hut.hp, game.hut.attack_alert_remaining, game.hut.destroyed] if game.hut else [],
		"keys": game.forest_keys.owned.duplicate(), "key_positions": key_positions, "mushroom_positions": mushroom_positions, "bars": bars, "intact": intact, "deer": animals,
		"time": game.day_night.clock_seconds, "phase": NetSession.phase,
		"difficulty": game.settings.difficulty,
		"wave": [game.waves.wave, game.waves.completed, game.waves.phase, game.waves.timer, game.waves.total, game.alive_zombies()+game.waves.queue.size()],
		"stats": [game.stats.kills, game.stats.headshots, game.stats.shots, game.stats.hits, game.stats.seconds, game.stats.best_streak, game.stats.grenades_thrown, game.stats.melee_hits, game.stats.barricades_built, game.stats.mushrooms_eaten, game.stats.damage_taken, game.stats.points_earned],
		"achievements": [game.achievements.counters.duplicate(), game.achievements.session_unlocked.duplicate()]}

func _apply_drops(states: Dictionary) -> void:
	for id in drops.keys():
		if not states.has(id):
			if is_instance_valid(drops[id]): drops[id].queue_free()
			drops.erase(id)
	for id in states:
		if not drops.has(id) or not is_instance_valid(drops[id]):
			var drop := Pickup.new()
			drop.amount = int(states[id][3])
			drop.owner_peer = int(states[id][4])
			drop.setup(states[id][0])
			game.add_child(drop)
			drops[id] = drop
		drops[id].global_position = states[id][1]
		drops[id]._t = states[id][2]

func apply_snapshot(data: Dictionary, initial: bool) -> void:
	if not NetSession.is_client(): return
	var pumpkin_states: Array = data.get("pumpkins", [])
	for i in mini(pumpkin_states.size(), game.pumpkins.size()):
		if pumpkin_states[i]: game.pumpkins[i].shatter(not initial)
	if initial: NetSession.trace_load("STATE_STAGE structures")
	game.defences.apply_snapshot(data.get("towers", {}), initial)
	game.progression.apply_snapshot(data.get("progression", {}), initial)
	game.fireworks.apply_snapshot(data.get("fireworks", {}))
	game.hunting.apply_snapshot(data.get("hunting", {}))
	game.difficulty = GameSettings.DIFFICULTIES[int(data.difficulty)]
	if initial: game.hud._mark_difficulty(int(data.difficulty))
	if initial: NetSession.trace_load("STATE_STAGE players")
	for id in data.players:
		add_player(id)
		var p: Player = actor(id)
		var s: Dictionary = data.players[id]
		p.hp = s.hp
		p.max_hp = s.max_hp
		p.alive = s.alive
		var previous_tower := p.mounted_tower
		p.mounted_tower = int(s.get("tower",0))
		if previous_tower!=p.mounted_tower:
			p.set_crouching(p.mounted_tower!=0,false)
			p.head.position.y = Player.CROUCH_EYE if p.mounted_tower else Player.EYE
		p.score = s.score
		p.speed_mul = s.speed
		p.regen_mul = s.regen
		p.mushroom_effects = s.get("effects", {}).duplicate()
		if id != NetSession.local_id():
			p.set_crouching(bool(s.get("crouch", false)), false)
			p.velocity = s.v
			p.pitch = s.pitch
			p.flashlight.visible = s.light
			if initial: p.global_position = s.p
			move_targets[id] = [s.p, s.yaw]
			avatars[id].set_weapon(s.weapon)
			avatars[id].set_mods(s.get("mod_loadout", {}).get(s.weapon, {}))
			avatars[id].set_skin(str(s.get("skins", {}).get(s.weapon, "")))
		else:
			var previous_position := p.global_position
			p.global_position = movement_sync.reconcile(s.p, int(s.get("pose_ack", 0)), previous_position, initial or previous_tower!=p.mounted_tower)
			if p.mounted_tower and previous_tower!=p.mounted_tower:
				p.recoil_offset = Vector2.ZERO
				p.rotation.y = s.yaw
				p.pitch = s.pitch
				game.defences.input_grace = 0.25
			if initial or p.global_position.distance_to(previous_position) > 4.0:
				p.velocity = Vector3.ZERO
			if initial:
				p.rotation.y = s.yaw
				p.pitch = s.pitch
			game.hud.hp_bar.max_value = p.max_hp
			game.hud.set_health(p.hp)
			game.hud.set_score(p.score)
			p.relic = s.get("relic", "")
			# Barrel heat and spin-up are host truth and must not wait for the acknowledged block
			# below: while the trigger is held there is always an unacknowledged command in flight,
			# so that block never runs and an overheating weapon would look cold on the client.
			if game.weapons.specials:
				for wid in s.get("specials", {}):
					game.weapons.specials.apply_net_state(game.weapons, str(wid), s.specials[wid])
			if initial or int(s.ack) >= NetSession._command_seq:
				var w: Weapons = game.weapons
				var inventory_changed: bool = w.unlocked != s.unlocked or game.inventory.mushrooms != s.mushrooms or w.grenades != s.grenades
				inventory_changed = inventory_changed or w.mod_loadout != s.get("mod_loadout", {})
				w.apply_mod_snapshot(s.get("mod_owned", {}), s.get("mod_loadout", {}))
				w.unlocked = s.unlocked.duplicate()
				for wid in s.get("skins", {}): w.apply_skin(wid, s.skins[wid])
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
	if initial: NetSession.trace_load("STATE_STAGE enemies")
	for id in zombies.keys():
		if not data.zombies.has(id):
			if is_instance_valid(zombies[id]):
				if is_instance_valid(zombies[id]._pool): zombies[id]._pool.queue_free()
				zombies[id].queue_free()
			zombies.erase(id)
	game._alive_count = 0
	for id in data.zombies:
		var s: Array = data.zombies[id]
		var fresh := not zombies.has(id)
		if not zombies.has(id):
			var z: Zombie = Titan.new() if Zombie.is_titan_kind(s[0]) else Zombie.new()
			z.replica = true
			z.setup(s[0], game.player, game.barricades, s[6], Callable())
			z.model_path = s[9]
			z.appearance_seed = s[10]
			z.height = s[11]
			game.zombies_root.add_child(z)
			z.global_position = s[1]
			zombies[id] = z
		var z: Zombie = zombies[id]
		z.max_hp = s[7]
		z.rare_status = s[12] if s.size() > 12 else ""
		if z is Titan: z.apply_boss_state(s[8], initial or fresh)
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
	_apply_drops(data.drops)
	if initial: NetSession.trace_load("STATE_STAGE items")
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
		elif node is Loot and node.id == "goldroehrling":
			node.taken = not key in data.loots
			node.visible = not node.taken
			if not node.taken and data.get("mushroom_positions", {}).has(key):
				node.global_position = data.mushroom_positions[key]
		elif node is Loot and node.kind == "maze_cache":
			var cache_state: Array = data.get("maze_caches", {}).get(key, [0, -1])
			node.stocked_wave = int(cache_state[0])
			node.cache_respawn_wave = int(cache_state[1])
			node.update_cache_tier(node.stocked_wave)
			node.taken = not key in data.loots
			node.visible = not node.taken
		elif node is Loot and node.renewable:
			node.stocked_wave = int(data.wave[0])
			node.magazines = mini(4, 1 + maxi(0, node.stocked_wave - 1) / 4)
			node.taken = not key in data.loots
			node.visible = not node.taken
		elif not key in data.loots:
			node.taken = true
			if node is ForestKey: node.pickup_visual.hide()
			else:
				node.hide()
				node.queue_free()
		elif node is ForestKey and data.key_positions.has(key):
			node.global_position = data.key_positions[key]
			node.taken = false
			node.pickup_visual.show()
	if initial: NetSession.trace_load("STATE_STAGE barricades")
	for i in game.barricades.size():
		var b: Barricade = game.barricades[i]
		var changed: bool = b.level != data.bars[i][0] or b.hp != data.bars[i][1]
		var rebuild: bool = b.level != data.bars[i][0]
		if b.level > 0 and data.bars[i][0] == 0:
			Sfx.play_at(game, "barricade_break", b.center, 0.0)
			game.hud.message("Barrikade %s durchbrochen!" % b.slot.name, 2.0)
		b.level = data.bars[i][0]
		b.hp = data.bars[i][1]
		if data.bars[i].size() > 2:
			b.update_attack_alert(float(data.bars[i][2]), state_loaded)
		if changed:
			if rebuild: b.rebuild()
			b.changed.emit()
	if game.hut and data.get("hut", []).size() == 3:
		game.hut.hp = float(data.hut[0])
		game.hut.destroyed = bool(data.hut[2])
		game.hut.update_attack_alert(float(data.hut[1]), state_loaded)
	for id in broken_nodes:
		if not id in data.intact and is_instance_valid(broken_nodes[id]): broken_nodes[id].shatter()
	for i in mini(deer.size(), data.deer.size()):
		if deer[i].get_meta("hunted_dead", false): continue
		deer[i].global_position = data.deer[i][0]
		deer[i].rotation = data.deer[i][1]
		deer[i].state = data.deer[i][2]
	game.day_night.clock_seconds = data.time
	game.waves.wave = data.wave[0]
	game.waves.completed = data.wave[1]
	game.waves.phase = data.wave[2]
	game.waves.timer = data.wave[3]
	game.waves.total = data.wave[4]
	if data.wave[2] == "intro":
		game.hud.set_wave(1, "Erreiche den Weg zur Hütte")
	else:
		game.hud.set_wave(data.wave[0] if data.wave[2] != "idle" else data.wave[0]+1, "%d übrig" % data.wave[5] if data.wave[2] != "idle" else "Start in %d s · Host startet die nächste Welle" % ceili(data.wave[3]))
	game.hud.set_wave_progress(data.wave[5], data.wave[4])
	if current_wave != data.wave[0]:
		current_wave = data.wave[0]
		game.hud.message("Welle %d" % current_wave, 2.0)
		if game.music: game.music.play("combat")
	elif game.music and game.music.current == "combat" and data.wave[2] == "idle":
		# Clients follow the host into the pause and get the same daylight / night choice.
		game.music.play(game.music.intermission_track(game.day_night.clock_seconds / 3600.0) if game.day_night else "night")
	game.stats.kills = data.stats[0]
	game.stats.players = data.get("leaderboard", {}).duplicate(true)
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

func wave_started(_number: int) -> void:
	pass

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
		NetSession.feedback(id, "message", ["Welle überstanden · Pistolenreserve gesichert · +%d Rem Dollars" % bonus, 3.0])
