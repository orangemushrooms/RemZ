extends VBoxContainer
const Classes = preload("res://scripts/character_classes.gd")
var hud: Node
var title: Label
var bar: ProgressBar
var notice: Label
var level_notice: Label
var ability: Label
var talent_status: Label
var _status_time := 0.0
var _toast_time := 0.0
var _level_time := 0.0

func setup(owner_hud: Node) -> void:
	hud = owner_hud
	set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 30
	offset_top = -225
	offset_right = 315
	offset_bottom = -160
	custom_minimum_size.x = 285
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	title = hud._label("", 13)
	add_child(title)
	bar = ProgressBar.new()
	bar.custom_minimum_size = Vector2(285, 5)
	bar.show_percentage = false
	add_child(bar)
	ability = hud._label("", 13, Color("b6a0d8"))
	add_child(ability)
	talent_status = hud._label("",13,Hud.GOLD)
	add_child(talent_status)
	notice = hud._label("", 13, Hud.GOLD)
	add_child(notice)
	level_notice = hud._label("", 19, Hud.GOLD)
	level_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	level_notice.position = Vector2(-240, 240)
	level_notice.custom_minimum_size = Vector2(480, 0)
	level_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	level_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud._root.add_child(level_notice)
	CharacterProfile.changed.connect(refresh)
	CharacterProfile.xp_gained.connect(func(amount: int, reason: String):
		notice.text = Lang.t("+%d XP · %s", [amount, reason])
		_toast_time = 3.0)
	CharacterProfile.level_gained.connect(func(id: String, level: int):
		if not hud.game.started: return
		level_notice.text = Lang.t("LEVEL UP\n%s · LEVEL %d", [Classes.CLASSES[id].name, level])
		if level in Classes.TIERS: level_notice.text += "\n" + Lang.t("New talent available in the main menu.")
		_level_time = 6.0)
	refresh()

func refresh() -> void:
	var id := CharacterProfile.active_class()
	if CharacterProfile.data.is_empty(): return
	var progress := Classes.progress(int(CharacterProfile.data.classes[id].total_xp))
	title.text = Lang.t("%s · LVL %d · %d%%", [Classes.CLASSES[id].name, progress.level, roundi(float(progress.xp) / progress.required * 100) if progress.required > 0 else 100])
	title.add_theme_color_override("font_color", Classes.CLASSES[id].color)
	bar.max_value = maxi(1, progress.required)
	bar.value = progress.xp if progress.required > 0 else 1
	bar.add_theme_stylebox_override("fill", hud._flat(Classes.CLASSES[id].color, 2))
	bar.add_theme_stylebox_override("background", hud._flat(Color(0, 0, 0, 0.4), 2))

func _process(delta: float) -> void:
	visible = hud.game.started and not hud.overlay.visible and not hud.game.over
	_toast_time = maxf(0.0, _toast_time - delta)
	_level_time = maxf(0.0, _level_time - delta)
	notice.visible = _toast_time > 0.0
	level_notice.visible = visible and _level_time > 0.0
	var actor: Player = hud.game.player
	_status_time -= delta
	if actor and _status_time<=0.0:
		_status_time = 0.1
		var equipped := actor.equipped_weapons()
		talent_status.text = actor.class_combat.status(equipped.current if equipped else "",actor.hp<actor.max_hp*Classes.LAST_STAND_HEALTH)
		talent_status.visible = not talent_status.text.is_empty()
	var mode := AssassinTeleport.mode_for(actor) if actor else ""
	ability.visible = not mode.is_empty()
	if ability.visible:
		ability.text = Lang.t("Teleport: %.1f s", [actor.teleport_cooldown]) if actor.teleport_cooldown > 0 else Lang.t("V / Teleport: Map") if mode == "map" else Lang.t("V / Teleport: Forward")
	elif actor and hud.game.get("expedition") and hud.game.expedition.enabled:
		ability.text = hud.game.expedition.action_status(actor.peer_id)
		ability.visible = not ability.text.is_empty()
