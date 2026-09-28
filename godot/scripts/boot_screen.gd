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
const TITLE := "RemZ"
const SUBTITLE := "SURVIVE. SCAVENGE. ADAPT."
const TITLE_FONT_SIZE := 48
const COLUMN := 420.0
const GAP := 10.0
const BAR_HEIGHT := 6.0
const TIP_SECONDS := 7.0
const TIP_WIDTH := 640.0
const TIP_FONT_SIZE := 18
const TIPS := [
	"Explore the forest to find the Secret Vendor. Once discovered, the trader is marked on your map.",
	"Press M to enlarge the map. Keep track of the hut, paths and discovered traders.",
	"Collect field flowers with E. Take them to a campfire to brew useful drinks.",
	"Press C at a campfire to brew tea and drinks. Some recipes also need mushrooms.",
	"Meadow Tea restores 45 health. Keep a bottle ready for the next wave.",
	"Collect mushrooms in the forest. Check their effects in your inventory before using them.",
	"Open your inventory with I to drink a brew. Right-click a drink to assign it to the quickbar.",
	"Weapon mods are sold by Mechanic and the Secret Vendor. Improve the weapon you use most.",
	"The drone console is upstairs in the forest hut. Find its key first; the first drone unlocks at wave 5.",
	"Your body stays at the console while you fly a drone. Keep the hut defended.",
	"Press T to build towers. At a tower, use F to repair and R to adjust its aim.",
	"Repair the forest hut with E at its walls. If the hut falls, the round ends.",
	"Grill raw venison at the campfire with E. Grilled venison restores 35 health.",
	"Drinks can improve speed, protection or damage. Read the recipe before choosing your brew.",
	"In co-op, menus do not pause the fight. Cover teammates while they shop or brew.",
	"Speak to traders with E. Turn in completed quests to receive rewards and unlock new equipment.",
]
# The crest with the zombie deer, cut out of the game icon by tools/build_crest.py (827 x 959 px, soft
# red glow included). It takes whatever height the window leaves above the title column, up to its
# own pixels times MAX_UPSCALE on the physical screen, so it never turns soft.
const CREST := preload("res://assets/ui/remz_crest.png")
const CREST_GAP := 18.0
const MAX_UPSCALE := 1.1
const MARGIN := 0.04
var _item: RID                   # everything visible: backdrop, title, bar, gameplay tip
var _track := Hud._flat(Color(1, 1, 1, 0.08), 3)
var _fill := Hud._flat(Hud.GOLD, 3)
var _bar := 0.0
var _closing := false
var _target := 0.0
var _tip_rng := RandomNumberGenerator.new()
var _tip_order: Array[int] = []
var _tip_index := 0
var _next_tip_ms := 0
static var _last_tip := -1
var _tip_paragraph := TextParagraph.new()
var _paragraph_text := ""
var _paragraph_width := 0.0

# The screen for a menu action that is about to rebuild the scene; reused when one is already up.
static func cover(tree: SceneTree) -> BootScreen:
	var screen := find(tree)
	# A rapid second scene change can arrive during the previous cover's fade.
	# Its tween will free it; never hand that dying cover to the new scene.
	if screen and screen._closing:
		screen.name = "ClosingBootScreen"
		screen.queue_free()
		screen = null
	if screen == null:
		screen = BootScreen.new()
		screen.name = NODE_NAME
		tree.root.add_child(screen)
	screen.step(0.0)
	return screen

static func find(tree: SceneTree) -> BootScreen:
	var node := tree.root.get_node_or_null(NODE_NAME)
	return node as BootScreen if node and not node.is_queued_for_deletion() else null

func _init() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	_tip_rng.randomize()
	_update_tip()
	_item = RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(_item, get_canvas())
	RenderingServer.canvas_item_set_default_texture_filter(_item, RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS)
	var blocker := Control.new()
	blocker.set_anchors_preset(Control.PRESET_FULL_RECT)
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP   # nothing behind it may be clicked while loading
	add_child(blocker)

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _item.is_valid():
		RenderingServer.free_rid(_item)
	elif what == NOTIFICATION_TRANSLATION_CHANGED:
		_paint()

# One finished build step. With draw (main.gd's _ready, where no frame is drawn for seconds) it also
# keeps the window answering and shows this frame; input arriving meanwhile is dropped, nothing in the
# half-built scene may react to it. Outside _ready the normal frames animate the bar.
func step(fraction: float, draw := true) -> void:
	if _closing: return
	_target = maxf(_target, clampf(fraction, 0.0, 1.0))
	_update_tip()
	if not draw or DisplayServer.get_name() == "headless": return
	_bar = _target
	_paint()
	DisplayServer.force_process_and_drop_events()
	RenderingServer.force_draw(true, 0.0)

# Between steps the bar glides on and creeps a little further, so a long wait never looks frozen.
func _process(delta: float) -> void:
	if _closing: return
	_target = minf(_target + delta * 0.004, 0.99)
	_bar = move_toward(_bar, _target, delta * 0.8)
	_update_tip()
	_paint()

