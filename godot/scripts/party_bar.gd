# The bar of the Secret Night (26 Sep 2026): while the Goa party runs, E at the bar - whenever the quest
# has nothing to do there - opens the drinks card: the party drinks of Mushrooms.DRINKS (a buff like a
# mushroom, some with a trip, the Clear Head sobers you up) and the Vendor's fireworks. The host (or solo)
# confirms every order through buy(); a co-op client sends the command "bar_order". Solo pauses like a shop.
class_name PartyBar
extends CanvasLayer

const REACH := 3.8
const FIREWORKS := ["fw_ruby", "fw_aurora", "fw_gold", "fw_cracker"]

var night: SecretNight
var main: Node
var is_open := false
var panel: PanelContainer
var list: VBoxContainer
var status: Label
var orders := 0          # statistics / tests

func setup(owner_night: SecretNight) -> void:
	night = owner_night
	main = owner_night.main
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(620, 0)
	panel.offset_left = -310
	panel.offset_right = 310
	panel.offset_top = -300
	panel.offset_bottom = 300
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.02, 0.1, 0.94)
	style.border_color = Color(1.0, 0.25, 0.75)
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.text = "GOA BAR · OBERER SCHORCHEN"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.95))
	box.add_child(title)
	status = Label.new()
	status.add_theme_font_size_override("font_size", 16)
	status.add_theme_color_override("font_color", Color(1.0, 0.8, 0.35))
	box.add_child(status)
	list = VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	box.add_child(list)
	var close_button := Button.new()
	close_button.text = "Back to the dance floor · Esc"
	close_button.pressed.connect(close)
	box.add_child(close_button)
	panel.hide()

func near(p: Player) -> bool:
	return Vector2(p.global_position.x, p.global_position.z).distance_to(SecretNight.BAR + Vector2(0, 2)) <= REACH

func prompt(p: Player) -> String:
	if not night.active or not p.alive or p.downed or p.controlling_drone or p.mounted_tower or not near(p): return ""
	if not night.prompt(p).is_empty(): return ""
	return "[E] Bar · drinks and fireworks"

func open() -> void:
	if is_open or not night.active: return
	is_open = true
	main.player.active = false
	main.weapons.viewmodel.hide()
	for part in main.hud.crosshair_parts: part.hide()
	main.hud.set_prompt("")
	get_tree().paused = not NetSession.enabled
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	panel.show()
	refresh()

func close() -> void:
	if not is_open: return
	is_open = false
	panel.hide()
	get_tree().paused = false
	main.player.active = main.player.alive and not main.over
	main.weapons.viewmodel.visible = main.player.active
	for part in main.hud.crosshair_parts: part.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func refresh() -> void:
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var score: int = main.player.score
	for kind in Inventory.Mushrooms.DRINKS:
		var drink: Dictionary = Inventory.Mushrooms.DRINKS[kind]
		_add(Lang.t("%s · %d R\n%s", [drink.name, drink.price, drink.text]), kind, score < int(drink.price), Color(drink.color))
	for id in FIREWORKS:
		var firework: Dictionary = Fireworks.DEFS[id]
		_add(Lang.t("Firework · %s · %d R", [firework.name, firework.price]), id, score < int(firework.price), Color(firework.color))
	status.text = Lang.t("%d Rem Dollars · the DJ says: drink responsibly, dance irresponsibly.", [score])

func _add(text: String, kind: String, disabled: bool, colour: Color) -> void:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = disabled
	button.add_theme_color_override("font_color", colour.lightened(0.35))
	button.pressed.connect(order.bind(kind))
	list.add_child(button)

func order(kind: String) -> void:
	if NetSession.enabled: NetSession.command("bar_order", [kind])
	else: main.hud.message(buy(main.player, kind), 3.5)
	# the host's answer arrives as a message; the balance follows with the next snapshot
	get_tree().create_timer(0.3, true).timeout.connect(func(): if is_open: refresh())
	refresh()

# Host / solo: one order for one actor. Empty text never comes back: it is the message the player sees.
func buy(p: Player, kind: String) -> String:
	if NetSession.is_client(): return "The host confirms the order."
	if not night.active: return "The bar is closed."
	if not p.alive or p.downed: return "You cannot order right now."
	if not near(p): return "Walk up to the bar to order."
	if FIREWORKS.has(kind):
		orders += 1
		return main.fireworks.buy(p, kind)
	if not Inventory.Mushrooms.DRINKS.has(kind): return "The bartender does not know that drink."
	var drink: Dictionary = Inventory.Mushrooms.DRINKS[kind]
	if p.score < int(drink.price): return Lang.t("Not enough Rem Dollars: %d R needed.", [drink.price])
	p.add_score(-int(drink.price))
	p.hp = clampf(p.hp + float(drink.get("heal", 0.0)), 1.0, p.max_hp)
	if drink.has("duration"): p.mushroom_effects[kind] = float(drink.duration)
	p.hud.set_health(p.hp)
	if drink.has("trip"): _feedback(p, "hallucinate", [float(drink.trip)])
	if drink.get("sober", false): _feedback(p, "sober", [])
	orders += 1
	Sfx.event(main, p.peer_id, "consume")
	return Lang.t("%s: %s", [drink.name, drink.text])

func _feedback(p: Player, kind: String, args: Array) -> void:
	if p == main.player:
		if kind == "hallucinate": main.hud.hallucinate(float(args[0]))
		elif kind == "sober": main.hud.sober()
	else:
		NetSession.feedback(p.peer_id, kind, args)

func _process(_delta: float) -> void:
	if is_open and (not night.active or not main.player.alive or not near(main.player) or main.over): close()

func _input(event: InputEvent) -> void:
	if is_open and event.is_action_pressed("pause"):
		close()
		get_viewport().set_input_as_handled()
