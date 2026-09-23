# One-time import of the saves from the game's old name ("Birkenhof Nacht" -> "RemZ", 23 Sep 2026):
# settings and co-op address copied only when missing, achievements unioned, high scores merged
# without doubles, nothing again on the next start. Works on temporary folders, never on real saves.
# Godot.exe --headless --path godot --script res://tests/run.gd -- --suite=legacy_user_data
extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")

func check(ok: bool, description: String) -> void:
	checks += 1
	if ok: print("PASS: ", description)
	else:
		failures += 1
		push_error("FAIL: " + description)

func write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)

func read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

func read_json(path: String) -> Variant:
	return JSON.parse_string(read(path)) if FileAccess.file_exists(path) else null

func fresh(dir: String) -> void:
	if DirAccess.dir_exists_absolute(dir):
		for file in DirAccess.get_files_at(dir): DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.make_dir_recursive_absolute(dir)

func run() -> void:
	var base := OS.get_temp_dir().path_join("remz-legacy-test")
	var old := base.path_join(LegacyUserData.OLD_NAME)
	var new := base.path_join("RemZ")
	fresh(old)
	fresh(new)
	write(old.path_join("settings.cfg"), "[video]\n\nprofile=2\n")
	write(old.path_join("network.cfg"), "[network]\n\nname=\"Keknyan\"\n")
	write(old.path_join("achievements.json"), JSON.stringify({"unlocked": ["head_1", "road", "wave_1"]}))
	var runs := []
	for i in 10:
		runs.append({"score": 1000.0 - i * 50.0, "wave": 5.0, "kills": 40.0 + i, "seconds": 300.0 + i, "date": "2026-09-2%d" % (i % 3)})
	write(old.path_join("highscores.json"), JSON.stringify({"runs": runs}))

	# First start under the new name, empty folder
	var report := LegacyUserData.import_once(new, old)
	check(read(new.path_join("settings.cfg")).contains("profile=2") and read(new.path_join("network.cfg")).contains("Keknyan"),
		"Settings and co-op name come over into an empty folder")
	check(read_json(new.path_join("achievements.json")).unlocked == ["head_1", "road", "wave_1"], "Every achievement comes over")
	check(read_json(new.path_join("highscores.json")).runs.size() == 10, "The whole high-score table comes over")
	check(FileAccess.file_exists(new.path_join(LegacyUserData.MARKER)) and report.size() == 4, "The import reports four files and leaves its marker (%s)" % JSON.stringify(report))

	# Second start: the marker stops it, even when the old folder changes
	write(old.path_join("achievements.json"), JSON.stringify({"unlocked": ["head_1", "road", "wave_1", "later"]}))
	check(LegacyUserData.import_once(new, old).is_empty() and not read(new.path_join("achievements.json")).contains("later"),
		"The next start imports nothing again")

	# A player who already played under the new name before the import ran
	fresh(new)
	write(new.path_join("settings.cfg"), "[video]\n\nprofile=0\n")
	write(new.path_join("achievements.json"), JSON.stringify({"unlocked": ["road", "titan_1"]}))
	# one fresh run (ints, as RunStats writes them) and the old best run again, as a second copy would bring it
	write(new.path_join("highscores.json"), JSON.stringify({"runs": [
		{"score": 5000, "wave": 12, "kills": 300, "seconds": 1200, "date": "2026-09-23"},
		{"score": 1000, "wave": 5, "kills": 40, "seconds": 300, "date": "2026-09-20"}]}))
	LegacyUserData.import_once(new, old)
	check(read(new.path_join("settings.cfg")).contains("profile=0"), "Settings chosen under the new name stay")
	check(read_json(new.path_join("achievements.json")).unlocked == ["head_1", "road", "wave_1", "later", "titan_1"],
		"Achievements from both folders add up, none twice")
	var table: Array = read_json(new.path_join("highscores.json")).runs
	var best_twice := table.filter(func(r): return int(r.score) == 1000).size()
	check(table.size() == 10 and int(table[0].score) == 5000 and best_twice == 1 and int(table.back().score) == 600,
		"High scores merge: the new best leads, the shared run counts once, the table keeps ten (%d rows)" % table.size())

	# No old folder (a fresh install) and an unrenamed project do nothing and leave no marker
	fresh(new)
	check(LegacyUserData.import_once(new, base.path_join("nothing-here")).is_empty() and not FileAccess.file_exists(new.path_join(LegacyUserData.MARKER)),
		"Without an old folder nothing happens")
	check(LegacyUserData.import_once(old, old).is_empty(), "Under the old name the import stands still")
	# The game's own call looks beside its user folder: only true while Godot keeps user:// in
	# app_userdata/<project name> (a custom user dir would need its own path here)
	var user_dir := OS.get_user_data_dir()
	check(user_dir.get_file() == str(ProjectSettings.get_setting("application/config/name")) and user_dir.get_base_dir().get_file() == "app_userdata",
		"The saves live in app_userdata/<name>, so the old ones are found beside them (%s)" % user_dir)

	fresh(old)
	fresh(new)
	DirAccess.remove_absolute(old)
	DirAccess.remove_absolute(new)
	DirAccess.remove_absolute(base)
	print("LEGACY_USER_DATA_DONE checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
