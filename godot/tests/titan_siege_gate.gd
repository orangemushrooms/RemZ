# Why a field titan that reaches a gate may never damage it: it stops at `reach` and its slam
# lands at reach * 0.8, so the shockwave has to cross the remaining gap and keep a clear line.
# --suite=titan_siege_gate --smoke-test --no-intro --no-music --no-foliage
extends SceneTree

var game: Node3D
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, text: String) -> void:
	checks += 1
	if ok: print("PASS: ", text)
	else:
		failures += 1
		push_error("FAIL: " + text)

func run() -> void:
	seed(772)
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	var player: Player = game.player
	player.hp = 100000
	player.max_hp = 100000

	for index in game.barricades.size():
		for degrees: float in [0.0, 25.0, 45.0, -25.0, -45.0]:
			var bar: Barricade = game.barricades[index]
			bar.build()
			bar.hp = bar.max_hp()
			var outward := Vector3(bar.normal2.x, 0, bar.normal2.y).rotated(Vector3.UP, deg_to_rad(degrees))
			# Stand a titan exactly where the walk stops: `reach` away, outside the gate.
			var spot: Vector3 = bar.attack_point(bar.center + outward * 20.0) + outward * 14.0
			game.spawn_zombie("titan", Vector2(spot.x, spot.z), 1.0)
			var titan: Titan = game.zombies_root.get_child(game.zombies_root.get_child_count() - 1)
			titan.set_physics_process(false)
			titan.global_position = Map.ground_pos(spot.x, spot.z)
			await physics_frame
			await physics_frame
			var target: Vector3 = bar.attack_point(titan.global_position)
			titan.begin_strike(target)
			var reach_point: Vector3 = titan.strike_point
			var gap := reach_point.distance_to(bar.attack_point(reach_point))
			var line: bool = titan.clear_strike_line(bar.attack_point(reach_point), bar.body)
			var before := bar.hp
			titan.resolve_strike()
			var hurt := bar.hp < before
			print("GATE %d @ %+.0f deg: stand %.1f m out, slam lands %.1f m short, blast %.1f, line_clear=%s, damage=%s" % [
				index, degrees, titan.global_position.distance_to(target), gap, titan.blast_radius(), line, hurt])
			if not line:
				var q := PhysicsRayQueryParameters3D.create(reach_point + Vector3.UP, bar.attack_point(reach_point) + Vector3.UP, 1 | 8, [titan.get_rid()])
				var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
				print("   blocked by: ", hit.get("collider"), " groups=", hit.collider.get_groups() if hit.has("collider") else [])
			check(hurt, "Titan at reach damages gate %d from %+.0f deg" % [index, degrees])
			titan.queue_free()
			await physics_frame

	print("TITAN_SIEGE_GATE_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
