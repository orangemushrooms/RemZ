extends Control
## Quiet contour lines and layered forest silhouettes, drawn at the actual UI resolution.
var accent := Color("cba66a")
var forest := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	if size.x < 1 or size.y < 1: return
	for band in 48:
		var t := float(band) / 47.0
		var colour := Color("17251e").lerp(Color("0a1110"), t)
		draw_rect(Rect2(0, size.y * t, size.x, size.y / 47.0 + 1), colour)
	var centre := Vector2(size.x * 0.75, size.y * 0.34)
	for contour in 19:
		var points := PackedVector2Array()
		var radius := 25.0 + contour * 24.0
		for step in 100:
			var angle := float(step) / 99.0 * TAU
			var ripple := 1.0 + sin(angle * 3.0 + contour * 0.15) * 0.12 + cos(angle * 5.0) * 0.05
			points.append(centre + Vector2(cos(angle) * 1.4, sin(angle)) * radius * ripple)
		draw_polyline(points, Color(accent, 0.045 if contour % 3 else 0.085), 1, true)
	if forest:
		for layer in 3:
			for i in 13:
				var x := float(i) / 12.0 * size.x + sin(i * 5.4 + layer) * 17
				var height := (0.10 + absf(sin(i * 2.1 + layer)) * 0.18) * size.y
				var ground := size.y * (0.80 + layer * 0.1)
				var col := Color("26372d").lerp(Color("080e0c"), float(layer) * 0.47)
				col.a = 0.36
				draw_line(Vector2(x, ground), Vector2(x, ground - height), col, 2)
				for branch in 4:
					var y := ground - height + branch * height * 0.17
					var half_width := height * (0.12 + branch * 0.055)
					draw_colored_polygon(PackedVector2Array([Vector2(x,y),Vector2(x-half_width,y+height*0.39),Vector2(x+half_width,y+height*0.39)]), col)
	draw_line(Vector2(0, 1), Vector2(size.x, 1), Color(accent, 0.5), 1, true)
