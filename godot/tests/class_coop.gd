extends SceneTree
const Classes = preload("res://scripts/character_classes.gd")
var game: Node
var role := "host"
var folder := ""
var began := Time.get_ticks_msec()
var checks := 0
var failures := 0
func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--class-role="): role = arg.get_slice("=", 1)
		if arg.begins_with("--class-test-folder="): folder = arg.trim_prefix("--class-test-folder=")
	call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 210000: print("CLASS_COOP_TIMEOUT ", role); quit(1)
	return false
func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)
func write(id: String) -> void: FileAccess.open(folder.path_join(id), FileAccess.WRITE).store_string("ready")
func wait_for(id: String) -> void:
	while not FileAccess.file_exists(folder.path_join(id)): await create_timer(0.1).timeout

func run() -> void:
	CharacterProfile.data = CharacterProfile.empty_profile(role)
	CharacterProfile.data.selected = "gunslinger" if role == "host" else "assassin"
	CharacterProfile.data.classes.assassin.total_xp = Classes.threshold(30)
	CharacterProfile.data.classes.assassin.choices = [0,1,0,1,1,0]
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game.player.set_physics_process(false)
	if role == "host": await host_run()
	else: await client_run()
	print("CLASS_COOP_DONE role=%s checks=%d failures=%d" % [role, checks, failures])
	quit(1 if failures else 0)

func host_run() -> void:
	check(NetSession.host("Class host", 24774) == OK, "Host opens with its own profile")
	write("ready")
	while NetSession.roster.size() < 2 or false in NetSession.ready_peers.values(): await create_timer(0.1).timeout
	var client := 0
	for peer in NetSession.roster:
		if peer != 1: client = int(peer)
	check(NetSession.class_roster[client].id == "assassin" and NetSession.class_roster[client].level == 30, "Client class and level reach the host")
	check(NetSession.choose_class("gunslinger", true), "Host explicitly confirms its class")
	NetSession.start_game()
	check(NetSession.phase == "lobby", "An unlocked remote player blocks match start")
	NetSession._auto_start = 2
	await create_timer(0.2).timeout
	check(NetSession.phase == "lobby" and NetSession._auto_start == 2, "Automatic starts wait for class confirmation without losing the pending start")
	write("confirm")
	while not NetSession.class_roster[client].locked: await create_timer(0.1).timeout
	check(NetSession.class_roster[client].id == "assassin", "Client lock is received over reliable RPC")
	NetSession.start_game()
	game.waves.set_process(false)
	var p: Player = NetSession.world.actor(client)
	check(p.class_combat.has("light_footed") and p.effective_speed_mul() > 1.1, "Host simulates the remote Assassin's movement bonuses")
	await wait_for("running")
	await create_timer(0.4).timeout
	check(NetSession.class_roster[client].id == "assassin", "A client cannot change its class after match start")
	game.spawn_zombie("shambler", Vector2(20,110), 1)
	var z: Zombie = game.zombies_root.get_children().back()
	z.set_physics_process(false)
	z.killer_peer = client
	z.killer_weapon = "knife"
	z.last_headshot = false
	z.damage(100000, Vector3.FORWARD)
	game.classes.quest(client, "coop_test_quest", 400)
	game.classes.quest(client, "coop_test_quest", 400)
	game.classes.achievement("coop_test_achievement", 100)
	game.classes.achievement("coop_test_achievement", 100)
	game.classes.cosmetic(client, "pistol:forest")
	game.progression.people.erase(client)
	check(game.progression.data(client).skins.get("pistol:forest", false), "Remote cosmetics survive rebuilding the host's round inventory")
	check(CharacterProfile.data.classes.gunslinger.stats.kills == 0, "Remote kills never increase the host's personal kills")
	check(not CharacterProfile.data.quests.has("coop_test_quest"), "Remote quest XP never reaches the host's profile")
	write("rewards")
	await wait_for("verified")
	write("rejoin")
	while NetSession.roster.size() > 1: await create_timer(0.1).timeout
	while NetSession.roster.size() < 2 or false in NetSession.ready_peers.values(): await create_timer(0.1).timeout
	for peer in NetSession.roster:
		if peer != 1: client = int(peer)
	check(not NetSession.class_roster[client].locked and not NetSession.world.actor(client).active, "A late join remains inactive until class confirmation")
	var waiting: Player = NetSession.world.actor(client)
	var hp_before := waiting.hp
	waiting.damage(1000)
	check(waiting.hp == hp_before, "A player still choosing a class cannot be damaged")
	write("late_ready")
	await wait_for("late_running")
	check(NetSession.class_roster[client].locked and waiting.active, "The host activates a confirmed late join")
	check(not waiting.get_meta("class_mission_from_start", true) and game.player.get_meta("class_mission_from_start", false), "Even a first-wave late join cannot claim an entire damage-free mission")
	game.classes.wave(25)
	game.victory = true
	NetSession.world.campaign_victory()
	await wait_for("victory")
	check(CharacterProfile.data.classes.gunslinger.stats.multiplayer_missions == 1, "Host saves its multiplayer mission completion")
	write("done")
	await create_timer(0.5).timeout

