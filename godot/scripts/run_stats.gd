# Run statistics (kills, headshots, shots, hits, time) plus the persistent high-score table (user://highscores.json).
# Other systems report through the counters; main.gd finishes a run with finish() at game over.
class_name RunStats
extends Node

const SAVE := "user://highscores.json"
const MAX_ENTRIES := 10

var kills := 0
var headshots := 0
var shots := 0
var hits := 0
var grenades_thrown := 0
var melee_hits := 0
var barricades_built := 0
var mushrooms_eaten := 0
var damage_taken := 0.0
var points_earned := 0
var seconds := 0.0
var best_streak := 0
var _streak := 0
var _streak_t := 0.0
var _finished := false
var table: Array = []          # [{score, wave, kills, headshots, seconds, difficulty, date}], best first
var persist := true            # test runs never write the table

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	for a in OS.get_cmdline_user_args():
		if a in ["--autotest", "--smoke-test", "--benchmark", "--shot-ui", "--intro-test"] or a.begins_with("--view"):
			persist = false
	_load()

func tick(delta: float) -> void:
	seconds += delta
	if _streak_t > 0.0:
		_streak_t -= delta
		if _streak_t <= 0.0:
			_streak = 0

func kill(head: bool, points: int) -> void:
	kills += 1
	points_earned += points
	if head:
		headshots += 1
	_streak += 1
	_streak_t = 4.0
	best_streak = maxi(best_streak, _streak)

func streak() -> int:
	return _streak

func accuracy() -> float:
	return (float(hits) / shots) if shots > 0 else 0.0

static func time_text(s: float) -> String:
	var m := int(s) / 60
	return "%d:%02d min" % [m, int(s) % 60]

func _load() -> void:
	table = []
	if FileAccess.file_exists(SAVE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(SAVE))
		if d is Dictionary and d.get("runs") is Array:
			for r in d["runs"]:
				if r is Dictionary:
					table.append(r)
	table.sort_custom(func(a, b): return int(a.get("score", 0)) > int(b.get("score", 0)))

func _save() -> void:
	if not persist:
		return
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({ "runs": table }))

func best() -> Dictionary:
	return table[0] if not table.is_empty() else {}

# Records the run; returns the 1-based rank in the table or 0 when it did not make the list.
func finish(score: int, wave: int, difficulty: String) -> int:
	if _finished:
		return 0
	_finished = true
	if kills == 0 and wave == 0:
		return 0
	var entry := { "score": score, "wave": wave, "kills": kills, "headshots": headshots, "seconds": int(seconds),
		"accuracy": accuracy(), "difficulty": difficulty, "date": Time.get_date_string_from_system() }
	table.append(entry)
	table.sort_custom(func(a, b): return int(a.get("score", 0)) > int(b.get("score", 0)))
	var rank := table.find(entry) + 1
	if table.size() > MAX_ENTRIES:
		table.resize(MAX_ENTRIES)
	_save()
	return rank if rank <= MAX_ENTRIES else 0
