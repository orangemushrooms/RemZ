extends PanelContainer

signal finished

const PAGES := [
	["Your gear", "I", "Press [b]I[/b] to open the inventory. Pick a weapon or an item there. [b]I or Esc[/b] takes you back into the game.\n\nYou reach the filled slots of your quick bar with [b]1–9 and 0[/b].", "After our talk, try out the inventory first."],
	["Supplies and quests", "E  ·  Q", "Talk to traders with [b]E[/b]. I sell weapons and ammo. You pay with [b]Rem Dollars (R)[/b]. Locked offers show you the missing requirements.\n\nAccept quests in the [b]Quests[/b] tab and collect the reward from whoever gave you the quest. [b]Q[/b] shows or hides your quest overview.", "Purchases cost Rem Dollars. This introduction is free."],
	["Build your first tower", "T  →  R  →  E", "[b]T[/b] opens the tower build menu. Choose a tower (from [b]120 R[/b]) and find a free spot. The preview shows the range and possible obstacles.\n\n[b]R or the mouse wheel[/b] rotates the tower. [b]E[/b] confirms the build. [b]T or Esc[/b] cancels the preview.", "Only a confirmed build costs Rem Dollars. You don't have to buy a tower for the tutorial."],
	["Defend the hut", "E  ·  R  ·  F", "At a barricade, [b]E[/b] builds or repairs; the hint shows the price.\n\nAt a finished tower: [b]E[/b] to climb in, left click to fire, [b]E[/b] to climb out. [b]R[/b] starts aiming; rotate and confirm with [b]E[/b]. [b]F[/b] repairs.\n\n[b]Mechanic[/b] offers tower upgrades and training. Protect the hut and keep an eye on its condition.", "You can review these basics any time with Vendor under Quests."],
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
	back.text = "Back"
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
	heading.text = Lang.t("VENDOR · %d/%d · %s", [step + 1, PAGES.size(), page[0]])
	keys.text = page[1]
	body.text = page[2]
	body.scroll_to_line(0)
	note.text = page[3]
	back.disabled = step == 0
	next.text = "Got it · Back to Vendor" if step == PAGES.size() - 1 else "Continue"

func advance() -> void:
	if step < PAGES.size() - 1:
		step += 1
		refresh()
	else:
		hide()
		finished.emit()
