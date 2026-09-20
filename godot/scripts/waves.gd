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
const SPAWN_DISTANCE := 28.0
const TITAN_SPAWN_DISTANCE := 40.0
const SPAWN_RETRY_DELAY := 1.0
const TITAN_FIELDS := [Vector2(10, 126), Vector2(-110, 108), Vector2(-42, 126)]
const STRAGGLER_LIMIT := 3
const STRAGGLER_DELAY := 20.0
var _straggler_time := 0.0
var _stragglers_hunting := false
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
	var fields := TITAN_FIELDS
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
	_straggler_time = 0.0
	_stragglers_hunting = false
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

func skip_current_wave() -> bool:
	if NetSession.is_client() or not main.started or main.over:
		return false
	queue.clear()
	for zombie in main.zombies_root.get_children():
		if zombie is Zombie and zombie.alive:
			zombie.damage(maxf(zombie.hp, 1.0), Vector3.ZERO)
	if phase == "spawning":
		_complete_wave()
	start(wave + 1)
	return true

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
			# Keep blocked entries queued, but allow other enemy types to enter meanwhile.
			var e: Dictionary = queue[0]
			if _try_spawn(e):
				queue.pop_front()
				spawn_t = maxf(0.3, 1.5 - wave * 0.1)
			else:
				queue.append(queue.pop_front())
				spawn_t = SPAWN_RETRY_DELAY
		var alive: int = main.alive_zombies()
		_update_stragglers(delta, alive)
		hud.set_wave(wave, "%d übrig" % (alive + queue.size()))
		hud.set_wave_progress(alive + queue.size(), total)
		if main.music:
			main.music.horde = clampf(alive / 10.0, 0.15, 1.0)
		if queue.is_empty() and alive == 0:
			_complete_wave()

func _complete_wave() -> void:
	if main.music:
		main.music.horde = 0.0
		main.music.play("night")
	completed = wave
	phase = "idle"
	timer = 90.0
	hud.set_wave_progress(0, total)
	if "achievements" in main and main.achievements:
		main.achievements.wave_cleared(wave)
	var bonus := 20 + wave * 6
	player.add_score(bonus)
	weapons.refill_all()
	if NetSession.is_host(): NetSession.world.wave_cleared(bonus)
	hud.message("Welle %d überstanden\n+%d Punkte, Pistolenreserve gesichert\nHändler und Aufträge: Vendor & Mechanic · T: Turm" % [wave, bonus], 4.0)
	Sfx.play(self, "menu", -6.0)

func _try_spawn(entry: Dictionary) -> bool:
	if entry["type"] == "titan":
		# Giants stay on the open fields even when their planned entrance is occupied.
		var fields: Array = TITAN_FIELDS.duplicate()
		if entry.has("point"):
			fields.erase(entry.point)
			fields.push_front(entry.point)
		for point: Vector2 in fields:
			var lane := "east" if point == TITAN_FIELDS[0] else "south"
			if main.spawn_zombie("titan", point, speed_mul, lane, TITAN_SPAWN_DISTANCE):
				return true
		return false
	var lanes: Array = Map.SPAWNS.keys()
	lanes.shuffle()
	lanes.erase(entry["lane"])
	lanes.push_front(entry["lane"])
	for lane: String in lanes:
		var points: Array = Map.SPAWNS.get(lane, []).duplicate()
		points.shuffle()
		for point: Vector2 in points:
			var candidate := point + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
			if main.spawn_zombie(entry["type"], candidate, speed_mul, lane, SPAWN_DISTANCE):
				return true
	return false

func _update_stragglers(delta: float, alive: int) -> void:
	if not queue.is_empty() or alive <= 0 or alive > STRAGGLER_LIMIT:
		_straggler_time = 0.0
		return
	if _stragglers_hunting: return
	_straggler_time += delta
	if _straggler_time < STRAGGLER_DELAY: return
	_stragglers_hunting = true
	for zombie in main.zombies_root.get_children():
		if zombie is Zombie and zombie.alive: zombie.begin_hunt()
	hud.message("Die letzten Zombies suchen dich!", 3.0)
	if NetSession.is_host():
		for peer in NetSession.ready_peers:
			if peer != 1: NetSession.feedback(peer, "message", ["Die letzten Zombies suchen dich!", 3.0])
