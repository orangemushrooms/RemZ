extends PanelContainer

signal finished

const PAGES := [
	["Deine Ausrüstung", "I", "Mit [b]I[/b] öffnest du das Inventar. Wähle dort eine Waffe oder einen Gegenstand aus. Mit [b]I oder Esc[/b] gehst du zurück ins Spiel.\n\nDie belegten Plätze deiner Schnellleiste erreichst du mit [b]1–9 und 0[/b].", "Probiere nach unserem Gespräch zuerst das Inventar aus."],
	["Vorräte und Aufträge", "E  ·  Q", "Sprich Händler mit [b]E[/b] an. Bei mir bekommst du Waffen und Munition. Bezahlt wird mit [b]Rem Dollars (R)[/b]. Gesperrte Angebote zeigen dir die fehlenden Voraussetzungen.\n\nNimm Aufträge im Reiter [b]Aufträge[/b] an und hole die Belohnung beim Auftraggeber ab. [b]Q[/b] blendet deine Auftragsübersicht ein oder aus.", "Käufe kosten Rem Dollars. Diese Einführung ist kostenlos."],
	["Deinen ersten Turm bauen", "T  →  R  →  E", "[b]T[/b] öffnet das Turmbaumenü. Wähle einen Turm aus (ab [b]120 R[/b]) und suche einen freien Platz. Die Vorschau zeigt Reichweite und mögliche Hindernisse.\n\nMit [b]R oder dem Mausrad[/b] drehst du den Turm. [b]E[/b] bestätigt den Bau. Mit [b]T oder Esc[/b] brichst du die Vorschau ab.", "Nur ein bestätigter Bau kostet Rem Dollars. Du musst für das Tutorial keinen Turm kaufen."],
	["Die Hütte verteidigen", "E  ·  R  ·  F", "An einer Barrikade kannst du mit [b]E[/b] bauen oder reparieren; der Hinweis zeigt den Preis.\n\nAn einem fertigen Turm: [b]E[/b] zum Einsteigen, Linksklick zum Feuern, [b]E[/b] zum Aussteigen. [b]R[/b] startet das Ausrichten; drehen und mit [b]E[/b] bestätigen. [b]F[/b] repariert.\n\n[b]Mechanic[/b] bietet Turmausbauten und Training an. Schütze die Hütte und behalte ihren Zustand im Blick.", "Du kannst diese Grundlagen jederzeit bei Vendor unter Aufträge erneut ansehen."],
]

var step := 0
var heading: Label
var keys: Label
var body: RichTextLabel
var note: Label
var back: Button
var next: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.044, 1.0)
	style.set_content_margin_all(36)
	add_theme_stylebox_override("panel", style)
	var center := CenterContainer.new()
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(620, 520)
	column.add_theme_constant_override("separation", 20)
	center.add_child(column)
	heading = Label.new()
	heading.add_theme_font_size_override("font_size", 25)
	column.add_child(heading)
	keys = Label.new()
	keys.add_theme_font_size_override("font_size", 34)
	keys.add_theme_color_override("font_color", Color(1, 0.79, 0.33))
	column.add_child(keys)
	body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.custom_minimum_size = Vector2(620, 280)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_font_size_override("normal_font_size", 19)
	body.add_theme_font_size_override("bold_font_size", 19)
	column.add_child(body)
	note = Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.y = 48
	note.add_theme_color_override("font_color", Color(0.75, 0.82, 0.75))
	column.add_child(note)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	column.add_child(buttons)
	back = Button.new()
	back.text = "Zurück"
	back.custom_minimum_size = Vector2(180, 46)
	back.pressed.connect(func(): step = maxi(0, step - 1); refresh())
	buttons.add_child(back)
	next = Button.new()
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next.pressed.connect(advance)
	buttons.add_child(next)
	hide()

func open() -> void:
	show()
	refresh()
	next.grab_focus()

func refresh() -> void:
	var page: Array = PAGES[step]
	heading.text = "VENDOR · %d/%d · %s" % [step + 1, PAGES.size(), page[0]]
	keys.text = page[1]
	body.text = page[2]
	body.scroll_to_line(0)
	note.text = page[3]
	back.disabled = step == 0
	next.text = "Verstanden · Zurück zu Vendor" if step == PAGES.size() - 1 else "Weiter"

func advance() -> void:
	if step < PAGES.size() - 1:
		step += 1
		refresh()
	else:
		hide()
		finished.emit()
