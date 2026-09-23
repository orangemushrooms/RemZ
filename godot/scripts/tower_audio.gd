extends Node3D
# One local positional emitter per tower; show_shot is also driven by remote snapshots.
const DIR := "res://assets/audio/sfx/towers/"
const CLIPS := {"standard": "sentinel_shot", "flame": "flame_loop", "mg42": "mg42_shot", "mortar": "mortar_shot", "tesla": "tesla_shot"}
const LEVELS := {"standard": -5.0, "flame": -10.0, "mg42": -8.0, "mortar": -3.0, "tesla": -5.0}
const DISTANCES := {"standard": 120.0, "flame": 70.0, "mg42": 140.0, "mortar": 160.0, "tesla": 110.0}
var tower: DefenceTower
var voice: AudioStreamPlayer3D
var hold := 0.0
var gain := 0.0
static var _streams: Dictionary = {}

static func prewarm() -> void:
	for kind: String in CLIPS:
		if not _streams.has(kind): _streams[kind] = load(DIR + CLIPS[kind] + ".wav")

func _ready() -> void:
	voice = AudioStreamPlayer3D.new()
	voice.name = "TowerShotSound"
	prewarm()
	var stream: AudioStreamWAV = _streams[tower.kind]
	if tower.kind == "flame":
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	voice.stream = stream
	voice.volume_db = LEVELS[tower.kind]
	voice.unit_size = 20.0 if tower.kind == "standard" else 12.0
	voice.max_distance = DISTANCES[tower.kind]
	voice.max_polyphony = 3 if tower.kind in ["standard", "mg42"] else 1
	add_child(voice)

func fire() -> void:
	if tower.kind == "flame":
		hold = 0.18 # Bridges shot intervals and snapshot jitter, then fades promptly.
		if not voice.playing:
			gain = 0.0
			voice.volume_db = -60.0
			voice.play()
	else:
		voice.pitch_scale = randf_range(0.985, 1.015)
		voice.play()

func _process(delta: float) -> void:
	if not tower.game.started or tower.game.over:
		voice.stop()
		hold = 0.0
		gain = 0.0
		return
	if tower.kind != "flame": return
	hold = maxf(0.0, hold - delta)
	gain = move_toward(gain, 1.0 if hold > 0 else 0.0, delta / (0.035 if hold > 0 else 0.10))
	voice.volume_db = float(LEVELS.flame) + linear_to_db(maxf(0.001, gain))
	if hold <= 0 and gain <= 0: voice.stop()
