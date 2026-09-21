class_name TitanPresence
extends Node
## Scene-owned presentation of authoritative boss events. No gameplay damage here.
## Reliable events are independent of snapshots: joining never replays an old slam.

const DIR := "res://assets/audio/sfx/titan/"
const SPAWN_CLIPS := ["Titan_spawn_1.mp3", "titan_spawn_2.mp3", "titan_spawn_3.mp3", "titan_spawn_4.mp3"]
const CUES := {
	"arrival": {"clips": SPAWN_CLIPS, "mapwide": true, "range": 0.0, "unit": 48.0, "db": -6.0, "voice": true, "shake": 0.14, "radius": 55.0, "duration": 2.1, "duck": 0.55},
	"roar": {"clips": ["roar_1", "roar_2", "roar_3"], "range": 230.0, "unit": 42.0, "db": -4.0, "voice": true, "shake": 0.10, "radius": 50.0, "duration": 1.8, "duck": 0.45},
	"rage": {"clips": ["roar_2"], "range": 250.0, "unit": 48.0, "db": -1.0, "voice": true, "shake": 0.25, "radius": 65.0, "duration": 2.5, "duck": 0.65},
	"windup": {"clips": ["windup"], "range": 135.0, "unit": 30.0, "db": -3.0, "voice": true, "shake": 0.07, "radius": 35.0, "duration": 1.2, "duck": 0.30},
	"death": {"clips": ["death"], "range": 220.0, "unit": 45.0, "db": -2.0, "voice": true, "shake": 0.12, "radius": 60.0, "duration": 1.8, "duck": 0.55},
	"step": {"clips": ["step_1", "step_2"], "range": 95.0, "unit": 20.0, "db": -4.0, "voice": false, "shake": 0.34, "radius": 75.0, "duration": 0.85, "duck": 0.0},
	"slam": {"clips": ["slam"], "range": 145.0, "unit": 35.0, "db": -2.0, "voice": false, "shake": 0.80, "radius": 105.0, "duration": 1.55, "duck": 0.20},
	"collapse": {"clips": ["slam"], "range": 160.0, "unit": 40.0, "db": -3.0, "voice": false, "shake": 0.65, "radius": 110.0, "duration": 2.0, "duck": 0.20},
}
var received: Dictionary = {} # useful for diagnostics, counts events rather than live voices
var _serials: Dictionary = {}
var _pending: Array[Dictionary] = []
var _voices: Array[AudioStreamPlayer3D] = []
var _streams: Dictionary = {}
var _player: Player
var _scene: Node

static func for_scene(scene: Node) -> TitanPresence:
	var existing := scene.get_node_or_null("TitanPresence") as TitanPresence
	if existing: return existing
	var result := TitanPresence.new()
	result.name = "TitanPresence"
	scene.add_child(result)
	return result

func _ready() -> void:
	_scene = get_parent()
	_player = _scene.player
	# Compress only the titan mix. Master volume still controls everything.
	if AudioServer.get_bus_index("Titans") < 0:
		var index := AudioServer.bus_count
		AudioServer.add_bus(index)
		AudioServer.set_bus_name(index, "Titans")
		AudioServer.set_bus_send(index, "Master")
		var compressor := AudioEffectCompressor.new()
		compressor.threshold = -10.0
		compressor.ratio = 4.0
		compressor.attack_us = 1500.0
		compressor.release_ms = 250.0
		AudioServer.add_bus_effect(index, compressor)
		var limiter := AudioEffectLimiter.new()
		limiter.ceiling_db = -2.0
		limiter.threshold_db = -4.0
		AudioServer.add_bus_effect(index, limiter)

