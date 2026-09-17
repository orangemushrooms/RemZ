class_name KeyHint
extends Control

var target: ForestKey
var player: Player
var marker := Vector2.ZERO
var direction := Vector2.DOWN
var distance := 0.0
var on_screen := false
const GOLD := Color(1.0, 0.79, 0.38)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hide()

func update_target(key: ForestKey, p: Player) -> void:
	target = key
	player = p
	visible = is_instance_valid(target) and not target.taken
	if visible:
		_update_marker()
	queue_redraw()

func _process(_delta: float) -> void:
	if visible and is_instance_valid(target):
		_update_marker()
		queue_redraw()

func _update_marker() -> void:
	if not player.active:
		hide()
		return
	var at := target.interaction_point()
	distance = player.global_position.distance_to(at)
	var camera := player.camera
	var safe := Rect2(Vector2(size.x * 0.12, 155), Vector2(size.x * 0.64, size.y * 0.64 - 155))
	var projected := camera.unproject_position(at) if not camera.is_position_behind(at) else Vector2(-10000, -10000)
	on_screen = safe.has_point(projected)
	if on_screen:
		marker = projected - Vector2(0, 30)
		direction = Vector2.DOWN
	else:
		var local := camera.to_local(at)
		direction = Vector2(local.x, -local.y)
		if local.z > 0:
			direction.y = maxf(absf(direction.y), 0.5)
		if direction.length_squared() < 0.01:
			direction = Vector2.DOWN
		direction = direction.normalized()
		var half := safe.size * 0.5
		var factor := minf(half.x / maxf(absf(direction.x), 0.001), half.y / maxf(absf(direction.y), 0.001))
		marker = safe.get_center() + direction * factor

func _draw() -> void:
	if not visible:
		return
	var font := ThemeDB.fallback_font
	var panel := Rect2(16, 46, 302, 62)
	draw_style_box(_panel_style(), panel)
	draw_string(font, Vector2(30, 71), "SCHLÜSSEL IN DER NÄHE", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, GOLD)
	draw_string(font, Vector2(30, 94), "%d m · Folge dem Richtungspfeil" % ceili(distance), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.87, 0.89, 0.84))
	var side := Vector2(-direction.y, direction.x)
	var points := PackedVector2Array([marker + direction * 13, marker - direction * 9 + side * 10, marker - direction * 5, marker - direction * 9 - side * 10])
	draw_circle(marker, 20, Color(0.02, 0.03, 0.02, 0.78))
	draw_colored_polygon(points, GOLD)
	if on_screen:
		draw_arc(marker + Vector2(0, 30), 7, 0, TAU, 20, GOLD, 1.5, true)
	draw_string(font, marker + Vector2(24, 5), "%d m" % ceili(distance), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, GOLD)

var _style: StyleBoxFlat
func _panel_style() -> StyleBoxFlat:
	if not _style:
		_style = StyleBoxFlat.new()
		_style.bg_color = Color(0.025, 0.035, 0.03, 0.88)
		_style.border_color = Color(0.63, 0.49, 0.25, 0.7)
		_style.set_border_width_all(1)
		_style.set_corner_radius_all(5)
	return _style