func client_run() -> void:
	await wait_for("ready")
	check(NetSession.join("127.0.0.1", "Class client", 24774) == OK, "Client joins using its separate profile")
	while not NetSession.ready_peers.get(NetSession.local_id(), false): await create_timer(0.1).timeout
	check(not game.started, "Loading the lobby does not start an unconfirmed player")
	check(not CharacterProfile.choose_skill("assassin", 0, 1), "Client cannot edit skills in the lobby")
	await wait_for("confirm")
	NetSession.choose_class("assassin", true)
	while not game.started: await create_timer(0.1).timeout
	check(CharacterProfile.active_class() == "assassin" and game.player.class_combat.has("light_footed"), "Client starts with the confirmed build")
	check(not NetSession.choose_class("gunslinger"), "Local UI/API blocks changing a locked class")
	# Also try the RPC directly, bypassing the menu: the host must still reject it.
	NetSession._class_choice.rpc_id(1, NetSession.epoch, "gunslinger", false)
	write("running")
	await wait_for("rewards")
	await create_timer(0.4).timeout
	check(CharacterProfile.data.classes.assassin.stats.kills == 1 and CharacterProfile.data.classes.assassin.stats.multiplayer_kills == 1, "Personal kill and multiplayer statistics reach the correct client")
	check(CharacterProfile.data.quests.get("coop_test_quest", 0) == 1, "Remote quest completion persists exactly once")
	check(CharacterProfile.data.achievements.get("world:coop_test_achievement", false), "Remote team achievements persist in the client's own profile")
	check(CharacterProfile.data.classes.assassin.total_xp == Classes.threshold(30) + 15 + 250 + 800 + 250 + 250, "Client gets kill, quest and one-time achievement XP without duplicate grants")
	check(CharacterProfile.data.classes.gunslinger.total_xp == 0, "Other client classes receive no XP")
	check(CharacterProfile.data.cosmetics.get("pistol:forest", false), "A purchased cosmetic is stored in the client's own profile")
	write("verified")
	await wait_for("rejoin")
	NetSession.leave()
	await scene_changed
	game = current_scene
	while not game.navigation_ready: await process_frame
	check(CharacterProfile.data.classes.assassin.stats.kills == 1, "Leaving and reloading preserves the client's personal progress")
	game.player.set_physics_process(false)
	check(NetSession.join("127.0.0.1", "Class client", 24774) == OK, "Client can rejoin an already running match")
	while not NetSession.ready_peers.get(NetSession.local_id(), false): await create_timer(0.1).timeout
	check(not game.started, "A late join still sees class confirmation")
	await wait_for("late_ready")
	NetSession.choose_class("assassin", true)
	while not game.started: await create_timer(0.1).timeout
	write("late_running")
	while not game.over: await create_timer(0.1).timeout
	check(CharacterProfile.data.classes.assassin.stats.multiplayer_missions == 1, "Client persists its own multiplayer mission completion")
	write("victory")
	await wait_for("done")
