extends SceneTree

class GameStub:
	extends Node3D
	var started := true
	var over := false
	var waves := {"wave": 1, "phase": "spawning"}

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", description)

func run() -> void:
	var game := GameStub.new()
	root.add_child(game)
	var keys := ForestKeys.new()
	game.add_child(keys)
	keys.set_process(false)
	keys.main = game
	var key := ForestKey.new()
	key.key_id = "waldhuette"
	key.pickup_visual = Node3D.new()
	key.add_child(key.pickup_visual)
	keys.spawned.append(key)
	var random := RandomNumberGenerator.new()
	var success_seed := 0
	while true:
		random.seed = success_seed
		if ForestKeys.roll_spawn(random): break
		success_seed += 1
	for phase in ["spawning", "idle"]:
		key.taken = true
		key.pickup_visual.hide()
		keys._spawn_random.seed = success_seed
		game.waves.phase = phase
		keys.refresh_availability()
		check(not key.taken and key.pickup_visual.visible, "Missing key can appear in phase " + phase)
		key.taken = true
		var state := keys._spawn_random.state
		keys.refresh_availability()
		check(key.taken and keys._spawn_random.state == state, "Repeated frames do not reroll phase " + phase)
	game.waves.wave = 2
	keys._spawn_random.seed = success_seed
	keys.refresh_availability()
	check(not key.taken, "Same phase in a later wave gives another chance")
	game.waves.phase = "spawning"
	var state := keys._spawn_random.state
	keys.refresh_availability()
	check(not key.taken and keys._spawn_random.state == state, "Available uncollected key persists without another roll")
	keys.owned.waldhuette = true
	key.taken = true
	game.waves.phase = "idle"
	keys.refresh_availability()
	check(key.taken and keys._spawn_random.state == state, "Owned key never respawns")
	keys.owned.clear()
	game.waves.wave = 3
	paused = true
	keys.refresh_availability()
	check(keys._last_spawn_phase == "2:idle", "Pause does not consume a new phase's chance")
	paused = false
	game.over = true
	keys.refresh_availability()
	check(keys._last_spawn_phase == "2:idle", "Game over does not spawn keys")
	key.free()
	print("KEY_PHASES_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
