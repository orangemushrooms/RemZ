extends "res://scripts/coop_world.gd"
## Shared combat/transport; field-specific economy, construction and session UI.
func setup(node: Node3D) -> void:
	super.setup(node)
	deer.assign(game.nature.deer)

func add_player(id: int) -> void:
	if actors.has(id): return
	super.add_player(id)
	var p: Player = actor(id)
	var w: Weapons = weapons[id]
	p.score = 150
	for wid in w.unlocked: w.unlocked[wid] = wid in ["pistol","knife"]
	w.network_apply = true
	w.set_weapon("pistol")
	w.network_apply = false
	w.refill_all()
	w.grenades = 3
	game.progression.field_data(id)
	p.died.connect(func():
		if NetSession.is_host() and id!=NetSession.local_id(): game.stats.record_death(id))

func make_client() -> void:
	super.make_client()

func move_player(id: int, position: Vector3, yaw: float, pitch: float, light: bool, motion: Vector3, now: float, sequence: int = 0, crouching: bool = false, teleport_seen: int = 0) -> void:
	if not preload("res://scripts/planes_boundary.gd").contains(Vector2(position.x,position.z)): return
	super.move_player(id,position,yaw,pitch,light,motion,now,sequence,crouching,teleport_seen)

func action(id: int, operation: String, args: Array) -> void:
	var p: Player = actor(id)
	if not p or not p.alive or p.downed:
		if operation in ["self_revive","revive"]: super.action(id,operation,args)
		return
	if operation=="range":
		if args.size()!=1 or not args[0] is String: return
		NetSession.feedback(id,"message",[game.shooting_range.transact(p,args[0]),4.0])
		NetSession._sequence += 1
		if id!=1: NetSession.send_reliable_state(id,false)
		return
	if operation=="planes":
		if args.size()!=2 or not args[0] is String or not args[1] is Array: return
		var result: String = game.progression.authoritative_action(p,str(args[0]),args[1])
		if not result.is_empty(): NetSession.feedback(id,"message",[result,2.5])
		NetSession._sequence += 1
		if id!=1: NetSession.send_reliable_state(id,false)
		else: game.quickbar.refresh()
		return
	# Only systems present on this map may receive commands.
	if operation not in ["hunting","brewing","eat","teleport","fire","weapon","reload","melee","grenade","revive","self_revive","next_wave","tower_place","tower_rotate","tower_move","tower_mount","tower_exit","tower_control","tower_upgrade","tower_repair","tower_sell","drop_cash"]: return
	super.action(id,operation,args)

func _close_local_menus() -> void:
	if game.inventory.is_open: game.inventory.close()
	if game.brewing.menu.is_open: game.brewing.menu.close()
	game.field_building.cancel()
	game.defences.close()
	game.progression.close()
	if game.cheat_menu.is_open: game.cheat_menu.close()
	game.get_tree().paused = false

func _show_game_over() -> void:
	game.over = true
	game.classes.finish()
	CharacterProfile.end_match()
	_close_local_menus()
	game.player.active = false
	if game.victory: game.campaign.record_wave(25,str(game.difficulty.name))
	game.hud.show_overlay("REGION SECURED" if game.victory else "TEAM DOWN","THE PLANES / REMETSCHWIL","New round" if NetSession.is_host() else "Waiting for host","","over")
	game.hud.overlay_button.disabled = NetSession.is_client()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
