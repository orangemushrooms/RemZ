extends VBoxContainer
## Shared, fixed scales across every trader. Numbers retain detail beyond a full bar.
const METRICS := [["Damage / shot", "damage", 300.0], ["Magazine", "mag", 150.0], ["Reload speed", "reload", 1.0], ["Range", "range", 180.0]]
var meters: Array[ProgressBar] = []
var values: Array[Label] = []
var labels: Array[Label] = []

func _init() -> void:
	add_theme_constant_override("separation", 4)
	for metric in METRICS:
		var line := HBoxContainer.new()
		add_child(line)
		var label := Label.new()
		label.text = metric[0]
		label.custom_minimum_size.x = 116
		label.add_theme_font_size_override("font_size", 12)
		line.add_child(label)
		labels.append(label)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.custom_minimum_size = Vector2(70, 7)
		for part in ["background", "fill"]:
			var style := StyleBoxFlat.new()
			style.bg_color = Color("ba4545") if part == "fill" else Color("302728")
			style.set_corner_radius_all(3)
			bar.add_theme_stylebox_override(part, style)
		line.add_child(bar)
		meters.append(bar)
		var value := Label.new()
		value.custom_minimum_size.x = 80
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 12)
		line.add_child(value)
		values.append(value)

func update_stats(spec: Dictionary) -> void:
	visible = not spec.is_empty()
	if spec.is_empty(): return
	labels[0].text = "Damage" if spec.get("melee", false) else "Damage / shot"
	for i in METRICS.size():
		var field: String = METRICS[i][1]
		var amount := float(spec.get(field, 0.0))
		if field == "damage": amount *= int(spec.get("pellets", 1))
		meters[i].value = clampf((1.0 / maxf(amount, 0.1) if field == "reload" else amount / float(METRICS[i][2])) * 100.0, 0, 100)
		values[i].text = "%.2f s" % amount if field == "reload" else ("%.2f m" % amount if field == "range" and amount < 10 else "%d m" % amount if field == "range" else str(roundi(amount)))
		var enabled: bool = not spec.get("melee", false) or field not in ["mag", "reload"]
		meters[i].get_parent().visible = enabled
		meters[i].tooltip_text = Lang.t("Longer bars are better. Reload speed uses the inverse reload time. Shotgun damage assumes every pellet hits.")
