extends SceneTree

# The eight towers of 2 Oct 2026, mechanic by mechanic: the searchlight's mark and its stalker reveal,
# the siren's lure, the supply post's repairs and ammunition (and its one-per-team rule), the frost
# cannon's chill and freeze, the sniper's pierce and head hit, the rocket salvo's blast, the harpoon's
# tether on a brute, the graviton trap's pull, plus the tables every kind has to appear in, the roof
# bans, the Planes catalogue and the co-op snapshot fields. Headless:
#
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=tower_batch --smoke-test --no-intro --no-music --no-foliage
#   ... --render-towers (windowed): artifacts/towers2/<kind>.png, one picture per new tower in action
const NEW := ["searchlight", "siren", "supply", "frost", "sniper", "rocket", "harpoon", "graviton"]
var game: Node
var checks := 0
var failures := 0
var began := Time.get_ticks_msec()
var render := false
var folder := ProjectSettings.globalize_path("res://../artifacts/towers2/")

func _initialize() -> void: call_deferred("run")
func _process(_dt: float) -> bool:
	if Time.get_ticks_msec() - began > 300000:
		print("FAIL: tower_batch timeout")
		quit(1)
	return false

func check(ok: bool, text: String) -> void:
	checks += 1
	if ok: print("PASS: ", text)
	else:
		failures += 1
		push_error("FAIL: " + text)

func settle() -> void:
	await physics_frame
	await physics_frame

func shot(name: String) -> void:
	if not render: return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(folder + name + ".png")

func spawn(kind: String, at: Vector2, hp := 10000.0) -> Zombie:
	game.spawn_zombie(kind, at, 1)
	var z: Zombie = game.zombies_root.get_child(game.zombies_root.get_child_count() - 1)
	z.set_physics_process(false)
	z.agent.avoidance_enabled = false
	z.hp = hp
	return z

func clear_zombies() -> void:
	for z in game.zombies_root.get_children(): z.queue_free()
	await settle()

