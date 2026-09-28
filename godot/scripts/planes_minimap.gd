extends Minimap
## Reuse Forest's panel, metric projection, compass, expansion and cached layers.
var game: Node
var _map_cache: SubViewport
const LEGEND := "▲ You   • Enemies   M Map size"

func _ready() -> void:
	super._ready()
	setup(game.player,game)
	# Surveyed hill shading and land cover, generated once, never per frame.
	var image := Image.create(384,384,false,Image.FORMAT_RGB8)
	var light := Vector3(-0.55,0.8,-0.25).normalized()
	for y in 384:
		for x in 384:
			var p := _map_bounds.position+Vector2(x+0.5,y+0.5)*_map_bounds.size/384.0
			var cover := Map.cover(p.x,p.y)
			var colour := Color(0.31,0.38,0.25).lerp(Color(0.115,0.20,0.15),cover.r)
			colour = colour.lerp(Color(0.56,0.54,0.43),cover.b)
			colour *= 0.73+maxf(0.0,Map.ground_normal(p.x,p.y).dot(light))*0.35
			image.set_pixel(x,y,colour)
	_terrain = ImageTexture.create_from_image(image)
	_cartography.queue_redraw()
	# Cache the entire static map at expansion resolution, including roads and
	# building outlines. Only the compass, player and enemies redraw at 10 Hz.
	_map_cache = SubViewport.new()
	_map_cache.disable_3d = true
	_map_cache.transparent_bg = true
	_map_cache.size = Vector2i(PANEL_SIZE*3)
	_map_cache.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_map_cache)
	_cartography.reparent(_map_cache,false)
	_cartography.position = Vector2.ZERO
	_map_cache.canvas_transform = Transform2D(0,Vector2.ZERO).scaled(Vector2.ONE*3)
	var cached := TextureRect.new()
	cached.texture = _map_cache.get_texture()
	cached.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cached.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	cached.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cached.position = -MAP_RECT.position
	cached.size = PANEL_SIZE
	var clip := get_node("MapClip")
	clip.add_child(cached)
	clip.move_child(cached,0)

func _notification(what: int) -> void:
	if what==NOTIFICATION_TRANSLATION_CHANGED and _map_cache:
		queue_redraw()
		_cartography.queue_redraw()
		_map_cache.render_target_update_mode = SubViewport.UPDATE_ONCE

func _draw_frame() -> void:
	draw_style_box(_panel_style(),Rect2(Vector2.ZERO,PANEL_SIZE))
	draw_string(_font,Vector2(14,25),"The Planes / Remetschwil",HORIZONTAL_ALIGNMENT_LEFT,274,17,Color(0.96,0.87,0.64))
	draw_string(_font,Vector2(14,331),Lang.text(LEGEND),HORIZONTAL_ALIGNMENT_LEFT,278,11,Color(0.76,0.81,0.75))

func _draw_cartography() -> void:
	var c := _cartography
	c.draw_texture_rect(_terrain,MAP_RECT,false)
	for field: Dictionary in Map._d.fields:
		var polygon := PackedVector2Array()
		for p in field.poly: polygon.append(_point(Vector2(p[0],p[1])))
		c.draw_colored_polygon(polygon,Color(0.42,0.49,0.26,0.85) if field.kind=="corn" else Color(0.68,0.57,0.32,0.9))
		polygon.append(polygon[0])
		c.draw_polyline(polygon,Color(0.75,0.75,0.49,0.5),0.8,true)
	for road: Dictionary in Map.ROADS:
		var points := PackedVector2Array()
		for p in road.pts: points.append(_point(p))
		var width := maxf(1.2,float(road.width)*_scale)
		c.draw_polyline(points,Color(0.09,0.13,0.12),width+2.0,true)
		c.draw_polyline(points,Color(0.66,0.68,0.62) if road.surface=="asphalt" else Color(0.77,0.69,0.47),width,true)
	for building: Dictionary in Map.VILLAGE:
		var polygon := PackedVector2Array()
		for p in building.poly: polygon.append(_point(Vector2(p[0],p[1])))
		if polygon[0].is_equal_approx(polygon[-1]): polygon.remove_at(polygon.size()-1)
		if building.get("kind","")=="shooting_targets":
			c.draw_colored_polygon(polygon,Color(0.48,0.51,0.46))
			var center := Vector2.ZERO
			for p in polygon: center += p/polygon.size()
			c.draw_circle(center,2.8,Color(0.94,0.91,0.77))
			c.draw_circle(center,1.5,Color(0.08,0.10,0.08))
			continue
		c.draw_colored_polygon(polygon,Color(0.72,0.46,0.3))
		polygon.append(polygon[0])
		c.draw_polyline(polygon,Color(0.94,0.79,0.56),0.8,true)
	var boundary := PackedVector2Array()
	for p in preload("res://scripts/planes_boundary.gd").OUTLINE: boundary.append(_point(p))
	boundary.append(boundary[0])
	c.draw_polyline(boundary,Color(0.08,0.08,0.05),3.5,true)
	c.draw_polyline(boundary,Color(1.0,0.74,0.25),1.8,true)
	# A few geographic labels remain readable on the compact map.
	for label in [["Rigiweg",Vector2(-116,-127)],["Sennhof",Vector2(310,-150)],["Remetschwil",Vector2(-290,-280)]]:
		var at := _point(label[1])
		c.draw_string_outline(_font,at,label[0],HORIZONTAL_ALIGNMENT_LEFT,-1,10,3,Color(0.04,0.07,0.05))
		c.draw_string(_font,at,label[0],HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color(0.96,0.88,0.66))
	var start := Vector2(22,297)
	var distance := 100.0*_scale
	c.draw_line(start,start+Vector2(distance,0),Color.WHITE,2.0)
	for x in [0.0,distance]: c.draw_line(start+Vector2(x,-3),start+Vector2(x,3),Color.WHITE)
	c.draw_string(_font,start+Vector2(0,-6),"100 m",HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color.WHITE)
	c.draw_rect(MAP_RECT,Color(0.71,0.73,0.62,0.4),false,1.0)

func _draw_symbols(c: Control) -> void:
	if not is_instance_valid(player): return
	_draw_compass(c)
	var at := Vector2(player.global_position.x,player.global_position.z)
	if preload("res://scripts/planes_boundary.gd").closest(at).distance_to(at)<8.0:
		c.draw_style_box(_panel_style(),Rect2(10,40,284,29))
		c.draw_string(_font,Vector2(20,60),Lang.text("Map boundary ? turn back"),HORIZONTAL_ALIGNMENT_LEFT,264,14,Color(1.0,0.8,0.35))
	for enemy in game.zombies_root.get_children():
		if enemy is Zombie and enemy.alive and enemy.visible_on_map():
			c.draw_circle(map_position(enemy.global_position),2,Color(1.0,0.29,0.22))
	var p := map_position(player.global_position).clamp(MAP_RECT.position+Vector2.ONE*8,MAP_RECT.end-Vector2.ONE*8)
	var heading := Vector2(-sin(player.rotation.y),-cos(player.rotation.y))
	var side := heading.orthogonal()
	var half_fov := deg_to_rad(player.camera.fov*0.5)
	c.draw_colored_polygon(PackedVector2Array([p,p+heading.rotated(-half_fov)*24,p+heading.rotated(half_fov)*24]),Color(0.8,0.94,1,0.15))
	c.draw_circle(p,6.0,Color(0.025,0.04,0.035,0.9))
	c.draw_colored_polygon(PackedVector2Array([p+heading*8,p-heading*5+side*4,p-heading*5-side*4]),Color(0.88,0.98,1))
