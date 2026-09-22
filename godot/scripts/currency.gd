extends RefCounted

# Shared original artwork, loaded with the UI rather than on each transaction.
const ICON := preload("res://assets/RemZ_Currency.png")

static func icon(side := 40.0, tint := Color.WHITE) -> TextureRect:
	var view := TextureRect.new()
	view.texture = ICON
	view.custom_minimum_size = Vector2(side, side)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.modulate = tint
	view.tooltip_text = "Rem Dollars (R)"
	return view
