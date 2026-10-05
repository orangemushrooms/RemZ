extends RefCounted
## Bounded plain-Variant saves; never instantiate objects from disk. Validate before mutating.
const VERSION := 1
const MAX_BYTES := 8*1024*1024
const STATS := ["kills", "headshots", "shots", "hits", "grenades_thrown", "melee_hits", "barricades_built", "mushrooms_eaten", "damage_taken", "points_earned", "seconds", "best_streak", "downs", "revives", "repairs", "rescues", "healing"]
const WEAPON_RUNTIME := ["cooldown", "reloading", "heat", "vent", "idle", "regen", "spin", "spin_idle", "cycle_t"]
var director: RunDirector
var override_path := ""
var windows: Dictionary = {}

func index_world() -> void:
	for pane in get_tree_for_game().get_nodes_in_group("breakable"):
		windows["window:%d" % windows.size()] = {"path": str(director.game.get_path_to(pane)), "parent": str(director.game.get_path_to(pane.get_parent())), "name": str(pane.name), "position": pane.position, "rotation": pane.rotation, "size": pane.pane_size}

func path() -> String:
	return override_path if not override_path.is_empty() else "user://expedition_%s_%s.save" % [director.config.region, CharacterProfile.profile_id]

func eligibility() -> String:
	var game := director.game
	if NetSession.is_client(): return "Only the host can save or continue an expedition."
	if NetSession.enabled:
		var names: Array = NetSession.roster.values()
		for name in names:
			if names.count(name) != 1: return "Use distinct player names for cooperative checkpoints."
	if game.over or game.waves.phase != "idle" or not game.waves.queue.is_empty() or game.alive_zombies() > 0: return "Save only during a quiet wave intermission."
	if not director.finale.is_empty() or (not director.operation.is_empty() and director.operation.stage == "active"): return "Finish the active objective before saving."
	if game.secret_night and game.secret_night.active: return "Finish the active objective before saving."
	if game.field_trials and game.field_trials.active: return "Finish the active objective before saving."
	if not game.brewing.jobs.is_empty() or not game.hunting.jobs.is_empty(): return "Finish cooking and brewing before saving."
	if game.get("drones") and not game.drones.drones.is_empty(): return "Recall active drones before saving."
	if game.get("fireworks") and not game.fireworks.active.is_empty(): return "Wait for active fireworks before saving."
	if game.fortune and game.fortune.pending.any(func(item): return not item.is_empty()): return "Wait for the fortune wheel payout before saving."
	if not director.range_game.is_empty() and director.range_game.timer > 0: return "Finish the active objective before saving."
	if director.sites.any(func(site): return site.kind == "outpost" and not site.done and site.timer > 0): return "Finish the active objective before saving."
	for p: Player in director.actors():
		if not p.alive or p.downed or p.mounted_tower or p.controlling_drone: return "All players must be alive and on foot."
	for node in game.get_children():
		if node is Grenade and not node.is_queued_for_deletion(): return "Wait for the grenade to explode before saving."
		if node is Pickup and not node._taken and not node.is_queued_for_deletion(): return "Collect dropped supplies before saving."
	return ""

