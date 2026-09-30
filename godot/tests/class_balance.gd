extends SceneTree
const Classes = preload("res://scripts/character_classes.gd")
var game: Node3D
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
func _initialize() -> void: call_deferred("run")
func _process(_delta: float) -> bool:
	if Time.get_ticks_msec()-began>240000: print("CLASS_BALANCE_TIMEOUT"); quit(1)
	return false
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",label)
func build(id: String, choices: Array = [], level: int = 30) -> void:
	game.player.class_combat.configure({"id":id,"level":level,"choices":choices})
	game.weapons.refresh_class_magazines()
func equip(id: String) -> void:
	var w: Weapons = game.weapons
	w.unlocked[id] = true
	w.set_weapon(id)
	w._switch_t = 0
	w.cur().ammo = w.cur().def.mag
	w.cur().reloading = 0
	w.cur().cooldown = 0
func fire(z: Zombie) -> float:
	var w: Weapons = game.weapons
	w.cur().ammo = w.cur().def.mag
	w.cur().reloading = 0
	w.cur().cooldown = 0
	w.cur().def.spread = 0.0
	w._aim_kick = Vector2.ZERO
	w._bloom = 0
	w.camera.look_at(z.global_position+Vector3.UP*z.height*0.5)
	var before := z.hp
	w.try_fire()
	return before-z.hp
func run() -> void:
	CharacterProfile.data = CharacterProfile.empty_profile("Balance test")
	var planes := "--class-planes" in OS.get_cmdline_user_args()
	game = load("res://scenes/planes.tscn" if planes else "res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	if planes:
		while not game.ready_for_exploration: await process_frame
	else:
		while not game.navigation_ready: await process_frame
		game._on_start(false)
	game.waves.set_process(false)
	game.classes.set_process(false)
	game.weapons.set_process(false)
	game.player.set_physics_process(false)
	var p: Player = game.player
	var w: Weapons = game.weapons
	p.active = true
	p.revive_protection = 0
	p.global_position = Map.ground_pos(20,105)+Vector3.UP*100
	p.velocity = Vector3.ZERO
	game.spawn_zombie("shambler",Vector2(20,115),1)
	var z: Zombie = game.zombies_root.get_children().back()
	z.set_physics_process(false)
	z.agent.avoidance_enabled = false
	z.global_position = p.global_position+Vector3(0,0,-5)
	z.hp = 1000000
	z.max_hp = z.hp
	for i in 4: await physics_frame
	# Real ray casts, ammo consumption and zombie HP: no mocked damage path.
	for spec in [["gunslinger","pistol"],["assault","ak47"],["breacher","shotgun"],["marksman","marksman"],["assassin","pistol"]]:
		build(spec[0],[],1)
		equip(spec[1])
		var baseline := fire(z)
		build(spec[0])
		var scaled := fire(z)
		check(baseline>0 and absf(scaled/baseline-1.58)<0.02,"%s level 30 mastery changes real shot damage on %s" % [spec[0],"Planes" if planes else "Forest"])
	build("breacher",[])
	equip("shotgun")
	var baseline := fire(z)
	build("breacher",[-1,-1,-1,-1,-1,1])
	check(absf(fire(z)/baseline-3.0)<0.02,"Boomstick triples a complete real shotgun blast")
	build("gunslinger",[-1,-1,-1,-1,-1,1])
	equip("pistol")
	fire(z)
	check(is_equal_approx(w.cur().cooldown,float(w.cur().def.rate)/1.25),"Gunslinger Mastery changes the real firing interval")
	build("assault",[-1,-1,-1,-1,-1,1])
	equip("ak47")
	p.hp = 49
	p.damage(10)
	check(is_equal_approx(p.hp,43),"Last Stand reduces actual incoming damage while holding a rifle")
	equip("pistol")
	p.hp = 49
	p.damage(10)
	check(is_equal_approx(p.hp,39),"Switching off the rifle removes Last Stand protection")
	build("breacher",[-1,-1,-1,-1,1,0])
	p.class_combat.nearby = 2
	p.class_combat.killed("shotgun",false,3)
	p.hp = 100
	p.damage(20)
	check(is_equal_approx(p.hp,94.9),"Juggernaut and Stand Your Ground combine in actual damage processing")
	build("marksman",[])
	equip("plasma_sniper")
	w.cur().heat = 1.0
	w.cur().vent = false
	w.reload()
	var normal_vent: float = w.cur().reloading
	build("marksman",[-1,-1,-1,-1,-1,1])
	p.class_combat.precision_chain = 5
	w.cur().heat = 1.0
	w.cur().vent = false
	w.cur().reloading = 0
	w.reload()
	var fast_vent: float = w.cur().reloading
	check(normal_vent>0 and is_equal_approx(fast_vent,normal_vent*0.5),"Marksman's Rhythm halves the actual plasma heat lock")
	w._tick_ammo(fast_vent+0.1)
	check(not w.specials.blocks_fire(w,"plasma_sniper"),"Plasma can fire when its accelerated reload finishes")
	build("marksman",[-1,-1,-1,-1,-1,0])
	p.class_combat.time_since_miss = 2.1
	await create_timer(0.2).timeout
	check(Lang.text(p.class_combat.status(w.current)).contains("READY"),"Charged ultimate exposes its readiness for the HUD")
	print("CLASS_BALANCE_DONE map=%s checks=%d failures=%d" % ["Planes" if planes else "Forest",checks,failures])
	quit(1 if failures else 0)
