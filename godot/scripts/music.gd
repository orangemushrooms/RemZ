# Music: title screen, calm loop between waves, combat track during a wave, game over. Between waves
# the track follows the clock, so a round that runs into the day does not repeat the night loop.
# Tracks crossfade; an extra "horde" layer (distant zombie choir) is mixed in with the number of
# zombies alive. Files live in assets/audio/music (from the user's sound library).
class_name Music
extends Node

const DIR := "res://assets/audio/music/"
# "file" names the mp3 when it differs from the logical track name.
const TRACKS := {
	"title": { "loop": true, "db": -10.0 },
	"night": { "loop": true, "db": -14.0 },
	"morning": { "loop": true, "db": -13.0, "file": "survived_the_night" },
	"combat": { "loop": true, "db": -11.0 },
	"gameover": { "loop": false, "db": -8.0 },
	"horde": { "loop": true, "db": -16.0 },
}
const FADE := 2.5

var _players: Dictionary = {}
var _target: Dictionary = {}   # track -> linear volume target
var current := ""
var horde := 0.0               # 0..1 intensity of the horde layer
var _titan_duck := 0.0
var _titan_hold := 0.0
var _titan_mix := 1.0

func titan_duck(amount: float, duration: float) -> void:
	_titan_duck = maxf(_titan_duck, clampf(amount, 0, 0.7))
	_titan_hold = maxf(_titan_hold, duration)

func _ready() -> void:
	for name in TRACKS:
		var path: String = DIR + str(TRACKS[name].get("file", name)) + ".mp3"
		if not ResourceLoader.exists(path):
			continue
		var st: AudioStream = load(path)
		if st is AudioStreamMP3:
			st.loop = TRACKS[name]["loop"]
		var p := AudioStreamPlayer.new()
		p.stream = st
		p.volume_db = TRACKS[name]["db"]
		p.volume_linear = 0.0
		add_child(p)
		_players[name] = p
		_target[name] = 0.0

func play(name: String) -> void:
	if name == current:
		return
	current = name
	for n in _players:
		if n == "horde":
			continue
		_target[n] = db_to_linear(TRACKS[n]["db"]) if n == name else 0.0
	if _players.has(name) and not _players[name].playing:
		_players[name].play()

# The calm track between two waves: daylight gets its own song, the night keeps the old loop.
# Never used before the first wave is over - the round still opens on the night track.
func intermission_track(hour: float) -> String:
	var h := fposmod(hour, 24.0)
	return "morning" if _players.has("morning") and h >= 5.0 and h < 17.0 else "night"

func stop_all() -> void:
	current = ""
	for n in _players:
		_target[n] = 0.0

func _process(delta: float) -> void:
	_titan_hold = maxf(0, _titan_hold - delta)
	if _titan_hold <= 0: _titan_duck = 0
	_titan_mix = move_toward(_titan_mix, 1.0 - _titan_duck, delta * (3.0 if _titan_duck > 0 else 0.45))
	_target["horde"] = clampf(horde, 0.0, 1.0) * db_to_linear(TRACKS["horde"]["db"]) if _target.has("horde") else 0.0
	for n in _players:
		var p: AudioStreamPlayer = _players[n]
		var want: float = _target[n] * _titan_mix
		var have: float = p.volume_linear
		if want > 0.0 and not p.playing:
			p.play()
		var speed := delta / FADE
		var v := move_toward(have, want, speed)
		p.volume_linear = v
		if v <= 0.001 and want <= 0.0 and p.playing:
			p.stop()