func _player(p: Player) -> Dictionary:
	var w := director.gear(p.peer_id)
	var ammo := {}
	for id in w.state: ammo[id] = [w.state[id].ammo, w.state[id].reserve]
	var weapon_runtime := {}
	for id in w.state:
		weapon_runtime[id] = {}
		for key in WEAPON_RUNTIME:
			if w.state[id].has(key): weapon_runtime[id][key] = w.state[id][key]
	return {"position": p.global_position, "yaw": p.rotation.y, "pitch": p.pitch, "hp": p.hp, "max_hp": p.max_hp,
		"score": p.score, "speed": p.speed_mul, "regen": p.regen_mul, "effects": p.mushroom_effects.duplicate(true), "relic": p.relic,
		"revives": p.self_revives, "teleport": p.teleport_cooldown, "class": p.class_combat.build.duplicate(true), "combat": p.class_combat.runtime_snapshot(),
		"physics": [p.crouching, p.regen_timer, p.revive_protection, p.cash_cooldown],
		"mission_from_start": bool(p.get_meta("class_mission_from_start", false)),
		"weapon": w.current, "ammo": ammo, "unlocked": w.unlocked.duplicate(), "skins": w.skins.duplicate(), "mod_owned": w.mod_owned.duplicate(true), "mod_loadout": w.mod_loadout.duplicate(true),
		"weapon_runtime": weapon_runtime,
		"grenades": w.grenades, "grenades_max": w.grenades_max, "mods": [w.damage_mul, w.reload_mul, w.spread_mul],
		"levels": (NetSession.world.levels[p.peer_id] if NetSession.is_host() else director.game.skills.levels).duplicate(true),
		"mushrooms": (NetSession.world.mushrooms[p.peer_id] if NetSession.is_host() else director.game.inventory.mushrooms).duplicate(true)}

func capture() -> Dictionary:
	var game := director.game
	var players := {}
	var roster := {}
	for p: Player in director.actors():
		players[p.peer_id] = _player(p)
		roster[p.peer_id] = str(NetSession.roster.get(p.peer_id, CharacterProfile.data.name))
	var statistics := {}
	for key in STATS: statistics[key] = game.stats.get(key)
	var bars: Array = []
	for b in game.barricades: bars.append([b.slot.duplicate(true), b.level, b.hp])
	var sand: Array = []
	for b in game.sandbags: sand.append([b.level, b.hp])
	var loots := {}
	for loot in get_tree_for_game().get_nodes_in_group("checkpoint_pickups"):
		if loot is Loot: loots[_key(loot)] = [loot.taken, loot.stocked_wave, loot.cache_respawn_wave, loot.global_position]
	var doors := {}
	for door in get_tree_for_game().get_nodes_in_group("hut_doors"):
		if door is Door: doors[_key(door)] = door.is_open
	var world := {"keys": [], "pumpkins": [], "windows": {}, "fortune": game.fortune.snapshot() if game.fortune else [], "fireworks": game.fireworks.snapshot() if game.get("fireworks") else {},
		"weather_rng": game.weather._rng.state, "spawn_rng": game._spawn_rng.state if director.config.region == "planes" else 0, "fortune_rng": game.fortune.rng.state if game.fortune else 0}
	if director.config.region == "forest":
		for key: ForestKey in game.forest_keys.spawned: world.keys.append([key.global_position, key.taken])
	for pumpkin in game.pumpkins: world.pumpkins.append(pumpkin.broken)
	for key in windows: world.windows[key] = is_instance_valid(game.get_node_or_null(windows[key].path))
	return {"version": VERSION, "region": director.config.region, "coop": NetSession.enabled, "roster": roster, "players": players,
		"director": director.snapshot(), "wave": [game.waves.wave, game.waves.completed, game.waves.timer], "stats": statistics,
		"leaderboard": game.stats.players.duplicate(true), "classes": [game.classes._serial, game.classes._received, game.classes._last_wave, game.classes._quests.duplicate(true)],
		"progression": game.progression.snapshot(), "brewing": game.brewing.snapshot(), "hunting": game.hunting.snapshot(), "towers": game.defences.snapshot(),
		"bars": bars, "sandbags": sand, "hut": game.hut.hp if game.hut else -1.0, "clock": game.day_night.clock_seconds, "night": game.day_night.night_index,
		"weather": game.weather.snapshot(), "weather_elapsed": game.weather.get("elapsed") if director.config.region == "planes" else 0.0,
		"secret_night": game.secret_night.snapshot() if game.secret_night else {}, "field_trials": game.field_trials.snapshot() if game.field_trials else {},
		"range": game.shooting_range.snapshot() if director.config.region == "planes" else {}, "fire": game.cornfield.fires.snapshot() if director.config.region == "planes" else {},
		"achievements": [game.achievements.counters.duplicate(true), game.achievements.session_unlocked.duplicate(true)], "loots": loots, "doors": doors,
		"keys": game.forest_keys.owned.duplicate(true) if director.config.region == "forest" else {}, "world": world, "purse": NetSession.world.purse if NetSession.is_host() else 0}

