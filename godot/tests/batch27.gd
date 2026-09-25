# The 26 Sep 2026 evening batch (after the weather release): one magazine more on every gun, the MG-60
# and the drones at twice the damage, the graviton's wider blast, the harder mortar, twice the tower
# limit, the spitter's acid eating far less of a gate, the stronger earthworm, the stag that no longer
# dips its hooves into the terrain, the titan's real crawl clip, the thrown tree with a forest tree
# model, the drone's rockets (RMB) and self-destruct (R), the Mechanic's tower beacons and tier preview,
# and the spectator camera of a player who is down or bled out in co-op.
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=batch27 --smoke-test --no-intro --no-music --no-foliage
extends SceneTree

var checks := 0
var failures := 0
var game: Node
var net: Node

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func lowest_point(model: Node3D, bounds: AABB) -> float:
	var lowest := INF
	for i in 8:
		var corner: Vector3 = model.global_transform * bounds.get_endpoint(i)
		lowest = minf(lowest, corner.y)
	return lowest

func point_at(drone: AttackDrone, target: Vector3) -> void:
	for i in 4:
		var dir := drone.camera.global_position.direction_to(target)
		drone.yaw = atan2(-dir.x, -dir.z)
		drone.pitch = atan2(dir.y, Vector2(dir.x, dir.z).length())
		drone.update_view()

func last_zombie() -> Zombie:
	var found: Zombie = null
	for z in game.zombies_root.get_children():
		if z is Zombie: found = z
	return found

