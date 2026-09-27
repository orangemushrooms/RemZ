class_name LiveMap
extends Control
## The artwork, region hit testing and overlays share one transform, including at ultrawide sizes.
signal region_hovered(id: String)
signal region_pressed(id: String)
const ART = preload("res://assets/Map.png")
const REGION_SHADER = preload("res://scripts/campaign_region.gdshader")
var interactive := false
var campaign: Campaign
var hovered := ""
var selected := "forest"
var clock := 0.0
var map_rect := Rect2()
var _art: TextureRect
var _regions: Array[Polygon2D] = []
var _ink: Control
var _fog: ColorRect

func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	_art = TextureRect.new()
	_art.texture = ART
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_art)
	if interactive:
		for entry: Dictionary in Campaign.REGIONS:
			var polygon := Polygon2D.new()
			polygon.polygon = PackedVector2Array(entry.outline)
			polygon.uv = polygon.polygon
			polygon.texture = ART
			var mat := ShaderMaterial.new()
			mat.shader = REGION_SHADER
			mat.set_shader_parameter("saturation", 1.0 if entry.available else 0.0)
			mat.set_shader_parameter("brightness", 1.16 if entry.available else 0.67)
			polygon.material = mat
			add_child(polygon)
			_regions.append(polygon)
	_fog = ColorRect.new()
	_fog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fog_mat := ShaderMaterial.new()
	fog_mat.shader = preload("res://scripts/campaign_fog.gdshader")
	fog_mat.set_shader_parameter("mist_texture", preload("res://assets/ui/campaign_mist.tres"))
	_fog.material = fog_mat
	add_child(_fog)
	_ink = Control.new()
	_ink.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ink.draw.connect(_draw_details)
	add_child(_ink)
	resized.connect(_layout)
	mouse_exited.connect(func(): _hover(""))
	_layout()

func _layout() -> void:
	if not _art: return
	var ratio := minf(size.x / Campaign.ART_SIZE.x, size.y / Campaign.ART_SIZE.y) if interactive else maxf(size.x / Campaign.ART_SIZE.x, size.y / Campaign.ART_SIZE.y)
	map_rect = Rect2((size - Campaign.ART_SIZE * ratio) * 0.5, Campaign.ART_SIZE * ratio)
	_art.position = map_rect.position
	_art.size = map_rect.size
	for polygon in _regions:
		polygon.position = map_rect.position
		polygon.scale = Vector2.ONE * ratio
	_ink.queue_redraw()

func region_at(local: Vector2) -> String:
	if not map_rect.has_point(local): return ""
	var point := (local - map_rect.position) / map_rect.size * Campaign.ART_SIZE
	for entry: Dictionary in Campaign.REGIONS:
		if Geometry2D.is_point_in_polygon(point, PackedVector2Array(entry.outline)): return entry.id
	return ""

func _hover(id: String) -> void:
	if hovered == id: return
	hovered = id
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if Campaign.region(id).get("available", false) else Control.CURSOR_ARROW
	region_hovered.emit(id)

func _gui_input(event: InputEvent) -> void:
	if not interactive: return
	if event is InputEventMouseMotion: _hover(region_at(event.position))
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var id := region_at(event.position)
		if not id.is_empty(): region_pressed.emit(id)
		accept_event()

func _process(delta: float) -> void:
	if not is_visible_in_tree(): return
	clock += minf(delta, 0.1)
	_fog.material.set_shader_parameter("clock", clock)
	if interactive:
		for i in _regions.size():
			var entry: Dictionary = Campaign.REGIONS[i]
			var bright := (1.35 if hovered == entry.id else 1.13) if entry.available else (0.98 if hovered == entry.id else 0.67)
			var mat := _regions[i].material as ShaderMaterial
			mat.set_shader_parameter("brightness", lerpf(float(mat.get_shader_parameter("brightness")), bright, 1.0 - exp(-delta * 9.0)))
	_ink.queue_redraw()

func _draw_details() -> void:
	var ratio := map_rect.size.x / Campaign.ART_SIZE.x
	if ratio <= 0: return
	if interactive:
		for entry: Dictionary in Campaign.REGIONS:
			var active: bool = entry.id == hovered or entry.id == selected
			var points := PackedVector2Array()
			for point: Vector2 in entry.outline: points.append(map_rect.position + point * ratio)
			var colour := Color(0.58, 0.8, 0.69) if entry.available else Color(0.65, 0.67, 0.69)
			if active:
				_ink.draw_colored_polygon(points, Color(colour, 0.10 if entry.available else 0.16))
			points.append(points[0])
			_ink.draw_polyline(points, Color(colour, 0.9 if active else 0.28), 1.8 if active else 1.0, true)
			var at: Vector2 = map_rect.position + entry.anchor * ratio
			_ink.draw_circle(at, 5.0, colour if entry.available else Color(0.45, 0.47, 0.49))
			if entry.available:
				_ink.draw_arc(at, 10.0 + fmod(clock * 6.0, 15.0), 0, TAU, 48, Color(colour, (1.0 - fmod(clock * 0.4, 1.0)) * 0.7), 1.2, true)
				if campaign and campaign.cleared(entry.id):
					_ink.draw_polyline(PackedVector2Array([at + Vector2(-4, 0), at + Vector2(-1, 3), at + Vector2(5, -4)]), Color(0.05,0.14,0.1), 2.0, true)
			else:
				_ink.draw_rect(Rect2(at + Vector2(-3, -1), Vector2(6, 5)), Color(0.1, 0.12, 0.13))
				_ink.draw_arc(at + Vector2(0,-1), 2.5, PI, TAU, 12, Color(0.1,0.12,0.13), 1.4, true)
	# Three small flocks circle independently, with staggered wingbeats and soft shadows.
	for i in 18:
		var flock := i / 6
		var t := clock * (0.06 + flock * 0.013) + i * 0.13
		var center := Vector2(0.51 + 0.22 * sin(t + flock * 2.2), 0.42 + 0.25 * cos(t * 0.84 + flock))
		var at := map_rect.position + center * map_rect.size + Vector2(sin(i * 7.3), cos(i * 3.7)) * (12 + i * 1.8) * ratio
		var forward := Vector2(cos(t + flock * 2.2), -sin(t * 0.84 + flock)).normalized()
		var side := forward.orthogonal()
		var wing := (2.3 + sin(clock * 5.0 + i * 1.7) * 1.7) * ratio
		var shape := PackedVector2Array([at - side * wing - forward * 2.0, at + forward * ratio, at + side * wing - forward * 2.0])
		var shadow := PackedVector2Array()
		for point in shape: shadow.append(point + Vector2(4, 6) * ratio)
		_ink.draw_polyline(shadow, Color(0,0,0,0.13), 2.0, true)
		_ink.draw_polyline(shape, Color(0.025,0.04,0.035,0.86), 1.4, true)
