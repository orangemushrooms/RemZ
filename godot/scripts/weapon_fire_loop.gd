# One sustained recording per shooter. Shots extend its lifetime, never restart
# the eight-second recording or stack another copy on top of it.
extends Node

const HOLD := 0.21 # Covers the minigun's slow spin-up shots and snapshot jitter.
const RELEASE := 0.04
var voice: Variant
var hold := 0.0
var gain := 0.0
var level := -9.0

func configure(source: AudioStreamWAV, spatial: bool) -> void:
	var stream := source.duplicate() as AudioStreamWAV
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = roundi(stream.get_length() * stream.mix_rate)
	voice = AudioStreamPlayer3D.new() if spatial else AudioStreamPlayer.new()
	voice.stream = stream
	add_child(voice)
	set_process(false)

func shot(volume_db: float, pitch: float, point: Vector3, unit_size: float, max_distance: float) -> void:
	hold = HOLD
	level = volume_db
	gain = 1.0
	voice.volume_db = level
	voice.pitch_scale = pitch
	if voice is AudioStreamPlayer3D:
		voice.unit_size = unit_size
		voice.max_distance = max_distance
		voice.global_position = point
	if not voice.playing: voice.play()
	set_process(true)

func release() -> void:
	hold = 0.0

func stop() -> void:
	hold = 0.0
	gain = 0.0
	if voice: voice.stop()
	set_process(false)

func _process(delta: float) -> void:
	hold = maxf(0.0, hold - delta)
	if hold > 0.0: return
	gain = maxf(0.0, gain - delta / RELEASE)
	if gain <= 0.0:
		stop()
	else:
		voice.volume_db = level + linear_to_db(gain)
