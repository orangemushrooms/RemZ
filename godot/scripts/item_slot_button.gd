extends Button

# Godot's default tooltip grows to one very long line. Keep item descriptions
# within a compact, opaque card with a separate heading and wrapped body.
func _make_custom_tooltip(text: String) -> Object:
	var card := PanelContainer.new()
	card.custom_minimum_size.x = 390
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025,0.035,0.045,0.99)
	style.border_color = Color(0.75,0.57,0.28)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(16)
	style.shadow_size = 8
	style.shadow_color = Color(0,0,0,0.5)
	card.add_theme_stylebox_override("panel",style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	card.add_child(column)
	var split := text.find("\n")
	var title := Label.new()
	title.text = text.substr(0,split) if split>=0 else text
	title.custom_minimum_size.x = 358
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size",19)
	title.add_theme_color_override("font_color",Color(1,0.77,0.4))
	column.add_child(title)
	var body := Label.new()
	body.text = text.substr(split+1) if split>=0 else ""
	body.custom_minimum_size.x = 358
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size",17)
	body.add_theme_constant_override("line_spacing",5)
	body.add_theme_color_override("font_color",Color(0.94,0.95,0.92))
	column.add_child(body)
	return card
