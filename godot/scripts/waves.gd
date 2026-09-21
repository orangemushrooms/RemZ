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
const MAX_CORPSES := 24
const MAX_TITANS := 4
const ARMY_START := 8
const ARMY_STEP := 0.2
const ARMY_MAX := 4.0
var _frame_time := 1.0 / 60.0
var _cleanup_time := 0.0
const SPAWN_DISTANCE := 28.0
const TITAN_SPAWN_DISTANCE := 40.0
const SPAWN_RETRY_DELAY := 1.0
const FOREST_SPAWN_SHARE := 0.2
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

static func army_multiplier(n: int) -> float:
	return minf(ARMY_MAX, 1.0 + maxf(0, n - ARMY_START + 1) * ARMY_STEP)

func regular_count(n: int) -> int:
	var count := roundi((10 + n * 5) * _difficulty("count") * army_multiplier(n))
	if NetSession.enabled: count = roundi(count * (1.0 + 0.55 * (NetSession.roster.size() - 1)))
	return count

func active_limit() -> int:
	# Never despawn living enemies; reduce only incoming reinforcements under load.
	return 40 if _frame_time > 1.0 / 35.0 else (56 if _frame_time > 1.0 / 50.0 else MAX_ACTIVE)

func spawn_interval() -> float:
	var base := maxf(0.3, 1.5 - wave * 0.1)
	return maxf(0.12, base / army_multiplier(wave)) * (1.5 if _frame_time > 1.0 / 35.0 else 1.0)

func trim_corpses() -> void:
	var corpses: Array[Zombie] = []
	for z in main.zombies_root.get_children():
		if z is Zombie and not z.alive and not z.is_queued_for_deletion(): corpses.append(z)
	corpses.sort_custom(func(a: Zombie, b: Zombie):
		if (a is Titan) != (b is Titan): return not a is Titan
		return a.dead_t > b.dead_t)
	for i in maxi(0, corpses.size() - MAX_CORPSES):
		var corpse := corpses[i]
		if is_instance_valid(corpse._pool): corpse._pool.queue_free()
		corpse.queue_free()

# size of wave n without touching the random generator (shown during the intermission)
func preview_count(n: int) -> int:
	var count := regular_count(n)
	return count + (3 + n / 4 if n % 5 == 0 else 0) + titan_count(n) + lesser_titan_count(n)

# field titans: the first one in wave 6, then every third wave, a second from wave 12, a third from wave 24
static func titan_count(n: int) -> int:
	if n < 6 or n % 3 != 0: return 0
	return mini(3, 1 + n / 12)

static func lesser_titan_count(n: int) -> int:
	return 0 if n < 8 else mini(3, 1 + (n - 8) / 8)

static func lesser_titan_kind(n: int, index: int) -> String:
	if n == 10 and index == 0: return "titan_siege"
	if n == 12 and index == 0: return "titan_ash"
	var choices := ["titan_hunter"]
	if n >= 10: choices.append("titan_siege")
	if n >= 12: choices.append("titan_ash")
	return choices[(n - 8 + index) % choices.size()]

