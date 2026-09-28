extends Node
## A local identity survives scene reloads, matches and class changes. Tests use in-memory profiles.
signal changed
signal xp_gained(amount: int, reason: String)
signal level_gained(class_id: String, level: int)
const Classes = preload("res://scripts/character_classes.gd")
const VERSION := 2 # Slower XP curve; old profiles retain their level and fractional progress.
const STAT_KEYS := ["kills", "headshots", "headshot_kills", "deaths", "boss_kills", "missions", "waves", "best_streak", "seconds", "multiplayer_kills", "multiplayer_missions"]
var profile_id := "local"
var data: Dictionary = {}
var directory := ""
var persist := true
var dirty := false
var save_error := ""
var context := "main"
var match_class := ""
var _save_t := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	directory = ProjectSettings.globalize_path("res://../profiles") if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("profiles")
	for arg in OS.get_cmdline_user_args():
		if arg in ["--smoke-test", "--autotest", "--benchmark", "--shot-ui", "--intro-test", "--trailer-run", "--eos-check"] or arg.begins_with("--suite=") or arg.begins_with("--view"): persist = false
	if persist:
		var config := ConfigFile.new()
		if config.load("user://character.cfg") == OK:
			directory = str(config.get_value("profile", "directory", directory))
			profile_id = str(config.get_value("profile", "id", "local"))
		if DirAccess.make_dir_recursive_absolute(directory) != OK:
			directory = ProjectSettings.globalize_path("user://profiles")
			DirAccess.make_dir_recursive_absolute(directory)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--character-profile="): profile_id = arg.trim_prefix("--character-profile=")
	if not profile_id.is_valid_identifier(): profile_id = "local"
	load_profile(profile_id)
	if data.is_empty(): data = empty_profile()
	if persist and save_error.is_empty() and not FileAccess.file_exists(path_for(profile_id)):
		dirty = true
		save()

static func empty_profile(name: String = "Player") -> Dictionary:
	var classes := {}
	for id in Classes.ORDER:
		var stats := {}
		for key in STAT_KEYS: stats[key] = 0
		classes[id] = {"total_xp": 0, "choices": [-1, -1, -1, -1, -1, -1], "stats": stats}
	return {"version": VERSION, "name": name, "selected": "gunslinger", "classes": classes,
		"quests": {}, "achievements": {}, "cosmetics": {}, "total_kills": 0}

static func number(value: Variant, limit: float = 1000000000000.0) -> float:
	if not (value is int or value is float) or not is_finite(float(value)): return 0.0
	return clampf(float(value), 0.0, limit)

static func sanitize(raw: Dictionary) -> Dictionary:
	var result := empty_profile(str(raw.get("name", "Player")).strip_edges().left(24))
	if result.name.is_empty(): result.name = "Player"
	if raw.get("selected") in Classes.ORDER: result.selected = raw.selected
	var stored: Variant = raw.get("classes")
	if stored is Dictionary:
		for id in Classes.ORDER:
			var entry: Variant = stored.get(id)
			if not entry is Dictionary: continue
			var total := number(entry.get("total_xp", 0))
			if int(number(raw.get("version", 1))) < 2:
				total = minf(1000000000000.0, int(total) * 11 / 10)
			result.classes[id].total_xp = int(total)
			result.classes[id].choices = Classes.valid_choices(id, Classes.level_for(result.classes[id].total_xp), entry.get("choices", []))
			var stats: Variant = entry.get("stats")
			if stats is Dictionary:
				for key in STAT_KEYS: result.classes[id].stats[key] = number(stats.get(key, 0))
			result.total_kills += int(result.classes[id].stats.kills)
	for field in ["quests", "achievements", "cosmetics"]:
		var entries: Variant = raw.get(field)
		if entries is Dictionary:
			for key in entries:
				if key is String and key.length() <= 100:
					result[field][key] = int(number(entries[key], 100000000)) if field == "quests" else entries[key] == true
	return result

func path_for(id: String) -> String:
	return directory.path_join(id + ".json")

static func read_json(path: String) -> Variant:
	var parser := JSON.new()
	return parser.data if parser.parse(FileAccess.get_file_as_string(path)) == OK else null

func load_profile(id: String) -> bool:
	if not id.is_valid_identifier() or context != "main": return false
	if dirty and not save(): return false
	var candidate := empty_profile()
	var migrated := false
	save_error = ""
	if persist:
		var raw: Variant = null
		for path in [path_for(id), path_for(id) + ".bak"]:
			if not FileAccess.file_exists(path): continue
			var parsed: Variant = read_json(path)
			if parsed is Dictionary and parsed.get("classes") is Dictionary:
				if int(number(parsed.get("version", 0))) > VERSION:
					save_error = "This profile needs a newer version of RemZ."
					return false
				raw = parsed
				break
		if raw is Dictionary:
			migrated = int(number(raw.get("version", 1))) < VERSION
			candidate = sanitize(raw)
		elif FileAccess.file_exists(path_for(id)) or FileAccess.file_exists(path_for(id) + ".bak"):
			save_error = "The profile could not be read. The original files have been kept."
			return false
	profile_id = id
	data = candidate
	if persist: _save_selection()
	dirty = migrated
	if migrated: save()
	changed.emit()
	return true

func _save_selection() -> void:
	if not persist: return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suite="): return
	var config := ConfigFile.new()
	config.set_value("profile", "id", profile_id)
	config.set_value("profile", "directory", directory)
	config.save("user://character.cfg")

