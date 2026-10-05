extends Node
## Plain 25-wave survival. Free fortification and a merchant economy.
signal wave_started(number: int)
const KINDS := ["shambler","runner","nurse","soldier","brute","bride","spitter","screamer","stalker","zombie_dog","zombie_stag","titan","titan_hunter","titan_siege","titan_ash","earthworm","earthworm_ancient","forest_spirit"]
const MAX_ACTIVE := 24
const MAX_CORPSES := 12
var main: Node3D
var wave := 0
var completed := 0
var phase := "idle"
var timer := 90.0
var queue: Array[String] = []
var total := 0
var boss_fight := false
var spawn_t := 0.0
var frame_time := 1.0/60.0
var rng := RandomNumberGenerator.new()

func setup(game: Node3D) -> void:
	main = game
	rng.seed = 478335

func plan(number: int) -> Array[String]:
	var result: Array[String] = []
	if number<1 or number>(main.expedition.round_limit() if main.get("expedition") else Campaign.ROUNDS): return result
	var forest := Waves.new()
	forest.main = main
	for entry in forest.plan(number): result.append(entry.type)
	forest.free()
	return result

func start(number: int) -> void:
	if NetSession.is_client() or main.over or not main.survival_active or number<1 or number>(main.expedition.round_limit() if main.get("expedition") else Campaign.ROUNDS) or phase in ["complete", "finale"]: return
	wave = number
	if main.get("expedition"): main.expedition.prepare_wave(number)
	boss_fight = number%5==0
	queue = plan(number)
	boss_fight = is_boss_fight()
	total = queue.size()
	phase = "spawning"
	spawn_t = 0.0
	wave_started.emit(wave)
	main.hud.message(Lang.t("Wave %d",[wave]),2.5)
	Sfx.play(self,"wave",-8)

func active_limit() -> int:
	return 16 if frame_time>0.022 else MAX_ACTIVE

func is_boss_fight() -> bool:
	if wave % 5 == 0 and phase == "spawning": return true
	for kind in queue:
		if Zombie.is_boss_kind(kind): return true
	for enemy in main.zombies_root.get_children():
		if enemy is Zombie and enemy.alive and Zombie.is_boss_kind(enemy.net_kind): return true
	return false

func _process(delta: float) -> void:
	if not main or not main.started or NetSession.is_client() or not main.survival_active or main.over or (not NetSession.enabled and not main.player.active): return
	frame_time = lerpf(frame_time,minf(delta,0.1),minf(1,delta))
	if phase=="idle":
		timer -= delta
		if Input.is_action_just_pressed("next_wave") and not NetSession.is_client(): timer = minf(timer,0.1)
		main.hud.set_wave(wave+1,Lang.t("Start in %d s · Enter: start now",[maxi(0,ceili(timer))]))
		main.hud.set_wave_progress(0,0)
		if timer<=0: start(wave+1)
	elif phase=="spawning":
		boss_fight = is_boss_fight()
		spawn_t -= delta
		if spawn_t<=0 and not queue.is_empty() and main.alive_zombies()<active_limit():
			var heavy := 0
			for enemy in main.zombies_root.get_children():
				if enemy is Zombie and enemy.alive and Zombie.is_boss_kind(enemy.net_kind): heavy += 1
			if not Zombie.is_boss_kind(queue[0]) or heavy<EncounterBalance.heavy_limit(wave):
				if main.spawn_enemy(queue[0],wave): queue.pop_front()
			spawn_t = maxf(0.28,1.5-wave*0.1)/Waves.army_multiplier(wave)
		var alive: int = main.alive_zombies()
		main.hud.set_wave(wave,Lang.t("%d left",[alive+queue.size()]))
		main.hud.set_wave_progress(alive+queue.size(),total)
		if queue.is_empty() and alive==0: complete_wave()

func complete_wave() -> void:
	if phase!="spawning" or not queue.is_empty() or main.alive_zombies()>0 or main.over: return
	completed = wave
	main.achievements.event("planes_waves",completed,true)
	if main.classes: main.classes.wave(completed)
	main.campaign.record_wave(completed,str(main.difficulty.name), not (main.get("expedition") and main.expedition.enabled))
	if main.get("expedition"): main.expedition.wave_cleared(completed)
	if completed==(main.expedition.round_limit() if main.get("expedition") else Campaign.ROUNDS):
		if main.get("expedition") and main.expedition.begin_finale(): return
		phase = "complete"
		if NetSession.is_host():
			main.victory = true
			NetSession.world.campaign_victory()
		else: main.finish_survival(true)
		return
	phase = "idle"
	timer = 60.0
	var players: Array = NetSession.world.actors.values() if NetSession.is_host() else [main.player]
	for actor: Player in players:
		var gear: Weapons = NetSession.world.weapons[actor.peer_id] if NetSession.is_host() else main.weapons
		actor.add_score(50+5*wave)
		if wave%3==0: gear.grenades = mini(gear.grenades_max,gear.grenades+1)
		gear.update_hud()
		actor.hp = minf(actor.max_hp,actor.hp+20)
		actor.self_revives = 1
		if actor.downed or not actor.alive: actor.revive(actor.max_hp)
		actor.hud.set_health(actor.hp)
	main.hud.message(Lang.t("Wave %d survived. Supply pay received; visit Vendor to restock.",[wave]),4)

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
