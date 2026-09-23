# The loading screen between the menus and the world. main.gd builds the whole map in _ready, which
# used to leave the last game frame frozen for many seconds - long enough for Windows to mark the
# window "Keine Rückmeldung" and offer to close it after every death or return to the menu. Now a menu
# action that rebuilds the scene covers the screen first (cover(), hung under the root window so it
# outlives the old scene), and main.gd reports every build step through step(), which also lets the
# window manager breathe and draws one frame of this screen. close() fades it out once the menu or the
# next round is ready.
class_name BootScreen
extends CanvasLayer

const NODE_NAME := "BootScreen"
var _bar: ProgressBar
var _status: Label
var _closing := false
var _target := 0.0
var _time := 0.0

# The screen for a menu action that is about to rebuild the scene; reused when one is already up.
static func cover(tree: SceneTree, text: String) -> BootScreen:
	var screen := find(tree)
	if screen == null:
		screen = BootScreen.new()
		screen.name = NODE_NAME
		tree.root.add_child(screen)
	screen.step(0.0, text)
	return screen

static func find(tree: SceneTree) -> BootScreen:
	var node := tree.root.get_node_or_null(NODE_NAME)
	return node as BootScreen if node and not node.is_queued_for_deletion() else null

func _init() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing behind it may be clicked while loading
	add_child(root)
	var back := ColorRect.new()
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	back.color = Hud.INK
	root.add_child(back)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(420, 0)
	column.add_theme_constant_override("separation", 10)
	center.add_child(column)
	var title := Label.new()
	title.text = "WALDHÜTTE REMETSCHWIL"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Hud.GOLD)
	column.add_child(title)
	var sub := Label.new()
	sub.text = "NACHT AM HEITERSBERG"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 12)
	sub.modulate.a = 0.6
	column.add_child(sub)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 6)
	_bar.max_value = 1.0
	_bar.show_percentage = false
	_bar.add_theme_stylebox_override("background", Hud._flat(Color(1, 1, 1, 0.08), 3))
	_bar.add_theme_stylebox_override("fill", Hud._flat(Hud.GOLD, 3))
	column.add_child(_bar)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Hud.MUTED)
	column.add_child(_status)

# One finished build step. With draw (main.gd's _ready, where no frame is drawn for seconds) it also
# keeps the window answering and shows this frame; input arriving meanwhile is dropped, nothing in the
# half-built scene may react to it. Outside _ready the normal frames animate the bar.
func step(fraction: float, text: String = "", draw := true) -> void:
	if _closing: return
	_target = maxf(_target, clampf(fraction, 0.0, 1.0))
	if not text.is_empty(): _status.text = text
	if not draw or DisplayServer.get_name() == "headless": return
	_bar.value = _target
	DisplayServer.force_process_and_drop_events()
	RenderingServer.force_draw(true, 0.0)

# Between steps the bar glides on and creeps a little further, so a long wait never looks frozen.
func _process(delta: float) -> void:
	_time += delta
	if _closing: return
	_target = minf(_target + delta * 0.004, 0.99)
	_bar.value = move_toward(_bar.value, _target, delta * 0.8)
	_status.modulate.a = 0.75 + 0.25 * sin(_time * 3.0)

# Fade out and go; the menu or the round underneath is ready.
func close() -> void:
	if _closing: return
	_closing = true
	_bar.value = 1.0
	var tween := create_tween()
	tween.tween_property(get_child(0), "modulate:a", 0.0, 0.35)
	tween.tween_callback(queue_free)
