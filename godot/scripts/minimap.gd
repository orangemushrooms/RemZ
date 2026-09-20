class_name Minimap
extends Control

const TITLE := "Remetschwil Sennhof"
const MAP_RECT := Rect2(12, 38, 276, 276)
const PANEL_SIZE := Vector2(300, 340)
var expanded := false
var player: Player
var world: Node
var _cartography: Control
var _terrain: ImageTexture
var _map_bounds := Rect2()
var _scale := 1.0
var _elapsed := 0.0
var _font: Font
var reveal_secret := false  # Cheat menu: show the secret vendor before discovery.
var reveal_wanderer := false  # Track the roaming merchant once he enters the forest.

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed and is_visible_in_tree():
		expanded = not expanded
		_update_layout()
		get_viewport().set_input_as_handled()
		return

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	_update_layout()
	get_parent().resized.connect(_update_layout)
	_font = ThemeDB.fallback_font
	Map._ensure()
	# Fit the complete playable area without distorting distances or angles.
	var span := maxf(Map.BOUNDS.size.x, Map.BOUNDS.size.y)
	_map_bounds = Rect2(Map.BOUNDS.get_center() - Vector2.ONE * span * 0.5, Vector2.ONE * span)
	_scale = MAP_RECT.size.x / span
	var image := Image.create(256, 256, false, Image.FORMAT_RGB8)
	for y in 256:
		for x in 256:
			var pos := _map_bounds.position + Vector2(x + 0.5, y + 0.5) * span / 256.0
			var cover := Map.cover(pos.x, pos.y)
			var color := Color(0.31, 0.38, 0.25).lerp(Color(0.115, 0.20, 0.15), cover.r)
			color = color.lerp(Color(0.56, 0.54, 0.43), cover.b)
			image.set_pixel(x, y, color)
	_terrain = ImageTexture.create_from_image(image)
	draw.connect(_draw_frame)
	var clipping := Control.new()
	clipping.position = MAP_RECT.position
	clipping.size = MAP_RECT.size
	clipping.clip_contents = true
	clipping.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clipping)
	_cartography = Control.new()
	_cartography.position = -MAP_RECT.position
	_cartography.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cartography.draw.connect(_draw_cartography)
	clipping.add_child(_cartography)
	# Dynamic symbols draw on their own layer; roads and terrain never rebuild per frame.
	var symbols := Control.new()
	symbols.position = -MAP_RECT.position
	symbols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	symbols.draw.connect(_draw_symbols.bind(symbols))
	symbols.name = "Symbols"
	clipping.add_child(symbols)
	clipping.name = "MapClip"
	set_process(false)

func _update_layout() -> void:
	if expanded:
		var available: Vector2 = get_parent().size * 0.85
		var factor := minf(available.x / PANEL_SIZE.x, available.y / PANEL_SIZE.y)
		set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		scale = Vector2.ONE * factor
		offset_left = -PANEL_SIZE.x * factor * 0.5
		offset_top = -PANEL_SIZE.y * factor * 0.5
		offset_right = offset_left + PANEL_SIZE.x
		offset_bottom = offset_top + PANEL_SIZE.y
	else:
		scale = Vector2.ONE
		set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		offset_left = -316
		offset_top = -356
		offset_right = -16
		offset_bottom = -16

func setup(p: Player, main: Node) -> void:
	player = p
	world = main
	set_process(true)

func map_position(position_3d: Vector3) -> Vector2:
	return MAP_RECT.position + (Vector2(position_3d.x, position_3d.z) - _map_bounds.position) * _scale

func _point(p: Vector2) -> Vector2:
	return MAP_RECT.position + (p - _map_bounds.position) * _scale

