# Palisade ring: geometry (closed, roads only crossed at the gates, navmesh enters only through gates) and
# behaviour (zombies outside sealed gates stay outside and attack the gate; a broken gate lets them in). Run:
#   Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=perimeter --smoke-test --no-intro --no-music
extends SceneTree

var game: Node
var began := Time.get_ticks_msec()
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func _process(_delta: float) -> bool:
	if Time.get_ticks_msec() - began > 240000:
		print("PERIMETER timeout")
		quit(1)
	return false

func check(name: String, ok: bool, detail := "") -> void:
	checks += 1
	if ok:
		print("PASS: ", name)
	else:
		failures += 1
		print("FAIL: ", name, "  ", detail)

func xz(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)

# wall (non-gate) edges crossed by the segment a -> b
func wall_crossings(ring: Perimeter, a: Vector2, b: Vector2) -> int:
	var n := 0
	for i in ring.points.size():
		if ring.gate_edge[i]: continue
		if Geometry2D.segment_intersects_segment(a, b, ring.points[i], ring.points[(i + 1) % ring.points.size()]) != null:
			n += 1
	return n

func outside_point(bar: Barricade, ring: Perimeter, dist: float) -> Vector2:
	var c := xz(bar.center)
	var p := c + bar.normal2 * dist
	if ring.contains(p):
		p = c - bar.normal2 * dist
	return p

