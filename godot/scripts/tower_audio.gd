extends Node3D
# One local positional emitter per tower; show_shot is also driven by remote snapshots.
const DIR := "res://assets/audio/sfx/towers/"
const CLIPS := {"standard": "sentinel_shot", "flame": "flame_loop", "mg42": "mg42_shot", "mortar": "mortar_shot", "tesla": "tesla_shot",
	# 2 Oct 2026 (tools/prepare_tower_audio.py, second block): the frost cannon loops like the flamethrower,
	# the siren's wail is one long clip, the rest are single reports and pulses.
	"searchlight": "searchlight_lock", "siren": "siren_wail", "supply": "supply_pulse", "frost": "frost_loop",
	"sniper": "sniper_shot", "rocket": "rocket_salvo", "harpoon": "harpoon_shot", "graviton": "graviton_pulse"}
const LEVELS := {"standard": -5.0, "flame": -10.0, "mg42": -8.0, "mortar": -3.0, "tesla": -5.0,
	"searchlight": -12.0, "siren": -2.0, "supply": -10.0, "frost": -11.0, "sniper": -2.0, "rocket": -4.0, "harpoon": -4.0, "graviton": -3.0}
const DISTANCES := {"standard": 120.0, "flame": 70.0, "mg42": 140.0, "mortar": 160.0, "tesla": 110.0,
	"searchlight": 80.0, "siren": 220.0, "supply": 70.0, "frost": 70.0, "sniper": 180.0, "rocket": 160.0, "harpoon": 130.0, "graviton": 140.0}
const LOOPED := ["flame", "frost"]
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
	if tower.kind in LOOPED:
		stream = stream.duplicate()
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	voice.stream = stream
	voice.volume_db = LEVELS[tower.kind]
	voice.unit_size = 20.0 if tower.kind == "standard" else 12.0
	voice.max_distance = DISTANCES[tower.kind]
	voice.max_polyphony = 3 if tower.kind in ["standard", "mg42", "sniper"] else 1
	add_child(voice)

func fire() -> void:
	if tower.kind in LOOPED:
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
	if tower.kind not in LOOPED: return
	hold = maxf(0.0, hold - delta)
	gain = move_toward(gain, 1.0 if hold > 0 else 0.0, delta / (0.035 if hold > 0 else 0.10))
	voice.volume_db = float(LEVELS[tower.kind]) + linear_to_db(maxf(0.001, gain))
	if hold <= 0 and gain <= 0: voice.stop()
