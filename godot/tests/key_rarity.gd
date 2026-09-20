extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var random := RandomNumberGenerator.new()
	random.seed = 54321
	var counts := [0, 0]
	var empty_runs := 0
	var both_runs := 0
	for i in 10000:
		var first := ForestKeys.roll_spawn(random)
		var second := ForestKeys.roll_spawn(random)
		if first: counts[0] += 1
		if second: counts[1] += 1
		if not first and not second: empty_runs += 1
		if first and second: both_runs += 1
	var ok: bool = counts[0] > 1800 and counts[0] < 2200 and counts[1] > 1800 and counts[1] < 2200 and empty_runs > 6000 and both_runs < 600
	print("KEY_RARITY counts=%s empty=%d both=%d" % [counts, empty_runs, both_runs])
	print("KEY_RARITY_DONE failures=%d" % (0 if ok else 1))
	quit(0 if ok else 1)
