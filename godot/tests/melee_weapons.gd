extends SceneTree

var game: Node
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", text)

func settle() -> void:
	await physics_frame
	await physics_frame
	await process_frame

func shot(id: String) -> void:
	if "--render-melee" not in OS.get_cmdline_user_args(): return
	var folder := ProjectSettings.globalize_path("res://../artifacts/melee/")
	DirAccess.make_dir_recursive_absolute(folder)
	await settle()
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder + id + ".png")

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	var w: Weapons = game.weapons
	var p: Player = game.player
	p.set_physics_process(false)
	w.set_process(false)
	check(w.unlocked.knife and not w.unlocked.hatchet, "Messer starts unlocked; axe is earned")
	w.set_weapon("hatchet")
	check(w.current == "pistol", "Locked axe cannot be equipped")
	p.global_position = game.progression.npcs.camp.global_position + Vector3(0, 0, 1)
	p.score = 500
	game.waves.completed = 1
	game.progression.data(p.peer_id).claimed.arrival = true
	var result: String = game.progression.transact(p, "camp", "weapon", "hatchet")
	check(w.unlocked.hatchet and p.score == 320 and result.begins_with("Gekauft"), "Vendor sells the axe for 180 points")
	check(game.progression.transact(p, "camp", "ammo", "hatchet").contains("keine Munition") and p.score == 320, "Vendor refuses melee ammunition without charging")
	game.day_night.set_time_hours(10.0)
	game.hud.msg_label.text = ""
	game.achievements.hide()
	for id in ["knife", "hatchet"]:
		w.set_weapon(id)
		w._handle_weapon_input(0.016)
		check(w.current == id and w.cur().node.visible, id + " equips its own visible model")
		check(game.hud.ammo_label.text.contains("Nahkampf"), id + " has a melee HUD")
		w.reload()
		check(w.cur().reloading == 0 and w.cur().ammo == 0, id + " never reloads or uses ammunition")
		await shot(id)
		w._melee_t = 0.0
		w.melee()
		w._handle_weapon_input(float(w.cur().def.rate) * 0.5)
		check(absf(w.cur().node.rotation.z) > 0.2, id + " has a visible swing")
		await shot(id + "-swing")
		if id in ["knife","hatchet"]:
			w._melee_t = 0
			w.melee(true)
			w._handle_weapon_input(float(w.cur().def.stab_rate)*0.5)
			await shot(id+"-heavy")
	w.set_weapon("knife")
	game.inventory._refresh()
	check(w.ammo_weapon() == "pistol", "Ammunition pickups while holding melee supply the last firearm")
	w.state.pistol.reserve = w.reserve_limit("pistol")
	var drop := Pickup.new()
	drop.kind = "ammo"
	check(not drop.can_collect(p, w), "Melee does not bypass full ammunition capacity")
	w.state.pistol.reserve -= 1
	check(drop.can_collect(p, w), "Melee allows ammunition when the firearm has room")
	drop.free()
	# An isolated physics target lets the weapon rays test range and walls.
	p.global_position = Vector3(0, 60, 0)
	p.rotation = Vector3.ZERO
	p.pitch = 0
	p.head.rotation = Vector3.ZERO
	var z := Zombie.new()
	z.setup("brute", p, [], 1.0, Callable())
	z.model_path = ""
	z.replica = false
	game.zombies_root.add_child(z)
	z.set_physics_process(false)
	z.agent.avoidance_enabled = false
	z.global_position = p.global_position + Vector3(0, 0, -1.5)
	await settle()
	for id in ["knife", "hatchet"]:
		w.set_weapon(id)
		z.hp = 1000
		w._melee_t = 0
		var shots_before: int = game.stats.shots
		w.try_fire()
		check(is_equal_approx(z.hp, 1000 - float(Weapons.DEFS[id].damage) * w.damage_mul), id + " left-click deals its melee damage")
		check(z.killer_weapon == id and game.stats.shots == shots_before, id + " records melee attribution without gunshot statistics")
		var after := z.hp
		w.melee()
		check(z.hp == after, id + " H and left-click share a cooldown")
		w.set_weapon("pistol")
		w.set_weapon(id)
		w.try_fire()
		check(z.hp == after, id + " weapon switching cannot bypass cooldown")
	w.set_weapon("hatchet")
	w._melee_t = 0
	z.hp = 1000
	Input.action_press("aim")
	w._handle_weapon_input(0.01)
	Input.action_release("aim")
	check(w._melee_stab and is_equal_approx(z.hp,1000-225*w.effective_damage_mul()),"Axe right-click deals heavy damage")
	check(is_equal_approx(w._melee_t,1.45),"Heavy axe has longer recovery")
	var axe_hp := z.hp
	w.try_fire()
	check(z.hp==axe_hp,"Light attack cannot bypass heavy axe cooldown")
	w.set_weapon("knife")
	w._melee_t = 0
	z.hp = 1000
	w.melee(true)
	check(is_equal_approx(z.hp,1000-110*w.effective_damage_mul()),"Knife stab deals its stronger damage")
	check(w._melee_stab and is_equal_approx(w._melee_t,0.85),"Stab has its own longer recovery")
	var stab_hp := z.hp
	w.try_fire()
	check(z.hp==stab_hp,"Switching mouse buttons cannot bypass stab recovery")
	w._melee_t = 0
	Input.action_press("aim")
	w._handle_weapon_input(0.01)
	Input.action_release("aim")
	check(w._melee_stab and w._melee_t>0,"Right mouse action triggers knife stab instead of aiming")
	w._handle_weapon_input(0.4)
	check(w.cur().node.rotation.x < -1.2,"Stab points the blade forward")
	w._melee_t = 0
	z.global_position.z = -5
	await settle()
	var hp := z.hp
	w.try_fire()
	check(z.hp == hp, "Melee cannot hit a distant enemy")
	z.global_position.z = -1.5
	var wall := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 5, 0.2)
	shape.shape = box
	wall.add_child(shape)
	game.add_child(wall)
	wall.global_position = p.global_position + Vector3(0, 1, -0.7)
	await settle()
	w._melee_t = 0
	w.try_fire()
	check(z.hp == hp, "Walls block melee strikes")
	w._melee_t = 0
	w.melee(true)
	check(z.hp == hp,"Walls also block knife stabs")
	wall.queue_free()
	await settle()
	NetSession.enabled = true
	NetSession.world.add_player(2)
	var remote: Player = NetSession.world.actor(2)
	var proxy: Weapons = NetSession.world.weapons[2]
	remote.set_physics_process(false)
	proxy.set_process(false)
	remote.active = true
	remote.global_position = p.global_position
	remote.rotation = Vector3.ZERO
	remote.head.rotation = Vector3.ZERO
	proxy.set_weapon("knife")
	proxy.try_fire()
	check(z.hp < hp and z.killer_peer == 2 and z.killer_weapon == "knife", "Host applies remote melee damage with the correct owner")
	proxy._melee_t = 0
	var before_stab := z.hp
	NetSession.world.action(2,"melee",[0.0,0.0,true])
	check(is_equal_approx(z.hp,before_stab-110*proxy.effective_damage_mul()),"Host validates and applies the remote right-click stab")
	NetSession.world.avatars[2].shot("knife",[true])
	check(NetSession.world.avatars[2].knife_stab,"Remote animation receives the stabbing attack mode")
	check(not NetSession.world.avatars[2].flash.visible, "Remote melee swings have no muzzle flash")
	proxy.unlocked.hatchet = true
	proxy.set_weapon("hatchet")
	proxy._melee_t = 0
	z.hp = 1000
	NetSession.world.action(2,"melee",[0.0,0.0,true])
	check(is_equal_approx(z.hp,1000-225*proxy.effective_damage_mul()),"Host applies remote heavy axe damage")
	NetSession.world.avatars[2].shot("hatchet",[true])
	check(NetSession.world.avatars[2].axe_heavy,"Remote avatar distinguishes heavy axe animation")
	NetSession.enabled = false
	print("MELEE_WEAPONS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
