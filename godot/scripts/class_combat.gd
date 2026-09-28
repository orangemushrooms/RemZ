extends RefCounted
## One frozen build and one set of timers per actor, including host-side remote actors.
const Classes = preload("res://scripts/character_classes.gd")
var build := {"id": "gunslinger", "level": 1, "choices": [-1, -1, -1, -1, -1, -1]}
var talents: Dictionary = {}
var timers: Dictionary = {}
var stacks: Dictionary = {}
var time_since_attack := 0.0
var time_since_damage := 0.0
var time_since_miss := 0.0
var aim_time := 0.0
var head_chain := 0
var precision_chain := 0
var streak := 0
var streak_time := 0.0
var damage_taken := 0.0
var nearby := 0
var _targets: Dictionary = {}
var _target_check := 0.0
var _shot_targets: Dictionary = {}
var _full_magazine := false
var _predator := false
var _shot_head := false
var _shot_body := false
var _duel_target := 0
var _duel_hits := 0
var _duel_time := 0.0
var _perfect_used := false

func configure(value: Dictionary) -> void:
	var clean := Classes.sanitize_loadout(value)
	if clean.is_empty(): return
	build = clean
	talents.clear()
	for i in 6:
		var choice := int(build.choices[i])
		if choice >= 0: talents[Classes.CLASSES[build.id].talents[i][choice][0]] = true
	timers.clear()
	stacks.clear()
	_targets.clear()
	_shot_targets.clear()
	head_chain = 0
	precision_chain = 0
	streak = 0
	streak_time = 0.0
	time_since_attack = 0.0
	time_since_damage = 0.0
	time_since_miss = 0.0
	aim_time = 0.0
	damage_taken = 0.0
	_duel_time = 0.0
	_duel_hits = 0

func has(id: String) -> bool:
	return talents.has(id)

func specialist(weapon: String) -> bool:
	return weapon in Classes.CLASSES[build.id].weapons

func buff(id: String, duration: float, cap: int = 1) -> void:
	timers[id] = duration
	stacks[id] = mini(cap, int(stacks.get(id, 0)) + 1)

func active(id: String) -> bool:
	return float(timers.get(id, 0.0)) > 0.0

func tick(delta: float, actor: Node3D, weapons: Node, enemies: Node) -> void:
	time_since_attack += delta
	time_since_damage += delta
	time_since_miss += delta
	_duel_time = maxf(0.0, _duel_time - delta)
	streak_time = maxf(0.0, streak_time - delta)
	if streak_time <= 0.0: streak = 0
	if weapons and float(weapons.ads) > 0.1: aim_time += delta
	else: aim_time = 0.0
	for id in timers.keys():
		timers[id] = maxf(0.0, float(timers[id]) - delta)
		if timers[id] <= 0.0: stacks.erase(id)
	_target_check -= delta
	if _target_check <= 0.0:
		_target_check = 0.25
		nearby = count_near(enemies, actor.global_position, 6.0) if has("stand_ground") else 0
		for id in _targets.keys():
			var target: Variant = _targets[id].get_ref()
			if not is_instance_valid(target) or not target.alive: _targets.erase(id)

static func count_near(enemies: Node, at: Vector3, radius: float) -> int:
	if not is_instance_valid(enemies): return 0
	var count := 0
	for enemy in enemies.get_children():
		if enemy.get("alive") == true and enemy.global_position.distance_squared_to(at) <= radius * radius:
			count += 1
			if count >= 3: break
	return count

