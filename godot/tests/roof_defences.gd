extends SceneTree
var game: Node
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
func _initialize() -> void: call_deferred("run")
func _process(_dt: float) -> bool:
	if Time.get_ticks_msec() - began > 180000: quit(1)
	return false
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)
func settle() -> void:
	await physics_frame
	await physics_frame
func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
	var d: DefenceSystem = game.defences
	d.set_process(false)
	var p: Player = game.player
	p.global_position = game.hut.center + Vector3(-5, 0, 0)
	p.score = 10000
	game.waves.completed = 8
	var hut_hp: float = game.hut.hp
	var hut_transform: Transform3D = game.hut.body.get_parent().global_transform
	d.begin_building()
	check(d.is_open and d.roof_slot == 0 and d.site_picker.item_count == 7, "Hut menu offers ground and six roof sockets")
	check(d.kind_buttons.size() == 5, "All five Meshy weapon types are offered")
	d.select_kind("standard")
	check(d.placing and not d.is_open and d.ghost.get_child(0).rooftop, "Selecting a roof weapon starts compact preview")
	check(p.camera.global_basis.z.dot(p.camera.global_position.direction_to(d.roof_position(0) + Vector3.UP * 0.65)) < -0.99, "Selecting roof socket turns view toward preview")
	d._process(0.02)
	check(d.build_position.is_equal_approx(d.roof_position(0)) and d.build_error.is_empty(), "Roof preview snaps to socket and validates")
	d.close()
	var near: Vector3 = p.global_position
	for i in 5:
		var kind: String = DefenceTower.TYPES[i]
		var point := d.roof_position(i)
		var before := p.score
		check(d.purchase(p, point, 0, kind).is_empty(), kind + " builds on roof")
		var t := d.roof_tower(i)
		if not t: continue
		t.set_physics_process(false)
		check(t.rooftop and t.gun.position.y < 1 and t.gun.has_node("WeaponModel"), kind + " has compact Meshy weapon")
		check(t.global_position.is_equal_approx(point) and p.score == before - int(t.spec().cost), kind + " preserves roof height and exact cost")
		var paid := p.score
		check(not d.purchase(p,point,0,kind).is_empty() and p.score == paid, kind + " duplicate socket rejects without charging")
		check(not d.mount(p,t.tower_id).is_empty() and p.mounted_tower == 0, kind + " automatic roof turret cannot teleport player")
		t.hp -= 50
		check(d.maintain(p,t.tower_id,"repair").is_empty() and t.hp == t.max_hp() and p.score == paid - 35, kind + " repair works from hut")
		check(d.rotate_tower(p,t.tower_id,PI).is_empty(), kind + " alignment works from hut")
		p.global_position = Map.ground_pos(60,112)
		t.hp -= 50
		paid = p.score
		check(not d.maintain(p,t.tower_id,"repair").is_empty() and p.score == paid, kind + " remote repair denied")
		check(not d.rotate_tower(p,t.tower_id,0).is_empty(), kind + " remote rotation denied")
		p.global_position = near
	check(game.hut.hp == hut_hp and game.hut.body.get_parent().global_transform == hut_transform, "Construction leaves hut health and transform unchanged")
	var spare := d.roof_position(5)
	for bad in [spare + Vector3.UP, spare + Vector3.RIGHT * 0.2, Vector3(NAN,0,0), Vector3(INF,0,0)]:
		var before := p.score
		check(not d.purchase(p,bad).is_empty() and p.score == before, "Forged or nonfinite roof position rejected")
	p.global_position = Map.ground_pos(60,112)
	check(not d.purchase(p,spare).is_empty(), "Roof construction requires hut proximity")
	p.global_position = near
	p.score = 0
	check(not d.purchase(p,spare).is_empty() and p.score == 0, "Insufficient funds rejected")
	p.score = 10000
	game.waves.completed = 0
	check(not d.purchase(p,spare,0,"tesla").is_empty(), "Roof respects wave unlocks")
	game.waves.completed = 8
	check(not d.purchase(p,spare,NAN).is_empty(), "Nonfinite rotation rejected")
	check(not d.purchase(p,spare,0,"unknown").is_empty(), "Unknown weapon rejected")
	p.alive = false
	check(not d.purchase(p,spare).is_empty(), "Dead builders rejected")
	p.alive = true
	game.hut.destroyed = true
	check(not d.purchase(p,spare).is_empty(), "Destroyed hut rejects roof construction")
	game.hut.destroyed = false
	check(d.purchase(p,spare).is_empty() and d.towers.size() == 6, "All six independent sockets usable")
	check(not d.build_requirement(p,"standard").is_empty(), "Roof shares existing team tower limit")
	d.begin_building()
	d._process(0.01)
	check(d.kind_buttons.standard.disabled and not d.roof_align.disabled, "Occupied roof socket disables purchase but allows alignment")
	var first := d.roof_tower(0)
	first.hp -= 50
	d._process(0.01)
	check(not d.roof_repair.disabled, "Damaged roof turret enables menu repair")
	d.roof_repair.pressed.emit()
	check(first.hp == first.max_hp(), "Menu repair operates selected roof turret")
	d.roof_align.pressed.emit()
	check(d.placing and d.rotating_id == first.tower_id and d.ghost.get_child(0).rooftop, "Menu alignment starts compact roof preview")
	d.close()
	var replica := DefenceSystem.new()
	game.add_child(replica)
	replica.game = game
	replica.set_process(false)
	replica.apply_snapshot(d.snapshot(),true)
	for id in d.towers:
		var t: DefenceTower = replica.towers[id]
		check(t.rooftop and t.replica and t.kind == d.towers[id].kind and t.position == d.towers[id].position and t.gun.position.y < 1, "Late join reconstructs compact roof tower %d" % id)
	for t: DefenceTower in replica.towers.values(): t.queue_free()
	replica.queue_free()
	for t: DefenceTower in d.towers.values(): t.queue_free()
	await settle()
	# Fire from the actual sloped roof at a real enemy outside its eaves.
	var point := d.roof_position(1)
	var yaw: float = Map.BUILDINGS.waldhuette.yaw
	var at := point + Vector3(0,0,-9).rotated(Vector3.UP,yaw)
	game.spawn_zombie("shambler",Vector2(at.x,at.z),1)
	var enemy: Zombie = game.zombies_root.get_child(game.zombies_root.get_child_count()-1)
	enemy.set_physics_process(false)
	enemy.agent.avoidance_enabled = false
	for kind in DefenceTower.TYPES:
		var t := d.create_tower(point,p.peer_id,0,false,kind)
		t.rotation.y = yaw
		t.set_physics_process(false)
		enemy.hp = 10000
		await settle()
		check(t.can_see(enemy),kind + " sees actual ground enemy from roof")
		for frame in 180: t._physics_process(1.0 / 60.0)
		check(t.shots > 0,kind + " automatically acquires, aims and fires from roof")
		if kind == "mortar": await create_timer(2.0,false).timeout
		check(enemy.hp < 10000,kind + " roof weapon damages actual ground enemy")
		t.queue_free()
		await settle()
	game.queue_free()
	await settle()
	print("ROOF_DEFENCES_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
