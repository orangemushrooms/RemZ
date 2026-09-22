# Procedural ambience: wind over the meadow, rustling forest, birds, fire crackle, stream.
# Synthesised ambience beds plus recorded wildlife and evening/night crickets.
class_name Ambience
extends Node

var player: Player
var wind: AudioStreamPlayer
var rustle: AudioStreamPlayer
var crickets: AudioStreamPlayer
var _cricket_level := 0.0
const CRICKETS = preload("res://assets/audio/sfx/night_crickets_sfx.mp3")
const CRICKETS_VOLUME_DB := -22.0
var fire: AudioStreamPlayer3D
var stream: AudioStreamPlayer3D
var _bird_t := 2.0
var _call_t := 6.0                 # recorded owl / raven calls (assets/audio/sfx/owl*, raven*)
var day_night: DayNightCycle       # set by main; owls at night, ravens by day
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
	var blend := mini(int(0.12 * rate), n / 2)
	var s := PackedFloat32Array()
	s.resize(n + blend)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var flame := 0.0
	var rumble := 0.0
	var detail := 0.0
	var ember := 0.0
	var ember_low := 0.0
	var texture := 0.0
	for i in s.size():
		var w := rng.randf_range(-1.0, 1.0)
		# Continuous fine crackle: no randomly triggered pops or burst envelopes.
		# Remove low thumps and soften the top end before gently varying the texture.
		flame += (w - flame) * 0.07
		rumble += (flame - rumble) * 0.025
		detail += (w - detail) * 0.40
		ember += (detail - ember) * 0.24
		ember_low += (ember - ember_low) * 0.10
		texture += (rng.randf_range(-1.0, 1.0) - texture) * 0.006
		var intensity := 0.55 + clampf(texture * 4.0, -0.25, 0.25)
		var sample := (flame - rumble) * 0.18 + (ember - ember_low) * intensity * 0.24
		# Smoothly bound peaks without a hard-clipping edge.
		s[i] = sample / (1.0 + absf(sample) / 0.12)
	# Blend an extra tail into the beginning so the loop itself cannot click.
	for i in blend:
		var t := smoothstep(0.0, 1.0, float(i) / maxf(blend - 1, 1))
		s[i] = lerpf(s[n + i], s[i], t)
	s.resize(n)
	return _loop(s, rate)

func setup(p: Player, fire_pos: Vector3, stream_pos: Vector3) -> void:
	player = p
	_rng.seed = 99
	wind = AudioStreamPlayer.new()
	wind.stream = _noise_bed(12.0, 0.012, 0.0008, 0.07, 0.8, 0.9, 1)
	wind.volume_db = -22.0
	add_child(wind)
	wind.play()
	rustle = AudioStreamPlayer.new()
	# Reduce leaf/tree rustling by one third at every distance/biome blend.
	rustle.stream = _noise_bed(9.0, 0.35, 0.02, 0.11, 0.9, 0.35 * (2.0 / 3.0), 2)
	rustle.volume_db = -24.0
	add_child(rustle)
	rustle.play()
	crickets = AudioStreamPlayer.new()
	crickets.name = "NightCrickets"
	var cricket_loop := CRICKETS.duplicate() as AudioStreamMP3
	cricket_loop.loop = true
	crickets.stream = cricket_loop
	crickets.volume_linear = 0.0
	add_child(crickets)
	fire = AudioStreamPlayer3D.new()
	fire.stream = _crackle(8.0, 3)
	fire.unit_size = 3.0
	fire.max_distance = 30.0
	fire.volume_db = -16.0
	fire.max_db = -16.0 # No near-field amplification, even directly over the fire bowl.
	add_child(fire)
	fire.global_position = fire_pos + Vector3(0, 0.5, 0)
	fire.play()
	if not Map.SMALL_CAMPSITE.is_empty():
		var small_fire := AudioStreamPlayer3D.new()
		small_fire.name = "SmallCampfireSound"
		small_fire.stream = fire.stream
		small_fire.unit_size = 1.5
		small_fire.max_distance = 18.0
		small_fire.volume_db = -23.0
		small_fire.max_db = -23.0
		add_child(small_fire)
		var at: Vector2 = Map.SMALL_CAMPSITE.pos
		small_fire.global_position = Map.ground_pos(at.x, at.y) + Vector3.UP * 0.3
		small_fire.play()
	stream = AudioStreamPlayer3D.new()
	stream.stream = _noise_bed(8.0, 0.25, 0.01, 0.5, 0.3, 0.5, 4)
	stream.unit_size = 5.0
	stream.max_distance = 40.0
	stream.volume_db = -60.0   # there is no stream at the real site
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
	pl.volume_db = -2.0
	add_child(pl)
	pl.global_position = pos
	pl.play()
	pl.finished.connect(pl.queue_free)