func get_tree_for_game() -> SceneTree:
	return director.game.get_tree()

static func plain(value: Variant, depth: int = 0) -> bool:
	if depth > 32: return false
	if value is Dictionary:
		if value.size() > 20000: return false
		for key in value:
			if not plain(key, depth+1) or not plain(value[key], depth+1): return false
	elif value is Array:
		if value.size() > 20000: return false
		for child in value:
			if not plain(child, depth+1): return false
	elif value is float: return is_finite(value)
	elif value is Vector2 or value is Vector3: return value.is_finite()
	elif value is String or value is StringName: return str(value).length() <= 20000
	elif value is PackedVector2Array or value is PackedVector3Array:
		for point in value:
			if not point.is_finite(): return false
	elif not (value == null or value is bool or value is int or value is Vector2i or value is PackedByteArray or value is Color): return false
	return true

static func pack(state: Dictionary) -> PackedByteArray:
	var data := var_to_bytes(state)
	var header := ("REMZ-CHECKPOINT-1\n"+digest(data)+"\n").to_utf8_buffer()
	header.append_array(data)
	return header

static func unpack(bytes: PackedByteArray) -> Dictionary:
	if bytes.size() < 84 or bytes.size() > MAX_BYTES: return {}
	var prefix := bytes.slice(0, 18).get_string_from_utf8()
	if prefix != "REMZ-CHECKPOINT-1\n": return {}
	var checksum := bytes.slice(18, 82).get_string_from_utf8()
	if bytes[82] != 10: return {}
	var data := bytes.slice(83)
	if digest(data) != checksum: return {}
	var state: Variant = bytes_to_var(data)
	if not state is Dictionary or not plain(state) or state.get("version") != VERSION: return {}
	return state

