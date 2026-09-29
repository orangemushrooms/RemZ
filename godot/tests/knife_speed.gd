extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ",message)

func run() -> void:
	CharacterProfile.persist = false
	var game: Node3D = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	current_scene = game
	while not game.navigation_ready: await process_frame
	var p: Player = game.player
	var w: Weapons = game.weapons
	w.set_weapon("pistol")
	var firearm_speed := p.effective_speed_mul()
	w.unlock("knife")
	w.set_weapon("knife")
	check(is_equal_approx(p.effective_speed_mul(),firearm_speed*Player.KNIFE_SPEED_MULTIPLIER),"Forest knife increases movement speed by ten percent")
	p.downed = true
	check(is_equal_approx(p.effective_speed_mul(),firearm_speed),"Downed crawl does not gain the knife bonus")
	p.downed = false
	w.set_weapon("pistol")
	check(is_equal_approx(p.effective_speed_mul(),firearm_speed),"Firearm restores baseline movement speed")
	print("KNIFE_SPEED_DONE checks=%d failures=%d" % [checks,failures])
	quit(0 if failures==0 else 1)
