extends Control
var game: Node
func point(p: Vector2) -> Vector2:
	return Vector2(8,24)+(p-Map.extent().position)/Map.extent().size*(size-Vector2(16,32))
func _draw() -> void:
	draw_style_box(_style(),Rect2(Vector2.ZERO,size))
	draw_string(ThemeDB.fallback_font,Vector2(10,16),"N ↑    THE PLANES",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color(0.8,0.86,0.76))
	for field: Dictionary in Map._d.fields:
		var polygon := PackedVector2Array()
		for p in field.poly: polygon.append(point(Vector2(p[0],p[1])))
		draw_colored_polygon(polygon,Color(0.36,0.42,0.2) if field.kind=="corn" else Color(0.6,0.5,0.28))
	for road: Dictionary in Map.ROADS:
		for i in road.pts.size()-1:
			if not Map.extent().has_point(road.pts[i]) or not Map.extent().has_point(road.pts[i+1]): continue
			draw_line(point(road.pts[i]),point(road.pts[i+1]),Color(0.8,0.8,0.68),1.2,true)
	var at := point(Vector2(game.player.position.x,game.player.position.z))
	var dir := Vector2(-sin(game.player.rotation.y),-cos(game.player.rotation.y))
	draw_circle(at,3,Color(0.9,1,0.82))
	draw_line(at,at+dir*12,Color(0.9,1,0.82),2,true)
func _style() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.04,0.07,0.04,0.83)
	box.set_corner_radius_all(3)
	return box
