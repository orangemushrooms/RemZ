extends Control

var magnification := 4.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func _draw() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.44
	var outer := size.length()
	var ink := Color(0.015, 0.018, 0.014)
	# Mask the periphery while leaving the magnified world visible in the lens.
	for i in 128:
		var a := Vector2.from_angle(TAU * i / 128.0)
		var b := Vector2.from_angle(TAU * (i + 1) / 128.0)
		draw_colored_polygon(PackedVector2Array([centre + a * radius, centre + a * outer, centre + b * outer, centre + b * radius]), Color.BLACK)
	draw_arc(centre, radius, 0, TAU, 128, Color(0.13, 0.14, 0.12), 8.0, true)
	for axis in [Vector2.RIGHT, Vector2.DOWN]:
		for direction in [-1.0, 1.0]:
			_reticle_line(centre + axis * 5.0 * direction, centre + axis * radius * 0.97 * direction, ink)
			for tick in range(1, 5):
				var point: Vector2 = centre + axis * radius * tick * 0.12 * direction
				var side: Vector2 = axis.orthogonal() * (5.0 if tick % 2 else 8.0)
				_reticle_line(point - side, point + side, ink)
	draw_circle(centre, 1.5, Color(0.65, 0.1, 0.05))
	var label := centre + Vector2(-18, radius * 0.77)
	draw_string_outline(ThemeDB.fallback_font, label, "%.0f×" % magnification, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 3, ink)
	draw_string(ThemeDB.fallback_font, label, "%.0f×" % magnification, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.82, 0.75))

func _reticle_line(from: Vector2, to: Vector2, ink: Color) -> void:
	draw_line(from, to, Color(0.8, 0.82, 0.75, 0.45), 3.0, true)
	draw_line(from, to, ink, 1.5, true)
