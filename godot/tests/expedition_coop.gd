extends SceneTree
var checks := 0
var failures := 0
var game: Node3D
var host := false
var region := "planes"
var folder := ""
var began := Time.get_ticks_msec()

func _initialize() -> void: call_deferred("test")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec()-began > 480000:
		print("FAIL: expedition cooperative timeout")
		quit(1)
	return false
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)
func signal_file(id: String) -> void:
	var file := FileAccess.open(folder+id, FileAccess.WRITE)
	file.store_string("ready")
	file.close()
func wait_file(id: String) -> void:
	while not FileAccess.file_exists(folder+id): await create_timer(0.1).timeout

func diagnose_plain(value: Variant, at: String = "checkpoint") -> void:
	if value is Dictionary:
		for key in value:
			if not preload("res://scripts/expedition_checkpoint.gd").plain(key): print("NON_PLAIN_KEY ", at, " ", type_string(typeof(key)))
			diagnose_plain(value[key], at+"/"+str(key))
	elif value is Array:
		for i in value.size(): diagnose_plain(value[i], at+"/"+str(i))
	elif not preload("res://scripts/expedition_checkpoint.gd").plain(value):
		print("NON_PLAIN_VALUE ", at, " ", type_string(typeof(value)), " ", value)

func test() -> void:
	host = "--test-host" in OS.get_cmdline_user_args()
	region = "forest" if "--test-forest" in OS.get_cmdline_user_args() else "planes"
	folder = "res://../artifacts/expansion-tests/coop-%s/" % region
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	if region == "planes": set_meta("planes_lobby", true)
	game = load("res://scenes/planes.tscn" if region == "planes" else "res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	if host:
		check(NetSession.host("Expedition host", 24783) == OK, "Host creates expedition lobby")
		game.expedition.configure({"seed": 53291, "region": region})
		signal_file("host-ready")
		while NetSession.ready_peers.size() < 2 or false in NetSession.ready_peers.values(): await create_timer(0.1).timeout
		while not NetSession.class_roster.values().all(func(value): return value.locked): await create_timer(0.1).timeout
		NetSession.start_game()
	else:
		await wait_file("host-ready")
		check(NetSession.join("127.0.0.1", "Expedition client", 24783) == OK, "Client connects through ENet")
	while NetSession.phase != "running" or not game.started: await create_timer(0.1).timeout
	game = NetSession.game
	game.waves.set_process(false)
	game.expedition.set_process(false)
	game.player.set_physics_process(false)
	await create_timer(1).timeout
	var run: RunDirector = game.expedition
	check(NetSession.world.actors.size() == 2, "Both peers have two authoritative player slots")
	check(run.config.seed == 53291 and run.config.region == region, "Host run settings reach the client")
	if host:
		var client_id: int = NetSession.world.actors.keys().filter(func(id): return id != 1)[0]
		var p: Player = NetSession.world.actor(client_id)
		game.player.global_position = run.camp()+Vector3(2, 0.3, 2)
		p.global_position = game.player.global_position+Vector3(1.5, 0, 0)
		p.hp = 30
		run.person(client_id).bandages = 2
		run.person(1).bandages = 2
		game.waves.wave = 3
		game.waves.completed = 3
		game.waves.phase = "idle"
		game.waves.queue.clear()
		run.wave_cleared(3)
		NetSession.send_reliable_state(client_id, false)
		signal_file("test-ready")
		await wait_file("client-choice")
		await create_timer(0.5).timeout
		check(run.person(client_id).augments.size() == 1 and run.person(client_id).offers.is_empty(), "Client augment command is applied once by the host")
		var supplies_before: int = run.person(client_id).bandages
		check(run.transact(client_id, "heal", [1]) == "Your teammate is already healthy.", "Healing a full-health teammate consumes nothing")
		check(run.person(client_id).bandages == supplies_before, "Rejected healing preserves the bandage")
		var host_hp: float = game.player.hp
		game.player.hp = 50
		NetSession.send_reliable_state(client_id, false)
		signal_file("heal-ready")
		await wait_file("client-heal")
		await create_timer(0.5).timeout
		check(game.player.hp > 50 and game.player.hp <= host_hp, "Client healing changes authoritative teammate health")
		check(run.person(client_id).bandages == supplies_before-1 and game.stats.healing > 0, "Healing conserves inventory and records support")
		var w: Weapons = NetSession.world.weapons[client_id]
		w.state.pistol.reserve = 60
		game.weapons.state.pistol.reserve = 0
		var total := int(w.state.pistol.reserve)+int(game.weapons.state.pistol.reserve)
		check(run.transact(client_id, "ammo", [1]) == "Supplies transferred.", "Cooperative ammunition transfer succeeds nearby")
		check(int(w.state.pistol.reserve)+int(game.weapons.state.pistol.reserve) == total, "Ammunition transfer creates no extra bullets")
		var bandage_total := int(run.person(client_id).bandages)+int(run.person(1).bandages)
		var host_bandages := int(run.person(1).bandages)
		check(run.transact(client_id, "bandage", [1]) == "Supplies transferred." and run.person(1).bandages == host_bandages+1, "Nearby teammate receives exactly one bandage")
		check(int(run.person(client_id).bandages)+int(run.person(1).bandages) == bandage_total, "Bandage sharing conserves the team's stock")
		game.brewing.stock(client_id).drinks.brew_meadow = 2
		game.brewing.stock(1).drinks.brew_meadow = 0
		check(run.transact(client_id, "drink", [1, "brew_meadow"]) == "Supplies transferred." and game.brewing.stock(client_id).drinks.brew_meadow == 1 and game.brewing.stock(1).drinks.brew_meadow == 1, "Drink sharing moves one prepared drink without duplicating it")
		run.person(client_id).bandages += 1 # Leave the original restore fixture nonempty.
		p.global_position += Vector3(30, 0, 0)
		check(run.transact(client_id, "bandage", [1]) != "Supplies transferred.", "Distant inventory transfers are refused")
		p.global_position = game.player.global_position+Vector3(1.5, 0, 0)
		if region == "planes":
			game.shooting_range.opened = true
			game.player.global_position = game.shooting_range.house.to_global(Vector3(0, 0.3, 0))
			p.global_position = game.player.global_position+Vector3(1, 0, 0)
			check(run.start_range(game.player, "competition") == "Thirty second range session started.", "Host starts an unlocked shared range competition")
			run.range_hit(1, 0, 5)
			run.range_hit(client_id, 1, 12)
			check(run.range_game.scores[1] == 5 and run.range_game.scores[client_id] == 12, "Shared range competition keeps participant scores separate")
			run._process(30)
			check(run.range_game.timer == 0 and CharacterProfile.data.mastery.range.competition >= 5, "Completed range competition records the host's personal best")
			game.player.global_position = run.camp()+Vector3(2, 0.3, 2)
			p.global_position = game.player.global_position+Vector3(1.5, 0, 0)
		run.checkpoints.override_path = "user://expedition_coop_test.save"
		check(run.transact(client_id, "save", []) == "Only the host can save or continue an expedition.", "Client cannot write the host checkpoint")
		var save_result: String = run.checkpoints.save_run()
		print("CHECKPOINT_SAVE_RESULT ", save_result)
		check(save_result == "Checkpoint saved.", "Host writes a cooperative intermission checkpoint")
		var saved: Dictionary = run.checkpoints.capture()
		if not run.checkpoints.plain(saved): diagnose_plain(saved)
		var old_id := 17777777
		var renumbered: Dictionary = saved.duplicate(true)
		var mapping := {client_id: old_id}
		for key in ["roster", "players", "leaderboard"]: renumbered[key] = run.checkpoints._peer_keys(renumbered[key], mapping)
		renumbered.director.people = run.checkpoints._peer_keys(renumbered.director.people, mapping)
		for section in ["progression", "brewing", "hunting", "range"]:
			for key in ["people", "stocks", "jobs"]:
				if renumbered[section].get(key) is Dictionary: renumbered[section][key] = run.checkpoints._peer_keys(renumbered[section][key], mapping)
		var restored: Dictionary = run.checkpoints.remap_players(renumbered)
		check(restored.players.has(client_id) and not restored.players.has(old_id) and restored.director.people.has(client_id), "Rejoining with a new ENet ID preserves the named player's inventory")
		var validation: String = run.checkpoints.validate(restored)
		print("CHECKPOINT_VALIDATE_RESULT ", validation, " director=", run.checkpoints._director_valid(restored.director), " plain=", run.checkpoints.plain(restored))
		check(validation.is_empty(), "Remapped cooperative checkpoint validates with current player slots")
		check(renumbered.players.has(old_id), "Rejoin remapping leaves the disk payload unchanged")
		var saved_hp := p.hp
		p.hp = 11
		run.person(client_id).bandages = 0
		check(run.checkpoints.load_run() == "Expedition continued." and p.hp == saved_hp, "Host restores all cooperative player slots")
		NetSession.send_reliable_state(client_id, true)
		signal_file("restored")
		await wait_file("client-restored")
		if region == "planes":
			var outpost: Dictionary = run.sites[0]
			game.player.global_position = outpost.at+Vector3.UP*0.3
			outpost.timer = 35.0
			outpost.pending = 0
			run._tick = 0.25
			run._process(1.0)
			check(outpost.occupied and outpost.timer == 34.0, "Host holds outpost while remote player is outside")
			NetSession.send_reliable_state(client_id, false)
			signal_file("outpost-ready")
			await wait_file("client-outpost")
			outpost.timer = 0.0
			var built := false
			for x in range(-120, 150, 15):
				for z in range(60, 250, 15):
					game.player.global_position = Map.ground_pos(x, z)+Vector3.UP*0.3
					game.player.rotation.y = 0
					if run.structures.build(game.player, "gate") == "Fortification built.":
						built = true
						break
				if built: break
			check(built, "Host builds a physical field gate for the remote client")
			NetSession.send_reliable_state(client_id, false)
			signal_file("structure-ready")
			await wait_file("client-structure")
		# Two additional host actors exercise inventory isolation at the supported party size.
		for id in [3003, 3004]:
			NetSession.roster[id] = "Fixture %d" % id
			NetSession.world.add_player(id)
			run.person(id)
		check(NetSession.world.actors.size() == 4 and run.people.size() == 4, "Four player slots retain separate expedition inventories")
		check(NetSession.world.snapshot().expedition.people.size() == 4, "Four-player expedition state fits the regular snapshot")
		for id in [3003, 3004]:
			NetSession.world.remove_player(id)
			NetSession.roster.erase(id)
			run.people.erase(id)
		game.campaign.progress.clear()
		game.waves.wave = run.round_limit()
		game.waves.completed = run.round_limit()-1
		game.waves.phase = "spawning"
		game.waves.queue.clear()
		if region == "planes": game.waves.complete_wave()
		else: game.waves._complete_wave()
		check(game.waves.phase == "finale" and not game.campaign.cleared(region), "Host enters the finale without prematurely securing the cooperative region")
		NetSession.send_reliable_state(client_id, false)
		signal_file("finale-ready")
		await wait_file("client-finale")
		game.player.global_position = run.finale.at+Vector3.UP*0.3
		p.global_position = game.player.global_position+Vector3(1, 0, 0)
		run.transact(1, "interact", ["finale"])
		for step in 600:
			if game.over: break
			run._tick_finale(0.75)
			for enemy in game.zombies_root.get_children():
				if enemy is Zombie: enemy.free()
			await physics_frame
		check(game.victory and game.over and game.campaign.cleared(region) and NetSession.phase == "over", "Complete cooperative finale secures the host's region and ends the session")
		signal_file("done")
		await wait_file("client-done")
	else:
		await wait_file("test-ready")
		await create_timer(0.5).timeout
		var id := NetSession.local_id()
		check(run.person(id).offers.size() == 3, "Client sees three personal augment offers")
		var choice: String = run.person(id).offers[0]
		NetSession.command("expedition", ["augment", [choice]])
		NetSession.command("expedition", ["augment", [choice]])
		await create_timer(0.7).timeout
		check(run.person(id).augments.size() == 1 and run.person(id).offers.is_empty(), "Repeated client choice cannot duplicate an augment")
		signal_file("client-choice")
		await wait_file("heal-ready")
		await create_timer(0.5).timeout
		run.book.open()
		check(not paused and not game.player.active, "Cooperative fieldbook captures controls without pausing the world")
		NetSession.command("expedition", ["heal", [1]])
		await create_timer(0.7).timeout
		run.book.close()
		signal_file("client-heal")
		await wait_file("restored")
		await create_timer(0.7).timeout
		check(game.player.hp > 11 and run.person(id).bandages > 0, "Client receives restored health and expedition inventory")
		check(game.stats.healing > 0, "Client summary receives support statistics")
		if region == "planes": check(CharacterProfile.data.mastery.range.get("competition", 0) >= 12, "Client receives its own completed range record reliably")
		signal_file("client-restored")
		if region == "planes":
			await wait_file("outpost-ready")
			await create_timer(0.7).timeout
			check(run.sites[0].timer == 34.0 and run.sites[0].get("occupied", false), "Client receives authoritative outpost countdown and occupancy")
			check(run.objective_status() == Lang.t("Securing outpost: %d s | Health %d", [34, 160]), "Distant client sees teammate holding outpost instead of a false pause")
			check(not run.sites.any(func(site): return site.kind != "outpost" and run.map_points().any(func(point): return point.at == site.at)), "Client minimap hides transmitters and caches")
			signal_file("client-outpost")
			await wait_file("structure-ready")
			await create_timer(0.7).timeout
			check(run.structures.items.size() == 1 and run.structures.nodes.size() == 1, "Client reconstructs the host's physical fortification")
			if run.structures.items.size() == 1:
				var at: Vector3 = run.structures.items.values()[0].at
				var ray := PhysicsRayQueryParameters3D.create(at+Vector3(0, 1, -3), at+Vector3(0, 1, 3), 8)
				check(not game.get_world_3d().direct_space_state.intersect_ray(ray).is_empty(), "Client gate collision matches the authoritative closed state")
			signal_file("client-structure")
		await wait_file("finale-ready")
		await create_timer(0.7).timeout
		check(game.waves.phase == "finale" and not game.campaign.cleared(region), "Client sees final-wave progress without an early region victory")
		signal_file("client-finale")
		await wait_file("done")
		await create_timer(0.7).timeout
		check(game.victory and game.over and game.campaign.cleared(region) and NetSession.phase == "over", "Client receives final victory, the region record and the finished session")
		signal_file("client-done")
	NetSession.leave()
	paused = false
	game.queue_free()
	await process_frame
	await physics_frame
	print("EXPEDITION_COOP_DONE role=%s region=%s checks=%d failures=%d" % ["host" if host else "client", region, checks, failures])
	quit(1 if failures else 0)
