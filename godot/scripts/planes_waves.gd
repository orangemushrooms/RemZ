extends Node
## Plain 25-wave survival. Map-specific objectives will be designed separately.
signal wave_started(number: int)
const KINDS := ["shambler","runner","nurse","soldier","brute"]
const MAX_ACTIVE := 24
const MAX_CORPSES := 12
var main: Node3D
var wave := 0
var completed := 0
var phase := "idle"
var timer := 15.0
var queue: Array[String] = []
var total := 0
var spawn_t := 0.0
var frame_time := 1.0/60.0
var rng := RandomNumberGenerator.new()

func setup(game: Node3D) -> void:
	main = game
	rng.seed = 478335

func plan(number: int) -> Array[String]:
	var result: Array[String] = []
	if number<1 or number>Campaign.ROUNDS: return result
	var count := roundi((10+number*4)*float(main.difficulty.count))
	for i in count:
		var kind := "shambler"
		var r := rng.randf()
		if r<minf(0.4,0.12+number*0.01): kind = "runner"
		elif number>=3 and r>0.8: kind = "nurse"
		elif number>=5 and r>0.65: kind = "soldier"
		if number%5==0 and i<1+number/5: kind = "brute"
		result.append(kind)
	return result

func start(number: int) -> void:
	if main.over or not main.survival_active or number<1 or number>Campaign.ROUNDS or phase=="complete": return
	wave = number
	queue = plan(number)
	total = queue.size()
	phase = "spawning"
	spawn_t = 0.0
	wave_started.emit(wave)
	main.hud.message(Lang.t("Wave %d",[wave]),2.5)
	Sfx.play(self,"wave",-8)

func active_limit() -> int:
	return 16 if frame_time>0.022 else MAX_ACTIVE

func _process(delta: float) -> void:
	if not main or not main.survival_active or main.over or not main.player.active: return
	frame_time = lerpf(frame_time,minf(delta,0.1),minf(1,delta))
	if phase=="idle":
		timer -= delta
		if Input.is_action_just_pressed("next_wave"): timer = minf(timer,0.1)
		main.hud.set_wave(wave+1,Lang.t("Start in %d s · Enter: start now",[maxi(0,ceili(timer))]))
		if timer<=0: start(wave+1)
	elif phase=="spawning":
		spawn_t -= delta
		if spawn_t<=0 and not queue.is_empty() and main.alive_zombies()<active_limit():
			if main.spawn_enemy(queue[0],wave): queue.pop_front()
			spawn_t = maxf(0.55,1.5-wave*0.04)
		var alive: int = main.alive_zombies()
		main.hud.set_wave(wave,Lang.t("%d left",[alive+queue.size()]))
		if queue.is_empty() and alive==0: complete_wave()

func complete_wave() -> void:
	if phase!="spawning" or not queue.is_empty() or main.alive_zombies()>0 or main.over: return
	completed = wave
	main.campaign.record_wave(completed,str(main.difficulty.name))
	if completed==Campaign.ROUNDS:
		phase = "complete"
		main.finish_survival(true)
		return
	phase = "idle"
	timer = 30.0
	main.weapons.refill_all()
	main.weapons.grenades = 3
	main.weapons.update_hud()
	main.player.hp = main.player.max_hp
	main.player.self_revives = 1
	if main.player.downed: main.player.revive(main.player.max_hp)
	main.hud.set_health(main.player.hp)
	main.hud.message(Lang.t("Wave %d survived. Health and ammunition restored.",[wave]),4)

func trim_corpses() -> void:
	var corpses: Array[Zombie] = []
	for enemy in main.zombies_root.get_children():
		if enemy is Zombie and not enemy.alive and not enemy.is_queued_for_deletion(): corpses.append(enemy)
	corpses.sort_custom(func(a: Zombie,b: Zombie): return a.dead_t>b.dead_t)
	for i in maxi(0,corpses.size()-MAX_CORPSES):
		main.discard_enemy(corpses[i])

func skip_current_wave() -> void:
	if not main.survival_active or main.over: return
	queue.clear()
	main._clear_combat()
	if phase=="spawning": complete_wave()
	if not main.over and phase!="complete": start(wave+1)