func run() -> void:
	net = root.get_node("NetSession")
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	check(net.host("Host", 24698) == OK, "The fixture hosts a round")
	if not net.is_host():
		quit(1)
		return
	net.roster[2] = "Anna"
	net.world.add_player(2)
	net._begin(net.epoch, false)
	game.waves.set_process(false)
	game.day_night.set_process(false)
	var world = net.world
	var host: Player = game.player
	var anna: Player = world.actor(2)
	host.set_physics_process(false)
	var w: Weapons = game.weapons
	# ---- the numbers
	check(Weapons.DEFS.lmg.reserve == 180 and w.reserve_limit("lmg") == 60 * 5 and Weapons.DEFS.ak47.reserve == 120 and w.reserve_limit("pistol") == 12 * 9, "Every gun carries one magazine more, in the pockets and at the limit")
	var all_more := true
	for id in Weapons.ORDER:
		if Weapons.is_melee(id): continue
		var mag: int = int(Weapons.DEFS[id].mag)
		var factor: int = int(Weapons.DEFS[id].get("reserve_factor", 8 if id == "pistol" else 4))
		if int(Weapons.DEFS[id].reserve) % mag != 0 or int(Weapons.DEFS[id].reserve) < mag * 2 or w.reserve_limit(id) != mag * (factor + 1): all_more = false
	check(all_more, "... for all %d firearms" % (Weapons.ORDER.size() - 2))
	check(Weapons.DEFS.lmg.damage == 80.0, "The MG-60 hits for 80")
	check(float(Weapons.DEFS.graviton_cannon.special.radius) >= 11.0, "The graviton blast reaches 11 m")
	check(float(DefenceTower.SPECS.mortar.damage) == 210.0 and DefenceTower.LIMIT == 40, "The mortar shell does 210, the team may raise 40 towers")
	check(AttackDrone.SPECS.scout.damage == 48.0 and AttackDrone.SPECS.viper.damage == 84.0 and AttackDrone.SPECS.tempest.damage == 124.0, "The drone guns hit twice as hard")
	check(float(Zombie.TYPES.spitter.ranged.structure) <= 24.0, "The acid eats at most 24 structure per second")
	check(Zombie.TYPES.earthworm.hp == 4400.0 and Zombie.TYPES.earthworm.damage == 70.0 and Zombie.TYPES.earthworm_ancient.hp == 6200.0 and Earthworm.GATE_HIT == 240.0 and Earthworm.EXPOSED_TIME < 7.0, "The earthworms are far stronger and strike sooner")
	check(game.defences.build_requirement(host, "standard") != "No more than 40 towers per team." or game.defences.towers.size() >= 40, "The limit message names 40")
	# ---- a whole acid pool no longer takes a timber gate down
	var gate: Barricade = game.barricades[0]
	gate.build()
	var gate_hp: float = gate.hp
	var pool := AcidPool.new()
	game.add_child(pool)
	pool.global_position = gate.attack_point(gate.center + Vector3(gate.normal2.x, 0, gate.normal2.y) * 3.0)
	pool.setup(Zombie.TYPES.spitter.ranged, false)
	for i in 13: pool._apply(0.5)
	check(gate.hp > 0.0 and gate.hp < gate_hp and pool.structure_dealt <= 24.0 * 6.5 + 0.01, "A full pool leaves the gate standing (%.0f -> %.0f, %.0f dealt)" % [gate_hp, gate.hp, pool.structure_dealt])
	pool.queue_free()
	gate.hp = gate_hp
	# ---- the stag keeps its hooves on the terrain
	check(game.spawn_zombie("zombie_stag", Vector2(10, 126), 1.0), "A stag stands on the meadow")
	var stag: ZombieBeast = last_zombie() as ZombieBeast
	if stag:
		stag.set_physics_process(false)
		await physics_frame
		var bounds: AABB = stag._mesh_bounds()
		stag._update_animation(0.016)
		var standing := lowest_point(stag.model, bounds) - stag.global_position.y
		check(absf(standing) < 0.12, "Standing, the lowest hoof rests on the terrain (%.2f m)" % standing)
		stag._charge_t = 1.5
		stag._lunge = 0.16
		stag._ground_speed = 8.0
		for i in 6: stag._update_animation(0.05)
		var charging := lowest_point(stag.model, bounds) - stag.global_position.y
		check(charging > -0.06 and absf(stag.model.rotation.x) > 0.05, "Charging head-down, no hoof goes below the terrain (%.2f m, tilt %.2f)" % [charging, stag.model.rotation.x])
		stag._charge_t = 0.0
		stag._lunge = 0.0
		stag.die(Vector3.FORWARD)
		await create_timer(0.7).timeout
		check(not stag.alive and stag.model.position.y > 0.15 and absf(absf(stag.model.rotation.z) - PI * 0.5) < 0.01, "The dead stag lies on its flank, not in the ground (centre %.2f m)" % stag.model.position.y)
		stag.queue_free()
		await process_frame
	# ---- the thrown tree is a forest tree
	var tree := ThrownTree.new()
	game.add_child(tree)
	tree.setup(Map.ground_pos(20, 120) + Vector3.UP * 14.0, Map.ground_pos(40, 120), 3.0, null, true)
	check(tree._visual.get_child_count() == 2, "The tree carries a root ball and one model")
	var meshes := tree._visual.find_children("*", "MeshInstance3D", true, false)
	var model: Node3D = tree._visual.get_child(1)
	var bounds := AABB()
	var first := true
	for m in meshes:
		if m.get_parent() == tree._visual: continue
		var b: AABB = (model.global_transform.affine_inverse() * m.global_transform) * m.get_aabb() if m.is_inside_tree() else m.get_aabb()
		bounds = b if first else bounds.merge(b)
		first = false
	check(meshes.size() >= 2 and not first and absf(bounds.size.y * model.scale.y - ThrownTree.HEIGHT) < 0.6, "The model is a %.1f m tree from the forest set (%d meshes)" % [bounds.size.y * model.scale.y, meshes.size()])
	tree.queue_free()
	# ---- the titan's crawl clip on every titan skin
	var crawl_all := true
	for skin in ["zombie_titan", "zombie_colossus", "zombie_bloater"]:
		var scene: PackedScene = load("res://assets/models/%s.glb" % skin)
		var probe: Node3D = scene.instantiate()
		var anim := probe.find_child("AnimationPlayer", true, false) as AnimationPlayer
		if not anim or not anim.has_animation("crawl"): crawl_all = false
		probe.free()
	check(crawl_all, "Titan, colossus and bloater carry the crawl clip")
	# ---- drone rockets and the self-destruct
	game.waves.wave = 5
	game.forest_keys.owned.waldhuette = true
	host.global_position = game.drones.station.to_global(Vector3(0, 0, 1.6))
	host.score = 5000
	check(game.drones.launch(host, "scout").is_empty() and host.controlling_drone > 0, "The pilot launches a scout")
	var drone: AttackDrone = game.drones.drones.get(host.controlling_drone)
	if drone:
		drone.global_position = Map.ground_pos(60, 112) + Vector3.UP * 6.0
		drone.velocity = Vector3.ZERO
		game.spawn_zombie("shambler", Vector2(60, 100), 1.0)
		var enemy := last_zombie()
		enemy.set_physics_process(false)
		enemy.agent.avoidance_enabled = false
		enemy.hp = 1.0
		await physics_frame
		await physics_frame
		point_at(drone, enemy.global_position + Vector3.UP * 1.0)
		var rockets_before: int = drone.rockets
		drone.rocket_pending = true
		drone._physics_process(0.016)
		var rocket: DroneRocket = null
		for child in game.get_children():
			if child is DroneRocket: rocket = child
		check(rocket != null and drone.rockets == rockets_before - 1 and drone.rocket_cooldown > 0.0, "A rocket leaves the drone (%d left)" % drone.rockets)
		var flown := 0
		while rocket and is_instance_valid(rocket) and not rocket.burst and flown < 200:
			rocket._physics_process(0.02)
			flown += 1
		check(not enemy.alive and enemy.killer_weapon == "drone" and enemy.killer_peer == 1, "The rocket's burst kills the zombie in its way and credits the pilot")
		drone.rocket_pending = true
		drone.rocket_cooldown = 1.0
		drone._physics_process(0.016)
		check(drone.rockets == rockets_before - 1, "The cooldown holds the next rocket back")
		# a right click becomes a rocket through the control packet
		var s: DroneSystem = game.drones
		var rmb := InputEventMouseButton.new()
		rmb.button_index = MOUSE_BUTTON_RIGHT
		rmb.pressed = true
		s.input_grace = 0.0
		s._input(rmb)
		check(s._rocket_pending, "A right click while flying queues a rocket")
		s._send_time = 0.0
		s._process(0.06)
		check(drone.rocket_pending and not s._rocket_pending, "... which the next control packet hands to the drone")
		drone.rocket_pending = false
		# the self-destruct
		await physics_frame
		for i in 3: game.spawn_zombie("shambler", Vector2(60 + i * 2.0, 108), 1.0)
		await physics_frame
		var near: Array = []
		for z in game.zombies_root.get_children():
			if z is Zombie and z.alive and z.global_position.distance_to(drone.global_position) < AttackDrone.DETONATE_RADIUS: near.append(z)
		check(near.size() == 3, "Three zombies stand inside the blast radius")
		for z in near: z.hp = 50.0
		var r_key := InputEventKey.new()
		r_key.physical_keycode = KEY_R
		r_key.pressed = true
		s._input(r_key)
		await physics_frame
		var dead := 0
		for z in near:
			if not z.alive: dead += 1
		check(dead == 3, "R blows the drone up and the blast kills all three (%d)" % dead)
		check(host.controlling_drone == 0 and game.drones.drones.is_empty() and float(game.drones.refit.get("scout", 0.0)) > 20.0, "The drone is gone and refits as destroyed")
	for z in game.zombies_root.get_children():
		if z is Zombie: z.queue_free()
	await process_frame
	# ---- the Mechanic's tower page: beacons in the world, the kind's icon, the next tier's numbers
	host.global_position = Map.ground_pos(60, 117) + Vector3.UP * 0.1
	var spot: Vector3 = Map.ground_pos(60, 112)
	await physics_frame
	await physics_frame
	var placed: String = game.defences.purchase(host, spot, 0.0, "standard", true)
	check(placed.is_empty() and game.defences.towers.size() == 1, "A sentinel stands for the Mechanic (%s)" % placed)
	var tower_id: int = game.defences.towers.keys()[0] if not game.defences.towers.is_empty() else 0
	var shop: Progression = game.progression
	shop.shop = "mechanic"
	shop.is_open = true
	shop.page = "Towers"
	shop._render()
	check(game.defences.markers_shown and game.defences._markers.has(tower_id) and is_instance_valid(game.defences._markers[tower_id]), "The tower page lights the beacons")
	var marker: Node3D = game.defences._markers.get(tower_id)
	var tag: Label3D = marker.get_child(0) as Label3D if marker else null
	check(tag != null and tag.text == "#%d" % tower_id and tag.no_depth_test, "The beacon shows the tower's number through walls")
	var row_text := ""
	for node in shop.rows.find_children("*", "RichTextLabel", true, false):
		row_text += Lang.text(node.text) + "\n"
	check(row_text.contains("Tier 1 → 2") and row_text.contains("damage 18 → 25"), "The row previews the next tier's numbers")
	check(ItemIcons.action_id(shop.request.bind("tower_upgrade", str(tower_id))) == "tower_standard", "The row's icon is the sentinel's own render")
	check(ItemIcons.texture("tower_mortar") != null and ItemIcons.texture("tower_nothing") == ItemIcons.texture("tower"), "Every kind has an icon, an unknown kind falls back to the generic tower")
	shop.page = "Quests"
	shop._render()
	check(not game.defences.markers_shown, "Another page puts the beacons out")
	shop.page = "Towers"
	shop._render()
	shop.close()
	check(not game.defences.markers_shown and game.defences._markers.is_empty(), "Closing the Mechanic puts them out too")
	# ---- spectating while down or bled out
	anna.global_position = Map.ground_pos(Map.FIRE.x - 6.0, Map.FIRE.y) + Vector3.UP * 0.3
	anna.rotation.y = 0.4
	anna.pitch = -0.1
	host.self_revives = 0
	host.go_down()
	world.tick(0.1)
	check(host.downed and world.spectating == 2 and host.spectating and world.spectator != null and world.spectator.current, "Down with a living teammate, the camera goes to her")
	var eye: Vector3 = anna.global_position + Vector3.UP * Player.EYE
	var forward := Vector3(-sin(anna.rotation.y), 0.0, -cos(anna.rotation.y))
	var offset: Vector3 = world.spectator.global_position - eye
	check(offset.dot(forward) < -1.5 and offset.length() < 3.4, "It hangs behind her shoulder (%.1f m)" % offset.length())
	check(not game.weapons.viewmodel.visible, "The own gun is out of the picture")
	for i in 2: await process_frame
	check(game.hud.downed_panel.visible and Lang.text(game.hud.downed_text.text).contains("Anna"), "The panel names who is being watched")
	net.roster[3] = "Ben"
	world.add_player(3)
	var ben: Player = world.actor(3)
	ben.global_position = Map.ground_pos(Map.FIRE.x + 6.0, Map.FIRE.y) + Vector3.UP * 0.3
	var lmb := InputEventMouseButton.new()
	lmb.button_index = MOUSE_BUTTON_LEFT
	lmb.pressed = true
	host._unhandled_input(lmb)
	world.tick(0.05)
	check(world.spectating == 3 and world.spectator.global_position.distance_to(ben.global_position) < 4.0, "A click switches to the next teammate")
	ben.go_down()
	world.tick(0.05)
	check(world.spectating == 2, "A teammate who goes down is no longer watched")
	host.revive(50.0)
	world.tick(0.05)
	check(not host.spectating and world.spectating == 0 and host.camera.current and game.weapons.viewmodel.visible, "Revived, the own camera and gun are back")
	host.alive = false
	host.downed = false
	world.tick(0.05)
	for i in 2: await process_frame
	check(world.local_dead and world.spectating == 2 and world.spectator.current and Lang.text(game.hud.downed_text.text).begins_with("YOU BLED OUT"), "Bled out, the camera watches the team until the revive")
	host.revive(40.0)
	world.tick(0.05)
	check(host.alive and not world.local_dead and host.camera.current and world.spectating == 0, "The revive ends the spectating")
	print("BATCH27_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
