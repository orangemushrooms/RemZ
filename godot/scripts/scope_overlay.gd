extends Control

# The lens the player looks through while scoped. The world camera does the magnifying; this only
# masks the periphery and draws the reticle. Every scoped weapon names its own optic in
# Weapons.DEFS ("scope_style"), so a hunting rifle and a plasma prototype do not share a sight
# picture: "mil" is the military mil-dot tree, "vintage" the thin duplex cross of an old hunting
# scope, "digital" the projected display of the energy rifle.
var magnification := 4.0
var style := "mil"
var heat := 0.0  # 0..1, only drawn by the digital optic (plasma barrel temperature)

const TINTS := {
	"mil": Color(0.8, 0.82, 0.75),
	"vintage": Color(0.86, 0.79, 0.58),
	"digital": Color(0.45, 0.92, 1.0),
}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)

func configure(magnification_value: float, style_value: String) -> void:
	if is_equal_approx(magnification, magnification_value) and style == style_value: return
	magnification = magnification_value
	style = style_value
	queue_redraw()

func set_heat(value: float) -> void:
	# Quantised: cooling changes the raw value every frame, and redrawing the lens means some five
	# hundred primitives. Two percent steps are finer than the arc can show anyway.
	var step := snappedf(clampf(value, 0.0, 1.0), 0.02)
	if style != "digital" or is_equal_approx(heat, step): return
	heat = step
	queue_redraw()

func _draw() -> void:
	var centre := size * 0.5
	var radius := minf(size.x, size.y) * 0.44
	var outer := size.length()
	var ink := Color(0.015, 0.018, 0.014)
	var tint: Color = TINTS.get(style, TINTS.mil)
	# Mask the periphery while leaving the magnified world visible in the lens.
	for i in 128:
		var a := Vector2.from_angle(TAU * i / 128.0)
		var b := Vector2.from_angle(TAU * (i + 1) / 128.0)
		draw_colored_polygon(PackedVector2Array([centre + a * radius, centre + a * outer, centre + b * outer, centre + b * radius]), Color.BLACK)
	match style:
		"vintage": _vintage(centre, radius, ink, tint)
		"digital": _digital(centre, radius, tint)
		_: _mil(centre, radius, ink)
	var label := centre + Vector2(-18, radius * 0.77)
	var text := "%.0f×" % magnification
	draw_string_outline(ThemeDB.fallback_font, label, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 3, ink)
	draw_string(ThemeDB.fallback_font, label, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, tint)

# The original mil-dot tree: heavy posts from the edge and ranging ticks along both axes.
func _mil(centre: Vector2, radius: float, ink: Color) -> void:
	draw_arc(centre, radius, 0, TAU, 128, Color(0.13, 0.14, 0.12), 8.0, true)
	for axis in [Vector2.RIGHT, Vector2.DOWN]:
		for direction in [-1.0, 1.0]:
			_reticle_line(centre + axis * 5.0 * direction, centre + axis * radius * 0.97 * direction, ink)
			for tick in range(1, 5):
				var point: Vector2 = centre + axis * radius * tick * 0.12 * direction
				var side: Vector2 = axis.orthogonal() * (5.0 if tick % 2 else 8.0)
				_reticle_line(point - side, point + side, ink)
	draw_circle(centre, 1.5, Color(0.65, 0.1, 0.05))

# An old hunting scope: brass ring, a duplex cross that thins towards the middle, nothing else.
func _vintage(centre: Vector2, radius: float, ink: Color, tint: Color) -> void:
	draw_arc(centre, radius, 0, TAU, 128, Color(0.20, 0.16, 0.10), 9.0, true)
	draw_arc(centre, radius * 0.985, 0, TAU, 128, Color(0.42, 0.33, 0.18, 0.7), 2.0, true)
	for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN]:
		for direction: float in [-1.0, 1.0]:
			var thick_end: Vector2 = centre + axis * radius * 0.42 * direction
			var thin_end: Vector2 = centre + axis * radius * 0.97 * direction
			draw_line(thick_end, thin_end, ink, 5.0, true)
			draw_line(thick_end, thin_end, tint.darkened(0.45), 3.0, true)
			draw_line(centre + axis * 6.0 * direction, thick_end, ink, 1.6, true)
	# A touch of warm vignette inside the glass, the way an uncoated lens falls off at the edge.
	for i in 5:
		var t := float(i) / 5.0
		draw_arc(centre, radius * (0.99 - t * 0.07), 0, TAU, 96, Color(0.25, 0.18, 0.08, 0.10 * (1.0 - t)), 10.0, true)

# A projected display: bracket corners, a fine cross with a gap, range ladder, heat arc.
func _digital(centre: Vector2, radius: float, tint: Color) -> void:
	draw_arc(centre, radius, 0, TAU, 128, Color(0.05, 0.10, 0.12), 8.0, true)
	draw_arc(centre, radius * 0.99, 0, TAU, 128, tint * Color(1, 1, 1, 0.35), 2.0, true)
	var gap := radius * 0.055
	for axis: Vector2 in [Vector2.RIGHT, Vector2.DOWN]:
		for direction: float in [-1.0, 1.0]:
			draw_line(centre + axis * gap * direction, centre + axis * radius * 0.5 * direction, tint * Color(1, 1, 1, 0.85), 1.5, true)
	# Corner brackets around the target box.
	var box := radius * 0.26
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var origin := centre + corner * box
		draw_line(origin, origin - Vector2(corner.x, 0) * box * 0.35, tint, 2.0, true)
		draw_line(origin, origin - Vector2(0, corner.y) * box * 0.35, tint, 2.0, true)
	# Elevation ladder on the left, ranging marks every 50 m of drop compensation.
	for step in range(1, 6):
		var y := centre.y + radius * 0.1 * step
		var width := 10.0 if step % 2 else 16.0
		draw_line(Vector2(centre.x - width, y), Vector2(centre.x + width, y), tint * Color(1, 1, 1, 0.55), 1.0, true)
	draw_circle(centre, 2.0, tint)
	# Barrel temperature as an arc that fills and turns red, so overheating is visible while scoped.
	var arc_colour := Color(0.3, 0.9, 1.0).lerp(Color(1.0, 0.35, 0.1), clampf(heat, 0.0, 1.0))
	draw_arc(centre, radius * 0.9, PI * 0.62, PI * 0.62 + TAU * 0.22, 48, Color(0.12, 0.18, 0.2), 6.0, true)
	if heat > 0.001:
		draw_arc(centre, radius * 0.9, PI * 0.62, PI * 0.62 + TAU * 0.22 * clampf(heat, 0.0, 1.0), 48, arc_colour, 6.0, true)

func _reticle_line(from: Vector2, to: Vector2, ink: Color) -> void:
	draw_line(from, to, Color(0.8, 0.82, 0.75, 0.45), 3.0, true)
	draw_line(from, to, ink, 1.5, true)
