extends SceneTree

var game: Node
var failures := 0
var checks := 0
var began := Time.get_ticks_msec()

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 240000: quit(1)
	return false

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	game.weapons.set_process(false)
	var bar: Barricade = game.barricades[1]
	bar.build()
	var center := Vector2(bar.center.x, bar.center.z)
	var outward := bar.normal2
	if game.perimeter.contains(center + outward * 4.0): outward = -outward
	var origin := center + outward * 4.0
	game.spawn_zombie("shambler", origin, 1.0, "east")
	var zombie: Zombie = game.zombies_root.get_children().back()
	zombie.set_physics_process(false)
	zombie.agent.avoidance_enabled = false
	zombie.siege_target = bar
	zombie.global_position = Map.ground_pos(origin.x, origin.y)
	game.player.global_position = Map.ground_pos(center.x - outward.x * 3, center.y - outward.y * 3)
	await physics_frame
	await physics_frame
	check(not zombie._nearby_player_priority(1.0), "Closed barricade prevents aggro through the gate")
	zombie._physics_process(0.016)
	check(zombie.siege_target == bar, "Zombie retains its gate target behind a closed barrier")
	var nearby := origin + bar.dir2 * 1.0
	game.player.global_position = Map.ground_pos(nearby.x, nearby.y)
	await physics_frame
	await physics_frame
	check(zombie._nearby_player_priority(1.0), "Nearby exposed player takes priority over committed siege target")
	zombie.attack_t = 0.0
	zombie._physics_process(0.016)
	check(zombie.hit_pending > 0 and zombie.hit_target == null, "Zombie swings at player instead of remembered barricade")
	var old_hp: float = game.player.hp
	zombie.hit_pending = 0.01
	zombie._physics_process(0.016)
	check(game.player.hp < old_hp, "Aggro attack actually damages player")
	var farther := origin + outward * 12.0
	game.player.global_position = Map.ground_pos(farther.x, farther.y)
	await physics_frame
	check(zombie._nearby_player_priority(1.0), "Acquired player stays targeted beyond initial aggro radius")
	farther = origin + outward * 18.0
	game.player.global_position = Map.ground_pos(farther.x, farther.y)
	await physics_frame
	check(not zombie._nearby_player_priority(1.0), "Distant player releases aggro")
	var return_target := bar.approach_point(zombie.global_position)
	zombie._physics_process(0.8)
	check(zombie.siege_target == bar and zombie.agent.target_position.distance_to(return_target) < 0.1, "Zombie resumes approaching its remembered barricade")
	game.waves.queue = [{"type": "shambler", "lane": "east"}]
	game.waves._update_stragglers(30.0, 1)
	check(not zombie.hunting, "Hunt waits until all enemies have spawned")
	game.waves.queue.clear()
	game.waves._update_stragglers(30.0, 4)
	check(not zombie.hunting, "Normal horde keeps its siege behaviour")
	game.waves._update_stragglers(19.0, 1)
	check(not zombie.hunting, "Last enemy gets a grace period")
	game.waves._update_stragglers(1.0, 1)
	check(zombie.hunting and zombie.siege_target == null and zombie.lane_bar == null, "Timeout releases the last enemy from stale gate targets")
	zombie._physics_process(1.0)
	check(zombie.siege_target == null and zombie.agent.target_position.distance_to(game.player.global_position) < 0.1, "Straggler pursues distant player instead of old gate")
	check(zombie.velocity.length() > 0.1, "Straggler actually moves toward exposed player")
	game.player.global_position = Map.ground_pos(center.x - outward.x * 3, center.y - outward.y * 3)
	await physics_frame
	zombie._aggro_check = 0.0
	zombie._physics_process(1.0)
	check(zombie.siege_target == bar, "Hunting zombie still attacks a gate that blocks the route")
	var held_gate := true
	for i in 3:
		zombie._physics_process(0.1)
		held_gate = held_gate and zombie.siege_target == bar
	check(held_gate, "Approaching the gate does not erase the route to the player")
	game.waves.start(2)
	check(game.waves._straggler_time == 0 and not game.waves._stragglers_hunting, "New wave resets the hunt timer")
	print("AGGRO_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