func run() -> void:
	game = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	var ring: Perimeter = game.perimeter
	check("ring exists with more than 250 m of wall", ring != null and ring.length > 250.0, str(ring.length if ring else 0))
	check("ring has four gate openings", ring.gate_edge.count(true) == 4)
	check("fire, both huts and the fork are inside", ring.contains(Vector2(7, -7)) and ring.contains(Vector2(9.1, 4.6)) and ring.contains(Vector2(-3, 26.3)) and ring.contains(Vector2(7, 61)))
	var spawns_outside := true
	for lane in Map.SPAWNS:
		for p in Map.SPAWNS[lane]:
			if ring.contains(p): spawns_outside = false
	check("every lane spawn point is outside", spawns_outside)
	check("the intro start is outside", not ring.contains(Vector2(136, 108)))
	var road_hits := 0
	for road in Map.ROADS:
		var pts: PackedVector2Array = road["pts"]
		for i in pts.size() - 1:
			road_hits += wall_crossings(ring, pts[i], pts[i + 1])
	check("no wall crosses a road (roads pass only through gates)", road_hits == 0, "crossings=%d" % road_hits)
	check("logs were placed (more than 600)", ring.log_count > 600, str(ring.log_count))
	check("all palisade sections start hidden", ring.sections.all(func(s): return not s.visible))
	check("unbuilt sections have no collision or navigation obstacles", ring._section_bodies.all(func(b): return b.collision_layer == 0 and not b.is_in_group("navsource")))
	game.barricades[0].build()
	check("building one gate reveals only its section", ring.sections[0].visible and ring.sections.filter(func(s): return s.visible).size() == 1)
	check("built section blocks movement", ring._section_bodies[0].collision_layer == 1 and ring._section_bodies[0].is_in_group("navsource"))
	game.barricades[0].damage(1e6)
	check("destroyed section disappears and becomes passable", not ring.sections[0].visible and ring._section_bodies[0].collision_layer == 0)
	# Also exercise the rebuild path used by multiplayer snapshots and round resets.
	game.barricades[0].level = 1
	game.barricades[0].hp = 300.0
	game.barricades[0].rebuild()
	check("replicated build restores its section", ring.sections[0].visible)
	game.barricades[0].level = 0
	game.barricades[0].hp = 0.0
	game.barricades[0].rebuild()
	check("replicated reset hides its section", not ring.sections[0].visible)
	for bar in game.barricades:
		for k in 3: bar.build()
	await process_frame
	while game.nav_region.is_baking() or game._perimeter_navigation_dirty: await process_frame
	await physics_frame
	await physics_frame
	NavigationServer3D.map_force_update(game.nav_region.get_navigation_map())
	# Publishing the newly baked region is asynchronous, even after bake_finished.
	await create_timer(1.0).timeout
	# navmesh: from each lane spawn a path leads to the plaza and only passes the ring at a gate
	var nav_map: RID = game.nav_region.get_navigation_map()
	var plaza := Map.ground_pos(7, -3)
	for lane in Map.SPAWNS:
		var from := Map.ground_pos(Map.SPAWNS[lane][0].x, Map.SPAWNS[lane][0].y)
		var path := NavigationServer3D.map_get_path(nav_map, from, plaza, true)
		var reaches := path.size() > 1 and path[path.size() - 1].distance_to(plaza) < 3.0
		var crossings := 0
		for i in path.size() - 1:
			crossings += wall_crossings(ring, xz(path[i]), xz(path[i + 1]))
		check("lane %s: navmesh path reaches the plaza without crossing a wall" % lane, reaches and crossings == 0, "points=%d crossings=%d" % [path.size(), crossings])
	# behaviour: seal all gates, put zombies 20 m outside each gate
	for bar in game.barricades:
		for k in 3: bar.build()
	game.player.global_position = plaza + Vector3.UP * 0.2
	var lanes := {"ne": "north", "e": "east", "s": "south", "w": "west"}
	for bar in game.barricades:
		var p := outside_point(bar, ring, 20.0)
		for k in 3:
			game.spawn_zombie("shambler", p + Vector2(k * 1.5 - 1.5, 0), 1.0, lanes[str(bar.slot["id"])])
	await create_timer(30.0).timeout
	var inside := 0
	var alive := 0
	for z in game.zombies_root.get_children():
		if z is Zombie and z.alive:
			alive += 1
			if ring.contains(xz(z.global_position)): inside += 1
	var damaged := 0
	for bar in game.barricades:
		if bar.hp < bar.max_hp(): damaged += 1
	check("after 30 s no zombie is inside the sealed ring", inside == 0, "inside=%d alive=%d" % [inside, alive])
	check("the zombies attack the gates (at least three gates damaged)", damaged >= 3, "damaged=%d" % damaged)
	check("no gate broke yet at level 3", game.barricades.all(func(b): return b.level > 0))
	# breach: the Wiesentor falls, the zombies waiting there come in
	var gate: Barricade = game.barricades[1]
	gate.damage(1e6)
	check("a destroyed gate is level 0 again", gate.level == 0 and gate.hp <= 0.0)
	await create_timer(22.0).timeout
	inside = 0
	for z in game.zombies_root.get_children():
		if z is Zombie and z.alive and ring.contains(xz(z.global_position)): inside += 1
	check("after the breach zombies are inside the ring", inside >= 2, "inside=%d" % inside)
	check("the player survived behind the walls", game.player.alive)
	# the player vaults a built gate: stand 1.2 m outside the Weg zur Huette gate, face it, hold forward + Space
	var vault_gate: Barricade = game.barricades[0]
	var start := outside_point(vault_gate, ring, 1.2)
	game.player.global_position = Map.ground_pos(start.x, start.y) + Vector3.UP * 0.2
	game.player.velocity = Vector3.ZERO
	var to_gate: Vector3 = vault_gate.center - game.player.global_position
	game.player.rotation.y = atan2(-to_gate.x, -to_gate.z)
	check("vault test starts outside the ring in front of a built gate", not ring.contains(start) and vault_gate.level > 0)
	var space := InputEventKey.new()
	space.pressed = true
	space.physical_keycode = KEY_SPACE
	space.keycode = KEY_SPACE
	Input.action_press("move_forward")
	Input.parse_input_event(space)
	await create_timer(1.8).timeout
	Input.action_release("move_forward")
	space.pressed = false
	Input.parse_input_event(space)
	check("holding forward and Space carries the player over the gate barricade", ring.contains(xz(game.player.global_position)), str(game.player.global_position))
	print("PERIMETER_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
