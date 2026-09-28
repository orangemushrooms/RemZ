extends Control
## A local, north-up map centred on the Assassin, using the same terrain as the minimap.
const SPAN := 96.0
var controller: Node
var origin := Vector2.ZERO
var hover := Vector2.ZERO
var valid := false

func _ready() -> void:
	clip_contents = true
	mouse_default_cursor_shape = Control.CURSOR_CROSS
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func world_point(pixel: Vector2) -> Vector2:
	return origin + (pixel / size - Vector2.ONE * 0.5) * SPAN

func pixel(point: Vector2) -> Vector2:
	return ((point - origin) / SPAN + Vector2.ONE * 0.5) * size

func _draw() -> void:
	if not controller or not controller.game: return
	var source: Minimap = controller.game.hud.minimap
	draw_rect(Rect2(Vector2.ZERO, size), Color("15211c"))
	if source and source._terrain:
		var region := Rect2((origin - Vector2.ONE * SPAN * 0.5 - source._map_bounds.position) / source._map_bounds.size * source._terrain.get_size(), Vector2.ONE * SPAN / source._map_bounds.size * source._terrain.get_size())
		draw_texture_rect_region(source._terrain, Rect2(Vector2.ZERO, size), region)
	for road: Dictionary in Map.ROADS:
		var points := PackedVector2Array()
		for point: Vector2 in road.pts: points.append(pixel(point))
		if points.size() >= 2: draw_polyline(points, Color("a69d7d"), maxf(2, float(road.width) * size.x / SPAN), true)
	for building: Dictionary in Map.BUILDINGS.values():
		var corners := PackedVector2Array()
		var half: Vector2 = building.size * 0.5
		for corner in [Vector2(-half.x,-half.y), Vector2(half.x,-half.y), half, Vector2(-half.x,half.y)]:
			corners.append(pixel(building.pos + corner.rotated(-float(building.yaw))))
		draw_colored_polygon(corners, Color("bb825a"))
	var actor: Player = controller.game.player
	var center := pixel(Vector2(actor.global_position.x, actor.global_position.z))
	draw_circle(center, AssassinTeleport.MAP_RANGE * size.x / SPAN, Color(0.72,0.61,0.9,0.09))
	draw_circle(center, AssassinTeleport.MAP_RANGE * size.x / SPAN, Color("b6a0d8"), false, 2, true)
	var arrow := PackedVector2Array()
	for point in [Vector2(0,-9), Vector2(6,6), Vector2(0,3), Vector2(-6,6)]: arrow.append(center + point.rotated(-actor.rotation.y))
	draw_colored_polygon(arrow, Color("f0e7d2"))
	var target := pixel(hover)
	var colour := Color("77deb4") if valid else Color("ef796e")
	draw_line(center, target, Color(colour, 0.5), 1.5, true)
	draw_circle(target, 8, colour, false, 2, true)
	draw_line(target - Vector2(12,0), target + Vector2(12,0), colour, 1, true)
	draw_line(target - Vector2(0,12), target + Vector2(0,12), colour, 1, true)
	draw_string(ThemeDB.fallback_font, Vector2(12,22), Lang.text("N / 40 m range"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