func run() -> void:
	render = "--render-towers" in OS.get_cmdline_user_args()
	if render: DirAccess.make_dir_recursive_absolute(folder)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	game.achievements.process_mode = Node.PROCESS_MODE_DISABLED
	game.day_night.set_process(false)
	game.day_night.set_time_hours(12)
	var defence: DefenceSystem = game.defences
	defence.set_process(false)
	var p: Player = game.player
	p.score = 100000
	game.waves.completed = 20
	var site := Map.ground_pos(60, 112)
	var camera := Camera3D.new()
	game.add_child(camera)
	camera.make_current()
	camera.global_position = site + Vector3(7, 6, 9)
	camera.look_at(site + Vector3(0, 2.5, -5))

	# --- the tables ----------------------------------------------------------------------------
	for kind in NEW:
		check(kind in DefenceTower.TYPES and DefenceTower.SPECS.has(kind), kind + " is a tower kind")
		var spec: Dictionary = DefenceTower.SPECS[kind]
		for key in ["unlock_waves", "name", "cost", "range", "damage", "rate", "heat", "health", "info"]:
			check(spec.has(key), kind + " spec carries " + key)
		check(preload("res://scripts/tower_audio.gd").CLIPS.has(kind) and ResourceLoader.exists("res://assets/audio/sfx/towers/%s.wav" % preload("res://scripts/tower_audio.gd").CLIPS[kind]), kind + " has its sound clip")
		check(kind == "supply" or ResourceLoader.exists("res://assets/models/tower_%s.glb" % kind), kind + " has its Meshy weapon model")
		check(ResourceLoader.exists("res://assets/ui/items/tower_%s.png" % kind), kind + " has its icon for the Mechanic's rows")
	var costs: Array = []
	for kind in DefenceTower.TYPES: costs.append(int(DefenceTower.SPECS[kind].cost))
	check(costs.max() == 900 and costs.min() == 120, "The ladder runs from the 120 R sentinel to the 900 R graviton trap")
	var waves: Array = []
	for kind in DefenceTower.TYPES: waves.append(int(DefenceTower.SPECS[kind].unlock_waves))
	var sorted_waves: Array = waves.duplicate()
	sorted_waves.sort()
	check(waves == sorted_waves, "TYPES is ordered by unlock wave: %s" % [waves])

	# --- the searchlight: a stalker lit, a target marked, towers hit it harder ----------------------
	var lamp := defence.create_tower(site, p.peer_id, 0, false, "searchlight")
	lamp.set_physics_process(false)
	var stalker := spawn("stalker", Vector2(60, 100))
	stalker.cloak = 0.07
	await settle()
	lamp.target = stalker
	lamp.aim_yaw = 0.0
	lamp.gun.rotation.y = lamp.aim_yaw
	for i in 30: lamp._physics_process(1.0 / 60.0)
	check(lamp._beam != null and lamp._beam.is_in_group("searchlights") and lamp._beam.light_energy > 0.5, "The lamp lights up once it rests on a target")
	check(stalker._lit_by_flashlight(), "A stalker inside the beam counts as lit by a lamp")
	check(stalker.spot_mark_t > 0.0, "The target carries the searchlight's mark")
	await shot("searchlight")
	var sentinel := defence.create_tower(Map.ground_pos(64, 112), p.peer_id, 0, false, "standard")
	sentinel.set_physics_process(false)
	await settle()
	var marked_hp := stalker.hp
	sentinel.target = stalker
	sentinel.fire_at(sentinel.target_point(stalker))
	var marked_hit := marked_hp - stalker.hp
	stalker.spot_mark_t = 0.0
	stalker.hp = 10000.0
	sentinel.fire_at(sentinel.target_point(stalker))
	var plain_hit := 10000.0 - stalker.hp
	check(marked_hit > 0.0 and is_equal_approx(marked_hit, plain_hit * DefenceTower.MARK_BONUS), "A marked body takes 15 %% more from another tower (%.1f vs %.1f)" % [marked_hit, plain_hit])
	sentinel.queue_free()
	lamp.queue_free()
	await clear_zombies()

	# --- the siren: the horde turns to the siren, bosses do not -----------------------------------
	var siren := defence.create_tower(site, p.peer_id, 0, false, "siren")
	siren.set_physics_process(false)
	var shambler := spawn("shambler", Vector2(60, 95))
	var brute := spawn("brute", Vector2(62, 95))
	var titan := spawn("titan", Vector2(70, 80))
	await settle()
	check(siren.can_see(shambler) and not siren.can_see(titan), "The siren counts the shambler and ignores the titan")
	siren.cooldown = 0.0
	siren._scan = 0.0
	siren._physics_process(0.02)
	check(siren.shots == 1 and siren.active_t > 10.0, "The siren sounds on its own once prey is in reach")
	check(shambler.lure_tower == siren and shambler.lure_t > 0.0 and brute.lure_tower == siren, "The shambler and the brute are lured")
	check(titan.lure_t == 0.0, "The titan is not lured")
	var chosen: Node3D = shambler._choose_defence(shambler.global_position, false)
	check(chosen == siren, "A lured zombie heads for the siren")
	chosen = shambler._choose_defence(shambler.global_position, true)
	check(chosen == siren, "The lure outranks a player standing close by")
	check(siren.cooldown > 40.0, "The siren needs 45 s before the next call")
	await shot("siren")
	siren.hp = 0.0
	shambler._nearby_player_priority(0.1)
	check(shambler.lure_t == 0.0 and shambler.lure_tower == null, "A fallen siren releases its lure")
	siren.queue_free()
	await clear_zombies()

	# --- the supply post: repairs, ammunition, one per team --------------------------------------------
	var post := defence.create_tower(site, p.peer_id, 0, false, "supply")
	post.set_physics_process(false)
	var neighbour := defence.create_tower(Map.ground_pos(63, 110), p.peer_id, 0, false, "standard")
	neighbour.set_physics_process(false)
	neighbour.hp = 100.0
	await settle()
	check(not post.can_see(neighbour as Node) if false else not post.can_see(spawn("shambler", Vector2(60, 100))), "The post never aims at a zombie")
	await clear_zombies()
	p.global_position = site + Vector3(2, 0.2, 2)
	var w: Weapons = game.weapons
	w.state.pistol.reserve = 0
	check(post._supply_needed(), "A damaged tower and an empty pocket call for a tick")
	post.fire_at(site + Vector3.UP * 2)
	check(neighbour.hp > 100.0 and neighbour.hp <= neighbour.max_hp(), "The tick repairs the neighbouring tower (%.0f)" % neighbour.hp)
	check(w.state.pistol.reserve > 0, "The tick hands the player half a magazine")
	var reserve: int = w.state.pistol.reserve
	post.fire_at(site + Vector3.UP * 2)
	check(w.state.pistol.reserve == reserve, "Ammunition comes once per 20 s and player")
	check(not defence.placement_error(p, Map.ground_pos(70, 112), "supply").is_empty(), "A second supply post is refused")
	check(defence.placement_error(p, Map.ground_pos(70, 112), "standard", true).is_empty(), "Other kinds still build beside it")
	for kind in DefenceTower.ROOF_BANNED:
		check(not defence.placement_error(p, defence.roof_position(1), kind, true).is_empty(), kind + " may not go onto the roof")
	await shot("supply")
	post.queue_free()
	neighbour.queue_free()
	await settle()

	# --- the frost cannon: chill builds up, then the body freezes ------------------------------------
	var frost := defence.create_tower(site, p.peer_id, 0, false, "frost")
	frost.set_physics_process(false)
	var runner := spawn("runner", Vector2(60, 104))
	await settle()
	frost.target = runner
	frost.fire_at(frost.target_point(runner))
	check(runner.hp < 10000.0, "A cold pulse hurts")
	check(runner.frost_mul < 1.0, "The first pulses chill the body (pace x%.2f)" % runner.frost_mul)
	for i in 12: frost.fire_at(frost.target_point(runner))
	check(runner.rare_status.contains("frost"), "Enough pulses freeze it solid")
	await shot("frost")
	frost.queue_free()
	await clear_zombies()

	# --- the sniper nest: one round through three bodies, the head hit ------------------------------------
	var nest := defence.create_tower(site, p.peer_id, 0, false, "sniper")
	nest.set_physics_process(false)
	var line: Array[Zombie] = []
	for z_at in [Vector2(60, 100), Vector2(60, 97), Vector2(60, 94), Vector2(60, 91)]: line.append(spawn("shambler", z_at))
	await settle()
	nest.target = line[0]
	nest.shoot()
	var hit_count := 0
	for z in line: if z.hp < 10000.0: hit_count += 1
	check(hit_count >= 2 and hit_count <= 3, "The round goes through up to three bodies (%d hit)" % hit_count)
	check(line[0].hp < line[1].hp or line[1].hp == 10000.0, "The first body takes the most")
	check(line[0].last_headshot or (10000.0 - line[0].hp) >= nest.damage_at(1) * 0.99, "The nest aims for the head (head hit %s, %.0f damage)" % [line[0].last_headshot, 10000.0 - line[0].hp])
	check(nest.aim_fov() < 35.0, "The nest's sights zoom in like a scope")
	await shot("sniper")
	nest.queue_free()
	await clear_zombies()

	# --- the rocket pod: a salvo of four with a blast, nothing inside eight metres ---------------------------
	var pod := defence.create_tower(site, p.peer_id, 0, false, "rocket")
	pod.set_physics_process(false)
	var close := spawn("shambler", Vector2(60, 107))
	var far := spawn("shambler", Vector2(60, 90))
	var beside := spawn("shambler", Vector2(63, 90))
	await settle()
	check(not pod.can_see(close) and pod.can_see(far), "Nothing inside the minimum range, the far one is a target")
	pod.target = far
	pod.shoot()
	var rockets := 0
	for node in game.get_children(): if node is DroneRocket: rockets += 1
	check(rockets >= 1 and pod.shots == 1, "The first rocket leaves at once (%d in flight)" % rockets)
	await create_timer(0.5, false).timeout
	rockets = 0
	for node in game.get_children(): if node is DroneRocket: rockets += 1
	check(rockets >= 2 or far.hp < 10000.0, "The rest of the salvo follows")
	await shot("rocket")
	await create_timer(1.5, false).timeout
	check(far.hp < 10000.0 and beside.hp < 10000.0, "The blasts hurt the target and its neighbour")
	check(far.killer_weapon == "tower", "Rocket kills are credited to the tower")
	pod.queue_free()
	await clear_zombies()

	# --- the harpoon: a brute on the rope at half pace, small fry barely scratched -------------------------
	var launcher := defence.create_tower(site, p.peer_id, 0, false, "harpoon")
	launcher.set_physics_process(false)
	var big := spawn("brute", Vector2(60, 98))
	var small := spawn("shambler", Vector2(62, 100))
	await settle()
	check(DefenceTower.is_heavy(big) and not DefenceTower.is_heavy(small), "The brute counts as heavy, the shambler does not")
	launcher.target = big
	launcher.shoot()
	check(big.hp < 10000.0 and big.tether_t > 5.0 and launcher.tether == big, "The harpoon tethers the brute")
	launcher._physics_process(0.016)
	check(launcher._rope.visible, "The rope hangs between launcher and brute")
	await shot("harpoon")
	launcher.tether_t = 0.0
	launcher.tether = null
	launcher.cooldown = 0.0
	launcher.target = small
	launcher.shoot()
	check(10000.0 - small.hp < (10000.0 - big.hp) * 0.5 and small.tether_t == 0.0, "A shambler takes a third of the harpoon and no rope")
	launcher.queue_free()
	await clear_zombies()

	# --- the graviton trap: the heap --------------------------------------------------------------------
	var trap := defence.create_tower(site, p.peer_id, 0, false, "graviton")
	trap.set_physics_process(false)
	var ring: Array[Zombie] = []
	for z_at in [Vector2(56, 96), Vector2(64, 96), Vector2(60, 92)]: ring.append(spawn("shambler", z_at))
	await settle()
	var centre := Map.ground_pos(60, 96)
	trap.fire_at(centre + Vector3.UP)
	var pulled := 0
	for z in ring:
		if z._knock.length() > 0.1 and z._knock.normalized().dot((centre - z.global_position).normalized()) > 0.7: pulled += 1
	check(pulled == ring.size(), "Every body in the ring is dragged towards the impact (%d)" % pulled)
	check(ring[0].hp < 10000.0, "The implosion hurts a little")
	await shot("graviton")
	trap.queue_free()
	await clear_zombies()

	# --- replication: a late joiner gets the rope, the wail and the beam -----------------------------------
	var host := defence.create_tower(site, p.peer_id, 0, false, "harpoon")
	host.set_physics_process(false)
	host.tether_t = 4.0
	host.tether_end = site + Vector3(0, 3, -12)
	host.active_t = 2.0
	var mirror := DefenceSystem.new()
	mirror.game = game
	game.add_child(mirror)
	mirror.set_process(false)
	mirror.apply_snapshot(defence.snapshot(), true)
	var copy: DefenceTower = mirror.towers[host.tower_id]
	copy.set_physics_process(false)
	check(copy.tether_t > 3.9 and copy.tether_end.is_equal_approx(host.tether_end) and copy.active_t > 1.9, "The snapshot carries rope end, tether and activity")
	copy._update_special_visuals(0.016)
	check(copy._rope.visible, "A replica draws the rope from the snapshot")
	mirror.apply_snapshot({}, false)
	mirror.queue_free()
	host.queue_free()
	await settle()

	# --- the Planes: the same catalogue, the same prices ------------------------------------------------
	for kind in NEW:
		check(defence.unlock_reason(kind).is_empty(), kind + " is unlocked once its wave is survived (planes and forest share DefenceTower.SPECS)")
	print("TOWER_BATCH_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
