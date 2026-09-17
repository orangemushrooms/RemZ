# Wave planning and spawning.
class_name Waves
extends Node

var main: Node
var hud: Hud
var player: Player
var weapons: Weapons
var wave := 0
var phase := "idle"
var timer := 4.0
var queue: Array = []
var spawn_t := 0.0
var speed_mul := 1.0

func setup(m: Node, h: Hud, p: Player, w: Weapons) -> void:
	main = m
	hud = h
	player = p
	weapons = w
	hud.set_wave(1, "Bereit machen ...")

func plan(n: int) -> Array:
	var q: Array = []
	var count := 6 + n * 3
	for i in count:
		var r := randf()
		var t := "shambler"
		if n >= 2 and r < 0.15 + n * 0.04:
			t = "runner"
		if n >= 2 and r > 0.7 and r < 0.85:
			t = "nurse"
		if n >= 3 and r > 0.85 and r < 0.93:
			t = "soldier"
		if n >= 4 and r > 0.93:
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
	wave = n
	queue = plan(n)
	phase = "spawning"
	spawn_t = 0.0
	speed_mul = 1.0 + (n - 1) * 0.04
	hud.set_wave(n, "%d Zombies" % queue.size())
	hud.message("Welle %d" % n, 2.0)
	Sfx.play(self, "wave", -6.0)
	if n == 3 and not weapons.unlocked["shotgun"]:
		weapons.unlock("shotgun")
		hud.message("Welle 3\nSchrotflinte freigeschaltet (Taste 2)", 3.5)

func _process(delta: float) -> void:
	if not player or not player.active or not player.alive:
		return
	if phase == "idle":
		timer -= delta
		hud.set_wave(wave + 1, "Start in %d s" % ceili(timer))
		if timer <= 0.0:
			start(wave + 1)
	elif phase == "spawning":
		spawn_t -= delta
		if spawn_t <= 0.0 and queue.size() > 0:
			var e: Dictionary = queue.pop_front()
			var pts: Array = Map.SPAWNS[e["lane"]]
			var p: Vector2 = pts[randi() % pts.size()] + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
			main.spawn_zombie(e["type"], p, speed_mul)
			spawn_t = maxf(0.6, 2.2 - wave * 0.12)
		var alive: int = main.alive_zombies()
		hud.set_wave(wave, "%d übrig" % (alive + queue.size()))
		if queue.is_empty() and alive == 0:
			phase = "idle"
			timer = 18.0
			var bonus := 40 + wave * 10
			player.add_score(bonus)
			weapons.refill_all()
			hud.message("Welle %d überstanden\n+%d Punkte, Munition aufgefüllt\nBaue Barrikaden mit E" % [wave, bonus], 4.0)
			Sfx.play(self, "pickup", -8.0)