static func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func validate(state: Dictionary) -> String:
	if state.is_empty() or not plain(state) or state.get("version") != VERSION: return "Checkpoint is damaged or incompatible."
	var template := capture()
	for key in template:
		if not state.has(key) or typeof(state[key]) != typeof(template[key]): return "Checkpoint is damaged or incompatible."
	if state.region != director.config.region: return "Choose the checkpoint's map before continuing."
	if bool(state.coop) != NetSession.enabled or state.roster != template.roster: return "The same cooperative player slots must join before continuing."
	var saved_ids: Array = state.players.keys()
	var current_ids: Array = template.players.keys()
	saved_ids.sort()
	current_ids.sort()
	if saved_ids != current_ids: return "The same cooperative player slots must join before continuing."
	if not _compatible(state.world, template.world) or state.world.keys.size() != template.world.keys.size() or state.world.pumpkins.size() != template.world.pumpkins.size(): return "Checkpoint is damaged or incompatible."
	for row in state.world.keys:
		if not row is Array or row.size() != 2 or not row[0] is Vector3 or not row[1] is bool: return "Checkpoint is damaged or incompatible."
	for flag in state.world.pumpkins:
		if not flag is bool: return "Checkpoint is damaged or incompatible."
	for section in ["progression", "brewing", "hunting", "weather", "secret_night", "field_trials", "range", "fire", "leaderboard"]:
		if not _compatible(state[section], template[section]): return "Checkpoint is damaged or incompatible."
	for entry in state.loots.values():
		if not entry is Array or entry.size() != 4 or not entry[0] is bool or not entry[1] is int or not entry[2] is int or not entry[3] is Vector3: return "Checkpoint is damaged or incompatible."
	if not _director_valid(state.director): return "Checkpoint is damaged or incompatible."
	if state.weather.size() != 7 or state.weather[0] not in ["clear", "fog", "rain", "storm"]: return "Checkpoint is damaged or incompatible."
	if state.wave.size() != 3 or int(state.wave[0]) != int(state.wave[1]) or int(state.wave[0]) < 0 or int(state.wave[0]) >= RunRules.rounds(RunRules.clean(state.director.config)): return "Checkpoint is damaged or incompatible."
	if state.classes.size() != 4 or not state.classes[3] is Dictionary or state.achievements.size() != 2: return "Checkpoint is damaged or incompatible."
	if state.bars.size() > 40 or state.towers.size() > DefenceTower.LIMIT or state.sandbags.size() != director.game.sandbags.size(): return "Checkpoint is damaged or incompatible."
	for id in state.players:
		var data: Variant = state.players[id]
		if not data is Dictionary: return "Checkpoint is damaged or incompatible."
		for key in template.players[id]:
			if not data.has(key) or typeof(data[key]) != typeof(template.players[id][key]): return "Checkpoint is damaged or incompatible."
		if data.weapon not in Weapons.DEFS or data.hp <= 0 or data.max_hp <= 0 or data.hp > data.max_hp or data.score < 0 or data.mods.size() != 3: return "Checkpoint is damaged or incompatible."
		if data.physics.size() != 4 or not data.physics[0] is bool: return "Checkpoint is damaged or incompatible."
		for value in data.physics.slice(1):
			if not (value is int or value is float) or value < 0: return "Checkpoint is damaged or incompatible."
		if preload("res://scripts/character_classes.gd").sanitize_loadout(data.class).is_empty(): return "Checkpoint is damaged or incompatible."
		if director.config.region == "planes" and not preload("res://scripts/planes_boundary.gd").contains(Vector2(data.position.x, data.position.z)): return "Checkpoint is damaged or incompatible."
		if not Map.BOUNDS.has_point(Vector2(data.position.x, data.position.z)): return "Checkpoint is damaged or incompatible."
		for weapon in data.ammo:
			if weapon not in Weapons.DEFS or not data.ammo[weapon] is Array or data.ammo[weapon].size() != 2 or int(data.ammo[weapon][0]) < 0 or int(data.ammo[weapon][1]) < 0: return "Checkpoint is damaged or incompatible."
		for weapon in data.weapon_runtime:
			if weapon not in Weapons.DEFS or not data.weapon_runtime[weapon] is Dictionary: return "Checkpoint is damaged or incompatible."
			for key in data.weapon_runtime[weapon]:
				var value: Variant = data.weapon_runtime[weapon][key]
				if key not in WEAPON_RUNTIME or not (value is int or value is float or value is bool): return "Checkpoint is damaged or incompatible."
	for row in state.bars:
		if not row is Array or row.size() != 3 or not row[0] is Dictionary or not row[0].has("pos") or not row[0].pos is Vector2 or int(row[1]) not in [0, 1, 2, 3]: return "Checkpoint is damaged or incompatible."
	for row in state.towers.values():
		if not row is Array or row.size() < 18 or not row[0] is Vector3 or row[10] not in DefenceTower.SPECS: return "Checkpoint is damaged or incompatible."
	for key in STATS:
		if not state.stats.has(key) or not (state.stats[key] is float or state.stats[key] is int): return "Checkpoint is damaged or incompatible."
	if not state.director.get("finale", {}).is_empty(): return "Checkpoint is damaged or incompatible."
	return ""

static func _compatible(value: Variant, prototype: Variant) -> bool:
	if typeof(value) != typeof(prototype): return false
	if value is Dictionary:
		for key in prototype:
			if not value.has(key) or not _compatible(value[key], prototype[key]): return false
	elif value is Array and not prototype.is_empty():
		for i in mini(value.size(), prototype.size()):
			if not _compatible(value[i], prototype[i]): return false
	return true

