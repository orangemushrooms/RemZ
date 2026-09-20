extends SceneTree

class World extends Node:
	var waves := {"completed": 0}
	var player := {"peer_id": 1}
	var barricades: Array = []
	var defences := {"towers": {}}

var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", message)

func run() -> void:
	var world := World.new()
	var shop := Progression.new()
	shop.game = world
	for id in Progression.QUESTS:
		var spec: Dictionary = Progression.QUESTS[id]
		shop.people.clear()
		var d := shop.data(1)
		d.claimed[spec.requires] = true
		world.waves.completed = maxi(0, int(spec.min_level) - 2)
		if int(spec.min_level) > 1:
			check(shop.quest_lock_reason(1, id).contains("Einsatzlevel"), id + " rejects acceptance below minimum level")
		world.waves.completed = int(spec.min_level) - 1
		check(shop.quest_lock_reason(1, id).is_empty(), id + " becomes available at intended level")
		d.accepted[id] = true
		d.accepted_wave[id] = world.waves.completed
		if int(spec.waves_after_accept) > 0:
			check(not shop.complete(id), id + " cannot be immediately claimed after acceptance")
			check(shop.quest_progress(id).contains("Nach Annahme"), id + " explains remaining wave requirement")
			world.waves.completed += int(spec.waves_after_accept)
			check(shop.required_completion_wave(1, id) == world.waves.completed, id + " uses a fixed completion boundary")
	shop.people.clear()
	world.waves.completed = 20
	shop.team.headshot_kills = 10000
	for peer in [1, 2]:
		var d := shop.data(peer)
		d.claimed.arrival = true
		d.accepted.steady_aim = true
		d.accepted_wave.steady_aim = 19 if peer == 1 else 20
	check(shop.complete("steady_aim", 1) and not shop.complete("steady_aim", 2), "Shared counters cannot bypass another peer's personal acceptance wave")
	check(shop.next_quest_step(2, "steady_aim").contains("noch 1 Welle"), "Peer-specific guidance uses its own progress")
	var snapshot := shop.snapshot()
	shop.people.clear()
	shop.apply_snapshot(snapshot)
	check(shop.complete("steady_aim", 1) and not shop.complete("steady_aim", 2), "Snapshot preserves acceptance boundaries")
	world.waves.completed = 21
	check(shop.complete("steady_aim", 2), "A later completion unlocks the second peer's reward")
	shop.data(2).claimed.steady_aim = true
	shop.data(2).accepted.marksman_training = true
	shop.data(2).accepted_wave.marksman_training = 21
	check(not shop.complete("marksman_training", 2), "Huge existing counters cannot immediately complete next chain stage")
	print("QUEST_BALANCE_DONE checks=%d failures=%d" % [checks, failures])
	shop.free()
	world.free()
	quit(1 if failures else 0)
