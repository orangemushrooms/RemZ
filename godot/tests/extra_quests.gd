extends SceneTree

class QuestWorld extends Node:
	var waves := {"completed": 0}
	var barricades: Array = []
	var defences := {"towers": {}}
	var player := {"peer_id": 1}

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	var world := QuestWorld.new()
	var shop := Progression.new()
	shop.game = world
	for i in 2:
		world.barricades.append(Barricade.new())
		world.defences.towers[i] = DefenceTower.new()
	var added := 0
	for id in Progression.QUESTS:
		var q: Dictionary = Progression.QUESTS[id]
		if not q.has("goals"): continue
		added += 1
		shop.team = {"headshot_kills": 0, "tower_kills": 0, "kills": 0, "titans": 0}
		world.waves.completed = 0
		for bar: Barricade in world.barricades:
			bar.level = 0
			bar.hp = 0
		for tower: DefenceTower in world.defences.towers.values(): tower.hp = 0
		check(not shop.complete(id), id + " starts incomplete")
		for goal in q.goals:
			var target := int(q.goals[goal])
			match goal:
				"waves": world.waves.completed = target
				"reinforced_barricades":
					for bar: Barricade in world.barricades:
						bar.level = 2
						bar.hp = 600
				"active_towers", "elite_towers":
					for tower: DefenceTower in world.defences.towers.values():
						tower.level = 3
						tower.hp = 600
				_: shop.team[goal] = target
		check(shop._objectives_complete(id), id + " satisfies objectives at its targets")
		check(not shop.quest_progress(id).is_empty(), id + " has progress text")
		shop.people.clear()
		var personal := shop.local_data()
		personal.discovered = true
		personal.accepted[id] = true
		world.waves.completed = maxi(world.waves.completed, int(q.min_level) - 1 + int(q.waves_after_accept))
		personal.accepted_wave[id] = world.waves.completed - int(q.waves_after_accept)
		check(not shop.has_ready_quest(q.npc), id + " respects prerequisite")
		personal.claimed[q.requires] = true
		check(shop.has_ready_quest(q.npc), id + " marks the right giver")
		personal.claimed[id] = true
		check(not shop.has_ready_quest(q.npc), id + " clears marker after reward")
	check(added == 13, "Thirteen goal-based quests including Marksman training")
	shop.team = {}
	shop.event("headshot_kills")
	shop.event("tower_kills")
	var snapshot := shop.snapshot()
	shop.team.clear()
	shop.apply_snapshot(snapshot)
	check(shop.goal_value("headshot_kills") == 1 and shop.goal_value("tower_kills") == 1, "New team counters survive snapshots and missing legacy keys")
	for tower: DefenceTower in world.defences.towers.values(): tower.hp = 0
	check(shop.goal_value("elite_towers") == 0, "Destroyed towers do not satisfy defence goals")
	for bar: Barricade in world.barricades: bar.free()
	for tower: DefenceTower in world.defences.towers.values(): tower.free()
	shop.free()
	world.free()
	print("EXTRA_QUESTS_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
