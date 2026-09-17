# Sound effects. Prefers the recorded clips in assets/audio/sfx (from the user's sound library),
# falls back to short procedural bursts for anything without a file (hurt, wood, boom, ...).
class_name Sfx

const DIR := "res://assets/audio/sfx/"

# logical name -> list of file stems; one is picked at random per play for variety
const FILES := {
	"pistol": ["pistol"],
	"revolver": ["revolver"],
	"smg": ["smg"],
	"ak47": ["ak47"],
	"shotgun": ["shotgun"],
	"reload": ["reload"],
	"empty": ["empty"],
	"click": ["click"],
	"confirm": ["confirm"],
	"menu": ["confirm_menu"],
	"hit": ["impact"],
	"growl": ["zombie_1", "zombie_2", "zombie_3", "zombie_4"],
	"barricade_break": ["barricade_break_1", "barricade_break_2", "barricade_break_3", "barricade_break_4"],
	"wave": ["wave_start"],
}

static var _cache: Dictionary = {}
static var _rng := RandomNumberGenerator.new()

static func _wav(samples: PackedFloat32Array, rate: int = 22050) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		var v := int(clampf(samples[i], -1.0, 1.0) * 32767.0)
		bytes.encode_s16(i * 2, v)
	wav.data = bytes
	return wav

static func _burst(dur: float, decay: float, lowpass: float, gain: float, tone: float = 0.0, slide: float = 0.0) -> AudioStreamWAV:
	var rate := 22050
	var n := int(dur * rate)
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var phase := 0.0
	for i in n:
		var t := float(i) / rate
		var env := exp(-t / decay)
		var noise := _rng.randf_range(-1.0, 1.0)
		lp += (noise - lp) * lowpass
		var v := lp * env * gain
		if tone > 0.0:
			var f := tone + slide * t
			phase += TAU * f / rate
			v += sin(phase) * env * gain * 0.6
		s[i] = v
	return _wav(s, rate)

static func _procedural(name: String) -> AudioStreamWAV:
	match name:
		"pistol": return _burst(0.25, 0.05, 0.6, 1.0, 160.0, -400.0)
		"shotgun": return _burst(0.45, 0.12, 0.35, 1.2, 80.0, -120.0)
		"reload": return _burst(0.12, 0.03, 0.9, 0.3, 900.0, 0.0)
		"empty": return _burst(0.05, 0.01, 0.9, 0.25, 1200.0, 0.0)
		"hit": return _burst(0.12, 0.04, 0.2, 0.5)
		"hurt": return _burst(0.4, 0.15, 0.15, 0.6, 120.0, -100.0)
		"growl": return _burst(0.8, 0.35, 0.05, 0.35, 70.0 + _rng.randf() * 50.0, -20.0)
		"build": return _burst(0.2, 0.06, 0.4, 0.5, 220.0, 0.0)
		"wave": return _burst(1.4, 0.6, 0.02, 0.4, 110.0, 30.0)
		"wood": return _burst(0.3, 0.1, 0.3, 0.8)
		"boom": return _burst(1.6, 0.45, 0.05, 1.4, 45.0, -30.0)
		"pickup": return _burst(0.2, 0.08, 0.9, 0.3, 660.0, 800.0)
	return _burst(0.1, 0.03, 0.5, 0.3)

static func _file(stem: String) -> AudioStream:
	var key := "file:" + stem
	if _cache.has(key):
		return _cache[key]
	var path := DIR + stem + ".mp3"
	var st: AudioStream = null
	if ResourceLoader.exists(path):
		st = load(path)
	_cache[key] = st
	return st

static func get_stream(name: String) -> AudioStream:
	if FILES.has(name):
		var variants: Array = FILES[name]
		var st := _file(variants[_rng.randi() % variants.size()])
		if st:
			return st
	if _cache.has(name):
		return _cache[name]
	var p := _procedural(name)
	_cache[name] = p
	return p

# slight random pitch so repeated clips (shots, growls) do not sound machine-like
static func _pitch(spread: float) -> float:
	return 1.0 + _rng.randf_range(-spread, spread)

static func play(node: Node, name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = get_stream(name)
	p.volume_db = volume_db
	p.pitch_scale = pitch * _pitch(0.04)
	node.add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

static func play_at(node: Node, name: String, pos: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var p := AudioStreamPlayer3D.new()
	p.stream = get_stream(name)
	p.volume_db = volume_db
	p.pitch_scale = pitch * _pitch(0.08)
	p.max_distance = 60.0
	node.add_child(p)
	p.global_position = pos
	p.play()
	p.finished.connect(p.queue_free)
