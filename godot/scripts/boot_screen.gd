# The loading screen between the menus and the world. main.gd builds the whole map in _ready, which
# used to leave the last game frame frozen for many seconds - long enough for Windows to mark the
# window "Keine Rückmeldung" and offer to close it after every death or return to the menu. Now a menu
# action that rebuilds the scene covers the screen first (cover(), hung under the root window so it
# outlives the old scene), and main.gd reports every build step through step(), which also lets the
# window manager breathe and draws one frame of this screen. close() fades it out once the menu or the
# next round is ready.
#
# The screen paints itself straight into the RenderingServer instead of using Labels and a
# ProgressBar: Controls only record their draw commands on the next idle frame, and inside main's long
# _ready there is none. At the very first start (no cover from an earlier scene) the Controls stayed
# empty, so every step() put the half-built world on screen instead - with the sky's radiance not
# baked yet that was a blown-out white picture of grass blades (23 Sep 2026, tests/start_exposure.gd).
class_name BootScreen
extends CanvasLayer

const NODE_NAME := "BootScreen"
const TITLE := "WALDHÜTTE REMETSCHWIL"
const SUBTITLE := "NACHT AM HEITERSBERG"
const COLUMN := 420.0
const GAP := 10.0
const BAR_HEIGHT := 6.0
var _item: RID                   # everything visible: backdrop, title, bar, status line
var _track := Hud._flat(Color(1, 1, 1, 0.08), 3)
var _fill := Hud._flat(Hud.GOLD, 3)
var _text := ""
var _bar := 0.0
var _closing := false
var _target := 0.0
var _time := 0.0
var _pulse := 1.0

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
	_item = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_item, get_canvas())
	var blocker := Control.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing behind it may be clicked while loading
	add_child(blocker)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _item.is_valid():
		RenderingServer.free_rid(_item)

# One finished build step. With draw (main.gd's _ready, where no frame is drawn for seconds) it also
# keeps the window answering and shows this frame; input arriving meanwhile is dropped, nothing in the
# half-built scene may react to it. Outside _ready the normal frames animate the bar.
func step(fraction: float, text: String = "", draw := true) -> void:
	if _closing: return
	_target = maxf(_target, clampf(fraction, 0.0, 1.0))
	if not text.is_empty(): _text = text
	if not draw or DisplayServer.get_name() == "headless": return
	_bar = _target
	_paint()
	DisplayServer.force_process_and_drop_events()
	RenderingServer.force_draw(true, 0.0)

# Between steps the bar glides on and creeps a little further, so a long wait never looks frozen.
func _process(delta: float) -> void:
	_time += delta
	if _closing: return
	_target = minf(_target + delta * 0.004, 0.99)
	_bar = move_toward(_bar, _target, delta * 0.8)
	_pulse = 0.75 + 0.25 * sin(_time * 3.0)
	_paint()

# Fade out and go; the menu or the round underneath is ready.
func close() -> void:
	if _closing: return
	_closing = true
	_bar = 1.0
	_paint()
	var tween := create_tween()
	tween.tween_method(func(alpha: float) -> void: RenderingServer.canvas_item_set_modulate(_item, Color(1, 1, 1, alpha)), 1.0, 0.0, 0.35)
	tween.tween_callback(queue_free)

# The same centred column the Label version had: title, subtitle, bar, status line.
func _paint() -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless": return
	var size := get_viewport().get_visible_rect().size
	var font := ThemeDB.fallback_font
	var left := (size.x - COLUMN) * 0.5
	var y := (size.y - (font.get_height(30) + font.get_height(12) + font.get_height(13) + BAR_HEIGHT + 3.0 * GAP)) * 0.5
	RenderingServer.canvas_item_clear(_item)
	RenderingServer.canvas_item_add_rect(_item, Rect2(Vector2.ZERO, size), Hud.INK)
	font.draw_string(_item, Vector2(left, y + font.get_ascent(30)), TITLE, HORIZONTAL_ALIGNMENT_CENTER, COLUMN, 30, Hud.GOLD)
	y += font.get_height(30) + GAP
	font.draw_string(_item, Vector2(left, y + font.get_ascent(12)), SUBTITLE, HORIZONTAL_ALIGNMENT_CENTER, COLUMN, 12, Color(0.875, 0.875, 0.875, 0.6))
	y += font.get_height(12) + GAP
	_track.draw(_item, Rect2(left, y, COLUMN, BAR_HEIGHT))
	if _bar * COLUMN >= 1.0:
		_fill.draw(_item, Rect2(left, y, COLUMN * _bar, BAR_HEIGHT))
	y += BAR_HEIGHT + GAP
	var status := Hud.MUTED
	status.a = _pulse
	font.draw_string(_item, Vector2(left, y + font.get_ascent(13)), _text, HORIZONTAL_ALIGNMENT_CENTER, COLUMN, 13, status)
