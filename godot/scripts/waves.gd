# Wave planning and spawning.
class_name Waves
extends Node

signal wave_started(number: int)

var main: Node
var hud: Hud
var player: Player
var weapons: Weapons
var wave := 0
var completed := 0
const MAX_ACTIVE := 72
var phase := "idle"
var timer := 4.0
var queue: Array = []
var spawn_t := 0.0
var speed_mul := 1.0
var total := 0
var boss_wave := false

func setup(m: Node, h: Hud, p: Player, w: Weapons) -> void:
	main = m
	hud = h
	player = p
	weapons = w
	hud.set_wave(1, "Bereit machen ...")

func _difficulty(key: String) -> float:
	if main and "difficulty" in main and main.difficulty is Dictionary:
		return float(main.difficulty.get(key, 1.0))
	return 1.0

# size of wave n without touching the random generator (shown during the intermission)
func preview_count(n: int) -> int:
	var count := int(round((10 + n * 5) * _difficulty("count")))
	if NetSession.enabled: count = roundi(count * (1.0 + 0.55 * (NetSession.roster.size()-1)))
	return count + (3 + n / 4 if n % 5 == 0 else 0) + titan_count(n)

# field titans: the first one in wave 6, then every third wave, a second from wave 12, a third from wave 24
static func titan_count(n: int) -> int:
	if n < 6 or n % 3 != 0: return 0
	return mini(3, 1 + n / 12)

func plan(n: int) -> Array:
	var q: Array = []
	# Titans enter across the open southern fields, never inside the forest.
	var fields := [Vector2(10, 126), Vector2(-110, 108), Vector2(-42, 126)]
	for i in titan_count(n):
		q.append({"type": "titan", "lane": "east" if i == 0 else "south", "point": fields[i]})
	var count := int(round((10 + n * 5) * _difficulty("count")))
	if NetSession.enabled: count = roundi(count * (1.0 + 0.55 * (NetSession.roster.size()-1)))
	boss_wave = n % 5 == 0
	if boss_wave:
		for k in 3 + n / 4:
			q.append({ "type": "brute", "lane": ["north", "south", "east", "west"][k % 4] })
	for i in count:
		var r := randf()
		var t := "shambler"
		if n >= 1 and r < 0.18 + n * 0.04:
			t = "runner"
		if n >= 2 and r > 0.7 and r < 0.85:
			t = "nurse"
		if n >= 3 and r > 0.85 and r < 0.93:
			t = "soldier"
		if n >= 3 and r > 0.92:
			t = "brute"
		var lr := randf()
		var lane := "north"
		if lr < 0.35:
			lane = "north"
		elif lr < 0.65:
			lane = "south"
		elif lr < 0.85:
			lane = "east"
		else:
			lane = "west"
		if n < 3 and lane == "west":
			lane = "north"
		q.append({ "type": t, "lane": lane })
	return q

func start(n: int) -> void:
	if NetSession.is_client(): return
	if NetSession.is_host(): NetSession.world.wave_started(n)
	wave = n
	wave_started.emit(n)
	# the fallen of the last round stay until the next wave begins, then sink into the forest floor
	if n > 1:
		for z in main.zombies_root.get_children():
			if z is Zombie and not z.alive:
				z.clear_body()
	queue = plan(n)
	total = queue.size()
	phase = "spawning"
	spawn_t = 0.0
	speed_mul = (1.0 + (n - 1) * 0.04) * _difficulty("speed")
	hud.set_wave(n, "%d Zombies" % queue.size())
	hud.set_wave_progress(total, total)
	if "achievements" in main and main.achievements:
		main.achievements.wave_started()
	hud.message("Welle %d" % n if not boss_wave else "Welle %d\nBOSSWELLE: die Brocken kommen" % n, 2.0 if not boss_wave else 3.5)
	if titan_count(n) > 0:
		hud.message("Welle %d · TITANEN\nBewegung auf dem Feld. Bereite die Verteidigung vor!" % n, 5.0)
	Sfx.play(self, "wave", -4.0)
	if main.music:
		main.music.play("combat")
	if n == 3 and not weapons.unlocked["shotgun"]:
		weapons.unlock("shotgun")
		hud.message("Welle 3\nSchrotflinte freigeschaltet (Taste 5)", 3.5)

func _process(delta: float) -> void:
	if NetSession.is_client() or (NetSession.enabled and (not main.started or main.over)):
		return
	if not player or (not NetSession.enabled and (not player.active or not player.alive)):
		return
	if phase == "intro":
		# the opening walk: no countdown, wave 1 is released when the Weg zur Hütte is reached
		hud.set_wave(1, "Erreiche den Weg zur Hütte")
		return
	if phase == "idle":
		timer -= delta
		if Input.is_action_just_pressed("next_wave") and wave > 0 and timer > 1.0:
			timer = 1.0
			hud.message("Welle %d kommt!" % (wave + 1), 1.2)
		var boss := (wave + 1) % 5 == 0 or titan_count(wave + 1) > 0
		hud.set_wave(wave + 1, "Start in %d s  ·  %d Zombies%s
Enter: sofort starten" % [ceili(timer), preview_count(wave + 1), "  ·  BOSSWELLE" if boss else ""])
		if timer <= 0.0:
			start(wave + 1)
	elif phase == "spawning":
		spawn_t -= delta
		if spawn_t <= 0.0 and queue.size() > 0 and main.alive_zombies() < MAX_ACTIVE:
			var e: Dictionary = queue.pop_front()
			var pts: Array = Map.SPAWNS[e["lane"]]
			var p: Vector2 = pts[randi() % pts.size()] + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
			if e.has("point"): p = e.point
			main.spawn_zombie(e["type"], p, speed_mul, e["lane"])
			spawn_t = maxf(0.3, 1.5 - wave * 0.1)
		var alive: int = main.alive_zombies()
		hud.set_wave(wave, "%d übrig" % (alive + queue.size()))
		hud.set_wave_progress(alive + queue.size(), total)
		if main.music:
			main.music.horde = clampf(alive / 10.0, 0.15, 1.0)
		if queue.is_empty() and alive == 0:
			if main.music:
				main.music.horde = 0.0
				main.music.play("night")
			completed = wave
			phase = "idle"
			timer = 18.0
			hud.set_wave_progress(0, total)
			if "achievements" in main and main.achievements:
				main.achievements.wave_cleared(wave)
			var bonus := 40 + wave * 10
			player.add_score(bonus)
			weapons.refill_all()
			if NetSession.is_host(): NetSession.world.wave_cleared(bonus)
			hud.message("Welle %d überstanden\n+%d Punkte, Munition aufgefüllt\nBaue Barrikaden mit E" % [wave, bonus], 4.0)
			Sfx.play(self, "menu", -6.0)
