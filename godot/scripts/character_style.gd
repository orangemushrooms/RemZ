extends RefCounted
## Shared dossier palette and typography. Kept local to the character interface.
const BODY = preload("res://assets/fonts/Barlow-Regular.ttf")
const MEDIUM = preload("res://assets/fonts/Barlow-SemiBold.ttf")
const DISPLAY = preload("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
const PAPER := Color("ede9dc")
const MUTED := Color("a4ada4")
const DIM := Color("68766d")
const GOLD := Color("cba66a")
const INK := Color("0a1110")
const PANEL := Color("101b18")
const LINE := Color("34403a")

static func box(fill: Color = PANEL, edge: Color = LINE, margin: int = 16, radius: int = 3) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = fill
	result.border_color = edge
	result.set_border_width_all(1)
	result.set_corner_radius_all(radius)
	result.set_content_margin_all(margin)
	return result

static func theme() -> Theme:
	var result := Theme.new()
	result.default_font = BODY
	result.default_font_size = 16
	result.set_color("font_color", "Label", PAPER)
	result.set_color("font_color", "LineEdit", PAPER)
	result.set_font("font", "Button", MEDIUM)
	result.set_font("font", "OptionButton", MEDIUM)
	result.set_stylebox("normal", "LineEdit", box(INK, LINE, 10))
	result.set_stylebox("focus", "LineEdit", box(INK, GOLD, 10))
	result.set_stylebox("normal", "OptionButton", box(PANEL, LINE, 10))
	result.set_stylebox("hover", "OptionButton", box(Color("1e2d25"), GOLD, 10))
	result.set_stylebox("panel", "PopupMenu", box(INK, LINE, 10))
	result.set_stylebox("hover", "PopupMenu", box(Color("29372b"), Color.TRANSPARENT, 8))
	result.set_font("font", "PopupMenu", BODY)
	result.set_stylebox("scroll", "VScrollBar", box(Color("151e1a"), Color.TRANSPARENT, 0))
	result.set_stylebox("grabber", "VScrollBar", box(Color("58634e"), Color.TRANSPARENT, 3))
	result.set_stylebox("grabber_highlight", "VScrollBar", box(GOLD, Color.TRANSPARENT, 3))
	result.set_stylebox("grabber_pressed", "VScrollBar", box(GOLD, Color.TRANSPARENT, 3))
	return result

static func button(node: Button, accent: Color = GOLD, active: bool = false, quiet: bool = false) -> void:
	var normal := box(Color("253028") if active else Color("141f1b"), accent if active else LINE, 14)
	if active: normal.border_width_left = 3
	if quiet: normal.bg_color = Color("0e1714")
	node.add_theme_stylebox_override("normal", normal)
	node.add_theme_stylebox_override("hover", box(Color("26362b"), accent, 14))
	node.add_theme_stylebox_override("pressed", box(Color("35412c"), accent.lightened(0.2), 14))
	var focus := box(Color.TRANSPARENT, accent, 0)
	focus.set_border_width_all(2)
	node.add_theme_stylebox_override("focus", focus)
	node.add_theme_stylebox_override("disabled", box(Color("101a16"), LINE, 14))
	node.add_theme_color_override("font_color", PAPER)
	node.add_theme_color_override("font_hover_color", Color.WHITE)
	node.add_theme_color_override("font_disabled_color", MUTED)
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	node.custom_minimum_size.y = 42
