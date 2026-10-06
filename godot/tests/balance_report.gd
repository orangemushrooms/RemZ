extends SceneTree

var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS: " if ok else "FAIL: ", message)

class DifficultyStub extends Node:
	var difficulty: Dictionary = GameSettings.DIFFICULTIES[1]
	var day_night = null   # waves.gd asks the main scene for the clock (blood moon, 26 Sep 2026); the stub has none

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
			# What a kill actually pays: score x KILL_VALUE (main.gd), before streaks and headshots.
			for entry in waves.plan(n): bounty += float(Zombie.TYPES[entry.type].score) * 0.6
		bounty /= 100.0
		var completion := 20 + n * 6   # waves.gd pays this, not 40 + n * 10
		check(is_finite(bounty) and bounty > 0 and waves.preview_count(n) > 0, "Wave %d has enemies and a finite positive expected reward" % n)
		cumulative += bounty + completion
		report.waves.append({"wave": n, "enemies": waves.preview_count(n), "expected_bounty": snappedf(bounty, 0.1), "completion_bonus": completion, "cumulative_gross": snappedf(cumulative, 0.1)})
	for id in Weapons.ORDER:
		var d: Dictionary = Weapons.DEFS[id]
		var shop: Dictionary = Progression.GOODS.get(id, {"price": 0, "wave": 0, "ammo": 12})
		var cycle := (int(d.mag) - 1) * float(d.rate) + float(d.reload)
		check(cycle > 0 and shop.price >= 0 and shop.ammo >= 0 and d.damage > 0, "Weapon %s has valid combat and economy parameters" % id)
		report.weapons[id] = {"price": shop.price, "completed_wave_required": shop.wave, "body_damage": d.damage, "pellets": d.pellets,
			"magazine": d.mag, "sustained_dps": snappedf(int(d.mag) * float(d.damage) * int(d.pellets) / cycle, 0.1),
			"ammo_price_per_round": snappedf(float(shop.ammo) / maxf(1.0, float(int(d.mag) * 2)), 0.01), "titan_bonus": d.get("titan_multiplier", 1.0)}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://../artifacts/progression"))
	var file := FileAccess.open("res://../artifacts/progression/balance.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	waves.free()
	stub.free()
	print("BALANCE_REPORT_DONE checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)