func profiles() -> Dictionary:
	var entries := {profile_id: data.get("name", "Player")}
	if persist and DirAccess.dir_exists_absolute(directory):
		for file in DirAccess.get_files_at(directory):
			if not file.ends_with(".json"): continue
			var raw: Variant = read_json(directory.path_join(file))
			if raw is Dictionary: entries[file.get_basename()] = str(raw.get("name", "Player")).left(24)
	return entries

func create_profile(display_name: String) -> bool:
	if not can_edit() or display_name.strip_edges().is_empty(): return false
	var id := "p_" + Crypto.new().generate_random_bytes(12).hex_encode()
	if not load_profile(id): return false
	data.name = display_name.strip_edges().left(24)
	dirty = true
	var saved := save()
	changed.emit()
	return saved

func can_edit() -> bool:
	return context == "main" and not NetSession.enabled and not NetSession.online_pending and save_error.is_empty()

func select_class(id: String) -> bool:
	var allowed := can_edit() or (context == "multiplayer" and not NetSession.enabled and not NetSession.online_pending and save_error.is_empty())
	if not allowed or not Classes.CLASSES.has(id): return false
	data.selected = id
	dirty = true
	save()
	changed.emit()
	return true

func choose_skill(id: String, tier: int, choice: int) -> bool:
	if not can_edit() or not Classes.CLASSES.has(id) or tier < 0 or tier >= 6 or choice not in [0, 1]: return false
	if level(id) < Classes.TIERS[tier]: return false
	data.classes[id].choices[tier] = choice
	dirty = true
	save()
	changed.emit()
	return true

func selected() -> String:
	return str(data.get("selected", "gunslinger"))

func active_class() -> String:
	return match_class if not match_class.is_empty() else selected()

func level(id: String) -> int:
	return Classes.level_for(int(data.classes[id].total_xp))

func loadout(id: String = "") -> Dictionary:
	if id.is_empty(): id = selected()
	return Classes.loadout(id, int(data.classes[id].total_xp), data.classes[id].choices)

func begin_match(id: String) -> void:
	match_class = id if Classes.CLASSES.has(id) else selected()
	context = "match"
	changed.emit()

func end_match() -> void:
	save()
	match_class = ""
	context = "main"

func add_xp(amount: int, reason: String) -> void:
	if amount <= 0 or data.is_empty(): return
	var id := active_class()
	var before := level(id)
	data.classes[id].total_xp = mini(1000000000000, int(data.classes[id].total_xp) + amount)
	dirty = true
	xp_gained.emit(amount, reason)
	var after := level(id)
	for gained in range(before + 1, after + 1): level_gained.emit(id, gained)
	if after > before:
		if after == 30: unlock("veteran", 2500)
		var all_max := true
		for cls in Classes.ORDER:
			if level(cls) < 30: all_max = false
		if all_max: unlock("master_of_arms", 5000)
		save()
	changed.emit()

func add_stat(key: String, amount: float = 1.0) -> void:
	if key not in STAT_KEYS or amount <= 0.0: return
	var stats: Dictionary = data.classes[active_class()].stats
	stats[key] = minf(1000000000000.0, float(stats[key]) + amount)
	if key == "kills": data.total_kills += int(amount)
	dirty = true

func record_kill(head: bool, boss: bool, coop: bool, streak: int) -> void:
	add_stat("kills")
	if head: add_stat("headshot_kills")
	if boss: add_stat("boss_kills")
	if coop: add_stat("multiplayer_kills")
	var stats: Dictionary = data.classes[active_class()].stats
	stats.best_streak = maxi(int(stats.best_streak), streak)
	unlock("first_blood", 250)
	if int(data.total_kills) >= 10000: unlock("exterminator", 5000)

func record_headshot() -> void:
	add_stat("headshots")
	var heads := 0
	for id in Classes.ORDER: heads += int(data.classes[id].stats.headshots)
	if heads >= 100: unlock("perfect_aim", 1000)

func unlock(id: String, reward: int = 500) -> bool:
	if data.achievements.get(id, false): return false
	data.achievements[id] = true
	dirty = true
	add_xp(reward, "Achievement completed")
	save()
	return true

func quest(id: String, reward: int) -> void:
	data.quests[id] = int(data.quests.get(id, 0)) + 1
	add_xp(reward, "Quest completed")
	save()

func favourite() -> String:
	var best := selected()
	for id in Classes.ORDER:
		if float(data.classes[id].stats.seconds) > float(data.classes[best].stats.seconds): best = id
	return best

func save() -> bool:
	if not persist: dirty = false; return true
	if not dirty: return save_error.is_empty()
	# A damaged or future profile is never replaced by a default profile.
	if not save_error.is_empty() and not save_error.begins_with("Progress could not"): return false
	var path := path_for(profile_id)
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.flush()
		var error := file.get_error()
		file.close()
		if error == OK:
			if FileAccess.file_exists(path):
				# Copy only validated data, so recovering a backup never destroys the good copy.
				var previous: Variant = read_json(path)
				if previous is Dictionary and previous.get("classes") is Dictionary:
					if DirAccess.copy_absolute(path, path + ".bak") != OK: return _save_failed()
			if DirAccess.rename_absolute(path + ".tmp", path) == OK:
				dirty = false
				save_error = ""
				return true
	return _save_failed()

func _save_failed() -> bool:
	save_error = "Progress could not be saved. Check free space and write access to the profile folder."
	changed.emit()
	return false

func _process(delta: float) -> void:
	_save_t += delta
	if _save_t >= 15.0:
		_save_t = 0.0
		if dirty: save()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: save()

func _exit_tree() -> void:
	save()
