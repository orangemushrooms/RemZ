# One-time move of the player's saves from the game's old name. Godot keeps user:// in
# <data dir>/Godot/app_userdata/<project name>, so renaming "Birkenhof Nacht" to "RemZ" (23 Sep 2026)
# would have started every player with default settings and no high scores or achievements.
# On the first start under the new name the saves come over: settings and the co-op name/address
# when the new folder has none yet, achievements and high scores merged with whatever the new
# folder already holds (a round played before this ran must not be lost either). A marker file in
# the new folder keeps it to that one time. Shader and pipeline caches stay behind: the pipeline
# cache is read before any script runs, and the loading screen compiles the shaders anyway.
class_name LegacyUserData
extends RefCounted

const OLD_NAME := "Birkenhof Nacht"
const MARKER := "legacy_imported.txt"
const COPY_WHEN_MISSING := ["settings.cfg", "network.cfg"]

# Returns what happened per file (empty when there was nothing to do). Both folders can be given for
# tests; the game calls it without arguments.
static func import_once(target_dir := "", source_dir := "") -> Dictionary:
	if target_dir.is_empty(): target_dir = OS.get_user_data_dir()
	if source_dir.is_empty(): source_dir = target_dir.get_base_dir().path_join(OLD_NAME)
	var report := {}
	if source_dir.simplify_path() == target_dir.simplify_path() or not DirAccess.dir_exists_absolute(source_dir):
		return report
	if FileAccess.file_exists(target_dir.path_join(MARKER)):
		return report
	DirAccess.make_dir_recursive_absolute(target_dir)
	for name: String in COPY_WHEN_MISSING:
		var from := source_dir.path_join(name)
		var to := target_dir.path_join(name)
		if FileAccess.file_exists(from) and not FileAccess.file_exists(to):
			report[name] = "copied" if DirAccess.copy_absolute(from, to) == OK else "failed"
	var merged := _merge_achievements(source_dir.path_join("achievements.json"), target_dir.path_join("achievements.json"))
	if not merged.is_empty(): report["achievements.json"] = merged
	merged = _merge_high_scores(source_dir.path_join("highscores.json"), target_dir.path_join("highscores.json"))
	if not merged.is_empty(): report["highscores.json"] = merged
	var marker := FileAccess.open(target_dir.path_join(MARKER), FileAccess.WRITE)
	if marker:
		marker.store_line("Saves imported from %s on %s" % [source_dir, Time.get_datetime_string_from_system()])
		marker.store_line(JSON.stringify(report))
	print("LEGACY_USER_DATA ", JSON.stringify(report))
	return report

static func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path): return null
	return JSON.parse_string(FileAccess.get_file_as_string(path))

static func _write_json(path: String, data: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(data))
	return true

# Achievements only ever grow: the union of both lists, the old order first.
static func _merge_achievements(from: String, to: String) -> String:
	var old = _read_json(from)
	if not (old is Dictionary and old.get("unlocked") is Array): return ""
	var current = _read_json(to)
	var ids: Array = []
	for id in old.unlocked:
		if not ids.has(id): ids.append(id)
	var added := ids.size()
	if current is Dictionary and current.get("unlocked") is Array:
		for id in current.unlocked:
			if not ids.has(id): ids.append(id)
	if not _write_json(to, {"unlocked": ids}): return "failed"
	return "%d old + %d new" % [added, ids.size() - added]

# High scores: both tables in one, the same run only once, best RunStats.MAX_ENTRIES by score.
static func _merge_high_scores(from: String, to: String) -> String:
	var old = _read_json(from)
	if not (old is Dictionary and old.get("runs") is Array): return ""
	var rows: Array = []
	var seen := {}
	var sources: Array = [old.runs]
	var current = _read_json(to)
	if current is Dictionary and current.get("runs") is Array: sources.append(current.runs)
	for runs: Array in sources:
		for run in runs:
			if not run is Dictionary: continue
			# JSON brings numbers back as floats in one file and ints in the other: key on the values
			var key := "%d|%d|%d|%s" % [int(run.get("score", 0)), int(run.get("seconds", 0)), int(run.get("kills", 0)), str(run.get("date", ""))]
			if seen.has(key): continue
			seen[key] = true
			rows.append(run)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("score", 0)) > int(b.get("score", 0)))
	if rows.size() > RunStats.MAX_ENTRIES: rows.resize(RunStats.MAX_ENTRIES)
	if not _write_json(to, {"runs": rows}): return "failed"
	return "%d runs" % rows.size()