func _process(delta: float) -> void:
	if not player:
		return
	_update_crickets(delta)
	var p := player.global_position
	var in_forest := Map.leaf_weight(p.x, p.z) > 0.5
	# wind is strongest on the open meadow, rustle strongest under trees
	# subtle: a soft leaf rustle under the trees, light wind on the meadow, birds clearly audible above it
	_wind_target = -17.0 if Map.meadow_weight(p.x, p.z) > 0.5 else (-26.0 if in_forest else -21.0)
	_rustle_target = -20.0 if in_forest else -27.0
	wind.volume_db = lerpf(wind.volume_db, _wind_target, delta * 0.8)
	rustle.volume_db = lerpf(rustle.volume_db, _rustle_target, delta * 0.8)
	_bird_t -= delta
	if _bird_t <= 0.0:
		_bird_t = _rng.randf_range(0.8, 3.0)
		# a bird somewhere in the trees around the player
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(15.0, 45.0)
		var bp := Vector3(p.x + cos(a) * r, 6.0 + _rng.randf() * 6.0, p.z + sin(a) * r)
		if Map.leaf_weight(bp.x, bp.z) > 0.3 and _daylight() > 0.15:
			_bird_chirp(bp)
	_call_t -= delta
	if _call_t <= 0.0:
		_call_t = _rng.randf_range(9.0, 24.0)
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(20.0, 50.0)
		var cp := Vector3(p.x + cos(a) * r, 7.0 + _rng.randf() * 6.0, p.z + sin(a) * r)
		if Map.leaf_weight(cp.x, cp.z) > 0.3:
			var night := _daylight() < 0.35
			_bird_call("owl" if night and _rng.randf() < 0.85 else "raven", cp)

static func cricket_level_at(hour: float) -> float:
	var h := fposmod(hour, 24.0)
	if h < 12.0:
		return 1.0 - smoothstep(5.0, 7.0, h)
	return smoothstep(17.0, 19.0, h)

func _update_crickets(delta: float) -> void:
	if not crickets: return
	var target := cricket_level_at(day_night.clock_seconds / 3600.0) if day_night else 0.0
	# Smooth volume in linear amplitude, including clock jumps in debug/coop.
	_cricket_level = lerpf(_cricket_level, target, 1.0 - exp(-maxf(delta, 0.0) / 2.0))
	crickets.volume_linear = db_to_linear(CRICKETS_VOLUME_DB) * _cricket_level
	if target > 0.0 and not crickets.playing:
		crickets.play()
	elif target == 0.0 and _cricket_level < 0.001 and crickets.playing:
		crickets.stop()

func _daylight() -> float:
	if day_night == null: return 0.0
	return DayNightCycle.daylight_at(day_night.clock_seconds / 3600.0)

# a recorded owl or raven call from a spot in the trees around the player
func _bird_call(name: String, pos: Vector3) -> void:
	var stream_res := Sfx.get_stream(name)
	if stream_res == null: return
	var pl := AudioStreamPlayer3D.new()
	pl.stream = stream_res
	pl.unit_size = 8.0
	pl.max_distance = 90.0
	pl.volume_db = -5.0
	pl.pitch_scale = 1.0 + _rng.randf_range(-0.04, 0.04)
	add_child(pl)
	pl.global_position = pos
	pl.play()
	pl.finished.connect(pl.queue_free)
