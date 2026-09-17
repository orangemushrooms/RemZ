# Procedural ambience: wind over the meadow, rustling forest, birds, fire crackle, stream.
# Everything is synthesised at startup (looping WAV clips), no audio files needed.
class_name Ambience
extends Node

var player: Player
var wind: AudioStreamPlayer
var rustle: AudioStreamPlayer
var fire: AudioStreamPlayer3D
var stream: AudioStreamPlayer3D
var _bird_t := 2.0
var _rng := RandomNumberGenerator.new()
var _wind_target := -12.0
var _rustle_target := -14.0

static func _loop(samples: PackedFloat32Array, rate: int) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = samples.size()
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	wav.data = bytes
	return wav

# filtered noise with slow amplitude modulation; lp = low-pass coefficient (0..1), hp removes rumble
static func _noise_bed(seconds: float, lp: float, hp: float, mod_hz: float, mod_depth: float, gain: float, seed_v: int) -> AudioStreamWAV:
	var rate := 22050
	var n := int(seconds * rate)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var l := 0.0
	var h := 0.0
	var prev := 0.0
	for i in n:
		var t := float(i) / rate
		var w := rng.randf_range(-1.0, 1.0)
		l += (w - l) * lp
		var v := l - h
		h += (l - h) * hp
		# fade the loop ends into each other
		var env := 1.0 + mod_depth * (0.6 * sin(TAU * mod_hz * t) + 0.4 * sin(TAU * mod_hz * 2.7 * t + 1.3))
		var edge := minf(1.0, minf(t, seconds - t) / 0.5)
		s[i] = v * env * gain * edge
	return _loop(s, rate)

static func _crackle(seconds: float, seed_v: int) -> AudioStreamWAV:
	var rate := 22050
	var n := int(seconds * rate)
	var s := PackedFloat32Array()
	s.resize(n)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var l := 0.0
	var pop := 0.0
	for i in n:
		var w := rng.randf_range(-1.0, 1.0)
		l += (w - l) * 0.08
		if rng.randf() < 0.0006:
			pop = rng.randf_range(0.4, 1.0)
		pop *= 0.995
		s[i] = l * 0.35 + w * pop * 0.5 * (1.0 if rng.randf() < 0.5 else 0.3)
	return _loop(s, rate)

func setup(p: Player, fire_pos: Vector3, stream_pos: Vector3) -> void:
	player = p
	_rng.seed = 99
	wind = AudioStreamPlayer.new()
	wind.stream = _noise_bed(12.0, 0.012, 0.0008, 0.07, 0.8, 0.9, 1)
	wind.volume_db = -14.0
	add_child(wind)
	wind.play()
	rustle = AudioStreamPlayer.new()
	rustle.stream = _noise_bed(9.0, 0.35, 0.02, 0.11, 0.9, 0.35, 2)
	rustle.volume_db = -16.0
	add_child(rustle)
	rustle.play()
	fire = AudioStreamPlayer3D.new()
	fire.stream = _crackle(8.0, 3)
	fire.unit_size = 4.0
	fire.max_distance = 30.0
	fire.volume_db = -4.0
	add_child(fire)
	fire.global_position = fire_pos + Vector3(0, 0.5, 0)
	fire.play()
	stream = AudioStreamPlayer3D.new()
	stream.stream = _noise_bed(8.0, 0.25, 0.01, 0.5, 0.3, 0.5, 4)
	stream.unit_size = 5.0
	stream.max_distance = 40.0
	stream.volume_db = -6.0
	add_child(stream)
	stream.global_position = stream_pos + Vector3(0, 0.3, 0)
	stream.play()

func _bird_chirp(pos: Vector3) -> void:
	var rate := 22050
	var notes := _rng.randi_range(2, 5)
	var total := 0.0
	var parts: Array = []
	for i in notes:
		var dur := _rng.randf_range(0.06, 0.16)
		parts.append([_rng.randf_range(2200.0, 4200.0), _rng.randf_range(-800.0, 1400.0), dur])
		total += dur + 0.04
	var n := int(total * rate)
	var s := PackedFloat32Array()
	s.resize(n)
	var idx := 0
	var phase := 0.0
	for prt in parts:
		var f0: float = prt[0]
		var slide: float = prt[1]
		var dur: float = prt[2]
		var cnt := int(dur * rate)
		for k in cnt:
			var t := float(k) / cnt
			var f := f0 + slide * t
			phase += TAU * f / rate
			var env := sin(PI * t)
			if idx < n:
				s[idx] = sin(phase) * env * 0.5
			idx += 1
		idx += int(0.04 * rate)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	var bytes := PackedByteArray()
	bytes.resize(n * 2)
	for i in n:
		bytes.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	wav.data = bytes
	var pl := AudioStreamPlayer3D.new()
	pl.stream = wav
	pl.unit_size = 6.0
	pl.max_distance = 70.0
	pl.volume_db = -8.0
	add_child(pl)
	pl.global_position = pos
	pl.play()
	pl.finished.connect(pl.queue_free)

func _process(delta: float) -> void:
	if not player:
		return
	var p := player.global_position
	var in_forest := Map.leaf_weight(p.x, p.z) > 0.5
	# wind is strongest on the open meadow, rustle strongest under trees
	_wind_target = -8.0 if Map.meadow_weight(p.x, p.z) > 0.5 else (-18.0 if in_forest else -13.0)
	_rustle_target = -9.0 if in_forest else -16.0
	wind.volume_db = lerpf(wind.volume_db, _wind_target, delta * 0.8)
	rustle.volume_db = lerpf(rustle.volume_db, _rustle_target, delta * 0.8)
	_bird_t -= delta
	if _bird_t <= 0.0:
		_bird_t = _rng.randf_range(1.5, 5.0)
		# a bird somewhere in the trees around the player
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(15.0, 45.0)
		var bp := Vector3(p.x + cos(a) * r, 6.0 + _rng.randf() * 6.0, p.z + sin(a) * r)
		if Map.leaf_weight(bp.x, bp.z) > 0.3:
			_bird_chirp(bp)
