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
	var bar: Barricade = game.barricades[0]
	check(not bar.health_display.visible, "Empty building site has no health bar")
	bar.build()
	check(bar.health_display.visible and bar.health_label.text == "300 / 300", "Building shows full health without focus")
	bar.damage(225)
	check(bar.health_label.text == "75 / 300" and is_equal_approx(bar.health_fill.region_rect.size.x, 64), "Damage updates number and proportional fill")
	check(bar.health_fill.modulate.r > bar.health_fill.modulate.g, "Critical health turns red")
	bar.repair()
	check(bar.health_label.text == "300 / 300" and bar.health_fill.region_rect.size.x == 256, "Repair restores the full bar")
	bar.build()
	check(bar.health_label.text == "600 / 600", "Upgrade updates maximum health")
	bar.hp = 200
	bar.changed.emit()
	check(bar.health_label.text == "200 / 600", "Replicated health changes refresh the display")
	bar.damage(10000)
	check(not bar.health_display.visible, "Destroyed barricade hides its bar")
	bar.build()
	check(bar.health_display.visible and bar.health_label.text == "300 / 300", "Rebuilding restores the display")
	print("BARRICADE_HEALTH_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
