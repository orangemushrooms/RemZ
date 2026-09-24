extends SceneTree

class World extends Node:
	var waves := {"completed": 4, "wave": 4}
	var player := {"peer_id": 1}
	var barricades: Array = []
	var defences := {"towers": {}}

var checks := 0
var failures := 0
func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", label)

func run() -> void:
	var world := World.new()
	var shop := Progression.new()
	shop.game = world
	var ids: Array = Progression.QUEST_CHAINS.drones.quests
	for i in ids.size():
		var id: String = ids[i]
		var spec: Dictionary = Progression.QUESTS[id]
		var kind: String = ["scout", "viper", "tempest"][i]
		var wave := int(spec.min_wave)
		world.waves.completed = wave-1
		world.waves.wave = wave-1
		shop.data(1).claimed[spec.requires] = true
		check(not shop.quest_lock_reason(1,id).is_empty(),id+" locked in break before required wave")
		world.waves.wave = wave
		check(shop.quest_lock_reason(1,id).is_empty(),id+" unlocks when wave starts")
		check(spec.npc == "mechanic",id+" belongs to Mechanic")
		check(not shop.complete(id,1),id+" must be accepted")
		shop.data(1).accepted[id] = true
		shop.data(1).accepted_wave[id] = world.waves.completed
		var meters := int(spec.goals["drone_"+kind+"_meters"])
		var kills := int(spec.goals["drone_"+kind+"_kills"])
		shop.record_drone_flight(kind,meters-0.5)
		for n in kills: shop.record_drone_kill(kind)
		check(not shop.complete(id,1),id+" cannot round distance up")
		shop.record_drone_flight(kind,0.5)
		check(shop.complete(id,1),id+" both goals complete at exact boundary")
		check(not shop.complete(id,2),id+" team progress does not accept another player's quest")
		shop.data(2).claimed[spec.requires] = true
		shop.data(2).accepted[id] = true
		shop.data(2).accepted_wave[id] = world.waves.completed
		check(shop.complete(id,2),id+" shared effort counts for second pilot")
		check(shop.completed_milestones(id,1).size()==2,id+" notification milestones include both goals")
		check(not shop.quest_progress(id,1).is_empty(),id+" journal displays progress")
		shop.data(1).claimed[id] = true
	var before := shop.team.duplicate(true)
	for bad in [NAN, INF, -1.0, 0.0]: shop.record_drone_flight("scout",bad)
	shop.record_drone_flight("unknown",100)
	shop.record_drone_kill("unknown")
	check(shop.team == before,"Invalid telemetry cannot corrupt counters")
	var state := shop.snapshot()
	shop.team.clear()
	shop.people.clear()
	shop.apply_snapshot(state)
	check(shop.team == before and shop.data(1).claimed.drone_air_support,"Snapshot preserves fractional counters and individual claims")
	check(shop.chain_complete(1,"drones") and not shop.chain_complete(2,"drones"),"Chain completion remains personal")
	shop.free()
	world.free()
	print("DRONE_QUESTS_DONE checks=%d failures=%d" % [checks,failures])
	quit(1 if failures else 0)
