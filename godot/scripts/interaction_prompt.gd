# Shared, non-interactive HUD card for nearby actions and tower placement.
# The source stays language-neutral; keycaps are extracted only after translation.
class_name InteractionPrompt
extends PanelContainer

const GOLD := Color(1.0, 0.74, 0.34)
const PAPER := Color(0.97, 0.97, 0.94)
var text := ""
var bottom_margin := 150.0
var _last_text := "\u0001"
var _last_language := ""
var _box: VBoxContainer
var _heading: Label
var _details: Label
var _rows: Array[Dictionary] = []
var _keys := RegEx.new()
var _width := 640.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.025, 0.045, 0.06, 0.96)
	background.border_color = Color(0.92, 0.64, 0.27, 0.8)
	background.set_border_width_all(1)
	background.border_width_left = 4
	background.set_corner_radius_all(8)
	background.content_margin_left = 16
	background.content_margin_right = 16
	background.content_margin_top = 10
	background.content_margin_bottom = 12
	background.shadow_color = Color(0, 0, 0, 0.4)
	background.shadow_size = 8
	add_theme_stylebox_override("panel", background)
	_box = VBoxContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_theme_constant_override("separation", 6)
	add_child(_box)
	_heading = _label("", 12, GOLD)
	_box.add_child(_heading)
	_details = _label("", 15, Color(0.77, 0.83, 0.85))
	_details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(_details)
	_keys.compile("\\[([^\\]\\n]+)\\]")
	minimum_size_changed.connect(_fit.call_deferred)
	get_viewport().size_changed.connect(_resize)
	_resize()
	hide()

func refresh(source: String) -> void:
	text = source
	if source == _last_text and Lang.current == _last_language: return
	_last_text = source
	_last_language = Lang.current
	_heading.text = Lang.text("AVAILABLE ACTIONS")
	var lines: Array[String] = []
	var used := 0
	for line in Lang.text(source).split("\n", false):
		var matches := _keys.search_all(line)
		if matches.is_empty():
			lines.append(line)
			continue
		var prefix := _clean(line.substr(0, matches[0].get_start()))
		if not prefix.is_empty(): lines.append(prefix)
		for i in matches.size():
			var token: RegExMatch = matches[i]
			var end: int = matches[i + 1].get_start() if i + 1 < matches.size() else line.length()
			var action := _clean(line.substr(token.get_end(), end - token.get_end()))
			_update_row(used, token.get_string(1), action)
			used += 1
	for i in range(used, _rows.size()): _rows[i].root.hide()
	_details.text = "\n".join(lines)
	_details.visible = not lines.is_empty()
	_fit.call_deferred()

func _process(_delta: float) -> void:
	# Placement callers also use the familiar .text property.
	refresh(text)

func _update_row(index: int, key: String, action: String) -> void:
	if index >= _rows.size():
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 12)
		_box.add_child(row)
		_box.move_child(row, _details.get_index())
		var cap := PanelContainer.new()
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(cap)
		var key_label := _label("", 21, Color(0.04, 0.06, 0.08))
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cap.add_child(key_label)
		var label := _label("", 20, PAPER)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(label)
		_rows.append({"root": row, "cap": cap, "key": key_label, "label": label})
	var row: Dictionary = _rows[index]
	var accent := Color(0.78, 0.64, 1.0) if key == "C" else Color(0.46, 0.87, 0.77) if key in ["T", "F"] else GOLD
	var style := StyleBoxFlat.new()
	style.bg_color = accent
	style.set_corner_radius_all(5)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	style.border_width_bottom = 3
	style.border_color = accent.darkened(0.4)
	row.cap.add_theme_stylebox_override("panel", style)
	row.key.text = key
	row.key.add_theme_font_size_override("font_size", 21 if key.length() <= 3 else 14)
	row.key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var cap_width := 38.0 if key.length() <= 3 else 146.0
	row.key.custom_minimum_size.x = cap_width - 16
	row.cap.custom_minimum_size = Vector2(cap_width, 32)
	row.label.custom_minimum_size.x = _width - 32 - cap_width - 12
	row.label.text = action
	row.root.show()

func _resize() -> void:
	_width = minf(640.0, get_viewport_rect().size.x - 40.0)
	custom_minimum_size.x = _width
	_details.custom_minimum_size.x = _width - 32
	_last_text = "\u0001"
	refresh(text)
	_fit.call_deferred()

func _fit() -> void:
	if not is_inside_tree(): return
	size = Vector2(_width, get_combined_minimum_size().y)
	offset_left = -size.x * 0.5
	offset_right = size.x * 0.5
	offset_top = -bottom_margin - size.y
	offset_bottom = -bottom_margin

static func _clean(value: String) -> String:
	return value.strip_edges().trim_suffix("·").strip_edges()

static func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label
