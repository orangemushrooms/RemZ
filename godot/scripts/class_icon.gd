extends Control
## Vector emblems remain crisp at every menu/HUD size; no font glyph or raster asset dependency.
const Classes = preload("res://scripts/character_classes.gd")
var class_id := "gunslinger":
	set(value): class_id = value; queue_redraw()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var colour: Color = Classes.CLASSES.get(class_id, Classes.CLASSES.gunslinger).color
	var scale_factor := minf(size.x, size.y) / 100.0
	draw_set_transform(size * 0.5, 0.0, Vector2.ONE * scale_factor)
	draw_arc(Vector2.ZERO, 44, 0, TAU, 64, Color(colour, 0.25), 1.5, true)
	match class_id:
		"gunslinger":
			for flip in [-1.0, 1.0]:
				draw_set_transform(size * 0.5, flip * -0.62, Vector2(flip, 1) * scale_factor)
				var outline := PackedVector2Array([Vector2(-20,-15),Vector2(33,-15),Vector2(33,-6),Vector2(-1,-6),Vector2(3,20),Vector2(-11,23),Vector2(-17,-3),Vector2(-20,-3),Vector2(-20,-15)])
				draw_colored_polygon(outline, colour)
				draw_polyline(outline, Color("0d1d18"), 2, true)
				draw_line(Vector2(2,-10), Vector2(28,-10), Color("0d1d18"), 1.2, true)
				draw_arc(Vector2(0,0), 6, -0.7, 2.0, 12, colour, 2, true)
		"assault":
			draw_colored_polygon(PackedVector2Array([Vector2(-31,-5),Vector2(-18,-5),Vector2(-12,-13),Vector2(15,-13),Vector2(15,-7),Vector2(33,-7),Vector2(33,-2),Vector2(10,-2),Vector2(5,16),Vector2(-4,14),Vector2(-2,-2),Vector2(-12,-2),Vector2(-15,9),Vector2(-22,9),Vector2(-22,1),Vector2(-31,8)]), colour)
			for i in 3: draw_line(Vector2(-11 + i*9,24), Vector2(-11 + i*9,33), colour, 4, true)
		"breacher":
			draw_polyline(PackedVector2Array([Vector2(-7,-29),Vector2(-29,-20),Vector2(-25,7),Vector2(-8,29),Vector2(-5,11)]), colour, 5, true)
			draw_polyline(PackedVector2Array([Vector2(9,-29),Vector2(29,-20),Vector2(25,7),Vector2(8,29),Vector2(12,5)]), colour, 5, true)
			draw_line(Vector2(7,-24), Vector2(-6,-1), colour, 5, true)
			draw_line(Vector2(-6,-1), Vector2(7,4), colour, 5, true)
			draw_line(Vector2(7,4), Vector2(-5,27), colour, 5, true)
		"marksman":
			draw_arc(Vector2.ZERO, 25, 0, TAU, 64, colour, 3, true)
			for i in 4:
				var axis := Vector2.from_angle(i * PI / 2)
				draw_line(axis * 13, axis * 36, colour, 3, true)
			draw_circle(Vector2.ZERO, 3, colour)
		"assassin":
			draw_polyline(PackedVector2Array([Vector2(-29,23),Vector2(-23,-13),Vector2(0,-33),Vector2(23,-13),Vector2(29,23)]), colour, 4, true)
			draw_colored_polygon(PackedVector2Array([Vector2(-6,-12),Vector2(6,-12),Vector2(4,16),Vector2(0,28),Vector2(-4,16)]), colour)
			draw_line(Vector2(-15,13), Vector2(15,13), colour, 4, true)
			draw_line(Vector2(-18,-7), Vector2(-10,-3), colour, 3, true)
			draw_line(Vector2(18,-7), Vector2(10,-3), colour, 3, true)
