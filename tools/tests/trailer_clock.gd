# Synthetic movie-clock fixture. No RemZ scene or assets are loaded.
extends SceneTree

var colour: ColorRect

func _initialize() -> void:
	colour = ColorRect.new()
	colour.size = Vector2(160, 90)
	root.add_child(colour)
	process_frame.connect(_paint_frame)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = 48000
	var samples := PackedByteArray()
	samples.resize(48000 * 4 * 2)
	for i in 48000 * 4:
		samples.encode_s16(i * 2, int(sin(TAU * 440.0 * i / 48000.0) * 3000.0))
	stream.data = samples
	var voice := AudioStreamPlayer.new()
	root.add_child(voice)
	voice.stream = stream
	voice.call_deferred("play")

func _paint_frame() -> void:
	var frame := Engine.get_process_frames()
	colour.color = Color.BLACK if frame < 30 else Color.RED if frame < 60 else Color.BLUE
	if frame == 90: quit()