func _director_valid(data: Dictionary) -> bool:
	var template := director.snapshot()
	for key in template:
		if not data.has(key) or typeof(data[key]) != typeof(template[key]): return false
	if data.config != RunRules.clean(data.config) or data.config.region != director.config.region or data.elapsed < 0: return false
	if data.puzzle_order.size() != 3 or not (0 in data.puzzle_order and 1 in data.puzzle_order and 2 in data.puzzle_order) or data.puzzle_step < 0 or data.puzzle_step > 3: return false
	if data.cargo_route < 0 or data.cargo_route > 2 or data.sites.size() != director.sites.size() or data.structures.size() > 40: return false
	for site in data.sites:
		if not site is Dictionary or not site.get("at") is Vector3 or site.get("kind") not in ["record", "signal", "outpost"] or not site.get("id") is String or not site.get("done") is bool: return false
		for key in ["health", "timer"]:
			if not (site.get(key) is float or site.get(key) is int) or float(site[key]) < 0: return false
	for person in data.people.values():
		if not person is Dictionary: return false
		var prototype := director.person(director.game.player.peer_id)
		for key in prototype:
			if not person.has(key) or typeof(person[key]) != typeof(prototype[key]): return false
		if person.bandages < 0 or person.bandages > 8 or person.offers.size() > 3 or person.augments.size() > RunRules.AUGMENTS.size(): return false
		for id in person.offers+person.augments:
			if not RunRules.AUGMENTS.has(id): return false
	for item in data.structures:
		if not item is Dictionary or not item.get("id") is int or item.id <= 0 or not item.get("at") is Vector3 or item.get("kind") not in ["gate", "embrasure", "observation"] or not item.get("open") is bool: return false
		if not (item.get("hp") is float or item.get("hp") is int) or item.hp <= 0 or item.hp > 600 or not item.get("yaw") is float or not item.get("owner") is int: return false
	if not data.operation.is_empty():
		for key in ["kind", "stage", "at", "health", "timer", "wave", "peer", "expires", "done"]:
			if not data.operation.has(key): return false
		if data.operation.kind not in ["drone", "escort", "radio"] or data.operation.stage not in ["offered", "complete", "failed"] or not data.operation.at is Vector3: return false
	return true

func save_run() -> String:
	var error := eligibility()
	if not error.is_empty(): return error
	var state := capture()
	if not plain(state): return "Checkpoint could not be written."
	var bytes := pack(state)
	if bytes.size() > MAX_BYTES: return "Checkpoint could not be written."
	var target := path()
	var file := FileAccess.open(target+".tmp", FileAccess.WRITE)
	if not file: return "Checkpoint could not be written."
	file.store_buffer(bytes)
	file.flush()
	var status := file.get_error()
	file.close()
	if status != OK: return "Checkpoint could not be written."
	if FileAccess.file_exists(target):
		if DirAccess.copy_absolute(target, target+".bak") != OK: return "Checkpoint could not be written."
	if DirAccess.rename_absolute(target+".tmp", target) != OK: return "Checkpoint could not be written."
	return "Checkpoint saved."

func load_run() -> String:
	var error := eligibility()
	if not error.is_empty(): return error
	if not FileAccess.file_exists(path()): return "No checkpoint found for this map and profile."
	var file := FileAccess.open(path(), FileAccess.READ)
	if not file or file.get_length() > MAX_BYTES: return "Checkpoint is damaged or incompatible."
	var state := unpack(file.get_buffer(file.get_length()))
	file.close()
	state = remap_players(state)
	error = validate(state)
	if not error.is_empty(): return error
	if not director.game.started:
		if NetSession.enabled:
			if not NetSession.is_host() or not NetSession.ready_peers.values().all(func(value): return value) or not NetSession.class_roster.values().all(func(value): return value.get("locked", false)): return "All teammates must be ready with their classes locked."
			NetSession.start_game()
		else: director.game._on_start(false)
	restore(state)
	return "Expedition continued."

