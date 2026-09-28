extends Node
## Authoritative gameplay events. A client receives only its own rewards over reliable host RPCs.
const Classes = preload("res://scripts/character_classes.gd")
var game: Node
var _serial := 0
var _received := 0
var _finished := false
var _last_wave := 0
var _quests: Dictionary = {}

func setup(main: Node) -> void:
	game = main
	CharacterProfile.context = "lobby" if NetSession.enabled else "main"
	CharacterProfile.match_class = ""
	game.player.class_combat.configure(CharacterProfile.loadout())

func begin() -> void:
	var build: Dictionary = NetSession.class_roster.get(NetSession.local_id(), CharacterProfile.loadout()) if NetSession.enabled else CharacterProfile.loadout()
	CharacterProfile.begin_match(str(build.id))
	if NetSession.is_host():
		for id in NetSession.world.actors:
			apply_build(NetSession.world.actor(id), NetSession.world.weapons[id], NetSession.class_roster.get(id, {}))
	else:
		apply_build(game.player, game.weapons, build)

func apply_build(actor: Node, weapons: Node, build: Dictionary) -> void:
	if build.is_empty(): return
	actor.class_combat.configure(build)
	weapons.refresh_class_magazines()
	actor.set_meta("class_mission_from_start", not game.started)

func _process(delta: float) -> void:
	if not game or not game.started or game.over: return
	var actors: Array = NetSession.world.actors.values() if NetSession.is_host() and NetSession.world else [game.player]
	for actor in actors:
		if not is_instance_valid(actor) or not actor.alive: continue
		var weapons: Node = NetSession.world.weapons.get(actor.peer_id) if NetSession.is_host() else game.weapons
		actor.class_combat.tick(delta, actor, weapons, game.zombies_root)
	if game.player.alive: CharacterProfile.add_stat("seconds", delta)

func _deliver(peer: int, kind: String, values: Array) -> void:
	if NetSession.is_client(): return
	_serial += 1
	if NetSession.is_host(): NetSession.feedback(peer, "class_reward", [_serial, kind, values])
	else: receive(_serial, kind, values)

func receive(serial: int, kind: String, values: Array) -> void:
	if serial <= _received: return
	_received = serial
	match kind:
		"kill":
			CharacterProfile.record_kill(bool(values[1]), bool(values[2]), NetSession.enabled, int(values[3]))
			CharacterProfile.add_xp(int(values[0]), "Boss kill" if values[2] else "Elite kill" if int(values[0]) >= 100 else "Zombie kill")
			if NetSession.is_client(): game.player.class_combat.killed(str(values[4]), bool(values[1]), float(values[5]))
		"quest": CharacterProfile.quest(str(values[0]), int(values[1]))
		"headshot": CharacterProfile.record_headshot()
		"achievement": CharacterProfile.unlock("world:" + str(values[0]), int(values[1]))
		"wave":
			CharacterProfile.add_stat("waves")
			CharacterProfile.add_xp(int(values[0]), "Wave survived")
			CharacterProfile.save()
		"death": CharacterProfile.add_stat("deaths"); CharacterProfile.save()
		"hurt":
			if NetSession.is_client(): game.player.class_combat.hurt(float(values[0]))
		"mission":
			CharacterProfile.add_stat("missions")
			if NetSession.enabled: CharacterProfile.add_stat("multiplayer_missions")
			CharacterProfile.add_xp(2000, "Mission completed")
			if bool(values[0]): CharacterProfile.unlock("untouchable", 2000)
			CharacterProfile.save()
		"objective": CharacterProfile.add_xp(int(values[0]), "Team objective completed"); CharacterProfile.save()
		"cosmetic": CharacterProfile.data.cosmetics[str(values[0])] = true; CharacterProfile.dirty = true; CharacterProfile.save()

func killed(enemy: Node3D) -> void:
	if NetSession.is_client() or enemy.replica or not game.started or game.over: return
	var actor: Node3D = NetSession.world.actor(enemy.killer_peer) if NetSession.is_host() else game.player
	if not is_instance_valid(actor): return
	var boss: bool = enemy.is_boss_kind(enemy.net_kind)
	var elite: bool = boss or enemy.armored or enemy.net_kind not in ["shambler", "runner"]
	var xp := 500 if boss else 100 if elite else 15
	var distance := actor.global_position.distance_to(enemy.global_position)
	actor.class_combat.killed(enemy.killer_weapon, enemy.last_headshot, distance)
	if enemy.last_headshot and actor.class_combat.has("bounty") and actor.class_combat.specialist(enemy.killer_weapon): xp += 5
	_deliver(actor.peer_id, "kill", [xp, enemy.last_headshot, boss, actor.class_combat.streak, enemy.killer_weapon, distance])

func quest(peer: int, id: String, dollars: int) -> void:
	var token := "%d:%s" % [peer, id]
	if _quests.has(token): return
	_quests[token] = true
	_deliver(peer, "quest", [id, Classes.quest_xp(dollars)])

func achievement(id: String, dollars: int) -> void:
	for peer in peers(): _deliver(peer, "achievement", [id, maxi(250, dollars * 2)])

func peers() -> Array:
	if not NetSession.is_host() or not NetSession.world: return [1]
	var joined := []
	for id in NetSession.world.actors:
		if NetSession.class_roster.get(id, {}).get("locked", false) and NetSession.ready_peers.get(id, false): joined.append(id)
	return joined

func headshot(peer: int) -> void:
	_deliver(peer, "headshot", [])

func wave(number: int) -> void:
	if NetSession.is_client() or number <= _last_wave: return
	_last_wave = number
	for peer in peers(): _deliver(peer, "wave", [200 + number * 20])
	if number == 25:
		for peer in peers():
			var actor: Node = NetSession.world.actor(peer) if NetSession.is_host() else game.player
			_deliver(peer, "mission", [actor.get_meta("class_mission_from_start", false) and actor.class_combat.damage_taken <= 0.0 and game.settings.difficulty >= 2])

func objective(id: String, xp: int = 500) -> void:
	if NetSession.is_client() or _quests.has("team:" + id): return
	_quests["team:" + id] = true
	for peer in peers(): _deliver(peer, "objective", [xp])

func died(peer: int) -> void:
	_deliver(peer, "death", [])

func hurt(peer: int, amount: float) -> void:
	if NetSession.is_host(): _deliver(peer, "hurt", [amount])

func cosmetic(peer: int, id: String) -> void:
	if NetSession.is_host():
		if not NetSession.cosmetic_profiles.has(peer): NetSession.cosmetic_profiles[peer] = {}
		NetSession.cosmetic_profiles[peer][id] = true
	_deliver(peer, "cosmetic", [id])

func finish() -> void:
	if _finished: return
	_finished = true
	CharacterProfile.save()

func _exit_tree() -> void:
	finish()
	CharacterProfile.end_match()
