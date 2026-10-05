extends PanelContainer

signal finished
signal skipped

const PAGES := [
	["Start with your gear", "I", "You already have a weapon. After our talk, open your [b]inventory[/b] and choose what to carry. Close it again when you are ready.\n\nI sell ammo and supplies for [b]Rem Dollars[/b]. Come back to me to collect your quest rewards.", "Try one thing at a time. This introduction costs nothing."],
	["Your class has an advantage", "Z", "", "Use your ability when it helps. Your ammunition is not spent."],
	["Make a plan between waves", "K", "Your [b]fieldbook[/b] keeps optional missions, team supplies and discoveries together. New augments become available as you survive.\n\nOpen it during a quiet moment. You can also find it in the pause menu.", "In co-op the world keeps moving while menus are open. Find cover first."],
	["Build when you are ready", "T", "Open the [b]tower planner[/b], choose a tower and inspect a clear spot. [b]Left click[/b] builds there; the preview tells you the price and obstacles.\n\nClose the planner without buying anything to look around for free. Mechanic has your first building job.", "At a structure, the nearby interaction hint tells you what you can do."],
]

const CLASS_LESSONS := {
	"gunslinger": "Your [b]Focus[/b] lasts six seconds and steadies your shots. Press [b]Z[/b] just before a difficult fight. It recharges in thirty seconds.",
	"assault": "Your [b]Suppression[/b] lasts eight seconds. Enemies you hit are slowed. Press [b]Z[/b] when the horde advances. It recharges in thirty seconds.",
	"breacher": "Your [b]Shockwave[/b] hurts and slows visible enemies within nine metres. Press [b]Z[/b] when they get close. It recharges in thirty seconds.",
	"marksman": "Aim at a visible enemy and press [b]Z[/b] to [b]mark[/b] it for ten seconds. The marked enemy takes more damage. It recharges in thirty seconds.",
	"assassin": "At [b]Assassin level 15[/b], choose a teleport mode in your class skills. Use it with [b]V[/b] once unlocked. Your current class does not use Z.",
}

var step := 0
var heading: Label
var keys: Label
var body: RichTextLabel
var note: Label
var back: Button
var next: Button
var skip: Button
var class_id := "gunslinger"
var region := "forest"

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.05, 0.044, 1.0)
	style.set_content_margin_all(24)
	add_theme_stylebox_override("panel", style)
	var center := CenterContainer.new()
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(620, 480)
	column.add_theme_constant_override("separation", 14)
	center.add_child(column)
	heading = Label.new()
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	heading.add_theme_font_size_override("font_size", 25)
	column.add_child(heading)
	keys = Label.new()
	keys.add_theme_font_size_override("font_size", 34)
	keys.add_theme_color_override("font_color", Color(1, 0.79, 0.33))
	column.add_child(keys)
	body = RichTextLabel.new()
	body.bbcode_enabled = true
	body.custom_minimum_size = Vector2(620, 200)
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
	skip = Button.new()
	skip.text = "I know my way · Skip guidance"
	skip.custom_minimum_size.y = 38
	skip.pressed.connect(func(): hide(); skipped.emit())
	column.add_child(skip)
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
	if step == 1:
		keys.text = "V" if class_id == "assassin" else "Z"
		body.text = CLASS_LESSONS.get(class_id, CLASS_LESSONS.gunslinger)
	elif step == 3 and region == "planes":
		body.text = "Choose a defensible spot in the fields. [b]T[/b] opens the tower planner; left click places the selected tower.\n\nFor walls, buy kits from [b]Mechanic[/b], then use [b]B[/b] on your chosen ground. The placement preview explains the next step."
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
