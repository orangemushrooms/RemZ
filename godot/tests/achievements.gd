extends SceneTree

var game: Node
var achievements: Achievements
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()

func _initialize() -> void: call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 180000: quit(1)
	return false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func reset_round() -> void:
	achievements.counters.clear()
	achievements.session_unlocked.clear()
	achievements._queue.clear()
	# Keep the toast queue for assertions without playing dozens of celebrations.
	achievements._showing = true
	game.stats._streak = 0
	game.stats._streak_t = 0
	game.stats.best_streak = 0

func enemy(kind := "shambler", weapon := "pistol", peer := 1) -> Zombie:
	game.spawn_zombie(kind, Vector2(55, 120), 1)
	var zombie: Zombie = game.zombies_root.get_children().back()
	zombie.set_physics_process(false)
	zombie.agent.avoidance_enabled = false
	zombie.killer_weapon = weapon
	zombie.killer_peer = peer
	return zombie

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	achievements = game.achievements
	achievements.set_process(false)
	check(not achievements.persist, "Test round cannot overwrite saved achievements")
	check(Achievements.DEFS.size() == 55, "Catalog contains 30 existing and 25 additional achievements")
	var ids := {}
	for definition in Achievements.DEFS: ids[definition.id] = true
	check(ids.size() == Achievements.DEFS.size(), "Every achievement has a unique persistent ID")
	reset_round()
	var normal := enemy()
	normal.damage(100000, Vector3.ZERO)
	check(not achievements.counters.has("titans"), "Ordinary zombie kill does not count as a titan")
	for kind in ["titan", "titan_hunter", "titan_siege", "titan_ash"]:
		var titan := enemy(kind)
		var before := int(achievements.counters.get("titans", 0))
		titan.damage(1, Vector3.ZERO)
		check(int(achievements.counters.get("titans", 0)) == before, kind + " must die before it counts")
		titan.damage(100000, Vector3.ZERO)
		check(int(achievements.counters.titans) == before + 1, kind + " advances titan achievements through actual death")
		titan.damage(100000, Vector3.ZERO)
		titan.die(Vector3.ZERO)
		check(int(achievements.counters.titans) == before + 1, kind + " cannot count twice from corpse hits")
	check(achievements.session_unlocked.has("titan_1") and not achievements.session_unlocked.has("titan_5"), "Four titan variants unlock Titankiller but not the five-titan tier")
	for milestone in [5, 15, 30]:
		achievements.counters.titans = milestone - 1
		var titan := enemy("titan_hunter")
		titan.damage(100000, Vector3.ZERO)
		check(achievements.session_unlocked.has("titan_%d" % milestone), "Fatal titan damage unlocks tier %d" % milestone)
	reset_round()
	for weapon in ["knife", "hatchet", "melee"]:
		var zombie := enemy("shambler", weapon)
		zombie.damage(100000, Vector3.ZERO)
	check(int(achievements.counters.melee_kills) == 3, "Knife, axe and gun-butt kills all count as melee")
	normal = enemy()
	normal.damage(100000, Vector3.ZERO)
	check(int(achievements.counters.melee_kills) == 3, "Firearm kill does not count as melee")
	var tower: DefenceTower = game.defences.create_tower(Map.ground_pos(60, 112), 1)
	tower.set_physics_process(false)
	for operated in [false, true]:
		tower.operator_peer = 1 if operated else 0
		normal = enemy()
		normal.hp = 1
		tower.hurt(normal, Vector3.ZERO)
	check(int(achievements.counters.tower_kills) == 2, "Automatic and manually operated tower kills both count")
	reset_round()
	game.stats._streak = 24
	normal = enemy()
	normal.damage(100000, Vector3.ZERO)
	check(achievements.session_unlocked.has("streak_25"), "Actual 25th consecutive kill awards the streak achievement")
	game.stats.tick(4.1)
	normal = enemy()
	normal.damage(100000, Vector3.ZERO)
	check(achievements.counters.best_streak == 25, "Expired streak preserves the best streak's progress")
	game.stats._streak = 49
	normal = enemy()
	normal.damage(100000, Vector3.ZERO)
	check(achievements.session_unlocked.has("streak_50"), "Actual 50th consecutive kill awards the late-game streak tier")
	# Check each added threshold and ensure replayed events cannot repeat rewards.
	var new_ids := ["hunter_10", "kills_500", "kills_1000", "kills_2500", "head_100", "head_250", "head_500",
		"titan_1", "titan_5", "titan_15", "titan_30", "tower_100", "tower_500", "melee_25", "melee_100",
		"wave_15", "wave_20", "wave_30", "wave_40", "flawless_5", "shroom_50", "streak_25", "streak_50", "drops_50"]
	for definition in Achievements.DEFS:
		if definition.id not in new_ids: continue
		reset_round()
		achievements.event(definition.counter, definition.target - 1, true)
		check(not achievements.session_unlocked.has(definition.id), str(definition.id) + " stays locked below its threshold")
		achievements.event(definition.counter)
		var balance: int = game.player.score
		var notifications := achievements._queue.size()
		achievements.event(definition.counter, definition.target, true)
		check(achievements.session_unlocked.has(definition.id) and game.player.score == balance and achievements._queue.size() == notifications,
			str(definition.id) + " unlocks at its threshold and rewards only once per round")
	reset_round()
	for wave in [15, 20, 30, 40]:
		achievements.wave_started()
		achievements.player_hurt()
		achievements.wave_cleared(wave)
		check(achievements.session_unlocked.has("wave_%d" % wave), "Clearing wave %d awards its late-game achievement" % wave)
	check(not achievements.counters.has("flawless"), "Waves with player damage do not count as flawless")
	for wave in range(1, 6):
		achievements.wave_started()
		achievements.wave_cleared(wave)
	check(achievements.session_unlocked.has("flawless_5"), "Five undamaged waves award Unberuehrbar")
	reset_round()
	check(achievements.unlocked.has("titan_30") and not achievements.session_unlocked.has("titan_30"), "Permanent unlocks survive a round reset while round rewards reset")
	var balance: int = game.player.score
	achievements.event("titans")
	check(game.player.score == balance + 75 and achievements.session_unlocked.has("titan_1"), "Previously unlocked Titankiller can be earned again in the next round")
	# The existing host-owned achievement flow must pay every teammate once.
	NetSession.enabled = true
	NetSession.world.add_player(1)
	NetSession.world.add_player(2)
	var teammate: Player = NetSession.world.actor(2)
	teammate.set_physics_process(false)
	NetSession.world.weapons[2].set_process(false)
	reset_round()
	achievements.counters.titans = 4
	# Suppress the lower tier, as in a real round after the first titan.
	achievements.session_unlocked.titan_1 = true
	balance = game.player.score
	var teammate_balance := teammate.score
	achievements.event("titans")
	achievements.event("titans", 5, true)
	check(game.player.score == balance + 125 and teammate.score == teammate_balance + 125, "Host grants the five-titan reward exactly once to each teammate")
	var titan := enemy("titan_siege", "pistol", 2)
	titan.damage(100000, Vector3.ZERO)
	check(achievements.counters.titans == 6 and game.stats.players[2].titan_kills == 1, "Remote player's lethal hit advances team achievements and their own leaderboard")
	var snapshot: Dictionary = NetSession.world.snapshot()
	check(snapshot.achievements[0].titans == 6 and snapshot.achievements[1].has("titan_5"), "Snapshot includes titan progress and round unlocks for late joiners")
	snapshot.achievements[0].titans = 999
	check(achievements.counters.titans == 6, "Snapshot is independent of authoritative counters")
	game.hud._fill_achievements()
	var text := ui_text(game.hud._achievements_box)
	check(text.contains("Titankiller") and text.contains("Legende des Heitersbergs") and text.contains("Runde: 6/15"), "Achievements menu includes new tiers and current-round progress")
	# A client must never award itself progress or rewards.
	NetSession.set_process(false)
	var client_peer := ENetMultiplayerPeer.new()
	var error := client_peer.create_client("127.0.0.1", 24699)
	check(error == OK, "Client authority fixture initializes")
	if error == OK:
		var original_peer := get_multiplayer().multiplayer_peer
		get_multiplayer().multiplayer_peer = client_peer
		balance = game.player.score
		achievements.event("titans", 30, true)
		check(NetSession.is_client() and achievements.counters.titans == 6 and game.player.score == balance, "Client-side events cannot forge a titan achievement")
		get_multiplayer().multiplayer_peer = original_peer
		client_peer.close()
	NetSession.enabled = false
	print("ACHIEVEMENTS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func ui_text(node: Node) -> String:
	var result: String = node.text if node is Label else ""
	for child in node.get_children(): result += "\n" + ui_text(child)
	return result