func modifier(attribute: String, weapon: String = "", ads: float = 0.0, low_health: bool = false, low_mag: bool = false, burst: int = 0) -> float:
	var value := 1.0
	var spec := specialist(weapon)
	match attribute:
		"reload":
			if has("weapon_master"): value *= 0.9
			if has("last_stand") and low_health: value *= 0.8
			if spec:
				if has("quick_hands") or has("speed_loader"): value *= 0.8
				if has("tactical_reload"): value *= 0.82
				if has("weapons_expert"): value *= 0.9
				if has("high_noon") and active("high_noon"): value *= 1.0 - 0.08 * int(stacks.get("high_noon", 0))
				if has("combat_drill") and active("kill"): value *= 0.75
				if has("veteran") and low_mag: value *= 0.7
				if has("rhythm"): value *= 1.0 - minf(0.25, precision_chain * 0.05)
		"recoil":
			if has("last_stand") and low_health: value *= 0.8
			if spec:
				if has("steady_hand"): value *= 0.85
				if has("weapons_expert"): value *= 0.9
				if has("ice_cold") and active("head"): value *= 0.7
				if has("frontline") and active("kill"): value *= 0.75
		"spread":
			if has("predator") and time_since_attack >= 5.0 and time_since_damage >= 5.0: value *= 0.5
			if spec:
				if has("tight_spread"): value *= 0.75
				if has("burst") and burst < 3: value *= 0.75
				if has("breath_control") and ads > 0.1: value *= 1.0 - minf(0.4, aim_time / 3.0 * 0.4)
		"bloom":
			if spec and has("fan_hammer"): value *= 0.6
		"magazine":
			if spec and has("ammo_discipline"): value *= 1.15
			if spec and has("weapons_expert"): value *= 1.1
		"rate":
			if spec and has("combat_momentum") and active("combat_momentum"): value /= 1.0 + 0.06 * int(stacks.get("combat_momentum", 0))
		"ads":
			if spec and has("fast_focus"): value *= 1.3
			if spec and has("rhythm"): value /= 1.0 - minf(0.25, precision_chain * 0.05)
		"sway":
			if spec and has("firm_stance") and ads > 0.1: value *= 0.5
		"switch":
			if spec and has("quick_swap"): value *= 0.5
			if has("weapon_master"): value *= 0.75
			if has("master_assassin"): value *= 0.8
		"speed":
			if has("light_footed"): value *= 1.1
			if has("master_assassin"): value *= 1.05
			if has("untouchable") and time_since_damage >= 8.0: value *= 1.12
			if has("escape_artist") and active("escape"): value *= 1.2
			if has("momentum") and active("kill"): value *= 1.15
			if has("sidestep") and active("sidestep"): value *= 1.15
			if has("gunslinger") and spec and ads > 0.1: value *= 1.15
			if has("last_stand") and low_health: value *= 1.1
		"guard":
			if has("stand_ground") and nearby >= 3: value *= 0.85
			if has("juggernaut") and active("juggernaut"): value *= 0.8
		"detection":
			if has("ghost_step"): value *= 0.8
			if has("master_assassin"): value *= 0.85
			if has("shadow") and time_since_attack >= 4.0: value *= 0.65
	return value

func begin_shot(full_magazine: bool) -> void:
	_full_magazine = full_magazine
	_predator = has("predator") and time_since_attack >= 5.0 and time_since_damage >= 5.0
	time_since_attack = 0.0
	_shot_targets.clear()
	_shot_head = false
	_shot_body = false
	_perfect_used = false

