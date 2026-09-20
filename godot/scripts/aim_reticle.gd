extends Control

var aim_position := Vector2.ZERO
var cone_radius := 8.0
var aiming := 0.0
var stress := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func update_aim(point: Vector2, radius: float, ads: float, bloom: float) -> void:
	aim_position = point
	cone_radius = maxf(3.5, radius)
	aiming = ads
	stress = bloom
	queue_redraw()

func _draw() -> void:
	var radius := cone_radius
	var tint := Color(0.76, 0.92, 0.9, lerpf(0.52, 0.28, aiming))
	var shadow := Color(0.015, 0.025, 0.025, 0.25)
	# Four straight ticks frame the dispersion cone without covering the target.
	for i in 4:
		var angle := float(i) * PI * 0.5
		var axis := Vector2.from_angle(angle)
		var start := aim_position + axis * radius
		var end := aim_position + axis * (radius + lerpf(7.0, 5.0, aiming) + stress * 2.0)
		draw_line(start, end, shadow, 3.0, true)
		draw_line(start, end, tint, 1.15, true)
