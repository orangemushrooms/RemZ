class_name Campaign
extends RefCounted
## Region IDs remain stable when new scenes are added. Construction regions cannot be selected.
const ROUNDS := 25
const SAVE := "user://campaign.json"
const ART_SIZE := Vector2(1312, 1199)
const REGIONS := [
	{"id": "forest", "title": "FOREST", "available": true, "scene": "res://scenes/main.tscn", "anchor": Vector2(682, 330),
		"outline": [Vector2(389,210),Vector2(712,116),Vector2(734,177),Vector2(765,182),Vector2(792,201),Vector2(828,215),Vector2(832,275),Vector2(816,290),Vector2(838,340),Vector2(865,399),Vector2(904,452),Vector2(860,511),Vector2(808,547),Vector2(705,566),Vector2(694,540),Vector2(623,561),Vector2(610,530),Vector2(580,525),Vector2(529,432),Vector2(520,402),Vector2(510,399),Vector2(495,377),Vector2(466,387),Vector2(424,280),Vector2(408,272)]},
	{"id": "north_end", "title": "NORTH END", "available": false, "anchor": Vector2(245, 320),
		"outline": [Vector2(71,334),Vector2(90,315),Vector2(104,290),Vector2(369,180),Vector2(408,272),Vector2(424,280),Vector2(466,387),Vector2(442,419),Vector2(425,463),Vector2(370,438),Vector2(348,434),Vector2(319,453),Vector2(264,462),Vector2(207,460),Vector2(177,452),Vector2(156,453),Vector2(139,413),Vector2(93,450),Vector2(72,382)]},
	{"id": "core", "title": "CORE", "available": false, "anchor": Vector2(284, 502),
		"outline": [Vector2(93,450),Vector2(139,413),Vector2(156,453),Vector2(177,452),Vector2(207,460),Vector2(264,462),Vector2(319,453),Vector2(348,434),Vector2(425,463),Vector2(435,507),Vector2(439,610),Vector2(414,631),Vector2(238,704),Vector2(195,645),Vector2(177,602),Vector2(151,585),Vector2(136,506)]},
	{"id": "east_end", "title": "EAST END", "available": false, "anchor": Vector2(466, 469),
		"outline": [Vector2(425,463),Vector2(442,419),Vector2(465,410),Vector2(480,421),Vector2(497,442),Vector2(529,432),Vector2(516,452),Vector2(520,574),Vector2(510,590),Vector2(491,606),Vector2(483,626),Vector2(466,633),Vector2(439,610),Vector2(435,507)]},
	{"id": "planes", "title": "THE PLANES", "available": true, "exploration": true, "survival": true, "scene": "res://scenes/planes.tscn", "anchor": Vector2(490, 743),
		"outline": [Vector2(259,868),Vector2(279,797),Vector2(306,751),Vector2(341,732),Vector2(366,709),Vector2(414,690),Vector2(459,680),Vector2(471,666),Vector2(521,650),Vector2(538,658),Vector2(584,650),Vector2(602,654),Vector2(616,667),Vector2(661,683),Vector2(680,706),Vector2(703,721),Vector2(731,854),Vector2(427,986),Vector2(413,965),Vector2(367,988),Vector2(350,981),Vector2(285,901),Vector2(265,890)]},
	{"id": "suburbs_lake", "title": "SUBURBS & LAKE", "available": false, "anchor": Vector2(1006, 571),
		"outline": [Vector2(703,721),Vector2(681,705),Vector2(685,661),Vector2(839,606),Vector2(874,594),Vector2(940,494),Vector2(1014,394),Vector2(1030,412),Vector2(1050,415),Vector2(1075,433),Vector2(1104,423),Vector2(1130,482),Vector2(1150,506),Vector2(1173,518),Vector2(1172,575),Vector2(1205,694),Vector2(1193,726),Vector2(1203,756),Vector2(1222,775),Vector2(1235,853),Vector2(1162,840),Vector2(1138,793),Vector2(1067,771),Vector2(1018,783),Vector2(1000,750),Vector2(991,718),Vector2(896,751),Vector2(774,786),Vector2(721,805)]},
]

var selected_id := "forest"
var progress: Dictionary = {}
var persist := true
var save_path := SAVE

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg in ["--smoke-test", "--autotest", "--benchmark", "--shot-ui"] or arg.begins_with("--suite="):
			persist = false
	if persist: load_progress()

static func region(id: String) -> Dictionary:
	for entry: Dictionary in REGIONS:
		if entry.id == id: return entry
	return {}

func select(id: String) -> bool:
	if not region(id).get("available", false): return false
	selected_id = id
	return true

func best_wave(id: String) -> int:
	return int(progress.get(id, {}).get("best_wave", 0))

func cleared(id: String) -> bool:
	return bool(progress.get(id, {}).get("cleared", false))

func cleared_count() -> int:
	var count := 0
	for entry: Dictionary in REGIONS:
		if cleared(entry.id): count += 1
	return count

func record_wave(number: int, difficulty: String) -> void:
	if not region(selected_id).get("available", false): return
	if region(selected_id).get("exploration", false) and not region(selected_id).get("survival",false): return
	var entry: Dictionary = progress.get(selected_id, {})
	entry.best_wave = maxi(best_wave(selected_id), clampi(number, 0, ROUNDS))
	if number >= ROUNDS:
		entry.cleared = true
		entry.difficulty = difficulty
	progress[selected_id] = entry
	if persist: save_progress()

func load_progress() -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(save_path)) if FileAccess.file_exists(save_path) else null
	if not data is Dictionary or not data.get("regions") is Dictionary: return
	progress.clear()
	for entry: Dictionary in REGIONS:
		var stored = data.regions.get(entry.id)
		if stored is Dictionary:
			progress[entry.id] = {"best_wave": clampi(int(stored.get("best_wave", 0)), 0, ROUNDS), "cleared": stored.get("cleared", false) == true}

func save_progress() -> void:
	var file := FileAccess.open(save_path + ".tmp", FileAccess.WRITE)
	if not file:
		push_warning("Campaign progress could not be saved.")
		return
	file.store_string(JSON.stringify({"version": 1, "regions": progress}))
	file.close()
	if DirAccess.rename_absolute(save_path + ".tmp", save_path) != OK:
		push_warning("Campaign progress could not be replaced.")