func damage_multiplier(weapon: String, enemy: Node3D, head: bool, actor: Node3D, enemies: Node) -> float:
	var target := enemy.get_instance_id()
	var first := not _targets.has(target)
	var first_pellet := not _shot_targets.has(target)
	var distance := actor.global_position.distance_to(enemy.global_position)
	var boss: bool = enemy.is_boss_kind(enemy.net_kind)
	var elite: bool = boss or enemy.armored or enemy.net_kind not in ["shambler", "runner"]
	var behind := enemy.global_basis.z.dot((actor.global_position - enemy.global_position).normalized()) < -0.4
	var value := 1.0
	if head: _shot_head = true
	else: _shot_body = true
	if specialist(weapon):
		if has("gunslinger"): value *= 1.1
		if has("large_caliber"): value *= 1.12
		if has("duelist"):
			if first_pellet:
				_duel_hits = mini(5, _duel_hits + 1) if _duel_target == target and _duel_time > 0.0 else 0
				_duel_target = target
				_duel_time = 3.0
			value *= 1.0 + _duel_hits * 0.05
		if has("executioner") and enemy.hp <= enemy.max_hp * 0.3: value *= 1.25
		if has("armor_breaker") and enemy.armored: value *= 1.25
		if has("crowd_control") and not elite: value *= 1.12
		if has("bloodbath") and active("bloodbath"): value *= 1.15
		if has("breaching") and (enemy.armored or boss or enemy.height >= 2.5): value *= 1.25
		if has("crowd_breaker") and count_near(enemies, enemy.global_position, 5.0) >= 3: value *= 1.2
		if has("no_mercy") and distance <= 4.0: value *= 1.2
		if has("boomstick") and _full_magazine: value *= 1.35
		if has("hunter") and elite: value *= 1.2
		if has("big_game") and elite: value *= 1.3
		if has("one_shot") and first: value *= 1.2
		if has("kill_chain") and active("kill_chain"):
			value *= 1.25
			timers.kill_chain = 0.0
		if head:
			if has("bounty"): value *= 1.15
			if has("weak_spot"): value *= 1.2
			if has("deadeye"): value *= 1.0 + minf(0.4, head_chain * 0.08)
			if has("quickscope") and aim_time > 0.0 and aim_time <= 0.6: value *= 1.2
			if has("perfect_shot") and time_since_miss >= 4.0 and not _perfect_used:
				value *= 1.5
				_perfect_used = true
				time_since_miss = 0.0
			if has("ice_cold"): buff("head", 3.0)
		if first_pellet and enemy.alive:
			if has("suppression") and not elite:
				if not first: enemy.class_slow_time = 2.0
	if has("opportunist") and is_instance_valid(enemy.player) and enemy.player != actor: value *= 1.15
	if has("silent_killer") and behind: value *= 1.2
	if has("assassination") and first and (behind or not is_instance_valid(enemy.player) or enemy.player != actor or (not enemy.hunting and enemy.get("_aggro_target") != actor)): value *= 1.35
	if head and _predator: value *= 1.25
	_targets[target] = weakref(enemy)
	_shot_targets[target] = true
	return value

func after_hit(weapon: String, enemy: Node3D, actor: Node3D) -> void:
	# Zombie.damage writes the normal hit impulse, so the stronger shove must follow it.
	if enemy.alive and specialist(weapon) and has("knockback") and not enemy.is_boss_kind(enemy.net_kind):
		enemy.shove((enemy.global_position - actor.global_position).normalized() * 7.0)

func end_shot(weapon: String, hit: bool) -> void:
	if not hit: time_since_miss = 0.0
	if specialist(weapon):
		head_chain = mini(5, head_chain + 1) if hit and _shot_head and not _shot_body else 0
		precision_chain = mini(5, precision_chain + 1) if hit else 0
	elif not hit:
		head_chain = 0
		precision_chain = 0

func killed(weapon: String, head: bool, distance: float) -> void:
	streak += 1
	streak_time = 4.0
	if weapon in ["tower", "drone", "grenade", "firework"]: return
	buff("kill", 4.0)
	if not specialist(weapon): return
	if has("sidestep"): buff("sidestep", 3.0)
	if has("juggernaut"): buff("juggernaut", 4.0)
	if has("combat_momentum"): buff("combat_momentum", 4.0, 3)
	if has("bloodbath") and distance <= 5.0: buff("bloodbath", 4.0)
	if head:
		if has("high_noon"): buff("high_noon", 5.0, 3)
		if has("kill_chain"): buff("kill_chain", 5.0)

func hurt(amount: float) -> void:
	if amount <= 0.0: return
	damage_taken += amount
	time_since_damage = 0.0
	if has("escape_artist") and amount >= 25.0: buff("escape", 3.0)

func extra_penetration(weapon: String, enemy: Node) -> int:
	if not specialist(weapon): return 0
	if has("piercing"): return 1
	if has("penetration") and not enemy.is_boss_kind(enemy.net_kind) and enemy.height < 2.5: return 1
	return 0

func runtime_snapshot() -> Dictionary:
	return {"timers": timers.duplicate(), "stacks": stacks.duplicate(), "head": head_chain, "precision": precision_chain, "miss": time_since_miss}

func apply_runtime(data: Dictionary) -> void:
	timers = data.get("timers", {}).duplicate()
	stacks = data.get("stacks", {}).duplicate()
	head_chain = int(data.get("head", 0))
	precision_chain = int(data.get("precision", 0))
	time_since_miss = float(data.get("miss", 0.0))
