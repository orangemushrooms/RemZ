extends PanelContainer
## Host-timed revive. Releasing E, walking away or opening a menu cancels it.
var world: RefCounted
var target := 0
var pulse := 0.0
var caption: Label
var progress: ProgressBar

func setup(coop: RefCounted) -> void:
	world = coop
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	offset_left = -210; offset_right = 210
	offset_top = -220; offset_bottom = -158
	var box := VBoxContainer.new()
	add_child(box)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_color_override("font_color",Hud.GOLD)
	caption.add_theme_font_size_override("font_size",20)
	box.add_child(caption)
	progress = ProgressBar.new()
	progress.max_value = 3.0
	progress.show_percentage = false
	progress.custom_minimum_size.y = 12
	var fill := StyleBoxFlat.new()
	fill.bg_color = Hud.GOLD
	progress.add_theme_stylebox_override("fill",fill)
	box.add_child(progress)
	hide()

func _process(delta: float) -> void:
	if not world or NetSession.world!=world:
		hide()
		return
	var p: Player = world.game.player
	var nearby: int = world.nearby_downed_player() if p.active and p.alive and not p.downed and world.game.started and not world.game.over else 0
	visible = nearby!=0
	var holding := nearby!=0 and Input.is_action_pressed("interact")
	var next := nearby if holding else 0
	if target and target!=next: NetSession.command("revive",[target,false])
	if target!=next: pulse = 0.0
	target = next
	pulse -= delta
	if target and pulse<=0:
		NetSession.command("revive",[target,true])
		pulse = 0.2
	if not visible: return
	caption.text = Lang.t("Hold E · Revive %s",[Lang.raw(str(NetSession.roster.get(nearby,"Teammate")))])
	var state: Dictionary = world.revive.get(NetSession.local_id(),{})
	progress.value = float(state.get("time",0)) if target and int(state.get("target",0))==target else 0.0
