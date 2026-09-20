extends SceneTree

class DifficultyStub extends Node:
	var difficulty: Dictionary = GameSettings.DIFFICULTIES[1]

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	seed(21926)
	var waves := Waves.new()
	var stub := DifficultyStub.new()
	waves.main = stub
	var report := {"assumptions": "Normal difficulty; 100 seeded wave plans per wave; body kills without streaks, achievements, quests or spending. DPS includes reloads, assumes every projectile hits. Not a substitute for playtesting.", "waves": [], "weapons": {}}
	var cumulative := 0.0
	for n in range(1, 13):
		var bounty := 0.0
		for trial in 100:
			for entry in waves.plan(n): bounty += float(Zombie.TYPES[entry.type].score)
		bounty /= 100.0
		cumulative += bounty + 40 + n * 10
		report.waves.append({"wave": n, "enemies": waves.preview_count(n), "expected_bounty": snappedf(bounty, 0.1), "completion_bonus": 40 + n * 10, "cumulative_gross": snappedf(cumulative, 0.1)})
	for id in Weapons.ORDER:
		var d: Dictionary = Weapons.DEFS[id]
		var shop: Dictionary = Progression.GOODS.get(id, {"price": 0, "wave": 0, "ammo": 12})
		var cycle := (int(d.mag) - 1) * float(d.rate) + float(d.reload)
		report.weapons[id] = {"price": shop.price, "completed_wave_required": shop.wave, "body_damage": d.damage, "pellets": d.pellets,
			"magazine": d.mag, "sustained_dps": snappedf(int(d.mag) * float(d.damage) * int(d.pellets) / cycle, 0.1),
			"ammo_price_per_round": snappedf(float(shop.ammo) / (int(d.mag) * 2), 0.01), "titan_bonus": d.get("titan_multiplier", 1.0)}
	var file := FileAccess.open("res://../artifacts/progression/balance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	waves.free()
	stub.free()
	print("BALANCE_REPORT_DONE")
	quit()
