extends SceneTree

var failures := 0
var checks := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	game._on_start()
	game.waves.set_process(false)
	game.player.set_physics_process(false)
	var progress: Progression = game.progression
	progress.set_process(false)
	progress._seen_npcs.clear()
	check(progress._seen_npcs.is_empty(), "NPCs start undiscovered")
	var npc: WorldNpc = progress.npcs.ranger
	var target := npc.global_position + Vector3.UP * 1.3
	game.player.global_position = npc.global_position + Vector3(0, 0.1, 2.3)
	game.player.camera.look_at(game.player.camera.global_position + Vector3.BACK)
	await physics_frame
	await physics_frame
	progress._discover_visible_npcs()
	check(not progress.has_seen_npc("ranger"), "Nearby NPC behind the player stays hidden")
	game.player.camera.look_at(target)
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 3, 0.2)
	shape.shape = box
	wall.add_child(shape)
	game.add_child(wall)
	wall.global_position = npc.global_position + Vector3(0, 1.2, 1)
	await physics_frame
	await physics_frame
	progress._discover_visible_npcs()
	check(not progress.has_seen_npc("ranger"), "Wall blocks discovery despite camera visibility")
	wall.free()
	await physics_frame
	await physics_frame
	progress._discover_visible_npcs()
	check(progress.has_seen_npc("ranger"), "First clear sight discovers NPC without a conversation")
	game.player.camera.look_at(game.player.camera.global_position + Vector3.BACK)
	progress._discover_visible_npcs()
	check(progress.has_seen_npc("ranger"), "Discovery remains after looking away")
	progress.apply_snapshot({"people": {}, "team": progress.team})
	check(progress.has_seen_npc("ranger"), "Host snapshots do not erase local discoveries")
	progress._seen_npcs.clear()
	game.player.global_position = npc.global_position + Vector3(0, 0, 40)
	game.player.camera.look_at(target)
	progress._discover_visible_npcs()
	check(not progress.has_seen_npc("ranger"), "Distant NPC does not reveal itself across the map")
	print("NPC_DISCOVERY_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