func plan(n: int) -> Array:
	var q: Array = []
	# Titans enter across the open southern fields, never inside the forest.
	var fields := TITAN_FIELDS
	for i in titan_count(n):
		q.append({"type": "titan", "lane": "east" if i == 0 else "south", "point": fields[i]})
	for i in lesser_titan_count(n):
		q.append({"type": lesser_titan_kind(n, i), "lane": "east" if i == 0 else "south", "point": fields[i] + Vector2(10, -6)})
	var count := regular_count(n)
	boss_wave = n % 5 == 0
	if boss_wave:
		for k in 3 + n / 4:
			q.append({ "type": "brute", "lane": ["north", "south", "east", "west"][k % 4] })
	var forest_indices: Array = range(count)
	forest_indices.shuffle()
	forest_indices.resize(roundi(count * FOREST_SPAWN_SHARE))
	var forest_slots := {}
	for index in forest_indices: forest_slots[index] = true
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
		q.append({ "type": t, "lane": lane, "forest": forest_slots.has(i) })
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
	if titan_count(n) + lesser_titan_count(n) > 0:
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
	_frame_time = lerpf(_frame_time, minf(delta, 0.1), 1.0 - exp(-delta * 0.7))
	_cleanup_time -= delta
	if _cleanup_time <= 0:
		_cleanup_time = 0.5
		trim_corpses()
	if phase == "intro":
		# the opening walk: no countdown, wave 1 is released when the Weg zur Hütte is reached
		hud.set_wave(1, "Erreiche den Weg zur Hütte")
		return
	if phase == "idle":
		timer -= delta
		if Input.is_action_just_pressed("next_wave") and wave > 0 and timer > 1.0:
			timer = 1.0
			hud.message("Welle %d kommt!" % (wave + 1), 1.2)
		var boss := (wave + 1) % 5 == 0 or titan_count(wave + 1) + lesser_titan_count(wave + 1) > 0
		hud.set_wave(wave + 1, "Start in %d s  ·  %d Zombies%s
Enter: sofort starten" % [ceili(timer), preview_count(wave + 1), "  ·  BOSSWELLE" if boss else ""])
		if timer <= 0.0:
			start(wave + 1)
	elif phase == "spawning":
		spawn_t -= delta
		if spawn_t <= 0.0 and queue.size() > 0 and main.alive_zombies() < active_limit():
			# Keep blocked entries queued, but allow other enemy types to enter meanwhile.
			var e: Dictionary = queue[0]
			if _try_spawn(e):
				queue.pop_front()
				spawn_t = spawn_interval()
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
		main.music.play(main.music.intermission_track(main.day_night.clock_seconds / 3600.0) if main.day_night else "night")
	completed = wave
	phase = "idle"
	timer = 120.0
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
	if Zombie.is_titan_kind(entry["type"]):
		var active := 0
		for z in main.zombies_root.get_children():
			if z is Titan and z.alive: active += 1
		if active >= MAX_TITANS: return false
		# Giants stay on the open fields even when their planned entrance is occupied.
		var fields: Array = TITAN_FIELDS.duplicate()
		if entry.has("point"):
			fields.erase(entry.point)
			fields.push_front(entry.point)
		for point: Vector2 in fields:
			var lane: String = entry["lane"] if point == entry.get("point", Vector2.INF) else ("east" if point == TITAN_FIELDS[0] else "south")
			if main.spawn_zombie(entry["type"], point, speed_mul, lane, TITAN_SPAWN_DISTANCE):
				return true
		return false
	# Forest enemies remain part of the normal wave budget. If all sampled
	# forest spots are blocked, use a safe entrance rather than stall the wave.
	if entry.get("forest", false) and _try_forest_spawn(entry["type"]):
		return true
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

# Sample beside forest tracks: the deep woods are blocked for zombie navigation.
# Validate the projected point as well, so navigation cannot move a forest spawn
# onto a road, into a building, or onto an isolated navigation island.
func _try_forest_spawn(kind: String) -> bool:
	if NetSession.is_client() or Zombie.is_titan_kind(kind) or Map.ROADS.is_empty(): return false
	var nav: RID = main.nav_region.get_navigation_map()
	if NavigationServer3D.map_get_iteration_id(nav) == 0: return false
	var destination := NavigationServer3D.map_get_closest_point(nav, Map.ground_pos(Map.FIRE.x, Map.FIRE.y))
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 2.6
	for attempt in 12:
		var road: Dictionary = Map.ROADS.pick_random()
		var segment := randi_range(0, road.pts.size() - 2)
		var a: Vector2 = road.pts[segment]
		var b: Vector2 = road.pts[segment + 1]
		var side := -1.0 if randf() < 0.5 else 1.0
		var candidate := a.lerp(b, randf_range(0.05, 0.95)) + (b - a).normalized().orthogonal() * (float(road.width) * 0.5 + randf_range(3.0, 10.0)) * side
		if not _forest_point_valid(candidate): continue
		var ground := Map.ground_pos(candidate.x, candidate.y)
		var point := NavigationServer3D.map_get_closest_point(nav, ground)
		var projected := Vector2(point.x, point.z)
		if projected.distance_to(candidate) > 0.85 or absf(point.y - ground.y) > 1.2: continue
		if not _forest_point_valid(projected): continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = capsule
		query.transform.origin = point + Vector3.UP * 1.5
		query.collision_mask = 1 | 2 | 8 | 16
		if not main.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty(): continue
		var path := NavigationServer3D.map_get_path(nav, point, destination, true)
		if path.is_empty() or path[path.size() - 1].distance_to(destination) > 0.8: continue
		if main.spawn_zombie(kind, projected, speed_mul, "", SPAWN_DISTANCE): return true
	return false

static func _forest_point_valid(point: Vector2) -> bool:
	return Map.BOUNDS.grow(-5).has_point(point) and Map.in_forest(point.x, point.y) and not Map.on_road(point.x, point.y, 2.0) and not Map.in_building(point.x, point.y, 8.0) and not Map.in_clearing(point.x, point.y) and Map.ground_normal(point.x, point.y).y > 0.86

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
