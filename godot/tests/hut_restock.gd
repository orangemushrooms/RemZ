extends SceneTree
class ClientPeer extends MultiplayerPeerExtension:
	func _is_server() -> bool: return false
	func _get_unique_id() -> int: return 2
	func _get_connection_status() -> MultiplayerPeer.ConnectionStatus: return MultiplayerPeer.CONNECTION_CONNECTED
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", message)
func run() -> void:
	var game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	var w: Weapons = game.weapons
	var supply: Loot
	var gun: Loot
	var count := 0
	for item in game.loots:
		if item is Loot and item.renewable:
			count += 1
			if item.kind == "ammo": supply = item
			if item.id == "smg": gun = item
	check(count == 12, "Twelve fixed hut supply slots, with no unbounded spawning")
	check(gun.taken and not gun.visible, "Additional gun stays hidden before its wave")
	w.state.pistol.reserve = w.reserve_limit("pistol")
	supply.take(w,game.hud)
	check(not supply.taken, "Full reserve leaves renewable ammunition intact")
	w.state.pistol.reserve = 0
	supply.take(w,game.hud)
	check(supply.taken and not supply.visible and not supply.is_queued_for_deletion(), "Collected supply retains its stable network identity")
	check(w.state.pistol.reserve == 12, "Early supply grants one magazine")
	game._restock_huts(2)
	check(not supply.taken and supply.visible, "Next wave restores collected supply")
	supply.take(w,game.hud)
	game._restock_huts(2)
	check(supply.taken, "Repeated restock in the same wave cannot duplicate supplies")
	game._restock_huts(3)
	check(not gun.taken and gun.visible, "MP5 joins the hut supply in wave three")
	gun.take(w,game.hud)
	check(not gun.taken and not w.unlocked.smg, "Weapon find respects missing quest permission")
	game.progression.data(game.player.peer_id).claimed.watch = true
	game.waves.completed = 2
	gun.take(w,game.hud)
	check(gun.taken and w.unlocked.smg, "Permitted weapon is awarded and consumed")
	game._restock_huts(5)
	w.state.pistol.reserve = 0
	supply.take(w,game.hud)
	check(w.state.pistol.reserve == 24, "Wave five increases supply to two magazines")
	game._restock_huts(100)
	check(supply.magazines == 4, "Late-wave supply growth stays capped")
	NetSession.enabled = true
	NetSession.world.add_player(1)
	game.waves.wave = 100
	var key := str(supply.get_meta("coop_id"))
	supply.taken = true
	supply.hide()
	var empty: Dictionary = NetSession.world.snapshot()
	check(not key in empty.loots, "Host snapshot marks the collected slot unavailable")
	supply.restock(101)
	game.waves.wave = 101
	var full: Dictionary = NetSession.world.snapshot()
	check(key in full.loots, "Host snapshot republishes the same slot after restock")
	empty.players = {}
	full.players = {}
	NetSession.multiplayer.multiplayer_peer = ClientPeer.new()
	check(NetSession.is_client(), "Snapshot test runs with client authority")
	NetSession.world.apply_snapshot(empty, false)
	check(supply.taken and not supply.visible and not supply.is_queued_for_deletion(), "Client keeps hidden renewable loot for future waves")
	NetSession.world.apply_snapshot(full, false)
	check(not supply.taken and supply.visible, "Client restores the slot from authoritative snapshot")
	NetSession.enabled = false
	NetSession.multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	print("HUT_RESTOCK_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