func _draw_cartography() -> void:
	var c := _cartography
	c.draw_style_box(_panel_style(), Rect2(Vector2.ZERO, Vector2(300, 340)))
	c.draw_string(_font, Vector2(14, 25), TITLE, HORIZONTAL_ALIGNMENT_LEFT, 274, 18, Color(0.96, 0.87, 0.64))
	c.draw_texture_rect(_terrain, MAP_RECT, false)
	var clearing := PackedVector2Array()
	for p in Map.CLEARING:
		clearing.append(_point(p))
	if clearing.size() >= 3:
		c.draw_colored_polygon(clearing, Color(0.58, 0.55, 0.42))
	for road: Dictionary in Map.ROADS:
		var points := PackedVector2Array()
		for p in road["pts"]:
			points.append(_point(p))
		var width := maxf(1.2, float(road["width"]) * _scale)
		c.draw_polyline(points, Color(0.09, 0.13, 0.12), width + 2.0, true)
		c.draw_polyline(points, Color(0.66, 0.68, 0.62) if road["surface"] == "asphalt" else Color(0.77, 0.69, 0.47), width, true)
	for building: Dictionary in Map.BUILDINGS.values():
		var polygon := PackedVector2Array()
		var center: Vector2 = building["pos"]
		var half: Vector2 = building["size"] * 0.5
		for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]:
			polygon.append(_point(center + corner.rotated(-float(building["yaw"]))))
		c.draw_colored_polygon(polygon, Color(0.78, 0.43, 0.24))
		polygon.append(polygon[0])
		c.draw_polyline(polygon, Color(0.94, 0.79, 0.56), 1.0, true)
	var fire := _point(Map.FIRE)
	c.draw_circle(fire, 3.0, Color(1.0, 0.68, 0.22))
	c.draw_string(_font, fire + Vector2(7, 4), "Hütte", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 0.91, 0.69))
	# A metric scale makes the overview useful for judging approach distances.
	var scale_origin := Vector2(22, 297)
	var fifty_meters := 50.0 * _scale
	c.draw_line(scale_origin, scale_origin + Vector2(fifty_meters, 0), Color.WHITE, 2.0)
	for x in [0.0, fifty_meters]:
		c.draw_line(scale_origin + Vector2(x, -3), scale_origin + Vector2(x, 3), Color.WHITE)
	c.draw_string(_font, scale_origin + Vector2(0, -6), "50 m", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
	c.draw_string(_font, Vector2(14, 331), "▲ Du   • Gegner   ━ Sperrlinie", HORIZONTAL_ALIGNMENT_LEFT, 278, 11, Color(0.76, 0.81, 0.75))
	c.draw_rect(MAP_RECT, Color(0.71, 0.73, 0.62, 0.4), false, 1.0)

func _draw_frame() -> void:
	draw_style_box(_panel_style(), Rect2(Vector2.ZERO, Vector2(300, 340)))
	draw_string(_font, Vector2(14, 25), TITLE, HORIZONTAL_ALIGNMENT_LEFT, 274, 18, Color(0.96, 0.87, 0.64))
	draw_string(_font, Vector2(14, 331), "▲ Du   • Gegner   ━ Sperrlinie", HORIZONTAL_ALIGNMENT_LEFT, 278, 11, Color(0.76, 0.81, 0.75))

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.04, 0.035, 0.94)
	style.border_color = Color(0.7, 0.69, 0.51, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(7)
	return style

func _draw_compass(c: Control) -> void:
	# the rose turns with the player: the top of the rose is the view direction, the orange needle points north
	var center := Vector2(263, 72)
	var rot: float = player.rotation.y if is_instance_valid(player) else 0.0
	c.draw_circle(center, 25.0, Color(0.025, 0.04, 0.035, 0.85))
	for i in 4:
		var direction := Vector2.UP.rotated(i * PI / 2.0 + rot)
		var side := direction.orthogonal() * 3.0
		c.draw_colored_polygon(PackedVector2Array([center + direction * 13, center + side, center - side]), Color(1, 0.72, 0.3) if i == 0 else Color(0.68, 0.72, 0.64))
	for label in [["N", Vector2(0, -19)], ["O", Vector2(19, 0)], ["S", Vector2(0, 19)], ["W", Vector2(-19, 0)]]:
		var p: Vector2 = center + (label[1] as Vector2).rotated(rot)
		c.draw_string(_font, p + Vector2(-3, 4), label[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)

func _npc_visible(id: String) -> bool:
	if id == "wanderer":
		if not world.progression.rare_market.active: return false
		if reveal_wanderer: return true
	return world.progression.has_seen_npc(id) or (id == "secret" and reveal_secret)

func _draw_symbols(c: Control) -> void:
	_draw_compass(c)
	if not is_instance_valid(player) or not is_instance_valid(world):
		return
	if "progression" in world and world.progression:
		for id in world.progression.npcs:
			if not _npc_visible(id): continue
			var npc_point := map_position(world.progression.npcs[id].global_position)
			var wandering: bool = id == "wanderer"
			var marker_color := Color(0.85, 0.58, 1.0) if wandering else Color(0.94, 0.73, 0.37)
			if wandering:
				c.draw_circle(npc_point, 6.0, Color(0.04, 0.02, 0.06, 0.9))
			c.draw_circle(npc_point, 4.0 if wandering else 3.5, marker_color)
			var label_offset := Vector2(-28, 13) if id == "camp" else Vector2(5, -5)
			var label := "Wanderhändler" if wandering else str(Progression.NPCS[id].name)
			if wandering:
				label_offset.x = -_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x - 5 if npc_point.x > MAP_RECT.get_center().x else 5
				c.draw_string_outline(_font, npc_point + label_offset, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 3, Color(0.04, 0.02, 0.06))
			c.draw_string(_font, npc_point + label_offset, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, marker_color if wandering else Color(1, 0.88, 0.65))
		if world.progression.local_data().accepted.get("supplies", false) and not world.progression.team.cache:
			var cache_point := map_position(Vector3(Progression.CACHE.x, 0, Progression.CACHE.y))
			c.draw_circle(cache_point, 4, Color(0.9, 0.67, 0.16), false, 1.5)
	if NetSession.enabled and NetSession.world:
		for id in NetSession.world.actors:
			if id == NetSession.local_id(): continue
			var teammate: Player = NetSession.world.actor(id)
			var point := map_position(teammate.global_position)
			if MAP_RECT.has_point(point):
				c.draw_circle(point, 4.0, Color(0.3, 0.8, 1.0) if teammate.alive else Color(1.0, 0.7, 0.2))
	if "perimeter" in world and world.perimeter:
		var ring: Perimeter = world.perimeter
		for i in ring.points.size():
			if ring.gate_edge[i] or not ring.is_wall_built(ring.points[i]): continue
			var wa := map_position(Vector3(ring.points[i].x, 0.0, ring.points[i].y))
			var wb := map_position(Vector3(ring.points[(i + 1) % ring.points.size()].x, 0.0, ring.points[(i + 1) % ring.points.size()].y))
			if MAP_RECT.has_point(wa) or MAP_RECT.has_point(wb):
				c.draw_line(wa, wb, Color(0.02, 0.04, 0.03), 3.0, true)
				c.draw_line(wa, wb, Color(0.86, 0.78, 0.6), 1.5, true)
	for barricade in world.barricades:
		var p := map_position(barricade.center)
		if MAP_RECT.has_point(p):
			var color := Barricade.PLAN_COLOR if barricade.level == 0 else (Barricade.BUILT_COLOR if barricade.hp >= barricade.max_hp() * 0.5 else Color(1.0, 0.72, 0.3))
			var a := map_position(barricade.point_at(-barricade.half_len))
			var b := map_position(barricade.point_at(barricade.half_len))
			var direction := (b - a).normalized()
			var extent := maxf(4.0, a.distance_to(b) * 0.5)
			c.draw_line(p - direction * extent, p + direction * extent, Color(0.02, 0.04, 0.03), 5.0, true)
			c.draw_line(p - direction * extent, p + direction * extent, color, 2.5, true)
	if world.defences:
		for tower in world.defences.towers.values():
			if not is_instance_valid(tower): continue
			var point := map_position(tower.global_position)
			if MAP_RECT.has_point(point):
				c.draw_rect(Rect2(point - Vector2.ONE * 3, Vector2.ONE * 6), Color(0.3, 0.85, 0.95))
	for zombie in world.zombies_root.get_children():
		if zombie is Zombie and zombie.alive:
			var p := map_position(zombie.global_position)
			if MAP_RECT.has_point(p):
				c.draw_circle(p, 5.0 if Zombie.is_titan_kind(zombie.net_kind) else 2.0, Color(1.0, 0.29, 0.22))
	var p := map_position(player.global_position).clamp(MAP_RECT.position + Vector2.ONE * 5, MAP_RECT.end - Vector2.ONE * 5)
	var heading := Vector2(-sin(player.rotation.y), -cos(player.rotation.y))
	var side := heading.orthogonal()
	var half_fov := deg_to_rad(player.camera.fov * 0.5)
	c.draw_colored_polygon(PackedVector2Array([p, p + heading.rotated(-half_fov) * 24, p + heading.rotated(half_fov) * 24]), Color(0.8, 0.94, 1, 0.15))
	c.draw_circle(p, 6.0, Color(0.025, 0.04, 0.035, 0.9))
	c.draw_colored_polygon(PackedVector2Array([p + heading * 8, p - heading * 5 + side * 4, p - heading * 5 - side * 4]), Color(0.88, 0.98, 1))
	# Alerts sit above enemy dots and the player marker so an attacked gate stays legible.
	for barricade: Barricade in world.barricades:
		if not barricade.under_attack(): continue
		var center := map_position(barricade.center)
		if not MAP_RECT.has_point(center): continue
		var a := map_position(barricade.point_at(-barricade.half_len))
		var b := map_position(barricade.point_at(barricade.half_len))
		var direction := (b - a).normalized()
		var extent := maxf(4.0, a.distance_to(b) * 0.5)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.009)
		c.draw_circle(center, 9.0 + pulse * 4.0, Color(1, 0.06, 0.02, 0.15 + pulse * 0.2))
		c.draw_line(center - direction * extent, center + direction * extent, Color(1, 0.08, 0.03, 0.3 + pulse * 0.4), 8.0, true)
		c.draw_line(center - direction * extent, center + direction * extent, Color(1, 0.12 + pulse * 0.18, 0.06), 3.5, true)
	if "hut" in world and world.hut and world.hut.under_attack():
		var hut_point := map_position(world.hut.center)
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.009)
		c.draw_circle(hut_point, 11.0 + pulse * 5.0, Color(1, 0.06, 0.02, 0.15 + pulse * 0.2))
		c.draw_circle(hut_point, 7.0, Color(1, 0.12 + pulse * 0.18, 0.06), false, 2.5, true)
	# Draw ready-to-turn-in quests last so nearby enemies and players cannot cover them.
	if "progression" in world and world.progression:
		for id in world.progression.npcs:
			if not _npc_visible(id): continue
			if not world.progression.has_ready_quest(id): continue
			var marker := map_position(world.progression.npcs[id].global_position) + Vector2(-5, -7)
			marker = marker.clamp(MAP_RECT.position + Vector2(2, 20), MAP_RECT.end - Vector2(12, 2))
			c.draw_string_outline(_font, marker, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, 4, Color(0.06, 0.045, 0.015))
			c.draw_string(_font, marker, "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Progression.QUEST_MARKER_COLOR)

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= 0.1 and is_visible_in_tree():
		_elapsed = 0.0
		get_node("MapClip/Symbols").queue_redraw()