func receive(kind: String, origin: Vector3, body_height: float, emitter: int, serial: int) -> void:
	if not CUES.has(kind) or not origin.is_finite() or not is_finite(body_height): return
	if serial <= int(_serials.get(emitter, 0)): return
	_serials[emitter] = serial
	if _serials.size() > 128: _serials.erase(_serials.keys()[0])
	received[kind] = int(received.get(kind, 0)) + 1
	var spec: Dictionary = CUES[kind]
	var distance := _player.global_position.distance_to(origin)
	var mapwide: bool = spec.get("mapwide", false)
	if not mapwide and distance >= float(spec.range): return
	var source := origin + Vector3.UP * (clampf(body_height, 1, 40) * 0.75 if spec.voice else 0.15)
	# Sound and soil vibration arrive slightly later in the distance.
	_pending.append({"kind": kind, "origin": origin, "source": source, "emitter": emitter,
		# The host's random appearance seed selects the same recording on every peer.
		"variant": posmod(emitter + serial, spec.clips.size()), "age": 0.0,
		"sound_at": 0.0 if mapwide else _player.camera.global_position.distance_to(source) / 343.0,
		"shake_at": distance / 180.0 + (0.35 if spec.voice else 0.03),
		"sounded": false, "shaken": false})

func _process(delta: float) -> void:
	for i in range(_pending.size() - 1, -1, -1):
		var event: Dictionary = _pending[i]
		event.age += delta
		var spec: Dictionary = CUES[event.kind]
		if not event.sounded and event.age >= event.sound_at:
			event.sounded = true
			_play_sound(event, spec)
		if not event.shaken and event.age >= event.shake_at:
			event.shaken = true
			var distance := _player.global_position.distance_to(event.origin)
			var strength := pow(maxf(0, 1.0 - distance / float(spec.radius)), 1.6) * float(spec.shake)
			_player.add_tremor(strength, float(spec.duration))
		if event.sounded and event.shaken: _pending.remove_at(i)

func _play_sound(event: Dictionary, spec: Dictionary) -> void:
	var mapwide: bool = spec.get("mapwide", false)
	var path := Sfx.DIR + str(spec.clips[event.variant]) if event.kind == "arrival" else DIR + str(spec.clips[event.variant]) + ".wav"
	if not _streams.has(path): _streams[path] = load(path)
	var audio := AudioStreamPlayer3D.new()
	audio.stream = _streams[path]
	audio.bus = "Titans"
	audio.volume_db = spec.db
	audio.max_db = -1.0
	audio.unit_size = spec.unit
	audio.max_distance = spec.range
	if mapwide: audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	audio.attenuation_filter_cutoff_hz = 3500.0
	audio.attenuation_filter_db = 0.0 if mapwide else -18.0
	audio.pitch_scale = 1.0 if mapwide else 0.97 + float(posmod(int(event.emitter), 7)) * 0.01
	audio.set_meta("emitter", event.emitter)
	audio.set_meta("voice", spec.voice)
	# A boss has one throat. Crossfade an interrupted roar into its attack/death cry.
	var live: Array[AudioStreamPlayer3D] = []
	for old in _voices:
		if not is_instance_valid(old) or old.is_queued_for_deletion(): continue
		if bool(spec.voice) and bool(old.get_meta("voice")) and old.get_meta("emitter") == event.emitter:
			if old.playing and int(old.get_meta("priority")) > _priority(event.kind):
				audio.free()
				return
	for old in _voices:
		if not is_instance_valid(old) or old.is_queued_for_deletion(): continue
		if bool(old.get_meta("voice")) == bool(spec.voice) and old.get_meta("emitter") == event.emitter:
			_fade_voice(old)
		else: live.append(old)
	while live.size() >= 8: _fade_voice(live.pop_front())
	live.append(audio)
	_voices = live
	audio.set_meta("priority", _priority(event.kind))
	add_child(audio)
	audio.global_position = event.source
	audio.finished.connect(audio.queue_free)
	audio.play()
	if float(spec.duck) > 0 and "music" in _scene and _scene.music:
		var distance := _player.global_position.distance_to(event.origin)
		var weight := 1.0 if mapwide else clampf(1.0 - distance / float(spec.range), 0, 1)
		_scene.music.titan_duck(float(spec.duck) * weight, minf(audio.stream.get_length(), 4.5))

func _priority(kind: String) -> int:
	return 4 if kind == "death" else 3 if kind in ["arrival", "rage"] else 2 if kind == "windup" else 1

func _fade_voice(audio: AudioStreamPlayer3D) -> void:
	var fade := create_tween()
	fade.tween_property(audio, "volume_db", -60.0, 0.18)
	fade.tween_callback(audio.queue_free)