func remap_players(original: Dictionary) -> Dictionary:
	if not original.get("roster") is Dictionary or not original.get("players") is Dictionary: return original
	var current := {}
	for p: Player in director.actors(): current[p.peer_id] = str(NetSession.roster.get(p.peer_id, CharacterProfile.data.name))
	if original.roster.size() != current.size(): return original
	var mapping := {}
	for old_id in original.roster:
		var name: String = str(original.roster[old_id])
		var matches: Array = current.keys().filter(func(id): return current[id] == name)
		if matches.size() != 1: return original
		mapping[old_id] = matches[0]
	var state := original.duplicate(true)
	state.roster = _peer_keys(state.roster, mapping)
	state.players = _peer_keys(state.players, mapping)
	state.leaderboard = _peer_keys(state.get("leaderboard", {}), mapping)
	for id in state.leaderboard:
		if state.leaderboard[id] is Dictionary: state.leaderboard[id].id = id
	if not state.get("director") is Dictionary: return state
	var run: Dictionary = state.director
	if run.get("people") is Dictionary: run.people = _peer_keys(run.people, mapping)
	if mapping.has(run.get("cargo_peer")): run.cargo_peer = mapping[run.cargo_peer]
	if run.get("operation") is Dictionary and mapping.has(run.operation.get("peer")): run.operation.peer = mapping[run.operation.peer]
	if run.get("structures") is Array:
		for item in run.structures:
			if item is Dictionary and mapping.has(item.get("owner")): item.owner = mapping[item.owner]
	if run.get("range") is Dictionary and not run.range.is_empty():
		for key in ["scores", "progress"]:
			if run.range.get(key) is Dictionary: run.range[key] = _peer_keys(run.range[key], mapping)
		if mapping.has(run.range.get("owner")): run.range.owner = mapping[run.range.owner]
	for section in ["progression", "brewing", "hunting", "range"]:
		if not state.get(section) is Dictionary: continue
		for key in ["people", "stocks", "jobs"]:
			if state[section].get(key) is Dictionary: state[section][key] = _peer_keys(state[section][key], mapping)
	if state.get("towers") is Dictionary:
		for tower in state.towers.values():
			if not tower is Array or tower.size() < 12: continue
			for index in [1, 11]:
				if mapping.has(tower[index]): tower[index] = mapping[tower[index]]
	if state.get("world") is Dictionary and state.world.get("fireworks") is Dictionary and state.world.fireworks.get("stocks") is Dictionary:
		state.world.fireworks.stocks = _peer_keys(state.world.fireworks.stocks, mapping)
	# Reward tokens contain peer IDs delimited by colons. Remap only the peer components.
	if run.get("rewards") is Dictionary: run.rewards = _reward_keys(run.rewards, mapping)
	if state.get("classes") is Array and state.classes.size() == 4 and state.classes[3] is Dictionary: state.classes[3] = _reward_keys(state.classes[3], mapping)
	return state

static func _peer_keys(values: Dictionary, mapping: Dictionary) -> Dictionary:
	var result := {}
	for key in values: result[mapping.get(key, key)] = values[key]
	return result

static func _reward_keys(values: Dictionary, mapping: Dictionary) -> Dictionary:
	var result := {}
	for key in values:
		var updated := str(key)
		var parts := updated.split(":")
		for i in parts.size():
			if parts[i].is_valid_int() and mapping.has(int(parts[i])): parts[i] = str(mapping[int(parts[i])])
		updated = ":".join(parts)
		result[updated] = values[key]
	return result

