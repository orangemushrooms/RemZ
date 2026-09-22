extends SceneTree
var game: Node3D
var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
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
	var p: Player = game.player
	var f: Fireworks = game.fireworks
	p.set_physics_process(false)
	p.score = 10000
	p.global_position = game.progression.npcs.camp.global_position + Vector3(0,0,1)
	for id in ["fw_battery_40", "fw_battery_90"]:
		var before := p.score
		game.progression.transact(p, "camp", "firework", id)
		check(f.stock(p.peer_id)[id] == 1 and p.score == before - int(Fireworks.DEFS[id].price), id + " purchase charges price and grants one box")
		check(ResourceLoader.exists("res://assets/models/" + str(Fireworks.DEFS[id].model) + ".glb"), id + " has Meshy model")
		f.select(id)
		check(f.armed and f.held.find_children("*", "MeshInstance3D", true, false).size() > 0, id + " can be equipped with visible box")
		f.cancel()
	var platform := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20,0.2,20)
	collider.shape = box
	platform.add_child(collider)
	game.add_child(platform)
	platform.position = Vector3(0,80,0)
	p.global_position = Vector3(0,80.2,0)
	p.rotation = Vector3.ZERO
	await physics_frame
	await physics_frame
	var error := f.ignite(p, "fw_battery_40")
	check(error.is_empty() and f.stock(p.peer_id).fw_battery_40 == 0, "Flat open placement consumes one battery: " + error)
	var first = f.active.values()[0] if not f.active.is_empty() else null
	check(first != null and first.get_script() == Fireworks.Battery, "Ignition instantiates battery timeline")
	f.cooldowns.clear()
	var stock_before: int = f.stock(p.peer_id).fw_battery_90
	error = f.ignite(p, "fw_battery_90")
	check(not error.is_empty() and f.stock(p.peer_id).fw_battery_90 == stock_before, "Overlapping placement rejected without spending stock")
	p.global_position.x += 5
	error = f.ignite(p, "fw_battery_90")
	check(error.is_empty(), "Second battery can be placed with clearance: " + error)
	f.stock(p.peer_id).fw_battery_40 = 1
	f.cooldowns.clear()
	p.global_position.x -= 10
	check(not f.ignite(p, "fw_battery_40").is_empty() and f.stock(p.peer_id).fw_battery_40 == 1, "Concurrent battery limit preserves stock")
	for id in ["fw_battery_40", "fw_battery_90"]:
		var spec: Dictionary = Fireworks.DEFS[id]
		var effect = Fireworks.make_effect(id)
		effect.configure(id, Vector3(0,80.2,0), Vector3.ZERO, 123, float(spec.duration) * 0.5)
		game.add_child(effect)
		effect.set_process(false)
		check(is_equal_approx(effect.shot_time(int(spec.shots) - 1) - effect.shot_time(0), float(spec.duration)), id + " launch sequence lasts exact advertised duration")
		check(effect.next_shot > 0 and effect.next_shot < int(spec.shots), id + " late join resumes in middle of sequence")
		var shells := 0
		for child in effect.get_children():
			if child.get_script() == Fireworks.Effect:
				shells += 1
				check(child.shell_mode and child.age < 9.7, "Late join restores only live shells without stick models")
		check(shells > 0 and shells < 18, "Live shell count stays bounded")
		var sent: int = effect.next_shot
		effect._tick()
		check(effect.next_shot == sent, "Repeated timeline update does not duplicate salvos")
		var payload: Array = effect.state()
		var replica = Fireworks.make_effect(str(payload[0]))
		replica.configure(payload[0], payload[1], payload[2], payload[3], payload[4], payload[5])
		game.add_child(replica)
		replica.set_process(false)
		check(replica.next_shot == effect.next_shot, "Snapshot replica resumes identical salvo index")
		replica.queue_free()
		effect.age = 1.2 + float(spec.duration)
		effect._tick()
		check(effect.next_shot == int(spec.shots) and not effect.fuse.emitting, "Final salvo ends firing at advertised duration")
		effect._process(10.1)
		check(effect.is_queued_for_deletion(), "Finished battery cleans up")
		await process_frame
	if "--render-batteries" in OS.get_cmdline_user_args():
		game.day_night.set_time_hours(21.0)
		game.weapons.viewmodel.hide()
		var camera := Camera3D.new()
		game.add_child(camera)
		camera.make_current()
		var at := Map.ground_pos(-100,155) + Vector3.UP * 0.04
		for id in ["fw_battery_40", "fw_battery_90"]:
			var visual = Fireworks.make_effect(id)
			visual.configure(id, at, at, 123, 0)
			game.add_child(visual)
			visual.set_process(false)
			camera.global_position = at + Vector3(1.5,1.4,2)
			camera.look_at(at + Vector3.UP * 0.35)
			await capture(id + "-box")
			visual.queue_free()
		var show = Fireworks.make_effect("fw_battery_90")
		show.configure("fw_battery_90", at, at, 123, 30.0)
		game.add_child(show)
		show.set_process(false)
		camera.global_position = at + Vector3(0,2,32)
		camera.look_at(at + Vector3.UP * 32)
		await capture("battery-salvos")
	print("BATTERIES_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)


func capture(id: String) -> void:
	for frame in 12: await process_frame
	await RenderingServer.frame_post_draw
	var folder := ProjectSettings.globalize_path("res://../artifacts/firework-batteries/")
	DirAccess.make_dir_recursive_absolute(folder)
	root.get_texture().get_image().save_png(folder + id + ".png")