func tip_text() -> String:
	return Lang.t(TIPS[_tip_index])

# Wall time also advances during synchronous map building, when _process cannot run.
# A shuffled bag shows every tip once before repeating, without changing gameplay RNG.
func _update_tip(now_ms := Time.get_ticks_msec()) -> void:
	if now_ms < _next_tip_ms: return
	if _tip_order.is_empty():
		for i in TIPS.size(): _tip_order.append(i)
		for i in range(_tip_order.size() - 1, 0, -1):
			var j := _tip_rng.randi_range(0, i)
			var swap := _tip_order[i]
			_tip_order[i] = _tip_order[j]
			_tip_order[j] = swap
		if _tip_order.back() == _last_tip:
			var swap := _tip_order[0]
			_tip_order[0] = _tip_order.back()
			_tip_order[_tip_order.size() - 1] = swap
	_tip_index = _tip_order.pop_back()
	_last_tip = _tip_index
	_next_tip_ms = now_ms + int(TIP_SECONDS * 1000.0)

# Fade out and go; the menu or the round underneath is ready.
func close() -> void:
	if _closing: return
	_closing = true
	_bar = 1.0
	_paint()
	var tween := create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)   # a planner opened within the fade paused the tree and froze the crest
	tween.tween_method(func(alpha: float) -> void: RenderingServer.canvas_item_set_modulate(_item, Color(1, 1, 1, alpha)), 1.0, 0.0, 0.35)
	tween.tween_callback(queue_free)

# Keep a fixed tip area so changing text never makes the crest or progress bar jump.
func _paint() -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless": return
	var size := get_viewport().get_visible_rect().size
	var font := ThemeDB.fallback_font
	var left := (size.x - COLUMN) * 0.5
	var tip_width := minf(TIP_WIDTH, size.x * (1.0 - MARGIN * 2.0))
	var text := Lang.text(tip_text())
	if text != _paragraph_text or tip_width != _paragraph_width:
		_tip_paragraph.clear()
		_tip_paragraph.width = tip_width
		_tip_paragraph.alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tip_paragraph.add_string(text, font, TIP_FONT_SIZE)
		_paragraph_text = text
		_paragraph_width = tip_width
	var tip_height := maxf(font.get_height(TIP_FONT_SIZE) * 4, _tip_paragraph.get_size().y)
	var column := font.get_height(TITLE_FONT_SIZE) + font.get_height(12) + font.get_height(14) + tip_height + BAR_HEIGHT + 4.0 * GAP
	var crest := crest_rect(size, column)
	var y := crest.end.y + CREST_GAP
	RenderingServer.canvas_item_clear(_item)
	RenderingServer.canvas_item_add_rect(_item, Rect2(Vector2.ZERO, size), Hud.INK)
	if crest.size.y >= 1.0:
		RenderingServer.canvas_item_add_texture_rect(_item, crest, CREST.get_rid())
	font.draw_string(_item, Vector2(left, y + font.get_ascent(TITLE_FONT_SIZE)), Lang.text(TITLE), HORIZONTAL_ALIGNMENT_CENTER, COLUMN, TITLE_FONT_SIZE, Hud.GOLD)
	y += font.get_height(TITLE_FONT_SIZE) + GAP
	font.draw_string(_item, Vector2(left, y + font.get_ascent(12)), Lang.text(SUBTITLE), HORIZONTAL_ALIGNMENT_CENTER, COLUMN, 12, Color(0.875, 0.875, 0.875, 0.6))
	y += font.get_height(12) + GAP
	_track.draw(_item, Rect2(left, y, COLUMN, BAR_HEIGHT))
	if _bar * COLUMN >= 1.0:
		_fill.draw(_item, Rect2(left, y, COLUMN * _bar, BAR_HEIGHT))
	y += BAR_HEIGHT + GAP
	font.draw_string(_item, Vector2(left, y + font.get_ascent(14)), Lang.text("TIP"), HORIZONTAL_ALIGNMENT_CENTER, COLUMN, 14, Hud.GOLD)
	y += font.get_height(14) + GAP
	_tip_paragraph.draw(_item, Vector2((size.x - tip_width) * 0.5, y), Hud.PAPER)

# Where the crest goes in a window of this (logical) size: as tall as the room above the text column
# allows, never wider than the window, and never past MAX_UPSCALE times its own pixels on screen - the
# canvas stretch maps logical to physical pixels, and a 1440p or 4K window would blow it up otherwise.
func crest_rect(size: Vector2, column: float) -> Rect2:
	var pixels := float(DisplayServer.window_get_size().y) / maxf(size.y, 1.0)
	var native := Vector2(CREST.get_size())
	var height := minf(size.y * (1.0 - 2.0 * MARGIN) - column - CREST_GAP, native.y * MAX_UPSCALE / maxf(pixels, 0.01))
	height = maxf(minf(height, size.x * (1.0 - 2.0 * MARGIN) * native.y / native.x), 0.0)
	var width := height * native.x / native.y
	var top := (size.y - (height + CREST_GAP + column)) * 0.5
	return Rect2((size.x - width) * 0.5, top, width, height)