func restore(state: Dictionary) -> void:
	var game := director.game
	director.apply_snapshot(state.director)
	game.settings.difficulty = director.config.difficulty
	game.difficulty = GameSettings.DIFFICULTIES[director.config.difficulty]
	game.waves.wave = int(state.wave[0])
	game.waves.completed = int(state.wave[1])
	game.waves.timer = maxf(1, float(state.wave[2]))
	game.waves.phase = "idle"
	game.waves.queue.clear()
	game.classes._serial = maxi(game.classes._serial, int(state.classes[0]))
	game.classes._received = maxi(game.classes._received, int(state.classes[1]))
	game.classes._last_wave = int(state.classes[2])
	game.classes._quests = state.classes[3].duplicate(true)
	for key in STATS: game.stats.set(key, state.stats[key])
	game.stats.players = state.leaderboard.duplicate(true)
	game.stats._finished = false
	game.classes._finished = false
	game.progression.apply_snapshot(state.progression, true)
	game.brewing.apply_snapshot(state.brewing)
	game.hunting.apply_snapshot(state.hunting)
	game.defences.apply_snapshot(state.towers, true)
	for tower in game.defences.towers.values(): tower.replica = false
	if director.config.region == "planes":
		for b in game.barricades: b.queue_free()
		game.barricades.clear()
		for row in state.bars:
			var bar: Barricade = SandbagLine.new() if row[0].get("name") == "sandbags" else Barricade.new()
			bar.setup(row[0], game.hud)
			game.add_child(bar)
			bar.level = int(row[1])
			bar.hp = float(row[2])
			bar.rebuild()
			game.barricades.append(bar)
			bar.breached.connect(func(): game.barricades.erase(bar); bar.queue_free())
		game.shooting_range.apply_snapshot(state.range)
		game.cornfield.fires.apply_snapshot(state.fire)
		game.weather.elapsed = float(state.weather_elapsed)
	else:
		for i in mini(state.bars.size(), game.barricades.size()):
			game.barricades[i].level = int(state.bars[i][1])
			game.barricades[i].hp = float(state.bars[i][2])
			game.barricades[i].rebuild()
		game.forest_keys.owned = state.keys.duplicate(true)
		game.secret_night.apply_snapshot(state.secret_night)
		game.field_trials.apply_snapshot(state.field_trials)
		game.hut.hp = float(state.hut)
	for i in game.sandbags.size():
		game.sandbags[i].level = int(state.sandbags[i][0])
		game.sandbags[i].hp = float(state.sandbags[i][1])
		game.sandbags[i].rebuild()
	game.day_night.clock_seconds = float(state.clock)
	game.day_night.night_index = int(state.night)
	game.weather.apply_snapshot(state.weather, true)
	game.weather._rng.state = int(state.world.weather_rng)
	if director.config.region == "planes": game._spawn_rng.state = int(state.world.spawn_rng)
	if game.fortune: game.fortune.rng.state = int(state.world.fortune_rng)
	game.achievements.counters = state.achievements[0].duplicate(true)
	game.achievements.session_unlocked = state.achievements[1].duplicate(true)
	for p: Player in director.actors(): _restore_player(p, state.players[p.peer_id])
	for loot in get_tree_for_game().get_nodes_in_group("checkpoint_pickups"):
		if loot is Loot and state.loots.has(_key(loot)):
			var entry: Array = state.loots[_key(loot)]
			loot.taken = bool(entry[0])
			loot.stocked_wave = int(entry[1])
			loot.cache_respawn_wave = int(entry[2])
			loot.global_position = entry[3]
			loot.visible = not loot.taken
	for door in get_tree_for_game().get_nodes_in_group("hut_doors"):
		if door is Door and state.doors.has(_key(door)): door._set_open(bool(state.doors[_key(door)]))
	if director.config.region == "forest":
		for i in game.forest_keys.spawned.size():
			var key: ForestKey = game.forest_keys.spawned[i]
			key.global_position = state.world.keys[i][0]
			key.taken = state.world.keys[i][1]
			key.pickup_visual.visible = not key.taken
	for i in game.pumpkins.size(): game.pumpkins[i].restore_broken(state.world.pumpkins[i])
	for key in windows:
		var pane := game.get_node_or_null(windows[key].path)
		if not state.world.windows.get(key, true):
			if is_instance_valid(pane): pane.free()
		elif not is_instance_valid(pane):
			var spec: Dictionary = windows[key]
			pane = Breakable.new()
			pane.name = spec.name
			pane.position = spec.position
			pane.rotation = spec.rotation
			game.get_node(spec.parent).add_child(pane)
			pane.setup(spec.size)
			spec.path = str(game.get_path_to(pane))
			if NetSession.is_host(): NetSession.world.broken_nodes[windows.keys().find(key)] = pane
	if game.fortune: game.fortune.apply_snapshot(state.world.fortune)
	if game.get("fireworks"): game.fireworks.apply_snapshot(state.world.fireworks)
	if NetSession.is_host():
		NetSession.world.purse = int(state.purse)
		NetSession._send_lobby()
		NetSession._sequence += 1
		for peer in NetSession.world.actors:
			if peer != NetSession.local_id(): NetSession.send_reliable_state(peer, true)

func _restore_player(p: Player, data: Dictionary) -> void:
	var game := director.game
	var w := director.gear(p.peer_id)
	p.global_position = data.position
	p.rotation.y = data.yaw
	p.pitch = data.pitch
	p.velocity = Vector3.ZERO
	p.reset_physics_interpolation()
	p.hp = data.hp
	p.max_hp = data.max_hp
	p.score = data.score
	p.speed_mul = data.speed
	p.regen_mul = data.regen
	p.mushroom_effects = data.effects.duplicate(true)
	p.relic = data.relic
	p.self_revives = data.revives
	p.teleport_cooldown = data.teleport
	p.set_crouching(data.physics[0], false)
	p.regen_timer = float(data.physics[1])
	p.revive_protection = float(data.physics[2])
	p.cash_cooldown = float(data.physics[3])
	p.set_meta("class_mission_from_start", data.mission_from_start)
	p.class_combat.configure(data.class)
	if p.peer_id == NetSession.local_id() or not NetSession.enabled: CharacterProfile.begin_match(str(data.class.id))
	if NetSession.is_host():
		NetSession.class_roster[p.peer_id] = data.class.duplicate(true)
		NetSession.class_roster[p.peer_id].locked = true
	p.class_combat.apply_runtime(data.combat)
	w.unlocked = data.unlocked.duplicate()
	w.skins = data.skins.duplicate()
	w.mod_owned = data.mod_owned.duplicate(true)
	w.mod_loadout = data.mod_loadout.duplicate(true)
	w.damage_mul = data.mods[0]
	w.reload_mul = data.mods[1]
	w.spread_mul = data.mods[2]
	w.refresh_class_magazines()
	for id in data.ammo:
		if not w.state.has(id): continue
		w.state[id].ammo = data.ammo[id][0]
		w.state[id].reserve = data.ammo[id][1]
		w.state[id].cooldown = 0.0
		w.state[id].reloading = 0.0
	w.grenades = data.grenades
	w.grenades_max = data.grenades_max
	w.network_apply = true
	w.set_weapon(data.weapon)
	w.network_apply = false
	# Selecting the saved weapon clears its reload bar; restore runtime afterwards.
	for id in w.state:
		for key in WEAPON_RUNTIME:
			if key not in ["cooldown", "reloading"]: w.state[id].erase(key)
	for id in data.weapon_runtime:
		for key in data.weapon_runtime[id]: w.state[id][key] = data.weapon_runtime[id][key]
	w.update_hud()
	p.hud.set_health(p.hp)
	p.hud.set_score(p.score)
	if NetSession.is_host():
		NetSession.world.levels[p.peer_id] = data.levels.duplicate(true)
		NetSession.world.mushrooms[p.peer_id] = data.mushrooms.duplicate(true)
	else:
		game.skills.levels = data.levels.duplicate(true)
		game.inventory.mushrooms = data.mushrooms.duplicate(true)

func _key(node: Node3D) -> String:
	if node is Loot: return "loot:%d" % director.game.loots.find(node)
	return "door:%.3f:%.3f:%.3f" % [node.global_position.x, node.global_position.y, node.global_position.z]
